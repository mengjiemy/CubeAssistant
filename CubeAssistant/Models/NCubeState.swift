import Foundation

// ============================================================
// 魔方学院 · N 阶魔方通用状态（order ≥ 4，纯 Foundation 可本地测试）
//
// 3 阶用 CubeState（54 facelet）+ Kociemba 求解；2 阶用 Cube2x2。
// 本类型服务 4~10 阶：每阶 totalFacelets = 6·N²，转动表来自
// tools/gen_perms.py 生成的 MovePerms{N}.swift（18 个置换，下标与
// Move 枚举 0..17 严格一致：U,U2,U',R,R2,R',…）。
//
// 目标（这一阶段）：让高阶魔方「可玩」——能选定阶数 → 看到对应 3D
// 魔方 → 打乱 → 手动转动 → 判定是否还原。降阶「扫描→引导还原」的
// 自动求解器为独立长线算法工程，不在本阶段。
//
// 设计要点：
// - facelets[i] 存颜色 id 0..5，面序 U,R,F,D,L,B，row-major。
// - apply(Move) 用对应阶 MovePerms 的置换做 new[i]=old[perm[i]]。
// - 只有最外层转动（wide turn / 内层 slice 不暴露给「还原判定」层），
//   与 3 阶 Move 枚举一致（U/R/F/D/L/B 六个面），保证高阶手动玩时
//   只转动最外层、能被 isSolved 正确判定。
// ============================================================

/// N 阶（4~10）几何：坐标支持半整数（偶数阶）。坐标为「块中心」，
/// 单位边长 1：奇数阶块坐标 ∈ {…, -1, 0, 1, …}，偶数阶 ∈ {…, -1.5, -0.5, 0.5, 1.5, …}。
struct NCubeGeometry: Equatable {
    let order: Int
    init(_ order: Int) { precondition(order >= 4 && order <= 10, "NCubeState 仅服务 4~10 阶"); self.order = order }

    var perFace: Int { order * order }
    var totalFacelets: Int { 6 * perFace }
    var faceCount: Int { 6 }

    /// 每维块坐标的「单位」：偶数阶为 1，坐标步进 1；块中心在 (i+0.5)*(偶数) 处用乘以 unit 表达
    /// 这里采用「格心坐标 = (col - (order-1)/2)」，返回的是**中心偏移的格序列**（可为半整数 ×2 表示）
    /// coord2x[col] = 2*(col - (order-1)/2)，是整数，/2 即真实中心坐标。
    func coord2x(_ i: Int) -> Int { 2 * i - (order - 1) }  // i∈0..<order

    /// 判断 (x,y,z) 格是否属于可见块（非内部核心）。可见块 = 至少有一面露出的块。
    /// 用「每维 ∈ 0..<order」的格坐标判断最简单：可见块 = 至少一个维度在边界。
    func isVisible(_ gx: Int, _ gy: Int, _ gz: Int) -> Bool {
        // gx,gy,gz ∈ 0..<order；可见 = x,y,z 至少有一个等于 0 或 order-1
        return gx == 0 || gx == order - 1 || gy == 0 || gy == order - 1 || gz == 0 || gz == order - 1
    }

    /// 第 gx 列对应的「中心坐标」（世界单位），用于放置 cubelet 节点。
    func centerX(_ gx: Int) -> Float { Float(gx) - Float(order - 1) / 2.0 }
}

/// N 阶（4~10）魔方状态。
struct NCubeState: Equatable {
    var facelets: [Int]          // 长度 = 6·N²
    let geometry: NCubeGeometry

    init(order: Int, solved: Bool = true) {
        let g = NCubeGeometry(order)
        self.geometry = g
        if solved {
            facelets = (0..<g.faceCount).flatMap { f in Array(repeating: f, count: g.perFace) }
        } else {
            facelets = Array(0..<g.totalFacelets)
        }
    }

    init(facelets: [Int], order: Int) {
        let g = NCubeGeometry(order)
        precondition(facelets.count == g.totalFacelets)
        self.geometry = g
        self.facelets = facelets
    }

    /// 对应阶的 18 个置换表（MovePerms{order}）。
    static func moveTable(order: Int) -> [[Int]] {
        switch order {
        case 4: return MovePerms4.table
        case 5: return MovePerms5.table
        case 6: return MovePerms6.table
        case 7: return MovePerms7.table
        case 8: return MovePerms8.table
        case 9: return MovePerms9.table
        case 10: return MovePerms10.table
        default: preconditionFailure("order \(order) 无置换表")
        }
    }

    var perFace: Int { geometry.perFace }

    /// 是否已复原（每面纯色）
    var isSolved: Bool {
        for f in 0..<geometry.faceCount {
            let base = f * perFace
            let c = facelets[base]
            for k in 1..<perFace where facelets[base + k] != c { return false }
        }
        return true
    }

    /// 应用一次转动（moveIndex = Move.rawValue，0..26）。
    /// 高阶当前只支持最外层转动（U/R/F/D/L/B），内层 M/E/S 忽略。
    mutating func apply(_ moveIndex: Int) {
        guard moveIndex < 18 else { return }
        let table = Self.moveTable(order: geometry.order)
        let p = table[moveIndex]
        let old = facelets
        for i in 0..<facelets.count { facelets[i] = old[p[i]] }
    }

    func applying(_ moveIndex: Int) -> NCubeState {
        var c = self; c.apply(moveIndex); return c
    }

    /// 随机打乱：做 count 次随机最外层转动（含偶发 180°），返回所用步骤便于回放/展示。
    mutating func scramble(count: Int) -> [Move] {
        var moves: [Move] = []
        var lastFace: Face? = nil
        for _ in 0..<count {
            let f = Face.allCases.filter { $0 != lastFace }.randomElement() ?? .U
            let turn = [1, 1, 2, 3, 3].randomElement() ?? 1   // 偏重 90°
            let mv = Move.face(f, turn) ?? .U
            apply(mv.rawValue)
            moves.append(mv)
            lastFace = f
        }
        return moves
    }

    /// 全复位
    mutating func reset() {
        facelets = (0..<geometry.faceCount).flatMap { f in Array(repeating: f, count: perFace) }
    }
}

extension Move {
    /// 依据面 + 转动量(1/2/3) 构造（供 N 阶打乱复用，等价 moveFor）
    static func face(_ f: Face, _ turn: Int) -> Move? {
        switch (f, turn) {
        case (.U, 1): return .U; case (.U, 2): return .U2; case (.U, 3): return .Up
        case (.R, 1): return .R; case (.R, 2): return .R2; case (.R, 3): return .Rp
        case (.F, 1): return .F; case (.F, 2): return .F2; case (.F, 3): return .Fp
        case (.D, 1): return .D; case (.D, 2): return .D2; case (.D, 3): return .Dp
        case (.L, 1): return .L; case (.L, 2): return .L2; case (.L, 3): return .Lp
        case (.B, 1): return .B; case (.B, 2): return .B2; case (.B, 3): return .Bp
        default: return nil
        }
    }
}

#if DEBUG
extension NCubeState {
    /// 自检：每个最外层转动 4 次回原；从还原态随机打乱后 isSolved == false（打乱充分时）；
    /// 回放打乱逆序可回到还原态（验证置换表自身闭合且与 Move 对齐）。
    static func runSelfCheck() -> Bool {
        var ok = true
        for order in 4...10 {
            let table = moveTable(order: order)
            // 1) 每个 move 4 次回原
            for mi in 0..<18 {
                var c = NCubeState(order: order, solved: true)
                for _ in 0..<4 { c.apply(mi) }
                if !c.isSolved { ok = false; print("[NCube] order=\(order) move \(mi) 4次未还原") }
            }
            // 2) 表长度与面片数一致
            if table.count != 18 { ok = false; print("[NCube] order=\(order) 表数 != 18") }
            for p in table where p.count != (6 * order * order) {
                ok = false; print("[NCube] order=\(order) 置换长度错误")
                break
            }
            // 3) 打乱 + 逆序回放还原
            var c = NCubeState(order: order, solved: true)
            var applied: [Move] = []
            for _ in 0..<40 {
                let m = Move.face(Face.allCases.randomElement()!, [1,2,3].randomElement()!)!
                c.apply(m.rawValue); applied.append(m)
            }
            if c.isSolved { ok = false; print("[NCube] order=\(order) 打乱后仍solved(异常)") }
            for m in applied.reversed() { c.apply(m.inverted().rawValue) }
            if !c.isSolved { ok = false; print("[NCube] order=\(order) 逆序回放未还原") }
        }
        return ok
    }
}
#endif
