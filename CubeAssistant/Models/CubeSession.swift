import Foundation
import SwiftUI

/// 魔方学院 · UI 层 ViewModel（包装领域模型 `CubeModel`）。
///
/// 领域模型 `CubeModel` 是纯 struct 值语义（无 SwiftUI 依赖），
/// 本类把它包成 `ObservableObject`，供 SwiftUI 界面观察驱动。
///
/// 关键点：
/// - 所有状态读写在主线程（`@MainActor`），3D 视图、计时、按钮都据此刷新。
/// - 计时用 `Timer` 驱动 0.1s 刷新 `elapsed` 显示值；真实用时仍由 `CubeModel`
///   内部用 `Date` 差值精确计算（停止时结算）。
@MainActor
final class CubeSession: NSObject, ObservableObject {
    /// 领域模型（值语义，每次改动整体替换触发 objectWillChange）
    @Published private(set) var model: CubeModel = CubeModel()

    /// 实时计时显示（0.1s 刷新），仅用于界面显示，结算用 `model.elapsed(at:)`
    @Published private(set) var liveElapsed: TimeInterval = 0

    /// 提示 / 错误信息
    @Published var message: String? = nil

    /// 当前还原指引会话（进入"学习/还原"时构建），nil 表示未进入指引
    @Published private(set) var solveSession: SolveSession?

    /// **2 阶专用还原指引**：解法步骤（Solver2x2 秒解）+ 当前步号。
    /// 2 阶步数短(≤11)，用"照着转，转完检测还原"的极简指引，不依赖 3 阶 SolveSession 轨道。
    @Published private(set) var solve2x2Steps: [Move] = []
    @Published private(set) var solve2x2StepIndex: Int = 0

    /// 当前已对齐到轨道的第几步（0 = 起点乱态，totalSteps = 已还原）。
    /// 转层/回退后实时 evaluate 更新；脱轨时置为 nil（需 undo 退回）。
    @Published private(set) var alignedStep: Int = 0

    /// 脱轨提示（转错/打乱导致偏离轨道时给出，如「这步该转 R」）
    @Published private(set) var offTrackMessage: String? = nil

    /// 是否正在求解（后台计算 Kociemba，避免卡 UI）
    @Published private(set) var isSolving: Bool = false

    /// 本地历史成绩（UserDefaults 持久化）
    @Published private(set) var history: [SolveRecord] = []

    /// 用户资料 / 偏好（昵称、签名、档位）—— UserDefaults 持久化
    @Published var profile: ProfileStore = .load()

    /// 相机复位令牌：自增一次，3D 视图据此把视角回正到默认朝向。
    @Published private(set) var cameraResetToken: Int = 0

    private var timer: Timer?
    /// 暂停前累计的用时（秒）。支持「暂停→继续」跨段累计。
    private var accumulatedElapsed: TimeInterval = 0

    override init() {
        super.init()
        history = Self.loadHistoryFromDefaults()
        profile = .load()
    }

    // MARK: - 便捷查询

    /// 当前魔方状态
    var cube: CubeState { model.cube }
    /// 魔方身份（物理/虚拟）
    var identity: CubeIdentity { model.identity }
    /// 转动方式（按钮/手势）
    var turnMode: TurnMode { model.turnMode }
    /// 魔方阶数（3/2 等）
    var order: Int { model.order }
    /// 是否正在计时
    var isTiming: Bool { model.isTiming }
    /// 是否已还原
    var isSolved: Bool { model.isSolved }
    /// 是否能继续 undo
    var canUndo: Bool { model.canUndo }
    /// undo 已走的步数（自 checkpoint 起）
    var undoCount: Int { model.undoStack.count }

    // MARK: - 身份 / 模式切换

    /// 切换魔方阶数（2 阶 / 3 阶）。切换时重建模型、清指引、复位计时。
    func setOrder(_ newOrder: Int) {
        guard newOrder == 2 || newOrder == 3, model.order != newOrder else { return }
        let m = CubeModel(identity: model.identity, order: newOrder)
        model = m
        clearSolve()
        stopTimerUI()
        accumulatedElapsed = 0
        message = newOrder == 2 ? "已切换到 2 阶" : "已切换到 3 阶"
    }

    /// 当前是否 2 阶
    var isOrder2: Bool { model.order == 2 }

    /// 2 阶状态（order==2 时非 nil）
    var cube2x2: Cube2x2? { model.cube2 }

    /// 按当前阶数返回用于渲染的 facelets（3阶=54，2阶=24）。
    /// Cube3DView 无 overrideFacelets 时（主页）据此渲染当前魔方。
    func renderedFacelets() -> [Int] {
        if model.order == 2 { return model.cube2?.facelets ?? [] }
        return model.cube.facelets
    }

    /// 切换魔方身份（物理 ↔ 虚拟）。切换时重置计时，避免状态混乱。
    func setIdentity(_ id: CubeIdentity) {
        guard model.identity != id else { return }
        var m = model
        m.identity = id
        _ = m.stopTiming()
        model = m
        stopTimerUI()
        accumulatedElapsed = 0
    }

    /// 切换转动方式（按钮/手势）
    func setTurnMode(_ mode: TurnMode) {
        var m = model
        m.turnMode = mode
        model = m
    }

    // MARK: - 状态建立（打乱/重置/扫描）

    /// 重置为还原态
    func reset() {
        var m = model
        m.reset()
        model = m
        clearSolve()
        stopTimerUI()
        accumulatedElapsed = 0
        message = "已还原为初始状态"
    }

    /// 随机打乱（默认 25 步，WCA 风格）
    func scramble(count: Int = 25) {
        var m = model
        m.scramble(count: count)
        model = m
        clearSolve()
        message = "已打乱，开始练习吧"
        stopTimerUI()
        accumulatedElapsed = 0
    }

    /// 由扫描/手填写入完整 54 色。返回是否成功（非法给出 message）。
    @discardableResult
    func setFacelets(_ facelets: [Int]) -> Bool {
        var m = model
        switch m.setFacelets(facelets) {
        case .success:
            model = m
            clearSolve()
            message = "已识别魔方状态"
            stopTimerUI()
            accumulatedElapsed = 0
            return true
        case .failure(let e):
            message = "魔方状态非法：\(e)"
            return false
        }
    }

    // MARK: - 手动转层（按钮/手势双模式共用）

    /// 施加一步转动。返回是否恰好还原（虚拟模式据此自动停表）。
    @discardableResult
    func apply(_ move: Move) -> Bool {
        var m = model
        let solved = m.apply(move)
        model = m
        // 虚拟模式：转完检测是否还原，还原则自动停表
        if solved && m.identity == .virtual {
            finalizeSolve()
            // 2 阶指引：还原成功即结束指引，避免卡在"下一步"
            if model.order == 2 { clear2x2Solve() }
        }
        // 指引会话中：转层后重新对齐轨道
        reevaluateAlignment()
        return solved
    }

    /// 连续回退一步（一路可退到 checkpoint）
    @discardableResult
    func undo() -> Bool {
        var m = model
        let ok = m.undo()
        model = m
        if ok {
            // 指引会话中：回退后重新对齐轨道（教程自动对齐到当前步）
            reevaluateAlignment()
        }
        return ok
    }

    /// 指引会话中，用当前魔方状态与轨道比对，更新对齐进度/脱轨提示。
    private func reevaluateAlignment() {
        guard let sol = solveSession else { return }
        if let step = sol.alignedStep(of: model.cube) {
            alignedStep = step
            offTrackMessage = nil
        } else {
            // 脱轨：告知用户该转哪一步（下一步该做的动作）
            let target = alignedStep < sol.totalSteps ? sol.move(at: alignedStep)?.notation : nil
            offTrackMessage = target.map { "这步该转 \($0)，或点「回退」回到轨道" } ?? "偏离教程轨道，点「回退」返回"
        }
    }

    // MARK: - 计时

    /// 开始计时（虚拟/物理通用入口）。若已在暂停态累计，则从累计值继续。
    func startTiming() {
        var m = model
        m.startTiming()
        model = m
        startTimerUI()
    }

    /// 暂停计时：停表但保留已累计用时（不清零），供「继续」恢复。
    func pauseTiming() {
        guard model.isTiming else { return }
        let d = model.elapsed(at: Date())
        accumulatedElapsed += d
        var m = model
        _ = m.stopTiming()
        model = m
        stopTimerUI()
        liveElapsed = accumulatedElapsed
    }

    /// 停止计时（返回本次总用时，含累计段）。清空累计。
    @discardableResult
    func stopTiming() -> TimeInterval {
        let d = accumulatedElapsed + model.elapsed(at: Date())
        var m = model
        _ = m.stopTiming()
        model = m
        stopTimerUI()
        accumulatedElapsed = 0
        return d
    }

    /// 手动结算一次成绩（物理模式：用户觉得自己完成了，手动停表）
    func finishManualSolve() {
        let d = stopTiming()
        guard d > 0.5 else { return }  // 过滤误触
        let record = SolveRecord(id: UUID().uuidString,
                                 duration: d,
                                 moves: undoCount,
                                 scramble: "-",
                                 date: Date(),
                                 order: model.order)
        history.insert(record, at: 0)
        saveHistoryToDefaults()
        message = "复原！用时 \(Self.format(d))"
    }

    /// 虚拟模式自动停表结算
    private func finalizeSolve() {
        let d = stopTiming()
        guard d > 0.5 else { return }
        let record = SolveRecord(id: UUID().uuidString,
                                 duration: d,
                                 moves: undoCount,
                                 scramble: "-",
                                 date: Date(),
                                 order: model.order)
        history.insert(record, at: 0)
        saveHistoryToDefaults()
        message = "🎉 复原！用时 \(Self.format(d))"
    }

    // MARK: - 还原指引（学习）

    /// 以当前状态为起点，构建还原指引会话（后台求解，避免卡 UI）
    func solve() {
        guard !isSolving else { return }
        let facelets = model.cube.facelets
        // 已还原则无需指引
        guard !CubeState(facelets: facelets).isSolved else {
            message = "魔方已还原"
            return
        }
        guard CubeValidator.isValid(facelets: facelets) else {
            message = "魔方状态非法，无法求解"
            return
        }
        isSolving = true
        message = nil
        // 关键：后台线程只做「纯计算」——facelets 是值类型（[Int]），在主线程取值后
        // 跨线程传递安全；不在后台闭包捕获 @MainActor 的 self，避免隔离边界隐患。
        DispatchQueue.global(qos: .userInitiated).async {
            let session = SolveSession(startFacelets: facelets)   // 可能首次构建 Kociemba BFS 表，耗时数百 ms~秒级
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSolving = false
                if let session {
                    self.solveSession = session
                    self.alignedStep = 0
                    self.offTrackMessage = nil
                    self.message = "共 \(session.totalSteps) 步，跟着做即可"
                } else {
                    self.message = "求解失败，请检查魔方状态"
                }
            }
        }
    }

    /// 退出还原指引（3 阶 SolveSession + 2 阶极简指引一并清）
    func clearSolve() {
        solveSession = nil
        alignedStep = 0
        offTrackMessage = nil
        message = nil
        clear2x2Solve()
    }

    /// 手动推进到下一步（物理模式：App 看不见真魔方，用户自己拧完点「下一步」）。
    /// 虚拟模式由 apply/undo 自动 evaluate，一般无需手动推进，但保留兜底。
    func advanceStep() {
        guard let sol = solveSession, alignedStep < sol.totalSteps else { return }
        alignedStep += 1
        offTrackMessage = nil
    }

    /// 手动回退一步（查看上一步）。
    func retreatStep() {
        guard solveSession != nil, alignedStep > 0 else { return }
        alignedStep -= 1
        offTrackMessage = nil
    }

    /// 回正 3D 视角（自增令牌，Cube3DView 检测到变化即复位相机）
    func resetCamera() {
        cameraResetToken += 1
    }

    // MARK: - 2 阶还原指引（极简：Solver2x2 秒解 → 照做 → 转完检测）

    /// 是否处于 2 阶指引中
    var isIn2x2Solve: Bool { isOrder2 && !solve2x2Steps.isEmpty }

    /// 当前 2 阶指引应转的下一步（nil = 未进入/已完成）
    func current2x2Move() -> Move? {
        guard isIn2x2Solve, solve2x2StepIndex < solve2x2Steps.count else { return nil }
        return solve2x2Steps[solve2x2StepIndex]
    }

    /// 求解当前 2 阶状态（后台，避免卡 UI），产出解法步骤。
    func solve2x2() {
        guard isOrder2 else { return }
        guard !isSolving else { return }
        guard let c2 = model.cube2 else {
            message = "无 2 阶状态"
            return
        }
        guard !c2.isSolved else {
            message = "2 阶已还原"
            return
        }
        isSolving = true
        message = nil
        let facelets = c2.facelets   // 值类型，主线程取值后跨线程安全
        DispatchQueue.global(qos: .userInitiated).async {
            let steps = Solver2x2.solve(facelets) ?? []
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSolving = false
                guard !steps.isEmpty else {
                    self.message = "2 阶求解失败，请检查状态"
                    return
                }
                self.solve2x2Steps = steps
                self.solve2x2StepIndex = 0
                self.message = "共 \(steps.count) 步，照着转即可"
            }
        }
    }

    /// 标记已按指引转了当前步 → 前进一步；若已还原则清指引
    func advance2x2Step() {
        guard isIn2x2Solve else { return }
        solve2x2StepIndex += 1
        if solve2x2StepIndex >= solve2x2Steps.count {
            solve2x2Steps = []
            solve2x2StepIndex = 0
        }
    }

    /// 退出 2 阶指引
    func clear2x2Solve() {
        solve2x2Steps = []
        solve2x2StepIndex = 0
    }

    // MARK: - Timer（UI 显示驱动）

    private func startTimerUI() {
        stopTimerUI()
        liveElapsed = accumulatedElapsed
        let t = Timer.scheduledTimer(timeInterval: 0.1, target: self,
                                     selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimerUI() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        liveElapsed = accumulatedElapsed + model.elapsed(at: Date())
    }

    // MARK: - 历史成绩持久化（UserDefaults）

    private static let historyKey = "cube_history_records"

    private func saveHistoryToDefaults() {
        if let data = try? JSONEncoder().encode(Array(history.prefix(100))) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private static func loadHistoryFromDefaults() -> [SolveRecord] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let records = try? JSONDecoder().decode([SolveRecord].self, from: data) else {
            return []
        }
        return records
    }

    /// 保存资料/偏好到 UserDefaults（profile 改动后调用）
    func saveProfile() {
        profile.save()
    }

    /// 删除单条历史（按 id）
    func deleteHistory(_ id: String) {
        history.removeAll { $0.id == id }
        saveHistoryToDefaults()
    }

    /// 清空全部历史（弹二次确认由 UI 层负责）
    func clearHistory() {
        history.removeAll()
        saveHistoryToDefaults()
    }

    // MARK: - 数据备份 / 恢复（§0.5）

    /// 导出当前成绩 + 资料为 JSON Data（供 UI 写文件/分享）。
    func exportBackupData() -> Data? {
        let backup = BackupData(records: history,
                                nickname: profile.nickname,
                                signature: profile.signature,
                                guideTier: profile.guideTier)
        return BackupManager.encode(backup)
    }

    /// 导入备份：解析 JSON 并覆盖成绩 + 资料。
    /// - 成功：返回 nil（无错误），history/profile 已更新并持久化。
    /// - 失败：返回可读错误信息（供 UI 提示）。
    func importBackupData(_ data: Data) -> String? {
        switch BackupManager.decode(data) {
        case .success(let backup):
            // 覆盖成绩（去重 + 按时间倒序 + 截断 100 条）
            var merged = backup.records
            merged.sort { $0.date > $1.date }
            history = Array(merged.prefix(100))
            saveHistoryToDefaults()
            // 覆盖资料
            profile.nickname = backup.nickname
            profile.signature = backup.signature
            profile.guideTier = GuideTier(rawValue: backup.guideTier) ?? .chinese
            profile.save()
            return nil
        case .failure(let e):
            return e.errorDescription
        }
    }

    // MARK: - 成就回算（纯计算，基于 history 实时推导）

    /// 还原成功总次数
    var totalSolves: Int { history.count }
    /// 最快用时（秒），无记录返回 nil
    var bestTime: TimeInterval? { history.map(\.duration).min() }
    /// 平均用时（秒），无记录返回 nil
    var averageTime: TimeInterval? {
        guard !history.isEmpty else { return nil }
        return history.map(\.duration).reduce(0, +) / Double(history.count)
    }

    // MARK: - 格式化

    /// 统一用时格式（mm:ss.cc，分不补零）。全 App 唯一权威实现。
    static func format(_ t: TimeInterval) -> String { formatSolveTime(t) }
}

/// 全 App 统一的计时格式（mm:ss.cc，分不补零）。
/// 之前散落在 CubeSession / HomeView / MineView / HistoryView 四处、且「分是否补零」
/// 不一致（`%d:%02d` vs `%02d:%02d`），统一收敛到此处，杜绝同一成绩显示两样。
func formatSolveTime(_ t: TimeInterval) -> String {
    let total = Int(t.rounded(.down))
    let m = total / 60
    let s = total % 60
    let cs = Int((t - floor(t)) * 100)
    return String(format: "%d:%02d.%02d", m, s, cs)
}
