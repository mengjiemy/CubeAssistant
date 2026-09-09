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

    /// 可选：覆盖渲染的 facelets（学习页内嵌魔方用，展示「轨道中间态」而非 session.cube）。
    /// 为 nil 时按 session.cube 渲染（主页默认）。
    var overrideFacelets: [Int]? = nil
    /// 渲染阶数：3=3阶(26块/每面9格)，2=2阶(8块/每面4格)。
    /// 默认取 session 当前阶数；独立传入时(如无 session 的场景)可显式指定。
    var order: Int = 3
    /// 可选：选中的层切片（按钮高亮态或手势选层），高亮覆盖该层全部 stickers。
    var selectedLayer: SelectedLayer? = nil
    /// 手势交互回调：点击某个 sticker 后选中对应层。
    var onLayerSelected: ((SelectedLayer) -> Void)? = nil
    /// 手势交互回调：滑动触发一次 90° 转动请求。
    var onTurnRequest: ((Move) -> Void)? = nil

    init(session: CubeSession,
         overrideFacelets: [Int]? = nil,
         order: Int? = nil,
         selectedLayer: SelectedLayer? = nil,
         onLayerSelected: ((SelectedLayer) -> Void)? = nil,
         onTurnRequest: ((Move) -> Void)? = nil) {
        self.session = session
        self.overrideFacelets = overrideFacelets
        self.order = order ?? session.order
        self.selectedLayer = selectedLayer
        self.onLayerSelected = onLayerSelected
        self.onTurnRequest = onTurnRequest
    }

    /// 一个层切片：轴 + 切片坐标 + 命中面法向（决定滑动方向观察基准）。
    struct SelectedLayer: Equatable, Hashable {
        enum Axis: Int, Equatable, Hashable { case x, y, z }
        let axis: Axis
        let slice: Int
        let normalFace: Face

        init(axis: Axis, slice: Int, normalFace: Face) {
            self.axis = axis; self.slice = slice; self.normalFace = normalFace
        }

        /// 由外层 face 构造（高阶/按钮模式用）。slice 用归一化坐标 ±1。
        init(outer face: Face) {
            switch face {
            case .U: self.init(axis: .y, slice: 1, normalFace: .U)
            case .D: self.init(axis: .y, slice: -1, normalFace: .D)
            case .R: self.init(axis: .x, slice: 1, normalFace: .R)
            case .L: self.init(axis: .x, slice: -1, normalFace: .L)
            case .F: self.init(axis: .z, slice: 1, normalFace: .F)
            case .B: self.init(axis: .z, slice: -1, normalFace: .B)
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
        scnView.allowsCameraControl = true   // 内置相机控制（单指旋转、双指缩放）
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.defaultCameraController.interactionMode = .orbitAngleMapping
        scnView.defaultCameraController.inertiaEnabled = true

        let scene = SCNScene()
        scnView.scene = scene
        context.coordinator.scene = scene
        context.coordinator.onLayerSelected = onLayerSelected
        context.coordinator.onTurnRequest = onTurnRequest
        let initial = resolveFacelets()
        // 按阶数构建：2 阶走独立路径（8 块），3 阶走原路径（26 块），>=4 阶走高阶渲染
        if order == 2 {
            context.coordinator.currentOrder = 2
            context.coordinator.buildCube2x2(facelets: initial)
        } else if order >= 4 {
            context.coordinator.currentOrder = order
            context.coordinator.buildCubeN(order: order, facelets: initial)
        } else {
            context.coordinator.currentOrder = 3
            context.coordinator.buildCube(facelets: initial)
        }
        context.coordinator.lastFacelets = initial

        // 默认相机节点（保留作「reset 模板」）。注意：SCNView 启用 allowsCameraControl
        // 后会接管 pointOfView 控制；本节点不参与渲染，只作为 resetCamera 时回正朝向的参照。
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        // 相机距离随阶数缩放：2 阶拉近，N 阶(>=4)拉远以容纳更大体积
        let distScale: Float = Self.cameraScale(for: order)
        camera.position = SCNVector3(4.5 * distScale, 4.0 * distScale, 6.5 * distScale)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        context.coordinator.defaultCameraNode = camera
        // 启动时把默认相机挂为 pointOfView，初始呈现正朝向
        scnView.pointOfView = camera

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

        // 手势模式：点击选面 + 滑动转层（仅在提供了回调时启用）。
        // 注意：手势识别器与 SCNView 内置相机控制（单指旋转视角）会竞争；
        // 这里靠 hitTest 必须有魔方节点才响应，且滑动阈值足够大，避免误触发。
        if onLayerSelected != nil || onTurnRequest != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleTap(_:)))
            tap.delegate = context.coordinator
            scnView.addGestureRecognizer(tap)
            context.coordinator.tapGesture = tap

            let pan = UIPanGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePan(_:)))
            pan.delegate = context.coordinator
            pan.maximumNumberOfTouches = 1
            scnView.addGestureRecognizer(pan)
            context.coordinator.panGesture = pan
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let co = context.coordinator
        // 相机复位：token 变化即回正视角
        if session.cameraResetToken != co.lastCameraResetToken {
            co.lastCameraResetToken = session.cameraResetToken
            co.resetCamera()
        }
        // 阶数变化：需重建 cube（cubelet 集合不同）
        if order != co.currentOrder {
            // 同步 defaultCameraNode 的距离：按阶数缩放
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
            co.resetCamera()  // 阶数切换后回正视角到对应距离
            return
        }
        // 选层高亮变化：重画高亮（不做几何变更）
        if selectedLayer != co.currentHighlightLayer {
            co.applyHighlight(layer: selectedLayer)
        }
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
    }

    /// 相机距离随阶数缩放：2 阶拉近(0.52)，3 阶基准(1.0)，N 阶拉远以容纳更大体积。
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
        /// 「默认视角」相机节点（reset 时的朝向参照）。注意：SCNView 启用
        /// allowsCameraControl 后，defaultCameraController 会接管实际渲染的
        /// pointOfView；本节点不直接渲染，仅在 reset 时被临时指回。
        weak var defaultCameraNode: SCNNode?
        /// cubelets[key] = 块节点；key 格式 "x_y_z"
        var cubelets: [String: SCNNode] = [:]
        var lastFacelets: [Int] = []
        var lastCameraResetToken: Int = 0
        /// 当前渲染阶数（3/2），buildCube 时设定，驱动 applyFacelets 分派与相机距离
        var currentOrder = 3
        /// 当前选中的层（用于 3D 魔方高亮）
        var currentHighlightLayer: SelectedLayer? = nil
        /// 高亮描边节点集合（key = cubelet key + sticker name）
        var highlightNodes: [String: SCNNode] = [:]
        /// —— 高阶（4~10）渲染节点 ——
        /// N 阶魔方所有已建节点（便于整体拆除重建）
        var cubeNAllNodes: [SCNNode] = []
        /// facelet 索引 → 对应 sticker 节点（repaint 用）
        var cubeNStickers: [Int: SCNNode] = [:]
        /// 手势交互回调
        var onLayerSelected: ((SelectedLayer) -> Void)?
        var onTurnRequest: ((Move) -> Void)?
        /// 手势识别器（用于 delegate / 复位）
        weak var tapGesture: UITapGestureRecognizer?
        weak var panGesture: UIPanGestureRecognizer?
        /// 滑动手势起点命中到的层
        private var panStartLayer: SelectedLayer? = nil

        /// 回正相机到默认视角（顶面朝上、前面朝前），按阶数调距离。
        /// 实现关键：SCNView 启用 allowsCameraControl 时，实际渲染的 pointOfView 由
        /// defaultCameraController 接管；直接改 defaultCameraNode.position 不会影响
        /// 用户看到的画面（这就是「回正视角按钮无效」的根因）。正确做法：
        /// 1) 停惯性；2) 把 pointOfView 临时换回默认相机节点 → 用户看到正朝向；
        /// 3) 立即重新启用 allowsCameraControl（让 defaultCameraController 重新接管），
        ///    用户可以继续拖动旋转。
        func resetCamera() {
            guard let scnView = scnView, let defaultCam = defaultCameraNode else { return }
            // 先停惯性，避免在切换 pointOfView 期间画面被前一次的旋转惯性继续推
            scnView.defaultCameraController.stopInertia()
            // 把 pointOfView 切回默认相机节点，触发 scene 重新渲染 → 用户看到正朝向
            scnView.pointOfView = defaultCam
            // 关再开 allowsCameraControl，让 defaultCameraController 重新生成一个干净的 pointOfView
            // （这样后续拖拽/缩放仍正常工作，且视角落回默认）
            scnView.allowsCameraControl = false
            scnView.allowsCameraControl = true
            scnView.defaultCameraController.interactionMode = .orbitAngleMapping
            scnView.defaultCameraController.inertiaEnabled = true
        }

        // MARK: - 手势交互（手势模式）

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)
            guard let layer = layerAt(point: point, in: scnView) else { return }
            onLayerSelected?(layer)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)

            switch gesture.state {
            case .began:
                panStartLayer = layerAt(point: point, in: scnView)
                gesture.setTranslation(.zero, in: scnView)
            case .ended, .cancelled:
                defer { panStartLayer = nil }
                guard let startLayer = panStartLayer else { return }
                let translation = gesture.translation(in: scnView)
                let dx = translation.x
                let dy = translation.y
                // 过滤过小的滑动，避免与相机旋转/惯性误判
                guard max(abs(dx), abs(dy)) > 24 else { return }
                guard let move = moveForSwipe(on: startLayer, dx: dx, dy: dy) else { return }
                onTurnRequest?(move)
            default:
                break
            }
        }

        /// 把命中结果解析为层（2/3 阶读 sticker_xxx + cubelet 坐标；高阶读 stickerN_idx 并退化到命中的外层）。
        private func layerAt(point: CGPoint, in scnView: SCNView) -> SelectedLayer? {
            let hits = scnView.hitTest(point, options: [SCNHitTestOption.boundingBoxOnly: false])
            guard let node = hits.first?.node else { return nil }

            // 高阶 sticker 节点名 stickerN_idx：退化到命中的外层
            if let name = node.name, name.hasPrefix("stickerN_"),
               let idx = Int(name.dropFirst("stickerN_".count)) {
                let faceIdx = idx / (currentOrder * currentOrder)
                guard faceIdx < Face.allCases.count, let face = Face(rawValue: faceIdx) else { return nil }
                return SelectedLayer(outer: face)
            }

            // 2/3 阶 sticker 节点名 sticker_px/nx/py/ny/pz/nz
            if let name = node.name, name.hasPrefix("sticker_"),
               let dir = FaceDir(rawValue: String(name.dropFirst("sticker_".count))),
               let coords = cubeletCoordinates(for: node) {
                let face = faceFor(dir: dir)
                return layerFor(coords: coords, face: face)
            }

            // 命中到 cubelet 内芯：向上查 sticker 子节点（取第一个可见面）
            if let parent = node.parent,
               let sticker = parent.childNodes.first(where: { $0.name?.hasPrefix("sticker") == true }),
               let name = sticker.name {
                if name.hasPrefix("stickerN_"), let idx = Int(name.dropFirst("stickerN_".count)) {
                    let faceIdx = idx / (currentOrder * currentOrder)
                    guard faceIdx < Face.allCases.count, let face = Face(rawValue: faceIdx) else { return nil }
                    return SelectedLayer(outer: face)
                }
                if name.hasPrefix("sticker_"), let dir = FaceDir(rawValue: String(name.dropFirst("sticker_".count))),
                   let coords = cubeletCoordinates(for: sticker) {
                    let face = faceFor(dir: dir)
                    return layerFor(coords: coords, face: face)
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

        private func layerFor(coords: (x: Int, y: Int, z: Int), face: Face) -> SelectedLayer {
            switch face {
            case .U: return SelectedLayer(axis: .y, slice: coords.y, normalFace: .U)
            case .D: return SelectedLayer(axis: .y, slice: coords.y, normalFace: .D)
            case .R: return SelectedLayer(axis: .x, slice: coords.x, normalFace: .R)
            case .L: return SelectedLayer(axis: .x, slice: coords.x, normalFace: .L)
            case .F: return SelectedLayer(axis: .z, slice: coords.z, normalFace: .F)
            case .B: return SelectedLayer(axis: .z, slice: coords.z, normalFace: .B)
            }
        }

        /// 从 sticker 节点向上追溯 cubelet 节点，解析归一化坐标（2 阶 ±1，3 阶 ±1/0）。
        private func cubeletCoordinates(for node: SCNNode) -> (x: Int, y: Int, z: Int)? {
            var n: SCNNode? = node
            while n != nil {
                guard let name = n?.name else { n = n?.parent; continue }
                if name.hasPrefix("cubelet_") {
                    let parts = name.dropFirst("cubelet_".count).split(separator: "_")
                    if parts.count == 3,
                       let x = Int(parts[0]), let y = Int(parts[1]), let z = Int(parts[2]) {
                        return (x, y, z)
                    }
                }
                if name.hasPrefix("cubelet2_") {
                    let parts = name.dropFirst("cubelet2_".count).split(separator: "_")
                    if parts.count == 3,
                       let x = Int(parts[0]), let y = Int(parts[1]), let z = Int(parts[2]) {
                        // 2 阶 key 为 ±5（表 ±0.5），归一化到 ±1
                        let div = max(abs(x), 1)
                        return (x / div, y / div, z / div)
                    }
                }
                n = n?.parent
            }
            return nil
        }

        /// 根据起点层和滑动方向生成一次 90° 转动。
        /// 规则：在命中面上沿主方向滑动；右/上=从该面看顺时针，左/下=逆时针。
        private func moveForSwipe(on layer: SelectedLayer, dx: CGFloat, dy: CGFloat) -> Move? {
            let horizontal = abs(dx) >= abs(dy)
            let clockwise: Bool
            if horizontal {
                clockwise = dx > 0
            } else {
                clockwise = dy < 0
            }
            let baseMove = baseMoveForLayer(layer)
            // 标准观察面：x 层从 R 看，y 层从 U 看，z 层从 F 看
            let standardFace: Face
            switch layer.axis {
            case .x: standardFace = .R
            case .y: standardFace = .U
            case .z: standardFace = .F
            }
            // normalFace 与标准观察面同向则方向一致，反向（L/D/B）则相反
            let sameDirection = (layer.normalFace == standardFace)
            let effectiveClockwise = sameDirection ? clockwise : !clockwise
            return effectiveClockwise ? baseMove : baseMove.inverted()
        }

        /// 从标准观察面看顺时针时，该层对应的 Move。
        private func baseMoveForLayer(_ layer: SelectedLayer) -> Move {
            switch (layer.axis, layer.slice) {
            case (.x, 1):  return .R
            case (.x, 0):  return .Mp
            case (.x, -1): return .Lp
            case (.y, 1):  return .U
            case (.y, 0):  return .Ep
            case (.y, -1): return .Dp
            case (.z, 1):  return .F
            case (.z, 0):  return .Sp
            case (.z, -1): return .Bp
            default:       return .R
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        /// 允许手势识别器与 SCNView 内置相机控制同时生效：
        /// 只有当命中到魔方节点时才由本 Coordinator 处理，否则交给 SCNView。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard let scnView = scnView else { return false }
            let point = touch.location(in: scnView)
            let hits = scnView.hitTest(point, options: [SCNHitTestOption.boundingBoxOnly: false])
            return hits.first != nil
        }

        /// 允许 tap 与 pan 同时识别（tap 选面，pan 转层）。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

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

        /// 构建可见块（内芯 + 可见面 sticker）。块数 = N³-1（3 阶 → 26）。
        /// 统一拆除所有阶数的魔方节点（切阶时避免旧阶节点残留叠加渲染 / 泄漏）。
        /// 三个 build 函数开头各调一次，确保场景里同一时刻只有一套 cube 节点。
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

        func buildCube(facelets: [Int]) {
            removeAllCubeNodes()
            let h = CubeGeometry.three.coordHalf   // 3 阶 → 1，坐标 -1...1
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
            guard facelets.count == CubeGeometry.three.totalFacelets else { return }

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

        // MARK: - 2 阶隔离渲染路径（8 角块，无中心/棱）
        // 说明：2 阶 24 面片通过 Cube2x2.to3x3Index 映射到 3 阶角贴纸(0,2,6,8 偏移)，
        // 再用本类的 3 阶 faceMap 得块坐标、dirForFaceletIndex 得面方向，×0.5 即 2 阶半整数坐标。
        // 因此这里无需为 2 阶单独维护一份 faceMap —— 复用 3 阶权威映射，杜绝坐标错配。
        /// 2 阶 cubelet 字典：key "x_y_z"（半整数 ×10 避免小数点 key，如 "5_-5_5" 表 0.5,-0.5,0.5）
        var cubelets2x2: [String: SCNNode] = [:]

        /// 把 3 阶整数坐标(±1) 转成 2 阶 key(半整数×10，避免负号歧义需带符号)
        private func key2x2(_ x3: Int, _ y3: Int, _ z3: Int) -> String {
            // 3 阶角块坐标 ±1 → 2 阶 ±0.5，×10 得 ±5
            let xs = (x3 >= 0 ? "+" : "-") + String(abs(x3) * 5)
            let ys = (y3 >= 0 ? "+" : "-") + String(abs(y3) * 5)
            let zs = (z3 >= 0 ? "+" : "-") + String(abs(z3) * 5)
            return "\(xs)_\(ys)_\(zs)"
        }

        /// 构建 2 阶 8 角块
        func buildCube2x2(facelets: [Int]) {
            removeAllCubeNodes()
            // 8 个角块坐标（3 阶 8 个角的 ±1 组合）
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

        /// 创建 2 阶角块：黑色内芯 + 3 个可见外表面 sticker（角块必暴露 3 面）
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
            // 角块暴露：符号为正的方向才有外表面
            if sx > 0 { addSticker(to: node, dir: .px) }
            if sx < 0 { addSticker(to: node, dir: .nx) }
            if sy > 0 { addSticker(to: node, dir: .py) }
            if sy < 0 { addSticker(to: node, dir: .ny) }
            if sz > 0 { addSticker(to: node, dir: .pz) }
            if sz < 0 { addSticker(to: node, dir: .nz) }
            return node
        }

        /// 给 2 阶魔方上色：24 facelet → 8 块对应可见面
        func applyFacelets2x2(_ facelets: [Int]) {
            guard facelets.count == Cube2x2Geometry.totalFacelets else { return }
            // 先全部 sticker 重置为内色
            for node in cubelets2x2.values {
                for child in node.childNodes where child.name?.hasPrefix("sticker_") == true {
                    child.geometry?.materials.first?.diffuse.contents = innerColor
                }
            }
            for (i, colorId) in facelets.enumerated() {
                guard colorId >= 0 && colorId < colorMap.count else { continue }
                let idx3 = Cube2x2.to3x3Index(i)   // 2 阶 facelet → 3 阶角贴纸索引
                guard idx3 < faceMap.count else { continue }
                let (x3, y3, z3) = faceMap[idx3]     // 3 阶整数块坐标(±1)
                let key = key2x2(x3, y3, z3)
                guard let node = cubelets2x2[key] else { continue }
                let dir = dirForFaceletIndex(idx3)   // 该面方向
                guard let sticker = node.childNode(withName: "sticker_\(dir.rawValue)", recursively: false) else { continue }
                sticker.geometry?.materials.first?.diffuse.contents = colorMap[colorId]
            }
        }

        // MARK: - 高阶（4~10 阶）渲染路径
        // 说明：N 阶不做逐块(cubelet)建模 + 转动动画（那需要为每层维护独立旋转组，复杂度随
        // 阶数爆炸且难在真机验证），而采用「六面贴纸网格」渲染：一个实体核心 + 每面 N×N 个
        // 贴纸平面（SCNPlane），每个贴纸 = 一个 facelet，颜色直接读该 facelet 值。
        // 转动 = 状态层 apply → 这里 applyFaceletsN 整面重绘贴纸颜色（无 3D 旋转动画），
        // 视觉上是「该面贴纸颜色即时变化」，配合 3 阶/2 阶已有的判定即可「玩起来」。
        // 优点：facelet ↔ 物理贴纸一一对应，永不与 movePerms 错位，逻辑可本地验证。
        func buildCubeN(order: Int, facelets: [Int]) {
            removeAllCubeNodes()

            let N = order
            let halfExtent = Float(N) / 2.0          // 实体核心半长
            // 实体核心：黑色（透出黑色「间隙」观感，像贴纸魔方）
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

            let stickerSize: Float = 0.88          // 单位格贴纸（留黑缝 0.12）
            let normalDistance = halfExtent + 0.02 // 贴纸微微凸出核心表面
            // 每个面：法向 + 两个面内轴的方向向量（把 facelet(row,col) 布局到该面）
            // 面 0..5 = U,R,F,D,L,B
            // 面内布局统一：col 沿「轴A」，row 沿「轴B」，均按贴纸格序 (row,col)→(c- (N-1)/2, r-(N-1)/2)
            // 物理坐标用 Float，中心 = (坐标) - (N-1)/2
            let halfGrid = Float(N - 1) / 2.0
            let faces: [(dir: (Float, Float, Float), axA: (Float, Float, Float), axB: (Float, Float, Float))] = [
                // U (+y 上)
                (dir: (0, 1, 0), axA: (1, 0, 0), axB: (0, 0, -1)),
                // R (+x 右)
                (dir: (1, 0, 0), axA: (0, 0, 1), axB: (0, -1, 0)),
                // F (+z 前)
                (dir: (0, 0, 1), axA: (1, 0, 0), axB: (0, -1, 0)),
                // D (-y 下)
                (dir: (0, -1, 0), axA: (1, 0, 0), axB: (0, 0, -1)),
                // L (-x 左)
                (dir: (-1, 0, 0), axA: (0, 0, 1), axB: (0, 1, 0)),
                // B (-z 后)
                (dir: (0, 0, -1), axA: (-1, 0, 0), axB: (0, 1, 0)),
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
                        // 让贴纸面向外：法向 = pos 方向（垂直于核心表面）
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

        /// 给高阶魔方重绘颜色：每个 facelet 值 → 对应贴纸节点颜色
        func applyFaceletsN(_ facelets: [Int]) {
            for (idx, node) in cubeNStickers {
                guard idx < facelets.count else { continue }
                let colorId = facelets[idx]
                guard colorId >= 0 && colorId < colorMap.count else { continue }
                node.geometry?.materials.first?.diffuse.contents = colorMap[colorId]
            }
        }

        // MARK: - 选层高亮（按钮/手势选中时，该切片内全部 stickers 加低透蓝色罩）
        func applyHighlight(layer: SelectedLayer?) {
            currentHighlightLayer = layer
            // 先清空所有高亮节点
            for n in highlightNodes.values { n.removeFromParentNode() }
            highlightNodes.removeAll()
            guard let layer = layer else { return }

            // 低透蓝色：只给一层淡淡提示，不遮挡原色
            let highlightColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 0.20)

            // 高阶（4~10）：只支持外层，退化到按命中的 face 高亮
            if currentOrder >= 4 {
                let perFace = currentOrder * currentOrder
                let fIdx = layer.normalFace.rawValue
                for idx in (fIdx * perFace)..<((fIdx + 1) * perFace) {
                    guard let sticker = cubeNStickers[idx] else { continue }
                    addOverlay(to: sticker, color: highlightColor, key: "n_\(idx)")
                }
                return
            }

            // 2/3 阶：按层切片筛选 cubelet，高亮该切片内所有 stickers
            let source = currentOrder == 2 ? cubelets2x2 : cubelets
            for (key, node) in source {
                guard let coords = parseCubeletKey(key) else { continue }
                let inSlice: Bool
                switch layer.axis {
                case .x: inSlice = coords.x == layer.slice
                case .y: inSlice = coords.y == layer.slice
                case .z: inSlice = coords.z == layer.slice
                }
                guard inSlice else { continue }
                for child in node.childNodes where child.name?.hasPrefix("sticker_") == true {
                    addOverlay(to: child, color: highlightColor, key: key + "_" + (child.name ?? ""))
                }
            }
        }

        private func addOverlay(to sticker: SCNNode, color: UIColor, key: String) {
            let overlay = SCNPlane(width: 0.86, height: 0.86)
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant   // 不受光照影响，恒亮
            m.isDoubleSided = true
            overlay.materials = [m]
            let overlayNode = SCNNode(geometry: overlay)
            overlayNode.name = "highlight_overlay"
            overlayNode.position = SCNVector3(0, 0, 0.02)
            overlayNode.eulerAngles = sticker.eulerAngles
            sticker.addChildNode(overlayNode)
            highlightNodes[key] = overlayNode
        }

        /// 解析 cubelet key 为归一化坐标（3 阶 "-1_0_1"；2 阶 "+5_-5_+5" → ±1）。
        private func parseCubeletKey(_ key: String) -> (x: Int, y: Int, z: Int)? {
            let parts = key.split(separator: "_")
            guard parts.count == 3,
                  let x = Int(parts[0]), let y = Int(parts[1]), let z = Int(parts[2]) else { return nil }
            // 2 阶坐标 ±5 归一化到 ±1；3 阶 ±1 保持不变
            let div = max(abs(x), abs(y), abs(z), 1)
            return (x / div, y / div, z / div)
        }
    }
}
