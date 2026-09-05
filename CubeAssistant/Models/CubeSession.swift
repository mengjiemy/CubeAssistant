import Foundation
import SwiftUI

/// 魔方对局会话：持有当前状态、负责打乱 / 求解 / 解法回放 / 计时 / 成绩存档。
///
/// 核心不变式：模型 `cube` 永远等于「从复原态依次施加 `fullSequence[0..<currentStep]` 所得」。
/// 3D 视图只负责把 `currentStep` 的增量以旋转动画呈现，因此模型与 3D 视图天然同步，
/// 无论是打乱、扫描输入还是求解回放都不会脱节。
///
/// UI 层（SwiftUI）直接观察本对象即可驱动界面与 3D 演示。
@MainActor
public final class CubeSession: NSObject, ObservableObject {
    /// 当前魔方状态（facelet 模型，颜色 id 0..5）
    @Published public private(set) var cube = CubeState(solved: true)
    /// 求解得到的步序（仅「复原」部分，用于横向列表展示），不含打乱步
    @Published public private(set) var solution: [Move] = []
    /// 已回放到第几步（索引 `fullSequence`，0 = 复原态）
    @Published public private(set) var currentStep = 0
    /// 代数计数器：打乱 / 重置 / 扫描输入时自增，通知 3D 视图整盘重建
    @Published public private(set) var generation = 0
    /// 是否正在求解（后台计算时置 true，避免界面卡顿）
    @Published public private(set) var isSolving = false
    /// 错误 / 提示信息
    @Published public private(set) var message: String?
    /// 本次解法用时（秒），求解完成并走完步序后写入
    @Published public private(set) var lastDuration: TimeInterval = 0
    /// 历史最佳用时（秒），本地 UserDefaults 持久化
    @Published public private(set) var bestTime: TimeInterval = UserDefaults.standard.double(forKey: "cube_best_time")
    /// 实时计时（求解进行中每秒刷新），用于界面显示
    @Published public private(set) var liveElapsed: TimeInterval = 0
    /// 历史成绩（从 CloudKit 拉取）
    @Published public private(set) var history: [SolveRecord] = []

    /// 已施加到当前 `cube` 上的全部转动（打乱步在前，求解步在后）
    private var fullSequence: [Move] = []
    /// 打乱步（求解步起点偏移，用于进度展示）
    private var scrambleMoves: [Move] = []
    /// 求解开始时刻（解法返回时记录，走到复原态时结算）
    private var solveStart: Date?
    /// 实时计时器
    private var timer: Timer?

    public override init() {}

    /// 供 3D 视图播放用的完整步序（打乱 + 求解）
    public var playbackSequence: [Move] { fullSequence }
    /// 求解步在 `playbackSequence` 中的起点
    public var solutionBase: Int { scrambleMoves.count }
    /// 当前模型是否已复原
    public var isSolvedNow: Bool { cube.isSolved }

    /// 复原到初始状态。
    public func reset() {
        generation += 1
        fullSequence = []
        scrambleMoves = []
        solution = []
        currentStep = 0
        solveStart = nil
        stopTimer()
        cube = CubeState(solved: true)
        message = nil
    }

    /// 随机打乱（默认 25 步），同面连续转动会被避免，更接近真实手拧。
    /// 打乱本身也会经由 3D 视图以动画呈现。
    public func scramble(count: Int = 25) {
        var moves: [Move] = []
        var prevFace = -1
        for _ in 0..<count {
            var m: Move
            repeat {
                m = Move(rawValue: Int.random(in: 0..<18))!
            } while m.face.rawValue == prevFace
            moves.append(m)
            prevFace = m.face.rawValue
        }
        scrambleMoves = moves
        fullSequence = moves
        currentStep = moves.count
        recomputeCube()
        generation += 1
        solution = []
        solveStart = nil
        stopTimer()
        message = "已打乱，点「求解」获取步骤"
    }

    /// 由摄像头扫描 / 手动编辑写入的完整 54 颜色 id。
    /// 校验通过则更新模型并触发 3D 重建，返回 true；非法返回 false（message 给出原因）。
    @discardableResult
    public func setFacelets(_ facelets: [Int]) -> Bool {
        let errs = CubeValidator.validate(facelets: facelets)
        guard errs.isEmpty else {
            message = "魔方状态非法：\(errs.map { "\($0)" }.joined(separator: "、"))"
            return false
        }
        generation += 1
        fullSequence = []
        scrambleMoves = []
        solution = []
        currentStep = 0
        solveStart = nil
        stopTimer()
        cube = CubeState(facelets: facelets)
        message = "已识别，点「求解」获取步骤"
        return true
    }

    /// 求解当前魔方。先在后台校验 + 计算，完成后再切回主线程更新。
    public func solve() {
        guard !isSolving else { return }
        let facelets = cube.facelets
        let errs = CubeValidator.validate(facelets: facelets)
        guard errs.isEmpty else {
            message = "魔方状态非法：\(errs.map { "\($0)" }.joined(separator: "、"))"
            return
        }
        isSolving = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let owner = self else { return }
            let sol: [Move]? = KociembaSolver.solve(facelets: facelets)
            Task { @MainActor in
                owner.isSolving = false
                guard let sol, !sol.isEmpty else {
                    owner.message = "已复原，无需求解"
                    return
                }
                // 拼接：打乱步 + 求解步。currentStep 保持在打乱步末尾，不触发额外动画。
                owner.fullSequence = owner.scrambleMoves + sol
                owner.solution = sol
                owner.solveStart = Date()
                owner.startTimer()
                owner.message = "共 \(sol.count) 步，开始计时"
            }
        }
    }

    /// 回放前进一步（自动判断方向：向前后/向后退）。
    public func stepForward() {
        guard currentStep < fullSequence.count else { return }
        currentStep += 1
        recomputeCube()
        finalizeIfSolved()
    }

    /// 回放后退一步（逆转动）。
    public func stepBackward() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        recomputeCube()
    }

    /// 一键自动回放全部解法（由 3D 视图负责逐帧动画；此处仅更新逻辑状态）。
    public func applyAll() {
        while currentStep < fullSequence.count { stepForward() }
    }

    /// 走到复原态时结算用时、刷新最佳成绩并存入 CloudKit。
    private func finalizeIfSolved() {
        guard !solution.isEmpty, currentStep == fullSequence.count, cube.isSolved else { return }
        guard let start = solveStart else { return }
        let d = Date().timeIntervalSince(start)
        lastDuration = d
        if bestTime == 0 || d < bestTime {
            bestTime = d
            UserDefaults.standard.set(bestTime, forKey: "cube_best_time")
        }
        message = "复原！用时 \(format(d))，共 \(solution.count) 步"
        solveStart = nil
        stopTimer()
        let scramble = scrambleMoves.map { $0.notation }.joined(separator: " ")
        CloudStore.shared.save(duration: d, moves: solution.count, scramble: scramble)
    }

    /// 从 CloudKit 拉取历史成绩。
    public func loadHistory() {
        CloudStore.shared.fetch { [weak self] records in
            Task { @MainActor in
                self?.history = records
            }
        }
    }

    /// 由 `fullSequence[0..<currentStep]` 重算模型状态，保证与 3D 播放进度一致。
    private func recomputeCube() {
        var c = CubeState(solved: true)
        for m in fullSequence[0..<currentStep] {
            c.apply(m.rawValue)
        }
        cube = c
    }

    /// 启动实时计时（主线程计时器，0.1s 刷新）
    private func startTimer() {
        stopTimer()
        liveElapsed = 0
        timer = Timer.scheduledTimer(timeInterval: 0.1, target: self,
                                     selector: #selector(tick), userInfo: nil, repeats: true)
    }

    /// 停止实时计时
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        liveElapsed = 0
    }

    @objc private func tick() {
        guard let start = solveStart else { return }
        liveElapsed = Date().timeIntervalSince(start)
    }

    /// 秒数 → "m:ss.cs"
    private func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }
}

/// CloudKit 成绩记录（UI 展示用，结构对齐 CloudStore 的 CKRecord）。
public struct SolveRecord: Identifiable {
    public let id: String
    public let duration: TimeInterval
    public let moves: Int
    public let scramble: String
    public let date: Date
}
