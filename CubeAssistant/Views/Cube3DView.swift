import Foundation
import SwiftUI
import SceneKit

/// 3D 魔方视图（SceneKit）—— 状态驱动渲染。
///
/// 与旧版「播放动画」不同，本版直接读取 `CubeModel` 的 facelet 状态，
/// 把 54 个贴纸颜色映射到 26 个角/棱块上，静态渲染当前状态。
/// 用户每转一步，`session.model` 变化 → `updateUIView` 重建贴纸颜色。
///
/// 支持单指拖动自由旋转视角（自定义手势，避免与动画竞态）。
struct Cube3DView: UIViewRepresentable {
    @ObservedObject var session: CubeSession

    init(session: CubeSession) { self.session = session }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        scnView.scene = scene
        context.coordinator.scene = scene
        context.coordinator.buildCube(facelets: session.cube.facelets)

        // 摄像机
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 40
        camera.position = SCNVector3(4.2, 4.0, 6.2)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        context.coordinator.cameraNode = camera

        // 光照：环境光 + 定向光（产生立体感）
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 500
        ambient.light!.color = UIColor(white: 0.85, alpha: 1)
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
        context.coordinator.lastFacelets = session.cube.facelets

        // 单指拖动旋转视角
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(pan)

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
        var cubelets: [SCNNode] = []
        var lastFacelets: [Int] = []

        /// 标准魔方配色（stickerless，与 facelet 颜色 id 严格对应）
        let colorMap: [UIColor] = [
            UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1), // 0 白 U
            UIColor(red: 0.85, green: 0.16, blue: 0.16, alpha: 1), // 1 红 R
            UIColor(red: 0.13, green: 0.62, blue: 0.28, alpha: 1), // 2 绿 F
            UIColor(red: 0.96, green: 0.82, blue: 0.12, alpha: 1), // 3 黄 D
            UIColor(red: 0.96, green: 0.55, blue: 0.12, alpha: 1), // 4 橙 L
            UIColor(red: 0.10, green: 0.32, blue: 0.72, alpha: 1), // 5 蓝 B
        ]
        let innerColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)

        /// 构建 26 个块（先全部贴内色，再由 facelets 覆盖可见面）
        func buildCube(facelets: [Int]) {
            cubelets.forEach { $0.removeFromParentNode() }
            cubelets.removeAll()
            for x in -1...1 {
                for y in -1...1 {
                    for z in -1...1 {
                        if x == 0 && y == 0 && z == 0 { continue }
                        let node = makeCubelet(x: x, y: y, z: z)
                        node.position = SCNVector3(Float(x), Float(y), Float(z))
                        scene.rootNode.addChildNode(node)
                        cubelets.append(node)
                    }
                }
            }
            applyFacelets(facelets)
        }

        func makeCubelet(x: Int, y: Int, z: Int) -> SCNNode {
            let geo = SCNBox(width: 0.96, height: 0.96, length: 0.96, chamferRadius: 0.09)
            // 6 面：+x R, -x L, +y U, -y D, +z F, -z B，先全部内色
            let mats: [UIColor] = [innerColor, innerColor, innerColor, innerColor, innerColor, innerColor]
            geo.materials = mats.map { color in
                let m = SCNMaterial()
                m.diffuse.contents = color
                m.lightingModel = .physicallyBased
                m.roughness.contents = 0.35
                m.metalness.contents = 0.0
                return m
            }
            let node = SCNNode(geometry: geo)
            node.castsShadow = true
            node.name = "cubelet_\(x)_\(y)_\(z)"
            return node
        }

        /// 依据 facelet 颜色，给每个块可见面贴对应颜色。
        ///
        /// facelet 索引约定：U0-8, R9-17, F18-26, D27-35, L36-44, B45-53。
        /// 每个面的 9 个 facelet 排列：row-major，行 0=顶部（y=+1 侧），行 2=底部。
        /// 我们据此定位该面每个贴纸对应的块坐标。
        func applyFacelets(_ facelets: [Int]) {
            guard facelets.count == 54 else { return }
            // 面 → 该面 9 个贴纸对应的 (x,y,z) 块坐标
            // U 面（y=+1）：facelet 0..8，z 从上到下 = -1,0,1，x 从左到右 = -1,0,1
            let faceCoords: [(Int, Int, Int)] = [
                // U 面 (facelet 0-8)：row-major，row 按 z 从 -1(前)到 +1(后)
                (-1, 1, 1), (0, 1, 1), (1, 1, 1),
                (-1, 1, 0), (0, 1, 0), (1, 1, 0),
                (-1, 1, -1), (0, 1, -1), (1, 1, -1),
                // R 面 (9-17)：x=+1
                (1, 1, 1), (1, 1, 0), (1, 1, -1),
                (1, 0, 1), (1, 0, 0), (1, 0, -1),
                (1, -1, 1), (1, -1, 0), (1, -1, -1),
                // F 面 (18-26)：z=+1
                (-1, 1, 1), (0, 1, 1), (1, 1, 1),
                (-1, 0, 1), (0, 0, 1), (1, 0, 1),
                (-1, -1, 1), (0, -1, 1), (1, -1, 1),
                // D 面 (27-35)：y=-1
                (-1, -1, -1), (0, -1, -1), (1, -1, -1),
                (-1, -1, 0), (0, -1, 0), (1, -1, 0),
                (-1, -1, 1), (0, -1, 1), (1, -1, 1),
                // L 面 (36-44)：x=-1
                (-1, 1, -1), (-1, 1, 0), (-1, 1, 1),
                (-1, 0, -1), (-1, 0, 0), (-1, 0, 1),
                (-1, -1, -1), (-1, -1, 0), (-1, -1, 1),
                // B 面 (45-53)：z=-1
                (1, 1, -1), (0, 1, -1), (-1, 1, -1),
                (1, 0, -1), (0, 0, -1), (-1, 0, -1),
                (1, -1, -1), (0, -1, -1), (-1, -1, -1),
            ]
            for (idx, colorId) in facelets.enumerated() {
                guard idx < faceCoords.count else { break }
                let (x, y, z) = faceCoords[idx]
                let node = cubelets.first { $0.position.x == Float(x) && $0.position.y == Float(y) && $0.position.z == Float(z) }
                guard let n = node, let geo = n.geometry else { continue }
                let matIndex = faceMaterialIndex(x: x, y: y, z: z)
                guard matIndex >= 0, matIndex < geo.materials.count else { continue }
                geo.materials[matIndex].diffuse.contents = colorMap[colorId]
            }
        }

        /// 块坐标 → 该贴纸在 SCNBox 材料数组里的下标（+x,-x,+y,-y,+z,-z）
        private func faceMaterialIndex(x: Int, y: Int, z: Int) -> Int {
            // 依据贴纸所在面判断
            if x == 1 { return 0 }   // +x = R
            if x == -1 { return 1 }  // -x = L
            if y == 1 { return 2 }   // +y = U
            if y == -1 { return 3 }  // -y = D
            if z == 1 { return 4 }   // +z = F
            if z == -1 { return 5 }  // -z = B
            return -1
        }

        // MARK: - 手势：单指拖动旋转视角
        private var lastPanLocation: CGPoint = .zero

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let camera = cameraNode else { return }
            let translation = gesture.translation(in: scnView)
            switch gesture.state {
            case .began:
                lastPanLocation = .zero
            case .changed:
                let dx = Float(translation.x - lastPanLocation.x)
                let dy = Float(translation.y - lastPanLocation.y)
                let yaw = SCNAction.rotate(by: CGFloat(dx) * 0.01, around: SCNVector3(0, 1, 0), duration: 0)
                camera.runAction(yaw)
                let pitch = SCNAction.rotate(by: CGFloat(dy) * 0.01, around: SCNVector3(1, 0, 0), duration: 0)
                camera.runAction(pitch)
                lastPanLocation = translation
            default:
                break
            }
        }
    }
}
