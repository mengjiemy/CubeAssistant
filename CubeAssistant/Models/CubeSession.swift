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

    /// 是否正在求解（后台计算 Kociemba，避免卡 UI）
    @Published private(set) var isSolving: Bool = false

    /// 本地历史成绩（UserDefaults 持久化）
    @Published private(set) var history: [SolveRecord] = []

    private var timer: Timer?
    /// 暂停前累计的用时（秒）。支持「暂停→继续」跨段累计。
    private var accumulatedElapsed: TimeInterval = 0

    override init() {
        super.init()
        history = Self.loadHistoryFromDefaults()
    }

    // MARK: - 便捷查询

    /// 当前魔方状态
    var cube: CubeState { model.cube }
    /// 魔方身份（物理/虚拟）
    var identity: CubeIdentity { model.identity }
    /// 转动方式（按钮/手势）
    var turnMode: TurnMode { model.turnMode }
    /// 是否正在计时
    var isTiming: Bool { model.isTiming }
    /// 是否已还原
    var isSolved: Bool { model.isSolved }
    /// 是否能继续 undo
    var canUndo: Bool { model.canUndo }
    /// undo 已走的步数（自 checkpoint 起）
    var undoCount: Int { model.undoStack.count }

    // MARK: - 身份 / 模式切换

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
        solveSession = nil
        message = nil
        stopTimerUI()
        accumulatedElapsed = 0
    }

    /// 随机打乱（默认 25 步，WCA 风格）
    func scramble(count: Int = 25) {
        var m = model
        m.scramble(count: count)
        model = m
        solveSession = nil
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
            solveSession = nil
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
        }
        return solved
    }

    /// 连续回退一步（一路可退到 checkpoint）
    @discardableResult
    func undo() -> Bool {
        var m = model
        let ok = m.undo()
        model = m
        return ok
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
                                 date: Date())
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
                                 date: Date())
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let session = SolveSession(startFacelets: facelets)
            Task { @MainActor in
                self.isSolving = false
                if let session {
                    self.solveSession = session
                    self.message = "共 \(session.totalSteps) 步，跟着做即可"
                } else {
                    self.message = "求解失败，请检查魔方状态"
                }
            }
        }
    }

    /// 退出还原指引
    func clearSolve() {
        solveSession = nil
        message = nil
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

    // MARK: - 格式化

    static func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }
}

/// 一次复原成绩记录（本地持久化，结构对齐旧 CloudStore 展示）。
struct SolveRecord: Identifiable, Codable, Equatable {
    let id: String
    let duration: TimeInterval
    let moves: Int
    let scramble: String
    let date: Date
}
