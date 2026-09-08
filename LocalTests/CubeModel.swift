import Foundation

// ============================================================
// 魔方学院 · 核心领域模型（纯逻辑，无 SwiftUI 依赖，本地可测）
//
// 架构原则：
// - 本层全部用 struct + 值语义，方法返回"新实例"，便于本地 CLI 单测
//   ／ Xcode 里由 UI 层的 ObservableObject 包装驱动。
// - 依赖：Foundation only（不含 Combine/SwiftUI），本地 swiftc 可直接编译。
// - 复用了 v1 已验证引擎：CubeState/Move/Scramble/CubeValidator/KociembaSolver。
// ============================================================

/// 魔方「身份」—— 决定 App 盯不盯、计时怎么走（功能说明书 §0.4，26 条定稿）。
/// - `.physical`：扫描进来的真魔方（默认）。App「看不见」用户在真魔方上的操作 →
///   关闭状态判定与提醒，屏幕当说明书；计时手动启停。
/// - `.virtual`：屏幕里生成的虚拟魔方。App「看得见」每一步 →
///   转完可检测还原成功自动停表；可做"这步还没转哦"轻提醒。
enum CubeIdentity: Equatable, Codable {
    case physical
    case virtual
}

/// 转动方式（设置里全局切换，默认按钮）。独立于新手/专业档（技术方案 §3.3）。
enum TurnMode: Equatable, Codable {
    case buttons      // 按钮模式（默认）：选层(顶层/中层/底层)→4向转
    case gestures     // 手势模式：短按选层→滑动定横竖方向→转一面
}

/// 主页工作台 + 手动转层的领域模型。
///
/// 承担：
/// 1. 当前魔方状态 + 身份 + 阶数
/// 2. 手动转层（apply）→ 压入 undo 栈；undo 可连续回退到 checkpoint（"最初"）
/// 3. 打乱 / 重置 / 扫描输入 → 设 checkpoint、清空 undo 栈
/// 4. 计时（虚拟自动判定停表 / 物理手动）—— 用时用 Date 计算，不依赖 Timer
struct CubeModel: Equatable {
    /// 当前魔方状态（facelet）。**order==3 时有效**（54 facelet）。
    var cube: CubeState
    /// 魔方身份（默认物理真魔方，功能说明书 §10 定稿）
    var identity: CubeIdentity = .physical
    /// 阶数。**默认 3 阶**。
    /// - order==3：用 `cube`（CubeState，54 facelet）+ 3 阶 movePerms。
    /// - order==2：用 `cube2`（Cube2x2，24 facelet）—— 独立存储，隔离不碰 3 阶路径。
    /// ⚠️ 4-10 阶需降阶引擎（CubeGeometry 已就绪几何量，但转动表/求解未实现）。
    var order: Int = 3
    /// 转动方式（按钮/手势）
    var turnMode: TurnMode = .buttons

    /// undo 栈的基准态（checkpoint）：
    /// 每次「打乱 / 重置 / 扫描输入」重设 = cube 快照，并清空 undoStack。
    /// undo 只能一路撤回到这个 checkpoint（= "最初"），不能越界。
    private(set) var checkpointFacelets: [Int]
    /// **order==2 时的魔方状态**（24 facelet）。order==3 时为 nil（用 cube）。
    /// 隔离存储：2 阶完全走 Cube2x2 体系，不碰 3 阶 CubeState/求解器依赖。
    private(set) var cube2: Cube2x2?
    /// **order>=4 时的魔方状态**（6·N² facelet）。order 为 2/3 时为 nil。
    /// 隔离存储：N 阶走 NCubeState（MovePerms{N} 置换表），不碰 3 阶求解器。
    private(set) var cubeN: NCubeState?
    /// 2 阶 undo 栈基准态（order==2 用）
    private(set) var checkpoint2: [Int]?
    /// N 阶 undo 栈基准态（order>=4 用）
    private(set) var checkpointN: [Int]?
    /// 用户自 checkpoint 之后实际施加的每一步（undo = 弹出并逆转动）
    private(set) var undoStack: [Move] = []

    // ---- 计时（用时用 Date 差值，无 Timer 依赖，便于本地测）----
    /// 是否正在计时
    private(set) var isTiming = false
    /// 计时开始时刻
    private(set) var timingStart: Date?

    init(cube: CubeState = CubeState(solved: true), identity: CubeIdentity = .physical, order: Int = 3) {
        self.cube = cube
        self.identity = identity
        self.order = order
        self.checkpointFacelets = cube.facelets
        if order == 2 {
            self.cube2 = Cube2x2(solved: true)
            self.checkpoint2 = self.cube2?.facelets
        } else if order >= 4 {
            let c = NCubeState(order: order, solved: true)
            self.cubeN = c
            self.checkpointN = c.facelets
        }
    }

    // MARK: - 查询

    /// 是否已还原（按阶数判定）
    var isSolved: Bool {
        if order == 2 { return cube2?.isSolved ?? true }
        if order >= 4 { return cubeN?.isSolved ?? true }
        return cube.isSolved
    }

    /// 是否能继续 undo（栈里还有步）
    var canUndo: Bool { !undoStack.isEmpty }

    /// 当前累计用时（正在计时则到现在，否则 0）
    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard isTiming, let start = timingStart else { return 0 }
        return now.timeIntervalSince(start)
    }

    // MARK: - 状态建立（打乱/重置/扫描 → 设 checkpoint）

    /// 重置为还原态（六面纯色），计时清零，undo 清空。
    /// 物理/虚拟通用：主页「重置」= 回出厂 + 计时归零（说明书 §9#1）。
    mutating func reset() {
        if order == 2 {
            cube2 = Cube2x2(solved: true)
            checkpoint2 = cube2?.facelets
            undoStack = []
            stopTiming()
            return
        }
        if order >= 4 {
            let c = NCubeState(order: order, solved: true)
            cubeN = c
            checkpointN = c.facelets
            undoStack = []
            stopTiming()
            return
        }
        cube = CubeState(solved: true)
        checkpointFacelets = cube.facelets
        undoStack = []
        stopTiming()
    }

    /// 随机打乱（保证可还原）。虚拟魔方打乱后通常紧接着开始练习计时。
    /// physical 打乱后是否计时由用户手动决定（说明书 §2.2）。
    mutating func scramble(count: Int = 25) {
        if order == 2 {
            // 2 阶打乱：God's number 11，给足步数（~12）保证足够乱
            cube2 = Cube2x2.scrambled(count: count <= 12 ? count : 12)
            checkpoint2 = cube2?.facelets
            undoStack = []
            stopTiming()
            return
        }
        if order >= 4 {
            var c = NCubeState(order: order, solved: true)
            // N 阶打乱步数按阶数放大（每层需足够随机）
            _ = c.scramble(count: max(20, min(count, 80)))
            cubeN = c
            checkpointN = c.facelets
            undoStack = []
            stopTiming()
            return
        }
        let moves = ScrambleGenerator.generate(length: count)
        var c = CubeState(solved: true)
        for m in moves { c.apply(m.rawValue) }
        cube = c
        checkpointFacelets = cube.facelets
        undoStack = []
        stopTiming()
    }

    /// 由扫描/手填写入完整色。校验通过 → 更新模型、设 checkpoint。
    /// - order==3：facelets 为 54；order==2：facelets 为 24（Cube2x2）。
    /// 返回是否合法（非法不入库，给出原因）。
    @discardableResult
    mutating func setFacelets(_ facelets: [Int]) -> Result<Void, CubeModelError> {
        if order == 2 {
            guard facelets.count == Cube2x2Geometry.totalFacelets else {
                return .failure(.invalidState("2 阶需 24 个色块"))
            }
            cube2 = Cube2x2(facelets: facelets)
            checkpoint2 = cube2?.facelets
            undoStack = []
            stopTiming()
            return .success(())
        }
        if order >= 4 {
            let expect = NCubeGeometry(order).totalFacelets
            guard facelets.count == expect else {
                return .failure(.invalidState("\(order) 阶需 \(expect) 个色块"))
            }
            cubeN = NCubeState(facelets: facelets, order: order)
            checkpointN = cubeN?.facelets
            undoStack = []
            stopTiming()
            return .success(())
        }
        let errs = CubeValidator.validate(facelets: facelets)
        guard errs.isEmpty else {
            return .failure(.invalidState(errs.map { "\($0)" }.joined(separator: "、")))
        }
        cube = CubeState(facelets: facelets)
        checkpointFacelets = cube.facelets
        undoStack = []
        stopTiming()
        return .success(())
    }

    // MARK: - 手动转层（按钮/手势双模式都走这里）

    /// 施加一步转动：压入 undo 栈，更新 cube（按阶数分派 2 阶/3 阶）。
    /// 返回转动后是否恰好还原（供虚拟模式自动判定停表用）。
    @discardableResult
    mutating func apply(_ move: Move) -> Bool {
        undoStack.append(move)
        if order == 2 {
            cube2?.apply(move.rawValue)
            return cube2?.isSolved ?? false
        }
        if order >= 4 {
            cubeN?.apply(move.rawValue)
            return cubeN?.isSolved ?? false
        }
        cube.apply(move.rawValue)
        return cube.isSolved
    }

    /// 连续回退一步：弹出 undo 栈最后一步并逆转动。
    /// 能一路回退到 checkpoint（"最初"），栈空则无操作。
    /// 返回是否真的退了（false = 已到最初无操作）。
    @discardableResult
    mutating func undo() -> Bool {
        guard let last = undoStack.popLast() else { return false }
        if order == 2 {
            cube2?.apply(last.inverted().rawValue)
            return true
        }
        if order >= 4 {
            cubeN?.apply(last.inverted().rawValue)
            return true
        }
        cube.apply(last.inverted().rawValue)
        return true
    }

    // MARK: - 计时

    /// 开始计时
    mutating func startTiming(at now: Date = Date()) {
        guard !isTiming else { return }
        isTiming = true
        timingStart = now
    }

    /// 停止计时，返回本次用时
    @discardableResult
    mutating func stopTiming(at now: Date = Date()) -> TimeInterval {
        let d = elapsed(at: now)
        isTiming = false
        timingStart = nil
        return d
    }
}

/// 模型错误
enum CubeModelError: Error, Equatable {
    case invalidState(String)
}
