import Foundation
import SwiftUI
import SceneKit

/// 3D 魔方视图（SceneKit）—— 状态驱动渲染。
///
/// 渲染方式：每个 cubelet 是 1 个黑色内芯 SCNBox；每个可见外表面再单独贴
/// 一张 SCNPlane 作为 sticker。这样完全绕过 SCNBox 6-material 顺序在不同平台
/// 不一致的问题，reset / 打乱 / 转动都能精确覆盖每一面。
///
/// 视角控制：手势模式「未选中层」时 = 允许单指 pan 旋转视角（SCNView 内置
/// allowsCameraControl）。一旦选中某层（9 种层之一），立刻锁定视角（关闭
/// allowsCameraControl），只能滑动转该层顺/逆；再次点击同一层或空白处取消选中。
struct Cube3DView: UIViewRepresentable {
    @ObservedObject var session: CubeSession

    /// 可选：覆盖渲染的 facelets（学习页内嵌魔方用，展示「轨道中间态」而非 session.cube）。
    /// 为 nil 时按 session.cube 渲染（主页默认）。
    var overrideFacelets: [Int]? = nil
    /// 渲染阶数：3=3阶(26块/每面9格)，2=2阶(8块/每面4格)。
    /// 默认取 session 当前阶数；独立传入时(如无 session 的场景)可显式指定。
    var order: Int = 3

    /// 当前选中的层（手势模式：点击魔方后写入）。
    /// nil = 未选中（相机可自由旋转）。
    var selectedLayer: SelectedLayer? = nil

    /// 手势交互回调：点击某个 sticker 后选中其所在层。
    var onLayerSelected: ((SelectedLayer) -> Void)? = nil
    /// 手势交互回调：用户取消选中（点击空白/再次点击同一层）。
    var onLayerDeselected: (() -> Void)? = nil
    /// 手势交互回调：滑动触发一次转动请求。
    var onTurnRequest: ((Move) -> Void)? = nil

    init(session: CubeSession,
         overrideFacelets: [Int]? = nil,
         order: Int? = nil,
         selectedLayer: SelectedLayer? = nil,
         onLayerSelected: ((SelectedLayer) -> Void)? = nil,
         onLayerDeselected: (() -> Void)? = nil,
         onTurnRequest: ((Move) -> Void)? = nil) {
        self.session = session
        self.overrideFacelets = overrideFacelets
        self.order = order ?? session.order
        self.selectedLayer = selectedLayer
        self.onLayerSelected = onLayerSelected
        self.onLayerDeselected = onLayerDeselected
        self.onTurnRequest = onTurnRequest
    }

    /// 一个层切片：轴 + 切片坐标 + 命中面法向（决定滑动方向观察基准）。
    struct SelectedLayer: Equatable, Hashable {
        enum Axis: Int, Equatable, Hashable { case x = 0, y = 1, z = 2 }
        let axis: Axis
        let slice: Int       // -1 (L/D/B), 0 (M/E/S 中层), +1 (R/U/F)
        let normalFace: Face // 命中的外层 face（用于滑动方向观察基准；2 阶/高阶退化用）

        /// 由外层 face 构造（高阶/按钮模式用）。
        init(outer face: Face) {
            switch face {
            case .U: self.init(axis: .y, slice:  1, normalFace: .U)
            case .D: self.init(axis: .y, slice: -1, normalFace: .D)
            case .R: self.init(axis: .x, slice:  1, normalFace: .R)
            case .L: self.init(axis: .x, slice: -1, normalFace: .L)
            case .F: self.init(axis: .z, slice:  1, normalFace: .F)
            case .B: self.init(axis: .z, slice: -1, normalFace: .B)
            }
        }

        /// 由 (axis, slice, normalFace) 构造
        init(axis: Axis, slice: Int, normalFace: Face) {
            self.axis = axis
            self.slice = slice
            self.normalFace = normalFace
        }

        /// 该层对应的「基础 move」（CW 90°）。
        /// 例如：x 轴 +1 层 → R，x 轴 0 层（中层）→ M，y 轴 +1 层 → U
        var baseMove: Move {
            let ax = self.axis
            let sl = self.slice
            switch ax {
            case .x:
                switch sl {
                case  1: return .R
                case  0: return .M
                case -1: return .L
                default: return .R
                }
            case .y:
                switch sl {
                case  1: return .U
                case  0: return .E
                case -1: return .D
                default: return .U
                }
            case .z:
                switch sl {
                case  1: return .F
                case  0: return .S
                case -1: return .B
                default: return .F
                }
            }
        }

        /// 标准显示字符串，如 "R", "M", "U", "E2"
        func notation(turn: Int) -> String {
            let base = baseMove.notation.replacingOccurrences(of: "'", with: "")
                                    .replacingOccurrences(of: "2", with: "")
            switch turn {
            case 1: return base
            case 2: return base + "2"
            default: return base + "'"
            }
        }
    }

    /// 解析本次要渲染的 facelets：优先 override；否则按当前阶数取 session 对应状态。
    private func resolveFacelets() -> [Int] {
        if let o = overrideFacelets { return o }
        return session.renderedFacelets()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.defaultCameraController.interactionMode = .orbitAngleMapping
        scnView.defaultCameraController.inertiaEnabled = true

        let scene = SCNScene()
        scnView.scene = scene
        let co = context.coordinator
        co.scene = scene
        co.onLayerSelected = onLayerSelected
        co.onLayerDeselected = onLayerDeselected
        co.onTurnRequest = onTurnRequest
        let initial = resolveFacelets()
        if order == 2 {
            co.currentOrder = 2
            co.buildCube2x2(facelets: initial)
        } else if order >= 4 {
            co.currentOrder = order
            co.buildCubeN(order: order, facelets: initial)
        } else {
            co.currentOrder = 3
            co.buildCube(facelets: initial)
        }
        co.lastFacelets = initial

        // 默认相机节点（保留作「reset 模板」）。
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        let distScale: Float = Self.cameraScale(for: order)
        camera.position = SCNVector3(4.5 * distScale, 4.0 * distScale, 6.5 * distScale)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        co.defaultCameraNode = camera
        scnView.pointOfView = camera

        // 光照
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

        co.scnView = scnView

        // 手势识别器（仅在提供回调时启用）
        if onLayerSelected != nil || onTurnRequest != nil {
            let tap = UITapGestureRecognizer(target: co, action: #selector(Coordinator.handleTap(_:)))
            tap.delegate = co
            scnView.addGestureRecognizer(tap)
            co.tapGesture = tap

            let pan = UIPanGestureRecognizer(target: co, action: #selector(Coordinator.handlePan(_:)))
            pan.delegate = co
            pan.maximumNumberOfTouches = 1
            scnView.addGestureRecognizer(pan)
            co.panGesture = pan
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let co = context.coordinator

        // 相机复位
        if session.cameraResetToken != co.lastCameraResetToken {
            co.lastCameraResetToken = session.cameraResetToken
            co.resetCamera()
        }

        // 阶数变化：重建 cube
        if order != co.currentOrder {
            let distScale = Self.cameraScale(for: order)
            co.defaultCameraNode?.position = SCNVector3(4.5 * distScale, 4.0 * distScale, 6.5 * distScale)
            co.defaultCameraNode?.look(at: SCNVector3(0, 0, 0))
            let f = resolveFacelets()
            if order == 2 {
                co.currentOrder = 2
                co.buildCube2x2(facelets: f)
            } else if order >= 4 {
                co.currentOrder = order
                co.buildCubeN(order: order, facelets: f)
            } else {
                co.currentOrder = 3
                co.buildCube(facelets: f)
            }
            co.lastFacelets = f
            co.resetCamera()
            return
        }

        // 选中层变化：重画高亮 + 锁定/解锁相机
        if selectedLayer != co.currentHighlightLayer {
            co.applyHighlight(layer: selectedLayer)
            // 选中时锁定相机（不允许单指 pan 旋转视角），取消选中时恢复
            let shouldLock = (selectedLayer != nil)
            if uiView.allowsCameraControl == shouldLock {
                uiView.allowsCameraControl = !shouldLock
            }
        }

        // 转动后重画（facelets 变了）
        let facelets = resolveFacelets()
        guard facelets != co.lastFacelets else { return }
        co.lastFacelets = facelets
        if co.currentOrder == 2 {
            co.applyFacelets2x2(facelets)
        } else if co.currentOrder >= 4 {
            co.applyFaceletsN(facelets)
        } else {
            co.applyFacelets(facelets)
        }
        // facelets 变化后保持高亮（在 applyFacelets 之后重画一次以防覆盖）
        if selectedLayer != nil {
            co.applyHighlight(layer: selectedLayer)
        }
    }

    /// 相机距离随阶数缩放
    static func cameraScale(for order: Int) -> Float {
        if order == 2 { return 0.52 }
        if order >= 4 { return Float(order) / 3.0 }
        return 1.0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var scene: SCNScene!
        weak var scnView: SCNView?
        weak var defaultCameraNode: SCNNode?
        var cubelets: [String: SCNNode] = [:]
        var cubelets2x2: [String: SCNNode] = [:]
        var lastFacelets: [Int] = []
        var lastCameraResetToken: Int = 0
        var currentOrder = 3
        var currentHighlightLayer: SelectedLayer? = nil
        var highlightNodes: [String: SCNNode] = [:]
        // 高阶
        var cubeNAllNodes: [SCNNode] = []
        var cubeNStickers: [Int: SCNNode] = [:]
        // 回调
        var onLayerSelected: ((SelectedLayer) -> Void)?
        var onLayerDeselected: (() -> Void)?
        var onTurnRequest: ((Move) -> Void)?
        // 手势
        weak var tapGesture: UITapGestureRecognizer?
        weak var panGesture: UIPanGestureRecognizer?
        private var panStartLayer: SelectedLayer? = nil

        func resetCamera() {
            guard let scnView = scnView, let defaultCam = defaultCameraNode else { return }
            scnView.defaultCameraController.stopInertia()
            scnView.pointOfView = defaultCam
            scnView.allowsCameraControl = false
            scnView.allowsCameraControl = true
            scnView.defaultCameraController.interactionMode = .orbitAngleMapping
            scnView.defaultCameraController.inertiaEnabled = true
        }

        // MARK: - 手势

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)

            // 1) 命中魔方节点 → 算出 SelectedLayer
            if let hit = hitInfo(point: point, in: scnView) {
                let layer = layerForHit(hit)
                // 如果点中同一层 → 取消选中
                if layer == currentHighlightLayer {
                    onLayerDeselected?()
                } else {
                    onLayerSelected?(layer)
                }
            } else {
                // 点空白 → 取消选中
                if currentHighlightLayer != nil {
                    onLayerDeselected?()
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)

            switch gesture.state {
            case .began:
                // 没选中层 → 滑动交给相机控制（SCNView 内置）；不响应转层
                if currentHighlightLayer == nil {
                    panStartLayer = nil
                    return
                }
                // 已选中层：起点必须是同一层（避免拖出层外时误转）
                if let hit = hitInfo(point: point, in: scnView) {
                    let layer = layerForHit(hit)
                    if layer == currentHighlightLayer {
                        panStartLayer = layer
                        gesture.setTranslation(.zero, in: scnView)
                    } else {
                        panStartLayer = nil
                    }
                } else {
                    panStartLayer = nil
                }
            case .ended, .cancelled:
                defer { panStartLayer = nil }
                guard let start = panStartLayer else { return }
                let translation = gesture.translation(in: scnView)
                let dx = translation.x
                let dy = translation.y
                guard max(abs(dx), abs(dy)) > 24 else { return }
                guard let move = moveForSwipe(startLayer: start, dx: dx, dy: dy) else { return }
                onTurnRequest?(move)
            default:
                break
            }
        }

        /// 标准魔方配色（与 facelet 颜色 id 严格对应）
        let colorMap: [UIColor] = [
            UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1), // 0 U 白
            UIColor(red: 0.88, green: 0.18, blue: 0.18, alpha: 1), // 1 R 红
            UIColor(red: 0.18, green: 0.62, blue: 0.30, alpha: 1), // 2 F 绿
            UIColor(red: 0.97, green: 0.82, blue: 0.15, alpha: 1), // 3 D 黄
            UIColor(red: 0.97, green: 0.55, blue: 0.12, alpha: 1), // 4 L 橙
            UIColor(red: 0.15, green: 0.36, blue: 0.78, alpha: 1), // 5 B 蓝
        ]
        let innerColor = UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)

        /// 高亮蓝（iOS 系统蓝）
        let highlightColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)

        /// 3 阶 facelet 索引 → (x, y, z) 块坐标（与 Kociemba faceMap 一致）
        let faceMap: [(Int, Int, Int)] = [
            // U 面 (0-8)：y=+1
            (-1, 1, -1), (0, 1, -1), (1, 1, -1),
            (-1, 1,  0), (0, 1,  0), (1, 1,  0),
            (-1, 1,  1), (0, 1,  1), (1, 1,  1),
            // R 面 (9-17)：x=+1
            (1, 1,  1), (1, 1,  0), (1, 1, -1),
            (1, 0,  1), (1, 0,  0), (1, 0, -1),
            (1, -1, 1), (1, -1, 0), (1, -1, -1),
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

        /// 统一拆除所有阶数的魔方节点
        func removeAllCubeNodes() {
            cubelets.values.forEach { $0.removeFromParentNode() }
            cubelets.removeAll()
            cubelets2x2.values.forEach { $0.removeFromParentNode() }
            cubelets2x2.removeAll()
            cubeNAllNodes.forEach { $0.removeFromParentNode() }
            cubeNAllNodes.removeAll()
            cubeNStickers.removeAll()
            highlightNodes.forEach { $0.value.removeFromParentNode() }
            highlightNodes.removeAll()
        }

        // MARK: - 3 阶构建 / 上色

        func buildCube(facelets: [Int]) {
            removeAllCubeNodes()
            let h = CubeGeometry.three.coordHalf
            for x in -h...h {
                for y in -h...h {
                    for z in -h...h {
                        if !CubeGeometry.three.isVisibleCubelet(x: x, y: y, z: z) { continue }
                        let key = "\(x)_\(y)_\(z)"
                        let node = makeCubelet(x: x, y: y, z: z)
                        node.position = SCNVector3(Float(x), Float(y), Float(z))
                        scene.rootNode.addChildNode(node)
                        cubelets[key] = node
                    }
                }
            }
            applyFacelets(facelets)
            if let l = currentHighlightLayer { applyHighlight(layer: l) }
        }

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

        private func addSticker(to parent: SCNNode, dir: FaceDir) {
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
            case 0..<9:   return .py
            case 9..<18:  return .px
            case 18..<27: return .pz
            case 27..<36: return .ny
            case 36..<45: return .nx
            default:      return .nz
            }
        }

        func applyFacelets(_ facelets: [Int]) {
            guard facelets.count == CubeGeometry.three.totalFacelets else { return }

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

        // MARK: - 2 阶构建 / 上色

        private func key2x2(_ x3: Int, _ y3: Int, _ z3: Int) -> String {
            let xs = (x3 >= 0 ? "+" : "-") + String(abs(x3) * 5)
            let ys = (y3 >= 0 ? "+" : "-") + String(abs(y3) * 5)
            let zs = (z3 >= 0 ? "+" : "-") + String(abs(z3) * 5)
            return "\(xs)_\(ys)_\(zs)"
        }

        func buildCube2x2(facelets: [Int]) {
            removeAllCubeNodes()
            let cornerSigns: [(Int, Int, Int)] = [
                (-1, -1, -1), (1, -1, -1), (-1, 1, -1), (1, 1, -1),
                (-1, -1,  1), (1, -1,  1), (-1, 1,  1), (1, 1,  1),
            ]
            for (sx, sy, sz) in cornerSigns {
                let key = key2x2(sx, sy, sz)
                let node = makeCubelet2x2(sx: sx, sy: sy, sz: sz)
                node.position = SCNVector3(Float(sx) * 0.5, Float(sy) * 0.5, Float(sz) * 0.5)
                scene.rootNode.addChildNode(node)
                cubelets2x2[key] = node
            }
            applyFacelets2x2(facelets)
            if let l = currentHighlightLayer { applyHighlight(layer: l) }
        }

        private func makeCubelet2x2(sx: Int, sy: Int, sz: Int) -> SCNNode {
            let core = SCNBox(width: 0.94, height: 0.94, length: 0.94, chamferRadius: 0.04)
            let coreMat = SCNMaterial()
            coreMat.diffuse.contents = innerColor
            coreMat.lightingModel = .physicallyBased
            coreMat.roughness.contents = 0.35
            coreMat.metalness.contents = 0.0
            core.materials = [coreMat]
            let node = SCNNode(geometry: core)
            node.castsShadow = true
            node.name = "cubelet2_\(key2x2(sx, sy, sz))"
            if sx > 0 { addSticker(to: node, dir: .px) }
            if sx < 0 { addSticker(to: node, dir: .nx) }
            if sy > 0 { addSticker(to: node, dir: .py) }
            if sy < 0 { addSticker(to: node, dir: .ny) }
            if sz > 0 { addSticker(to: node, dir: .pz) }
            if sz < 0 { addSticker(to: node, dir: .nz) }
            return node
        }

        func applyFacelets2x2(_ facelets: [Int]) {
            guard facelets.count == Cube2x2Geometry.totalFacelets else { return }
            for node in cubelets2x2.values {
                for child in node.childNodes where child.name?.hasPrefix("sticker_") == true {
                    child.geometry?.materials.first?.diffuse.contents = innerColor
                }
            }
            for (i, colorId) in facelets.enumerated() {
                guard colorId >= 0 && colorId < colorMap.count else { continue }
                let idx3 = Cube2x2.to3x3Index(i)
                guard idx3 < faceMap.count else { continue }
                let (x3, y3, z3) = faceMap[idx3]
                let key = key2x2(x3, y3, z3)
                guard let node = cubelets2x2[key] else { continue }
                let dir = dirForFaceletIndex(idx3)
                guard let sticker = node.childNode(withName: "sticker_\(dir.rawValue)", recursively: false) else { continue }
                sticker.geometry?.materials.first?.diffuse.contents = colorMap[colorId]
            }
        }

        // MARK: - 高阶（4~10 阶）构建 / 上色

        func buildCubeN(order: Int, facelets: [Int]) {
            removeAllCubeNodes()

            let N = order
            let halfExtent = Float(N) / 2.0
            let core = SCNBox(width: CGFloat(N), height: CGFloat(N), length: CGFloat(N), chamferRadius: 0.02)
            let coreMat = SCNMaterial()
            coreMat.diffuse.contents = UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
            coreMat.lightingModel = .physicallyBased
            coreMat.roughness.contents = 0.9
            coreMat.metalness.contents = 0.0
            core.materials = [coreMat]
            let coreNode = SCNNode(geometry: core)
            coreNode.name = "cubeN_core"
            scene.rootNode.addChildNode(coreNode)
            cubeNAllNodes.append(coreNode)

            let stickerSize: Float = 0.88
            let normalDistance = halfExtent + 0.02
            let halfGrid = Float(N - 1) / 2.0
            let faces: [(dir: (Float, Float, Float), axA: (Float, Float, Float), axB: (Float, Float, Float))] = [
                (dir: (0, 1, 0), axA: (1, 0, 0), axB: (0, 0, -1)),    // U
                (dir: (1, 0, 0), axA: (0, 0, 1), axB: (0, -1, 0)),    // R
                (dir: (0, 0, 1), axA: (1, 0, 0), axB: (0, -1, 0)),    // F
                (dir: (0, -1, 0), axA: (1, 0, 0), axB: (0, 0, -1)),   // D
                (dir: (-1, 0, 0), axA: (0, 0, 1), axB: (0, 1, 0)),    // L
                (dir: (0, 0, -1), axA: (-1, 0, 0), axB: (0, 1, 0)),   // B
            ]
            let perFace = N * N
            for f in 0..<6 {
                let spec = faces[f]
                for r in 0..<N {
                    for c in 0..<N {
                        let idx = f * perFace + r * N + c
                        let plane = SCNPlane(width: CGFloat(stickerSize), height: CGFloat(stickerSize))
                        let mat = SCNMaterial()
                        mat.diffuse.contents = innerColor
                        mat.lightingModel = .physicallyBased
                        mat.roughness.contents = 0.35
                        mat.metalness.contents = 0.0
                        mat.isDoubleSided = true
                        plane.materials = [mat]
                        let node = SCNNode(geometry: plane)
                        node.name = "stickerN_\(idx)"
                        let u = Float(c) - halfGrid
                        let v = Float(r) - halfGrid
                        let pos = SCNVector3(
                            spec.dir.0 * normalDistance + spec.axA.0 * u + spec.axB.0 * v,
                            spec.dir.1 * normalDistance + spec.axA.1 * u + spec.axB.1 * v,
                            spec.dir.2 * normalDistance + spec.axA.2 * u + spec.axB.2 * v)
                        node.position = pos
                        node.look(at: SCNVector3(spec.dir.0 * (halfExtent * 3),
                                                 spec.dir.1 * (halfExtent * 3),
                                                 spec.dir.2 * (halfExtent * 3)))
                        scene.rootNode.addChildNode(node)
                        cubeNAllNodes.append(node)
                        cubeNStickers[idx] = node
                    }
                }
            }
            applyFaceletsN(facelets)
            if let l = currentHighlightLayer { applyHighlight(layer: l) }
        }

        func applyFaceletsN(_ facelets: [Int]) {
            for (idx, node) in cubeNStickers {
                guard idx < facelets.count else { continue }
                let colorId = facelets[idx]
                guard colorId >= 0 && colorId < colorMap.count else { continue }
                node.geometry?.materials.first?.diffuse.contents = colorMap[colorId]
            }
        }

        // MARK: - 命中解析 / 选层映射

        /// 一次命中信息：sticker 节点 + 在魔方上的位置（用于选层）
        struct HitInfo {
            let stickerNode: SCNNode      // 命中的 sticker 节点
            let cubeletNode: SCNNode      // 该 sticker 所属 cubelet
            let cubeletCoord: (Int, Int, Int)?   // 3 阶坐标；高阶/2 阶退化用
            let face: Face                // 该 sticker 所在外层 face
            /// 命中的外层（U/D/L/R/F/B）
            var outerFace: Face { face }
        }

        /// 解析一次 hitTest：找最近的可识别 sticker + 它所在的外层 face。
        private func hitInfo(point: CGPoint, in scnView: SCNView) -> HitInfo? {
            let hits = scnView.hitTest(point, options: [SCNHitTestOption.boundingBoxOnly: false])
            guard let node = hits.first?.node else { return nil }

            // 高阶 sticker 节点 stickerN_<idx>
            if let name = node.name, name.hasPrefix("stickerN_"),
               let idx = Int(name.dropFirst("stickerN_".count)) {
                let faceIdx = idx / (currentOrder * currentOrder)
                let f = Face(rawValue: faceIdx) ?? .U
                // cubelet coord 不可用（高阶无 per-cubelet 模型），按 face 构造 layer
                return HitInfo(stickerNode: node, cubeletNode: node,
                               cubeletCoord: nil, face: f)
            }

            // 2/3 阶 sticker 节点 sticker_<dir>
            if let name = node.name, name.hasPrefix("sticker_") {
                let dirRaw = String(name.dropFirst("sticker_".count))
                if let dir = FaceDir(rawValue: dirRaw), let cubelet = node.parent {
                    let face = faceFor(dir: dir)
                    let coord = parseCubeletCoord(from: cubelet.name ?? "")
                    return HitInfo(stickerNode: node, cubeletNode: cubelet,
                                   cubeletCoord: coord, face: face)
                }
            }

            // 命中到内芯 → 找该 cubelet 的最近 sticker（向上找 parent）
            if let cubelet = node.parent,
               let sticker = cubelet.childNodes.first(where: { $0.name?.hasPrefix("sticker") == true }) {
                if let name = sticker.name {
                    if name.hasPrefix("stickerN_"), let idx = Int(name.dropFirst("stickerN_".count)) {
                        let faceIdx = idx / (currentOrder * currentOrder)
                        return HitInfo(stickerNode: sticker, cubeletNode: cubelet,
                                       cubeletCoord: nil, face: Face(rawValue: faceIdx) ?? .U)
                    }
                    if name.hasPrefix("sticker_") {
                        let dirRaw = String(name.dropFirst("sticker_".count))
                        if let dir = FaceDir(rawValue: dirRaw) {
                            let face = faceFor(dir: dir)
                            let coord = parseCubeletCoord(from: cubelet.name ?? "")
                            return HitInfo(stickerNode: sticker, cubeletNode: cubelet,
                                           cubeletCoord: coord, face: face)
                        }
                    }
                }
            }

            return nil
        }

        private func faceFor(dir: FaceDir) -> Face {
            switch dir {
            case .py: return .U
            case .ny: return .D
            case .nx: return .L
            case .px: return .R
            case .pz: return .F
            case .nz: return .B
            }
        }

        /// 解析 cubelet 名 "cubelet_x_y_z" 或 "cubelet2_+5_-5_+5" → (x,y,z)
        private func parseCubeletCoord(from name: String) -> (Int, Int, Int)? {
            let parts = name.split(separator: "_")
            // cubelet_x_y_z (3 parts: x, y, z)
            // cubelet2_+5_-5_+5 (5 parts: prefix "cubelet2", "+5", "-5", "+5")
            guard parts.count >= 4 else { return nil }
            let skipFirst = parts[0].hasPrefix("cubelet2") ? 2 : 1
            let coords = parts.dropFirst(skipFirst).prefix(3).compactMap { Int($0) }
            guard coords.count == 3 else { return nil }
            return (coords[0], coords[1], coords[2])
        }

        /// 把命中点映射到 9 种 SelectedLayer 之一
        private func layerForHit(_ hit: HitInfo) -> SelectedLayer {
            let normalFace = hit.face

            // 高阶（无 per-cubelet coord）：只能选外层 6 个
            if currentOrder >= 4 {
                return SelectedLayer(outer: normalFace)
            }

            // 2 阶：每个 cubelet 暴露 3 个 sticker，没有「内层」概念 → 选外层 6 个之一
            // 2 阶外层：选 normalFace 对应的 4 stickers（每角块的那一面）
            if currentOrder == 2 {
                return SelectedLayer(outer: normalFace)
            }

            // 3 阶：用 cubelet 坐标确定 axis + slice
            guard let (x, y, z) = hit.cubeletCoord else {
                return SelectedLayer(outer: normalFace)
            }

            // 确定该 sticker 所在「轴」= sticker 法向所在的轴
            // sticker 法向 = hit.face 决定：U/D → y 轴；R/L → x 轴；F/B → z 轴
            // 该轴上 sticker 的 slice = 该 cubelet 在该轴上的坐标
            let axis: SelectedLayer.Axis
            let slice: Int
            switch normalFace {
            case .U, .D: axis = .y; slice = y
            case .R, .L: axis = .x; slice = x
            case .F, .B: axis = .z; slice = z
            }

            return SelectedLayer(axis: axis, slice: slice, normalFace: normalFace)
        }

        /// 滑动手势 → 该层的 Move。
        /// 规则：相对 normalFace（命中面）= 「观察者看到的方向」，右滑/上滑 = 从该面看顺时针。
        /// M/E/S 等中层：从 normalFace 看时方向可能相反，需用 baseFace 反向判断。
        private func moveForSwipe(startLayer: SelectedLayer, dx: CGFloat, dy: CGFloat) -> Move? {
            let horizontal = abs(dx) >= abs(dy)
            let clockwise: Bool
            if horizontal {
                clockwise = dx > 0
            } else {
                clockwise = dy < 0
            }

            let base = startLayer.baseMove  // 该层 CW 90° 对应的标准 move
            let baseFace = base.outerFace
            // 如果 normalFace == baseFace，则"从 normalFace 看"就是"从 baseFace 看"，方向不变
            // 如果 normalFace != baseFace（仅当 normalFace 是命中外层，baseFace 是该层标准 face），
            //   方向需要翻转：例如点 L 面（normalFace=L），想转 M 层（baseFace=R/M），
            //   "从 L 看顺时针" = "从 R 看逆时针"，所以实际是 Mp
            let sameDirection = (startLayer.normalFace == baseFace)
            let effectiveClockwise = sameDirection ? clockwise : !clockwise
            return effectiveClockwise ? base : base.inverted()
        }

        // MARK: - UIGestureRecognizerDelegate

        /// tap/pan 都由 Coordinator 接管：tap 命中魔方节点 = 选层 / 空白 = 取消；
        /// pan 在选中层时 = 转该层，未选中时 = 不响应（让 SCNView 内置相机 pan 工作）。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer === panGesture, currentHighlightLayer == nil {
                // 未选中 → 不处理 pan（让 SCNView 接管旋转视角）
                return false
            }
            // tap 永远处理（用于空白处取消）
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        // MARK: - 高亮渲染

        /// 应用层高亮：清空旧高亮节点 → 给该层每个 sticker 加 4 条短边线（SCNBox）。
        /// 边线贴 sticker 平面外 0.01 处，constant lighting 蓝色实色，不挡原色。
        func applyHighlight(layer: SelectedLayer?) {
            // 先清空
            highlightNodes.values.forEach { $0.removeFromParentNode() }
            highlightNodes.removeAll()
            currentHighlightLayer = layer
            guard let layer = layer else { return }

            // 高阶：按 normalFace 高亮该面 N² 个 stickers
            if currentOrder >= 4 {
                let perFace = currentOrder * currentOrder
                let fIdx = layer.normalFace.rawValue
                for idx in (fIdx * perFace)..<((fIdx + 1) * perFace) {
                    guard let sticker = cubeNStickers[idx] else { continue }
                    addStickerOutline(to: sticker, key: "n_\(idx)")
                }
                return
            }

            // 2 阶：选中的 normalFace 对应的 4 个 stickers（每角块的 normalFace 面）
            if currentOrder == 2 {
                let dir = dirForNormalFace(layer.normalFace)
                for (key, node) in cubelets2x2 {
                    guard let sticker = node.childNode(withName: "sticker_\(dir.rawValue)", recursively: false) else { continue }
                    addStickerOutline(to: sticker, key: "2x2_\(key)")
                }
                return
            }

            // 3 阶：收集该层所有 sticker 节点
            let stickers = collectLayerStickers(layer: layer)
            for (i, sticker) in stickers.enumerated() {
                let key = sticker.name ?? "i_\(i)"
                addStickerOutline(to: sticker, key: key)
            }
        }

        private func dirForNormalFace(_ face: Face) -> FaceDir {
            switch face {
            case .U: return .py
            case .D: return .ny
            case .L: return .nx
            case .R: return .px
            case .F: return .pz
            case .B: return .nz
            }
        }

        /// 收集 3 阶该 SelectedLayer 涉及的所有 sticker 节点。
        /// - 外层（slice = ±1）：21 个（外表面 9 + 相邻 4 面边缘各 3）
        /// - 内层（slice = 0）：12 个（4 个相邻面各 3 个中央列）
        private func collectLayerStickers(layer: SelectedLayer) -> [SCNNode] {
            var indices = Set<Int>()

            switch layer.axis {
            case .x:
                for (idx, coord) in faceMap.enumerated() {
                    if coord.0 == layer.slice { indices.insert(idx) }
                }
            case .y:
                for (idx, coord) in faceMap.enumerated() {
                    if coord.1 == layer.slice { indices.insert(idx) }
                }
            case .z:
                for (idx, coord) in faceMap.enumerated() {
                    if coord.2 == layer.slice { indices.insert(idx) }
                }
            }

            var result: [SCNNode] = []
            for idx in indices {
                guard idx < faceMap.count else { continue }
                let (x, y, z) = faceMap[idx]
                let key = "\(x)_\(y)_\(z)"
                guard let node = cubelets[key] else { continue }
                let dir = dirForFaceletIndex(idx)
                if let sticker = node.childNode(withName: "sticker_\(dir.rawValue)", recursively: false) {
                    result.append(sticker)
                }
            }
            return result
        }

        /// 给一个 sticker 加一圈蓝色线框（4 条短 SCNBox，贴在 sticker 平面外 0.01 处）。
        /// SCNBox 厚度 0.02（line thickness），constant 蓝色实色，不挡 sticker 原色。
        /// 位置 / 朝向与 sticker 完全对齐，只在 +z 方向平移 0.01 避免 z-fight。
        private func addStickerOutline(to sticker: SCNNode, key: String) {
            let stickerSize: CGFloat = 0.82
            let lineThickness: CGFloat = 0.04
            let lineLength: CGFloat = stickerSize
            let outlineZ: Float = 0.02  // 在 sticker 平面外 0.02 处

            let parent = SCNNode()
            parent.name = "highlight_outline_\(key)"

            // 4 条边：水平两条（上边 + 下边），垂直两条（左边 + 右边）
            // 用 SCNBox，长 = stickerSize，宽 = lineThickness，高 = lineThickness
            let edges: [(position: SCNVector3, size: SCNVector3)] = [
                // 上边（沿 X 轴，y = stickerSize/2）
                (SCNVector3(0,  Float(stickerSize) / 2, outlineZ), SCNVector3(Float(lineLength), Float(lineThickness), Float(lineThickness))),
                // 下边
                (SCNVector3(0, -Float(stickerSize) / 2, outlineZ), SCNVector3(Float(lineLength), Float(lineThickness), Float(lineThickness))),
                // 左边（沿 Y 轴）
                (SCNVector3(-Float(stickerSize) / 2, 0, outlineZ), SCNVector3(Float(lineThickness), Float(lineLength), Float(lineThickness))),
                // 右边
                (SCNVector3( Float(stickerSize) / 2, 0, outlineZ), SCNVector3(Float(lineThickness), Float(lineLength), Float(lineThickness))),
            ]
            for edge in edges {
                let box = SCNBox(width: CGFloat(edge.size.x), height: CGFloat(edge.size.y), length: CGFloat(edge.size.z), chamferRadius: 0.005)
                let m = SCNMaterial()
                m.diffuse.contents = highlightColor
                m.lightingModel = .constant
                m.isDoubleSided = true
                box.materials = [m]
                let n = SCNNode(geometry: box)
                n.position = edge.position
                parent.addChildNode(n)
            }

            // 对齐 sticker 朝向 + 在 +z 方向偏移 outlineZ
            parent.eulerAngles = sticker.eulerAngles
            sticker.addChildNode(parent)
            highlightNodes[key] = parent
        }
    }
}
