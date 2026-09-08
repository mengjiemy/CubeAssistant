import Foundation

// ============================================================
// 还原指引 · 轨道模型（功能说明书 §4，26 条定稿）
//
// 概念：还原指引 = 一条「轨道」（解法步骤序列）。轨道从「进入还原时的乱态」
//       （startFacelets）出发，每步标准转动即可逐步还原。
//
// 本类是一个纯函数式的"轨道比对器"：
// - 持有轨道 orbit + 轨道起点 startFacelets
// - 不自己持有魔方状态；由外部把「当前 CubeState」传进来 evaluate，
//   算出当前状态与轨道对齐到第几步（0 = 起点，totalSteps = 已还原）。
//
// 由此天然支持：
//   · 虚拟模式：用户在屏幕转 → 每转一步 evaluate → 系统判定你已正确走到第几步；
//     转错 → 显示"该转的是 X"，用户 undo 撤回即可（连续回退到最初）。
//   · 物理模式：App 看不见用户真魔方 → 不 evaluate（屏幕当说明书），
//     进度由用户手动标记。
//
// 「回退」= 对 CubeModel 连续 undo（可一路退回 checkpoint）。轨道不因回退而消失，
// evaluate 会如实反映你当前退到了对齐进度第几步，教程文字自动对齐。
// ============================================================

/// 还原指引会话
struct SolveSession: Equatable {
    /// 轨道起点（= 进入还原时的乱态 facelets，用户 undo 的"最初"基准）
    let startFacelets: [Int]
    /// 解法轨道：从 startFacelets 解回复原的标准步序
    let orbit: [Move]

    /// 用轨道起点求解，构建会话。若输入非法（不可还原）或已还原则返回 nil。
    init?(startFacelets: [Int]) {
        // 1) 必须 54 个、每种颜色 9 次、角/棱方向与奇偶性合法（可被还原）
        guard CubeValidator.isValid(facelets: startFacelets) else { return nil }
        // 2) 不能是已还原态（已还原无需还原指引）
        guard !CubeState(facelets: startFacelets).isSolved else { return nil }
        // 3) 求解必须成功
        guard let sol: [Move] = KociembaSolver.solve(facelets: startFacelets),
              !sol.isEmpty else { return nil }
        self.startFacelets = startFacelets
        self.orbit = sol
    }

    /// 轨道总步数（不含打乱，纯解法）
    var totalSteps: Int { orbit.count }

    /// 当前是否已走完（对齐到总步数 = 已还原）
    func isComplete(atAligned aligned: Int) -> Bool {
        aligned >= orbit.count
    }

    /// 第 i 步该转什么（0-based），超界返回 nil
    func move(at i: Int) -> Move? {
        guard i >= 0 && i < orbit.count else { return nil }
        return orbit[i]
    }

    /// 计算当前状态与轨道对齐到第几步（0..totalSteps）。
    /// 从 startFacelets 出发，若 state == startFacelets 依次施加 orbit[0..<k] 则返回 k。
    /// - 返回 `Int`：对齐到第 k 步（0 = 仍在起点，totalSteps = 已完全还原）
    /// - 返回 `nil`：state 是轨道之外的乱态（用户转错了/打乱了，脱轨），
    ///   需通过 undo 退回轨道（功能说明书 §4 做法甲：不自动转回，用户手动回退）。
    func alignedStep(of state: CubeState) -> Int? {
        var probe = CubeState(facelets: startFacelets)
        if probe == state { return 0 }
        for (idx, m) in orbit.enumerated() {
            probe.apply(m.rawValue)
            if probe == state { return idx + 1 }
        }
        return nil   // 脱轨
    }
}
