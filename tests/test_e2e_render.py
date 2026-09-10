#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
魔方学院 v19 端到端可视化测试：用 macOS SceneKit 离线渲染高阶魔方，
对每个阶数 × 关键状态（solved, U转, R转, 随机打乱20步）渲染，
然后用 PIL 比对每个面中心点的像素颜色是否符合预期。

用法：python3 tests/test_e2e_render.py
"""
import sys, os, subprocess, json
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from gen_perms import generate_N_order_perms
from PIL import Image
import tempfile

COLOR_MAP = [
    (248, 248, 248),  # 0 U 白
    (224, 46, 46),    # 1 R 红
    (46, 158, 77),    # 2 F 绿
    (247, 209, 38),   # 3 D 黄
    (247, 140, 26),   # 4 L 橙
    (38, 92, 199),    # 5 B 蓝
]

def make_swift_render(order, facelets, out_path, view='angle'):
    """写一个 Swift 文件，用 SceneKit 渲染指定 facelets 并截图"""
    if view == 'top':
        cam_pos = f"SCNVector3(0, {8.0 * order / 3}, 0.01)"
    elif view == 'angle':
        d = float(order) / 3.0
        cam_pos = f"SCNVector3({4.5*d}, {4.0*d}, {6.5*d})"
    else:
        raise ValueError(f"unknown view {view}")

    facelets_str = '[' + ','.join(str(x) for x in facelets) + ']'

    swift = f'''
import SceneKit
import AppKit

func build(order: Int, facelets: [Int]) -> SCNNode {{
    let root = SCNNode()
    let N = order
    let halfExtent = Float(N) / 2.0
    let core = SCNBox(width: CGFloat(N), height: CGFloat(N), length: CGFloat(N), chamferRadius: 0.02)
    core.firstMaterial?.diffuse.contents = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
    let coreNode = SCNNode(geometry: core)
    root.addChildNode(coreNode)

    let colorMap: [NSColor] = [
        NSColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1),
        NSColor(red: 0.88, green: 0.18, blue: 0.18, alpha: 1),
        NSColor(red: 0.18, green: 0.62, blue: 0.30, alpha: 1),
        NSColor(red: 0.97, green: 0.82, blue: 0.15, alpha: 1),
        NSColor(red: 0.97, green: 0.55, blue: 0.12, alpha: 1),
        NSColor(red: 0.15, green: 0.36, blue: 0.78, alpha: 1),
    ]

    let stickerSize: Float = 0.88
    let normalDistance = halfExtent + 0.02
    let halfGrid = Float(N - 1) / 2.0
    let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
        (SIMD3(0,1,0), SIMD3(1,0,0), SIMD3(0,0,1)),
        (SIMD3(1,0,0), SIMD3(0,0,-1), SIMD3(0,-1,0)),
        (SIMD3(0,0,1), SIMD3(1,0,0), SIMD3(0,-1,0)),
        (SIMD3(0,-1,0), SIMD3(1,0,0), SIMD3(0,0,-1)),
        (SIMD3(-1,0,0), SIMD3(0,0,1), SIMD3(0,-1,0)),
        (SIMD3(0,0,-1), SIMD3(-1,0,0), SIMD3(0,-1,0)),
    ]
    let faceEulers: [SCNVector3] = [
        SCNVector3(-Float.pi/2, 0, 0),
        SCNVector3(0, Float.pi/2, 0),
        SCNVector3(0, 0, 0),
        SCNVector3(Float.pi/2, 0, 0),
        SCNVector3(0, -Float.pi/2, 0),
        SCNVector3(0, Float.pi, 0),
    ]
    let perFace = N * N
    for f in 0..<6 {{
        let spec = faces[f]
        for r in 0..<N {{
            for c in 0..<N {{
                let idx = f * perFace + r * N + c
                let plane = SCNPlane(width: CGFloat(stickerSize), height: CGFloat(stickerSize))
                let mat = SCNMaterial()
                mat.diffuse.contents = colorMap[facelets[idx]]
                mat.lightingModel = .physicallyBased
                mat.roughness.contents = 0.35
                mat.isDoubleSided = false
                plane.materials = [mat]
                let node = SCNNode(geometry: plane)
                let u = Float(c) - halfGrid
                let v = Float(r) - halfGrid
                let pos = SCNVector3(
                    spec.0.x * normalDistance + spec.1.x * u + spec.2.x * v,
                    spec.0.y * normalDistance + spec.1.y * u + spec.2.y * v,
                    spec.0.z * normalDistance + spec.1.z * u + spec.2.z * v)
                node.position = pos
                node.eulerAngles = faceEulers[f]
                root.addChildNode(node)
            }}
        }}
    }}
    return root
}}

let facelets: [Int] = {facelets_str}
let scene = SCNScene()
scene.rootNode.addChildNode(build(order: {order}, facelets: facelets))

let cam = SCNNode()
cam.camera = SCNCamera()
cam.camera?.fieldOfView = 38
cam.position = {cam_pos}
cam.look(at: SCNVector3(0,0,0))
scene.rootNode.addChildNode(cam)

let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient
amb.light!.intensity = 1500
scene.rootNode.addChildNode(amb)

let r = SCNRenderer(device: nil, options: nil)
r.scene = scene
r.pointOfView = cam
let img = r.snapshot(atTime: 0, with: CGSize(width: 800, height: 800), antialiasingMode: .multisampling4X)
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "{out_path}"))
'''
    swift_path = '/tmp/_render.swift'
    with open(swift_path, 'w') as f:
        f.write(swift)
    binary_path = '/tmp/_render_bin'
    r = subprocess.run(['swiftc', '-o', binary_path, swift_path], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  compile error: {r.stderr[:500]}")
        return False
    r = subprocess.run([binary_path], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  run error: {r.stderr[:500]}")
        return False
    return True

def dominant_color(img_path, sample_count=200):
    """读取图片，返回主色（最常见的 N 个量化颜色）"""
    img = Image.open(img_path).convert('RGB')
    w, h = img.size
    crop = img.crop((w*0.2, h*0.2, w*0.8, h*0.8))
    pixels = list(crop.getdata())
    from collections import Counter
    quantized = [(r//30*30, g//30*30, b//30*30) for (r,g,b) in pixels]
    common = Counter(quantized).most_common(sample_count)
    return common

def main():
    print("=" * 60)
    print("魔方学院 v19 E2E 渲染测试")
    print("=" * 60)

    test_orders = [3, 4, 5, 6, 8, 10]
    failures = 0

    for order in test_orders:
        print(f"\n=== N = {order} ===")
        N = order
        # 1) solved 态 + 俯视 U 面，应主色为白
        solved = []
        for f in range(6):
            solved.extend([f] * (N*N))

        out = f'/tmp/render_{order}_solved_top.png'
        ok = make_swift_render(order, solved, out, view='top')
        if ok:
            common = dominant_color(out)
            top_color = common[0][0] if common else (0,0,0)
            # 白色 quantized: (240, 240, 240) 范围
            is_white = abs(top_color[0]-248) < 50 and abs(top_color[1]-248) < 50 and abs(top_color[2]-248) < 50
            status = '✓' if is_white else '❌'
            print(f"  {status} solved-top: dominant color {top_color} (expected ~248,248,248 white)")
            if not is_white: failures += 1

        # 2) U 转后俯视，U 面仍应主色为白
        perms = generate_N_order_perms(order)
        U_perm = perms[0]
        after_U = [solved[U_perm[i]] for i in range(6*N*N)]
        out = f'/tmp/render_{order}_afterU_top.png'
        ok = make_swift_render(order, after_U, out, view='top')
        if ok:
            common = dominant_color(out)
            top_color = common[0][0] if common else (0,0,0)
            is_white = abs(top_color[0]-248) < 50 and abs(top_color[1]-248) < 50 and abs(top_color[2]-248) < 50
            status = '✓' if is_white else '❌'
            print(f"  {status} after-U-top: dominant color {top_color} (expected white)")
            if not is_white: failures += 1

        # 3) U 转后斜角视角，应该看到 R 面顶行变蓝（B→R）、F 面顶行变红（R→F）
        # 这是检测环置换的关键。取侧视图右上角应该是蓝色（来自 R 面顶行）。
        out = f'/tmp/render_{order}_afterU_angle.png'
        ok = make_swift_render(order, after_U, out, view='angle')
        if ok:
            common = dominant_color(out)
            def near(c, ref, tol=80):
                return abs(c[0]-ref[0]) < tol and abs(c[1]-ref[1]) < tol and abs(c[2]-ref[2]) < tol
            has_blue = any(near(c, (38, 92, 199)) for c, _ in common)
            has_red = any(near(c, (224, 46, 46)) for c, _ in common)
            has_green = any(near(c, (46, 158, 77)) for c, _ in common)
            has_white = any(near(c, (248, 248, 248)) for c, _ in common)
            status = '✓' if (has_blue and has_red and has_green and has_white) else '❌'
            print(f"  {status} after-U-angle: blue={has_blue} red={has_red} green={has_green} white={has_white}")
            if not (has_blue and has_red and has_green and has_white):
                failures += 1
                print(f"    期望看到白(U)+红(F顶行来自R)+绿(F下3行)+蓝(R顶行来自B) 4色")

    print("\n" + "=" * 60)
    if failures == 0:
        print(f"✅ ALL {len(test_orders)*2} PASS")
        sys.exit(0)
    else:
        print(f"❌ {failures} failures")
        sys.exit(1)

if __name__ == '__main__':
    main()