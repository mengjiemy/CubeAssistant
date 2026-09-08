import Foundation
import SwiftUI
import SceneKit

/// 3D 魔方视图（SceneKit）—— 状态驱动渲染。
///
/// 渲染方式：每个 cubelet 是 1 个黑色内芯 SCNBox；每个可见外表面再单独贴
/// 一张 SCNPlane 作为 sticker。这样完全绕过 SCNBox 6-material 顺序在不同平台
/// 不一致的问题，reset / 打乱 / 转动都能精确覆盖每一面。
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

        // 光照：强环境光打底 + 主定向光 + 相机方向补光
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 1100
        ambient.light!.color = UIColor(white: 0.96, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 700
        key.light!.color = UIColor.white
        key.position = SCNVector3(4.5, 6, 6)
        key.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 400
        fill.light!.color = UIColor(white: 0.95, alpha: 1)
        fill.position = SCNVector3(-4, 3, 4)
        fill.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(fill)

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

        /// facelet 索引 → (x, y, z) 块坐标（权威，来自 Kociemba corner/edge facelet 定义）
        let faceMap: [(Int, Int, Int)] = [
            // U 面 (0-8)：y=+1
            (-1, 1, -1), (0, 1, -1), (1, 1, -1),
            (-1, 1,  0), (0, 1,  0), (1, 1,  0),
            (-1, 1,  1), (0, 1,  1), (1, 1,  1),
            // R 面 (9-17)：x=+1
            (1, 1,  1), (1, 1,  0), (1, 1, -1),
            (1, 0,  1), (1, 0,  0), (1, 0, -1),
            (1, -1,  1), (1, -1,  0), (1, -1, -1),
            // F 面 (18-26)：z=+1
            (-1,  1, 1), (0,  1, 1), (1,  1, 1),
            (-1,  0, 1), (0,  0, 1), (1,  0, 1),
            (-1, -1, 1), (0, -1, 1), (1, -1, 1),
            // D 面 (27-35)：y=-1
            (-1, -1,  1), (0, -1,  1), (1, -1,  1),
            (-1, -1,  0), (0, -1,  0), (1, -1,  0),
            (-1, -1, -1), (0, -1, -1), (1, -1, -1),
            // L 面 (36-44)：x=-1
            (-1,  1, -1), (-1,  1,  0), (-1,  1,  1),
            (-1,  0, -1), (-1,  0,  0), (-1,  0,  1),
            (-1, -1, -1), (-1, -1,  0), (-1, -1,  1),
            // B 面 (45-53)：z=-1
            (1,  1, -1), (0,  1, -1), (-1,  1, -1),
            (1,  0, -1), (0,  0, -1), (-1,  0, -1),
            (1, -1, -1), (0, -1, -1), (-1, -1, -1),
        ]

        /// 构建 26 个块（内芯 + 可见面 sticker）
        func buildCube(facelets: [Int]) {
            cubelets.values.forEach { $0.removeFromParentNode() }
            cubelets.removeAll()
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

        /// 创建一个 cubelet：黑色内芯 SCNBox + 最多 3 个 SCNPlane sticker 子节点
        func makeCubelet(x: Int, y: Int, z: Int) -> SCNNode {
            let core = SCNBox(width: 0.96, height: 0.96, length: 0.96, chamferRadius: 0.04)
            let coreMat = SCNMaterial()
            coreMat.diffuse.contents = innerColor
            coreMat.lightingModel = .physicallyBased
            coreMat.roughness.contents = 0.35
            coreMat.metalness.contents = 0.0
            core.materials = [coreMat]

            let node = SCNNode(geometry: core)
            node.castsShadow = true
            node.name = "cubelet_\(x)_\(y)_\(z)"

            // 为该块可能暴露的 6 个外表面各预建一个 sticker plane（默认透明黑，applyFacelets 再上色）
            if z == 1  { addSticker(to: node, dir: .pz) }
            if z == -1 { addSticker(to: node, dir: .nz) }
            if x == 1  { addSticker(to: node, dir: .px) }
            if x == -1 { addSticker(to: node, dir: .nx) }
            if y == 1  { addSticker(to: node, dir: .py) }
            if y == -1 { addSticker(to: node, dir: .ny) }

            return node
        }

        enum FaceDir: String {
            case px, nx, py, ny, pz, nz
        }

        /// 在 cubelet 节点上添加一个外表面 sticker plane
        private func addSticker(to parent: SCNNode, dir: FaceDir) {
            // sticker 比内芯面略小且往外推，避免被 chamfer 黑边遮挡显得"脏"
            let plane = SCNPlane(width: 0.82, height: 0.82)
            let mat = SCNMaterial()
            mat.diffuse.contents = innerColor
            mat.lightingModel = .physicallyBased
            mat.roughness.contents = 0.35
            mat.metalness.contents = 0.0
            plane.materials = [mat]

            let sticker = SCNNode(geometry: plane)
            sticker.name = "sticker_\(dir.rawValue)"

            let half: Float = 0.50
            switch dir {
            case .pz:
                sticker.position = SCNVector3(0, 0, half)
                sticker.eulerAngles = SCNVector3(0, 0, 0)
            case .nz:
                sticker.position = SCNVector3(0, 0, -half)
                sticker.eulerAngles = SCNVector3(0, Float.pi, 0)
            case .px:
                sticker.position = SCNVector3(half, 0, 0)
                sticker.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
            case .nx:
                sticker.position = SCNVector3(-half, 0, 0)
                sticker.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
            case .py:
                sticker.position = SCNVector3(0, half, 0)
                sticker.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            case .ny:
                sticker.position = SCNVector3(0, -half, 0)
                sticker.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            }

            parent.addChildNode(sticker)
        }

        /// facelet 索引 → 对应 sticker 所在面的方向
        private func dirForFaceletIndex(_ idx: Int) -> FaceDir {
            switch idx {
            case 0..<9:   return .py   // U
            case 9..<18:  return .px   // R
            case 18..<27: return .pz   // F
            case 27..<36: return .ny   // D
            case 36..<45: return .nx   // L
            default:      return .nz   // B
            }
        }

        /// 根据 facelets 给每个块可见面贴对应颜色
        func applyFacelets(_ facelets: [Int]) {
            guard facelets.count == 54 else { return }

            // 先全部 sticker 重置为内色（避免旧颜色残留）
            for node in cubelets.values {
                for child in node.childNodes where child.name?.hasPrefix("sticker_") == true {
                    child.geometry?.materials.first?.diffuse.contents = innerColor
                }
            }

            for (idx, colorId) in facelets.enumerated() {
                guard idx < faceMap.count else { break }
                guard colorId >= 0 && colorId < colorMap.count else { continue }
                let (x, y, z) = faceMap[idx]
                let key = "\(x)_\(y)_\(z)"
                guard let node = cubelets[key] else { continue }
                let dir = dirForFaceletIndex(idx)
                guard let sticker = node.childNode(withName: "sticker_\(dir.rawValue)", recursively: false) else { continue }
                sticker.geometry?.materials.first?.diffuse.contents = colorMap[colorId]
            }
        }
    }
}
