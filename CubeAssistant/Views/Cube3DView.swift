import Foundation
import SwiftUI
import SceneKit

/// 3D 魔方视图（SceneKit）—— 状态驱动渲染。
///
/// 渲染方式：每个 cubelet 是 1 个黑色 SCNBox（占位几何）+ 最多 6 个 SCNPlane
/// 子节点（贴在外侧六面上，颜色按 facelet 决定）。这种"盒子+贴片"模式完全绕开
/// 了 SCNBox 的 6-materials 索引歧义（chamferRadius 会让圆角面 material 错乱）。
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

        // 摄像机（被 allowsCameraControl 自动接管，但保留初始位置）
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.position = SCNVector3(4.5, 4.0, 6.5)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        context.coordinator.cameraNode = camera

        // 光照：环境光 + 定向光
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
        /// 块节点上的贴片子节点，按面方向索引（"px"/"nx"/"py"/"ny"/"pz"/"nz"）
        var stickers: [String: [String: SCNNode]] = [:]
        var lastFacelets: [Int] = []

        /// 标准魔方配色（stickerless）
        let colorMap: [UIColor] = [
            UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1), // 0 U 白
            UIColor(red: 0.86, green: 0.18, blue: 0.18, alpha: 1), // 1 R 红
            UIColor(red: 0.15, green: 0.62, blue: 0.30, alpha: 1), // 2 F 绿
            UIColor(red: 0.97, green: 0.82, blue: 0.12, alpha: 1), // 3 D 黄
            UIColor(red: 0.97, green: 0.55, blue: 0.12, alpha: 1), // 4 L 橙
            UIColor(red: 0.12, green: 0.36, blue: 0.78, alpha: 1), // 5 B 蓝
        ]

        /// 构建 26 个块（盒子+贴片）
        func buildCube(facelets: [Int]) {
            cubelets.values.forEach { $0.removeFromParentNode() }
            cubelets.removeAll()
            stickers.removeAll()
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

        func makeCubelet(x: Int, y: Int, z: Int) -> SCNNode {
            // 黑色盒子作为占位几何 + 边缘
            let boxGeo = SCNBox(width: 0.92, height: 0.92, length: 0.92, chamferRadius: 0.04)
            let blackMat = SCNMaterial()
            blackMat.diffuse.contents = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            blackMat.lightingModel = .physicallyBased
            blackMat.roughness.contents = 0.5
            boxGeo.materials = [blackMat, blackMat, blackMat, blackMat, blackMat, blackMat]
            let node = SCNNode(geometry: boxGeo)
            node.name = "cubelet_\(x)_\(y)_\(z)"

            // 在每个外露面上贴一张 SCNPlane（带颜色的贴片）
            let stickerGeo = SCNPlane(width: 0.84, height: 0.84)
            let initialColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            stickerGeo.firstMaterial?.diffuse.contents = initialColor
            stickerGeo.firstMaterial?.lightingModel = .physicallyBased
            stickerGeo.firstMaterial?.roughness.contents = 0.3

            var map: [String: SCNNode] = [:]
            let s = 0.46  // 贴片中心偏移（盒子边长 0.92 的一半）

            // +x 面（仅当 x == 1 才露）
            if x == 1 {
                let n = SCNNode(geometry: stickerGeo.copy() as! SCNGeometry)
                n.position = SCNVector3(s, 0, 0)
                n.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
                node.addChildNode(n)
                map["px"] = n
            }
            // -x 面
            if x == -1 {
                let n = SCNNode(geometry: stickerGeo.copy() as! SCNGeometry)
                n.position = SCNVector3(-s, 0, 0)
                n.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
                node.addChildNode(n)
                map["nx"] = n
            }
            // +y 面
            if y == 1 {
                let n = SCNNode(geometry: stickerGeo.copy() as! SCNGeometry)
                n.position = SCNVector3(0, s, 0)
                n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                node.addChildNode(n)
                map["py"] = n
            }
            // -y 面
            if y == -1 {
                let n = SCNNode(geometry: stickerGeo.copy() as! SCNGeometry)
                n.position = SCNVector3(0, -s, 0)
                n.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                node.addChildNode(n)
                map["ny"] = n
            }
            // +z 面
            if z == 1 {
                let n = SCNNode(geometry: stickerGeo.copy() as! SCNGeometry)
                n.position = SCNVector3(0, 0, s)
                node.addChildNode(n)
                map["pz"] = n
            }
            // -z 面
            if z == -1 {
                let n = SCNNode(geometry: stickerGeo.copy() as! SCNGeometry)
                n.position = SCNVector3(0, 0, -s)
                n.eulerAngles = SCNVector3(0, Float.pi, 0)
                node.addChildNode(n)
                map["nz"] = n
            }

            stickers["\(x)_\(y)_\(z)"] = map
            return node
        }

        /// 根据 facelets 给每个贴片赋色
        func applyFacelets(_ facelets: [Int]) {
            guard facelets.count == 54 else { return }
            // facelet 索引 → (块坐标, 块上的面方向 key)
            let faceMap: [(Int, Int, Int, String)] = [
                // U 面 (0-8)：y=1，row-major，row 按 z 从 -1 到 +1
                (-1, 1, 1, "py"), (0, 1, 1, "py"), (1, 1, 1, "py"),
                (-1, 1, 0, "py"), (0, 1, 0, "py"), (1, 1, 0, "py"),
                (-1, 1, -1, "py"), (0, 1, -1, "py"), (1, 1, -1, "py"),
                // R 面 (9-17)：x=1，row-major，row 按 y 从 +1 到 -1，col 按 z 从 +1 到 -1
                (1, 1, 1, "px"), (1, 1, 0, "px"), (1, 1, -1, "px"),
                (1, 0, 1, "px"), (1, 0, 0, "px"), (1, 0, -1, "px"),
                (1, -1, 1, "px"), (1, -1, 0, "px"), (1, -1, -1, "px"),
                // F 面 (18-26)：z=1
                (-1, 1, 1, "pz"), (0, 1, 1, "pz"), (1, 1, 1, "pz"),
                (-1, 0, 1, "pz"), (0, 0, 1, "pz"), (1, 0, 1, "pz"),
                (-1, -1, 1, "pz"), (0, -1, 1, "pz"), (1, -1, 1, "pz"),
                // D 面 (27-35)：y=-1
                (-1, -1, -1, "ny"), (0, -1, -1, "ny"), (1, -1, -1, "ny"),
                (-1, -1, 0, "ny"), (0, -1, 0, "ny"), (1, -1, 0, "ny"),
                (-1, -1, 1, "ny"), (0, -1, 1, "ny"), (1, -1, 1, "ny"),
                // L 面 (36-44)：x=-1
                (-1, 1, -1, "nx"), (-1, 1, 0, "nx"), (-1, 1, 1, "nx"),
                (-1, 0, -1, "nx"), (-1, 0, 0, "nx"), (-1, 0, 1, "nx"),
                (-1, -1, -1, "nx"), (-1, -1, 0, "nx"), (-1, -1, 1, "nx"),
                // B 面 (45-53)：z=-1
                (1, 1, -1, "nz"), (0, 1, -1, "nz"), (-1, 1, -1, "nz"),
                (1, 0, -1, "nz"), (0, 0, -1, "nz"), (-1, 0, -1, "nz"),
                (1, -1, -1, "nz"), (0, -1, -1, "nz"), (-1, -1, -1, "nz"),
            ]
            for (idx, colorId) in facelets.enumerated() {
                guard idx < faceMap.count else { break }
                let (x, y, z, face) = faceMap[idx]
                guard colorId >= 0 && colorId < colorMap.count else { continue }
                let key = "\(x)_\(y)_\(z)"
                guard let map = stickers[key], let node = map[face] else { continue }
                node.geometry?.firstMaterial?.diffuse.contents = colorMap[colorId]
            }
        }
    }
}