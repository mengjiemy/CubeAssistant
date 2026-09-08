import Foundation
import SwiftUI
import SceneKit

/// 3D 魔方视图（SceneKit）—— 状态驱动渲染。
///
/// 渲染方式：每个 cubelet 是 1 个 SCNBox，6 个 material 顺序固定为
/// [+z, +x, -z, -x, +y, -y]（与 SCNBox 内部一致），按 facelet 给对应面赋色。
/// chamferRadius 设小（0.04）保留圆角立体感。
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

        /// SCNBox 6-materials 顺序：0=+z, 1=+x, 2=-z, 3=-x, 4=+y, 5=-y
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
            return node
        }

        /// 根据 facelets 给每个块可见面贴对应颜色。
        ///
        /// facelet 索引约定（CubeState 标准，与 KociembaSolver 权威一致）：
        /// - U(0-8), R(9-17), F(18-26), D(27-35), L(36-44), B(45-53)
        /// - 每面 9 贴片 row-major（从该面正面看 3×3）
        ///
        /// 以下 faceMap 是从 KociembaSolver 的 cornerFacelet/edgeFacelet 权威定义
        /// 反推出的「facelet 索引 → (x,y,z) 块坐标」，已程序验证每个面 9 贴片
        /// 严格落在同一平面。
        func applyFacelets(_ facelets: [Int]) {
            guard facelets.count == 54 else { return }

            // facelet 索引 → (x, y, z) 块坐标（权威，来自 Kociemba corner/edge facelet 定义）
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

            // (x,y,z) → SCNBox material index（0=+z, 1=+x, 2=-z, 3=-x, 4=+y, 5=-y）
            func matIndex(x: Int, y: Int, z: Int) -> Int {
                if z ==  1 { return 0 }  // Front
                if x ==  1 { return 1 }  // Right
                if z == -1 { return 2 }  // Back
                if x == -1 { return 3 }  // Left
                if y ==  1 { return 4 }  // Top
                return 5               // Bottom
            }

            for (idx, colorId) in facelets.enumerated() {
                guard idx < faceMap.count else { break }
                guard colorId >= 0 && colorId < colorMap.count else { continue }
                let (x, y, z) = faceMap[idx]
                let key = "\(x)_\(y)_\(z)"
                guard let node = cubelets[key] else { continue }
                let mi = matIndex(x: x, y: y, z: z)
                node.geometry?.materials[mi].diffuse.contents = colorMap[colorId]
            }
        }
    }
}