import Foundation
import SwiftUI
import SceneKit

/// 3D 魔方视图（SceneKit）。
/// - 以标准配色构建 26 个角/棱块（中心块不可见）。
/// - 通过对某一层的 9 个块绕面轴旋转 90°（带 pivot 重父化，保留世界变换）实现平滑转动动画。
/// - 与 `CubeSession` 绑定：当 `currentStep` 变化（前进/后退）时，自动播放对应解法步。
public struct Cube3DView: UIViewRepresentable {
    @ObservedObject var session: CubeSession

    public init(session: CubeSession) { self.session = session }

    public func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .clear
        context.coordinator.scene = SCNScene()
        scnView.scene = context.coordinator.scene
        context.coordinator.buildCube()
        // 摄像机
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(4.5, 4.5, 6.5)
        camera.look(at: SCNVector3(0, 0, 0))
        context.coordinator.scene.rootNode.addChildNode(camera)
        context.coordinator.scnView = scnView
        context.coordinator.lastStep = session.currentStep
        return scnView
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        let co = context.coordinator
        // 打乱 / 重置：整盘重建为复原态，再据 currentStep 把应播放的步补动画。
        if session.generation != co.generation {
            co.generation = session.generation
            co.buildCube()
            co.lastStep = 0
        }
        let target = session.currentStep
        let last = co.lastStep
        guard target != last else { return }
        let seq = session.playbackSequence
        if target > last {
            for i in last..<target {
                co.enqueue(seq[i])
            }
        } else {
            for i in stride(from: last - 1, through: target, by: -1) {
                co.enqueue(seq[i].inverted())
            }
        }
        co.lastStep = target
        co.pump()
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    public final class Coordinator {
        var scene: SCNScene!
        weak var scnView: SCNView?
        var cubelets: [SCNNode] = []
        var lastStep = 0
        var generation = 0
        var queue: [Move] = []
        var busy = false

        let colorMap: [Face: UIColor] = [
            .U: .white, .D: .yellow, .R: .systemRed,
            .L: .systemOrange, .F: .systemGreen, .B: .systemBlue,
        ]
        let innerColor = UIColor.darkGray

        func buildCube() {
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
        }

        func makeCubelet(x: Int, y: Int, z: Int) -> SCNNode {
            let geo = SCNBox(width: 0.95, height: 0.95, length: 0.95, chamferRadius: 0.08)
            // 材质顺序: +X,-X,+Y,-Y,+Z,-Z
            let mats: [UIColor] = [
                x == 1 ? colorMap[.R]! : innerColor,
                x == -1 ? colorMap[.L]! : innerColor,
                y == 1 ? colorMap[.U]! : innerColor,
                y == -1 ? colorMap[.D]! : innerColor,
                z == 1 ? colorMap[.F]! : innerColor,
                z == -1 ? colorMap[.B]! : innerColor,
            ]
            geo.materials = mats.map { color in
                let m = SCNMaterial()
                m.diffuse.contents = color
                m.specular.contents = UIColor(white: 0.3, alpha: 1)
                return m
            }
            return SCNNode(geometry: geo)
        }

        func enqueue(_ move: Move) { queue.append(move) }

        func pump() {
            guard !busy, let move = queue.first else { return }
            queue.removeFirst()
            busy = true
            animate(move) { [weak self] in
                self?.busy = false
                self?.pump()
            }
        }

        /// 绕对应面轴旋转该层的 9 个块 90°（带 pivot 重父化，保留世界变换）。
        func animate(_ move: Move, completion: @escaping () -> Void) {
            let axis: SCNVector3
            let layerTest: (SCNVector3) -> Bool
            var sign: Double = (move.turn == 3) ? -1 : 1   // turn==3 为逆时针(逆转)
            let turns: Double = (move.turn == 2) ? 2 : 1
            switch move.face {
            case .U: axis = SCNVector3(0, 1, 0); layerTest = { $0.y > 0.5 }; sign = (move.turn == 3) ? 1 : -1
            case .D: axis = SCNVector3(0, 1, 0); layerTest = { $0.y < -0.5 }; sign = (move.turn == 3) ? -1 : 1
            case .R: axis = SCNVector3(1, 0, 0); layerTest = { $0.x > 0.5 }; sign = (move.turn == 3) ? 1 : -1
            case .L: axis = SCNVector3(1, 0, 0); layerTest = { $0.x < -0.5 }; sign = (move.turn == 3) ? -1 : 1
            case .F: axis = SCNVector3(0, 0, 1); layerTest = { $0.z > 0.5 }; sign = (move.turn == 3) ? 1 : -1
            case .B: axis = SCNVector3(0, 0, 1); layerTest = { $0.z < -0.5 }; sign = (move.turn == 3) ? -1 : 1
            }
            let angle = sign * Double.pi / 2 * turns

            let layer = cubelets.filter { layerTest($0.position) }
            let pivot = SCNNode()
            scene.rootNode.addChildNode(pivot)
            for n in layer {
                let wt = n.worldTransform
                n.removeFromParentNode()
                pivot.addChildNode(n)
                n.transform = pivot.convertTransform(wt, from: nil)
            }
            let action = SCNAction.rotate(by: angle, around: axis, duration: 0.22)
            action.timingMode = .easeInEaseOut
            pivot.runAction(action) {
                for n in layer {
                    let wt = n.worldTransform
                    n.removeFromParentNode()
                    self.scene.rootNode.addChildNode(n)
                    n.transform = self.scene.rootNode.convertTransform(wt, from: nil)
                    n.position = SCNVector3(round(n.position.x), round(n.position.y), round(n.position.z))
                }
                pivot.removeFromParentNode()
                completion()
            }
        }
    }
}
