import Foundation
import SwiftUI
import SceneKit

/// 3D 魔方视图（SceneKit）—— 状态驱动渲染。
///
/// 渲染方式：每个 cubelet 是 1 个 SCNBox，6 个 material 顺序固定为
/// [+x, -x, +y, -y, +z, -z]（与 SCNBox 内部一致），按 facelet 给对应面赋色。
/// chamferRadius 设小（0.04）保留圆角立体感但避免 material 索引错乱。
///
/// 视角控制：直接用 SCNView 内置 `allowsCameraControl = true`（自带单指 pan
/// 旋转视角、双指捏合缩放），避免自定义手势穿透到 ScrollView 的问题。
struct Cube3DView: UIViewRepresentable {
    @ObservedObject var session: CubeSession

    init(session: CubeSession) { self.session = session }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true   // 内置相机控制（单指旋转、双指缩放）
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true

        let scene = SCNScene()
        scnView.scene = scene
        context.coordinator.scene = scene
        context.coordinator.buildCube(facelets: session.cube.facelets)
        context.coordinator.lastFacelets = session.cube.facelets

        // 摄像机
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.position = SCNVector3(4.5, 4.0, 6.5)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        context.coordinator.cameraNode = camera

        // 光照：环境光 + 定向光（产生立体感）
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 600
        ambient.light!.color = UIColor(white: 0.92, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.light!.color = UIColor.white
        key.position = SCNVector3(5, 8, 5)
        key.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(key)

        context.coordinator.scnView = scnView
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let co = context.coordinator
        let facelets = session.cube.facelets
        guard facelets != co.lastFacelets else { return }
        co.lastFacelets = facelets
        co.applyFacelets(facelets)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    final class Coordinator: NSObject {
        var scene: SCNScene!
        weak var scnView: SCNView?
        weak var cameraNode: SCNNode?
        /// cubelets[key] = 块节点；key 格式 "x_y_z"
        var cubelets: [String: SCNNode] = [:]
        /// 块节点 → 该块 6 个外露面在 materials 数组里的下标
        var exposedFaces: [String: [Int]] = [:]
        var lastFacelets: [Int] = []

        /// 标准魔方配色（stickerless，与 facelet 颜色 id 严格对应）
        let colorMap: [UIColor] = [
            UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1), // 0 U 白
            UIColor(red: 0.88, green: 0.18, blue: 0.18, alpha: 1), // 1 R 红
            UIColor(red: 0.18, green: 0.62, blue: 0.30, alpha: 1), // 2 F 绿
            UIColor(red: 0.97, green: 0.82, blue: 0.15, alpha: 1), // 3 D 黄
            UIColor(red: 0.97, green: 0.55, blue: 0.12, alpha: 1), // 4 L 橙
            UIColor(red: 0.15, green: 0.36, blue: 0.78, alpha: 1), // 5 B 蓝
        ]
        let innerColor = UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)

        /// 构建 26 个块（SCNBox 6-materials 方案）
        func buildCube(facelets: [Int]) {
            cubelets.values.forEach { $0.removeFromParentNode() }
            cubelets.removeAll()
            exposedFaces.removeAll()
            for x in -1...1 {
                for y in -1...1 {
                    for z in -1...1 {
                        if x == 0 && y == 0 && z == 0 { continue }
                        let key = "\(x)_\(y)_\(z)"
                        let node = makeCubelet(x: x, y: y, z: z)
                        node.position = SCNVector3(Float(x), Float(y), Float(z))
                        scene.rootNode.addChildNode(node)
                        cubelets[key] = node
                    }
                }
            }
            applyFacelets(facelets)
        }

        /// SCNBox 6-materials 顺序：0=+x, 1=-x, 2=+y, 3=-y, 4=+z, 5=-z
        func makeCubelet(x: Int, y: Int, z: Int) -> SCNNode {
            // 关键：chamferRadius 0.04 保留圆角立体感，但小到不触发 material 索引错乱
            let geo = SCNBox(width: 0.96, height: 0.96, length: 0.96, chamferRadius: 0.04)

            // 先 6 个 material 全置内色（黑），再由 applyFacelets 覆盖可见面
            var mats: [SCNMaterial] = []
            for _ in 0..<6 {
                let m = SCNMaterial()
                m.diffuse.contents = innerColor
                m.lightingModel = .physicallyBased
                m.roughness.contents = 0.35
                m.metalness.contents = 0.0
                mats.append(m)
            }
            geo.materials = mats

            let node = SCNNode(geometry: geo)
            node.castsShadow = true
            node.name = "cubelet_\(x)_\(y)_\(z)"

            // 记录该块哪些面是外露的（在 materials 数组里的下标）
            var exposed: [Int] = []
            if x == 1  { exposed.append(0) }  // +x
            if x == -1 { exposed.append(1) }  // -x
            if y == 1  { exposed.append(2) }  // +y
            if y == -1 { exposed.append(3) }  // -y
            if z == 1  { exposed.append(4) }  // +z
            if z == -1 { exposed.append(5) }  // -z
            exposedFaces["\(x)_\(y)_\(z)"] = exposed

            return node
        }

        /// 根据 facelets 给每个块可见面贴对应颜色。
        ///
        /// facelet 索引约定（CubeState 标准）：
        /// - U(0-8), R(9-17), F(18-26), D(27-35), L(36-44), B(45-53)
        /// - 每个面 9 贴片 row-major：行 0 在 z=-1 一侧，行 2 在 z=+1 一侧
        /// - 每行：列 0 在 x=-1，列 2 在 x=+1
        ///
        /// CubeState 的 U/D 面是从 +y 俯视，F 面是从 +z 看（x 左到右、y 上到下），
        /// L 面是从 -x 看（z 远到近、y 上到下），R 面从 +x 看（z 近到远、y 上到下），
        /// B 面从 -z 看（x 右到左、y 上到下）。
        func applyFacelets(_ facelets: [Int]) {
            guard facelets.count == 54 else { return }
            // (x, y, z) → 该面在 SCNBox materials 数组里的下标
            func matIndex(x: Int, y: Int, z: Int) -> Int? {
                if x ==  1 { return 0 }
                if x == -1 { return 1 }
                if y ==  1 { return 2 }
                if y == -1 { return 3 }
                if z ==  1 { return 4 }
                if z == -1 { return 5 }
                return nil
            }

            // facelet 索引 → (块坐标 x,y,z)
            // U 面 (0-8)：y=1，9 块在 xz 平面上
            //   观察方向：从 +y 俯视，row 按 z 从 -1 到 +1，col 按 x 从 -1 到 +1
            let uPositions: [(Int,Int,Int)] = [
                (-1, 1, -1), (0, 1, -1), (1, 1, -1),
                (-1, 1,  0), (0, 1,  0), (1, 1,  0),
                (-1, 1,  1), (0, 1,  1), (1, 1,  1),
            ]
            // R 面 (9-17)：x=1，9 块在 yz 平面上
            //   观察方向：从 +x 看，row 按 y 从 +1 到 -1，col 按 z 从 +1 到 -1
            let rPositions: [(Int,Int,Int)] = [
                (1,  1,  1), (1,  1,  0), (1,  1, -1),
                (1,  0,  1), (1,  0,  0), (1,  0, -1),
                (1, -1,  1), (1, -1,  0), (1, -1, -1),
            ]
            // F 面 (18-26)：z=1
            //   观察方向：从 +z 看，row 按 y 从 +1 到 -1，col 按 x 从 -1 到 +1
            let fPositions: [(Int,Int,Int)] = [
                (-1,  1, 1), (0,  1, 1), (1,  1, 1),
                (-1,  0, 1), (0,  0, 1), (1,  0, 1),
                (-1, -1, 1), (0, -1, 1), (1, -1, 1),
            ]
            // D 面 (27-35)：y=-1
            //   观察方向：从 -y 仰视，row 按 z 从 +1 到 -1，col 按 x 从 -1 到 +1
            //   (因为翻到下底面看，row 反转)
            let dPositions: [(Int,Int,Int)] = [
                (-1, -1,  1), (0, -1,  1), (1, -1,  1),
                (-1, -1,  0), (0, -1,  0), (1, -1,  0),
                (-1, -1, -1), (0, -1, -1), (1, -1, -1),
            ]
            // L 面 (36-44)：x=-1
            //   观察方向：从 -x 看，row 按 y 从 +1 到 -1，col 按 z 从 -1 到 +1
            let lPositions: [(Int,Int,Int)] = [
                (-1,  1, -1), (-1,  1,  0), (-1,  1,  1),
                (-1,  0, -1), (-1,  0,  0), (-1,  0,  1),
                (-1, -1, -1), (-1, -1,  0), (-1, -1,  1),
            ]
            // B 面 (45-53)：z=-1
            //   观察方向：从 -z 看，row 按 y 从 +1 到 -1，col 按 x 从 +1 到 -1
            let bPositions: [(Int,Int,Int)] = [
                ( 1,  1, -1), ( 0,  1, -1), (-1,  1, -1),
                ( 1,  0, -1), ( 0,  0, -1), (-1,  0, -1),
                ( 1, -1, -1), ( 0, -1, -1), (-1, -1, -1),
            ]

            let allFaces: [[(Int,Int,Int)]] = [uPositions, rPositions, fPositions, dPositions, lPositions, bPositions]
            for (faceIdx, positions) in allFaces.enumerated() {
                for (i, pos) in positions.enumerated() {
                    let faceletIdx = faceIdx * 9 + i
                    let colorId = facelets[faceletIdx]
                    guard colorId >= 0 && colorId < colorMap.count else { continue }
                    let (x, y, z) = pos
                    let key = "\(x)_\(y)_\(z)"
                    guard let node = cubelets[key],
                          let matIdx = matIndex(x: x, y: y, z: z) else { continue }
                    node.geometry?.materials[matIdx].diffuse.contents = colorMap[colorId]
                }
            }
        }
    }
}