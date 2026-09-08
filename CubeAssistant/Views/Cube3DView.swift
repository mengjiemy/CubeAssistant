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
    /// 可选：选中的面（按钮高亮态或手势选层），对应 3D 魔方该面加高亮描边。
    var selectedFace: Face? = nil

    init(session: CubeSession, overrideFacelets: [Int]? = nil, order: Int? = nil, selectedFace: Face? = nil) {
        self.session = session
        self.overrideFacelets = overrideFacelets
        self.order = order ?? session.order
        self.selectedFace = selectedFace
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
        let initial = resolveFacelets()
        // 按阶数构建：2 阶走独立路径（8 块），3 阶走原路径（26 块）
        if order == 2 {
            context.coordinator.currentOrder = 2
            context.coordinator.buildCube2x2(facelets: initial)
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
        let distScale: Float = (order == 2) ? 0.52 : 1.0
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
            // 同步 defaultCameraNode 的距离：2 阶整体小，拉近到一半
            let distScale: Float = (order == 2) ? 0.52 : 1.0
            co.defaultCameraNode?.position = SCNVector3(4.5 * distScale, 4.0 * distScale, 6.5 * distScale)
            co.defaultCameraNode?.look(at: SCNVector3(0, 0, 0))
            let f = resolveFacelets()
            if order == 2 {
                co.currentOrder = 2
                co.buildCube2x2(facelets: f)
            } else {
                co.currentOrder = 3
                co.buildCube(facelets: f)
            }
            co.lastFacelets = f
            co.resetCamera()  // 阶数切换后回正视角到对应距离
            return
        }
        // 选面高亮变化：重画高亮（不做几何变更）
        if selectedFace != co.currentHighlightFace {
            co.applyHighlight(face: selectedFace)
        }
        let facelets = resolveFacelets()
        guard facelets != co.lastFacelets else { return }
        co.lastFacelets = facelets
        if co.currentOrder == 2 {
            co.applyFacelets2x2(facelets)
        } else {
            co.applyFacelets(facelets)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    final class Coordinator: NSObject {
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
        /// 当前选中的面（用于 3D 魔方高亮）
        var currentHighlightFace: Face? = nil
        /// 高亮描边节点集合（key = cubelet key + dir）
        var highlightNodes: [String: SCNNode] = [:]

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
        func buildCube(facelets: [Int]) {
            cubelets.values.forEach { $0.removeFromParentNode() }
            cubelets.removeAll()
            highlightNodes.removeAll()  // 重建 cubelets 集合后高亮失效
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
            if let f = currentHighlightFace { applyHighlight(face: f) }
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
            cubelets2x2.values.forEach { $0.removeFromParentNode() }
            cubelets2x2.removeAll()
            highlightNodes.removeAll()  // 重建 cubelets 集合后高亮失效
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
            if let f = currentHighlightFace { applyHighlight(face: f) }
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

        // MARK: - 选面高亮（按钮/手势选中时，对应面 cubelet 加半透明描边框）
        /// 应用高亮：face=nil 时清空；非 nil 时给该面所有可见 cubelet 描边。
        func applyHighlight(face: Face?) {
            currentHighlightFace = face
            // 先清空所有高亮节点
            for n in highlightNodes.values { n.removeFromParentNode() }
            highlightNodes.removeAll()
            guard let face = face else { return }

            // 该面在 3 阶坐标空间的方向（dirForFaceletIndex 反推）
            let dir: FaceDir
            switch face {
            case .U: dir = .py
            case .D: dir = .ny
            case .L: dir = .nx
            case .R: dir = .px
            case .F: dir = .pz
            case .B: dir = .nz
            }
            // 高亮色：iOS 系统蓝（与按钮主色一致）
            let highlightColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 0.55)
            // 该方向上的 cubelet 集合（按阶数分派）
            let targets: [SCNNode]
            if currentOrder == 2 {
                targets = cubelets2x2.values.filter { $0.childNode(withName: "sticker_\(dir.rawValue)", recursively: false) != nil }
            } else {
                targets = cubelets.values.filter { $0.childNode(withName: "sticker_\(dir.rawValue)", recursively: false) != nil }
            }
            for node in targets {
                // 描边：稍大一点的 wireframe box，框住 cubelet
                let outline = SCNBox(width: 1.0, height: 1.0, length: 1.0, chamferRadius: 0.04)
                let m = SCNMaterial()
                m.diffuse.contents = highlightColor
                m.lightingModel = .constant   // 不受光照影响，恒亮
                m.transparency = 0.45
                outline.materials = [m]
                let outlineNode = SCNNode(geometry: outline)
                outlineNode.name = "highlight_outline"
                node.addChildNode(outlineNode)
                if let key = node.name?.replacingOccurrences(of: "cubelet_", with: "")
                                    .replacingOccurrences(of: "cubelet2_", with: "") {
                    highlightNodes[key + "_" + dir.rawValue] = outlineNode
                }
            }
        }
    }
}
