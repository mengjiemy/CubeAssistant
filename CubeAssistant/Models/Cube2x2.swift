import Foundation

// ============================================================
// 魔方学院 · 2×2 阶魔方领域模型（纯 Foundation，可本地测试）
//
// 设计：2 阶魔方 = 8 个角块，无棱、无中心。每面 4 贴纸，共 24 面片。
// 关键洞察：2 阶的 8 个角块与 3 阶的 8 个角块是**同一套**（位置/方向/转动完全一致）。
// 因此 2 阶可以直接复用 3 阶已充分验证的 `movePerms`（54 元素置换表）：
//   - 把 24 个 2 阶面片映射到 3 阶的 24 个「角贴纸」位置
//   - 应用 3 阶 movePerms 后，再提取回 24 面片
// 求解同理：用 3 阶 Kociemba 的角块坐标（cp/co）做 2 阶求解。
// ============================================================

/// 2 阶魔方几何常量
enum Cube2x2Geometry {
    static let order = 2
    static let perFace = 4       // 2×2
    static let faceCount = 6
    static let totalFacelets = 24  // 6 × 4
}

/// 2 阶魔方状态（24 面片，颜色 id 0..5，面顺序 U,R,F,D,L,B）。
public struct Cube2x2: Equatable {
    public var facelets: [Int]  // 长度 24

    public init(solved: Bool = true) {
        if solved {
            facelets = (0..<Cube2x2Geometry.faceCount).flatMap { face in
                Array(repeating: face, count: Cube2x2Geometry.perFace)
            }
        } else {
            facelets = Array(0..<Cube2x2Geometry.totalFacelets)
        }
    }

    public init(facelets: [Int]) {
        precondition(facelets.count == Cube2x2Geometry.totalFacelets)
        self.facelets = facelets
    }

    /// 是否已复原（每面纯色）
    public var isSolved: Bool {
        for f in 0..<Cube2x2Geometry.faceCount {
            let base = f * Cube2x2Geometry.perFace
            let c = facelets[base]
            for k in 1..<Cube2x2Geometry.perFace where facelets[base + k] != c { return false }
        }
        return true
    }

    /// 应用一次转动（moveIndex 对应 Move 枚举 0..17，与 3 阶 movePerms 下标一致）。
    /// 通过「映射到 3 阶角贴纸 → 应用 3 阶 movePerms → 提取回 24」实现，
    /// 复用已验证的 3 阶置换表，避免为 2 阶单独维护一份易错的转动表。
    public mutating func apply(_ moveIndex: Int) {
        facelets = Self.applyPerm(facelets, moveIndex)
    }

    public func applying(_ moveIndex: Int) -> Cube2x2 {
        var c = self; c.apply(moveIndex); return c
    }

    // MARK: - 3 阶角贴纸映射

    /// 2 阶面片索引 → 3 阶面片索引（24 个角贴纸位置）。
    /// 3 阶每面 9 贴纸（row-major）的 4 个角 = 0,2,6,8 偏移。
    static let cornerOffsets: [Int] = [0, 2, 6, 8]  // 2×2 网格的四个角在 3×3 网格中的位置

    /// 2 阶面片 i → 3 阶面片索引
    static func to3x3Index(_ i: Int) -> Int {
        let face = i / Cube2x2Geometry.perFace        // 0..5
        let pos = i % Cube2x2Geometry.perFace         // 0..3（2×2 内 row-major）
        return face * CubeGeometry.three.perFace + cornerOffsets[pos]
    }

    /// 把 2 阶 24 面片展开成 3 阶 54 面片（角位置填 2 阶值，棱/中心填 -1 占位）。
    static func expandTo3x3(_ f24: [Int]) -> [Int] {
        var f54 = [Int](repeating: -1, count: CubeGeometry.three.totalFacelets)
        for i in 0..<Cube2x2Geometry.totalFacelets {
            f54[to3x3Index(i)] = f24[i]
        }
        return f54
    }

    /// 从 3 阶 54 面片（仅角位置有效）提取回 2 阶 24 面片。
    static func extractFrom3x3(_ f54: [Int]) -> [Int] {
        var f24 = [Int](repeating: 0, count: Cube2x2Geometry.totalFacelets)
        for i in 0..<Cube2x2Geometry.totalFacelets {
            f24[i] = f54[to3x3Index(i)]
        }
        return f24
    }

    /// 应用 3 阶 movePerms 到 2 阶状态（核心复用点）。
    static func applyPerm(_ f24: [Int], _ moveIndex: Int) -> [Int] {
        let f54 = expandTo3x3(f24)
        let p = movePerms[moveIndex]
        var next = [Int](repeating: -1, count: CubeGeometry.three.totalFacelets)
        for i in 0..<CubeGeometry.three.totalFacelets {
            next[i] = f54[p[i]]
        }
        return extractFrom3x3(next)
    }

    /// 随机打乱（复用 ScrambleGenerator，转成 Move 再应用）
    public static func scrambled(count: Int = 12) -> Cube2x2 {
        var c = Cube2x2(solved: true)
        for m in ScrambleGenerator.generate(length: count) {
            c.apply(m.rawValue)
        }
        return c
    }
}

/// 2 阶求解器：角块坐标 + 双向 BFS（God's number = 11，秒级求解）。
///
/// 为什么不用 3 阶 Kociemba 套 2 阶：把 2 阶「角乱棱还原」喂给 3 阶两阶段求解器，
/// 会让 phase2 的 DFS 搜索空间异常大（8! 角排列无棱块辅助剪枝），单次可达数秒~数十秒，
/// 某些随机态甚至超时。2 阶本质是「8 角块」子问题，用角块坐标双向 BFS 才是正解。
public enum Solver2x2 {
    /// 状态编码：角排列 cp（8 数组）+ 角方向 co（8 数组），直接 Hashable。
    /// 用数组（而非 rank/unrank）作为 key，applyMove 只需 O(8) 的排列组合，
    /// 避免双向 BFS 大量状态时反复做 8! 排列编解码的 O(8²) 开销。
    private struct State: Hashable {
        let cp: [Int]
        let co: [Int]
    }

    /// 求解 2 阶，返回 Move 序列（0..17），无解返回 nil。
    public static func solve(_ facelets: [Int]) -> [Move]? {
        guard facelets.count == Cube2x2Geometry.totalFacelets else { return nil }

        // 把 2 阶面片映射到 3 阶角贴纸，棱/中心填还原态，提取角块
        var f54 = [Int](repeating: 0, count: CubeGeometry.three.totalFacelets)
        for face in 0..<Cube2x2Geometry.faceCount {
            for k in 0..<CubeGeometry.three.perFace { f54[face * CubeGeometry.three.perFace + k] = face }
        }
        for i in 0..<Cube2x2Geometry.totalFacelets {
            f54[Cube2x2.to3x3Index(i)] = facelets[i]
        }
        let cubie = KociembaSolver.toCubie(f54)
        let start = State(cp: cubie.cp, co: cubie.co)
        let goal = State(cp: Array(0..<8), co: [Int](repeating: 0, count: 8))

        if start == goal { return [] }

        // 双向 BFS：前向（打乱→还原）、后向（还原→打乱）
        var front: [State: [Int]] = [start: []]
        var back: [State: [Int]] = [goal: []]
        var frontQueue: [State] = [start]
        var backQueue: [State] = [goal]

        // 2 阶 God's number = 11，双向各 6 层内必相遇
        for _ in 0..<6 {
            var nextFront: [State] = []
            for s in frontQueue {
                let path = front[s]!
                let lastFace = path.last.map { KociembaSolver.MOVE_FACE[$0] }
                for m in 0..<18 {
                    if KociembaSolver.MOVE_FACE[m] == lastFace { continue }
                    let ns = applyMove(s, m)
                    if front[ns] != nil { continue }
                    let np = path + [m]
                    if back[ns] != nil { return merge(front: np, back: back[ns]!) }
                    front[ns] = np
                    nextFront.append(ns)
                }
            }
            frontQueue = nextFront

            var nextBack: [State] = []
            for s in backQueue {
                let path = back[s]!
                let lastFace = path.last.map { KociembaSolver.MOVE_FACE[$0] }
                for m in 0..<18 {
                    if KociembaSolver.MOVE_FACE[m] == lastFace { continue }
                    let ns = applyMove(s, m)
                    if back[ns] != nil { continue }
                    let np = path + [m]
                    if front[ns] != nil { return merge(front: front[ns]!, back: np) }
                    back[ns] = np
                    nextBack.append(ns)
                }
            }
            backQueue = nextBack
        }

        return nil
    }

    /// 对状态应用 move：cp/co 数组与 moveCube[m] 组合，O(8)。
    private static func applyMove(_ s: State, _ m: Int) -> State {
        let mc = KociembaSolver.moveCube[m]
        var ncp = [Int](repeating: 0, count: 8)
        var nco = [Int](repeating: 0, count: 8)
        for i in 0..<8 {
            ncp[i] = s.cp[mc.cp[i]]
            nco[i] = (s.co[mc.cp[i]] + mc.co[i]) % 3
        }
        return State(cp: ncp, co: nco)
    }

    /// 合并前向路径（打乱→中间）与后向路径（还原→中间），拼成完整解。
    private static func merge(front: [Int], back: [Int]) -> [Move] {
        let invBack = back.reversed().map { inverseMove($0) }
        let all = front + invBack
        return all.compactMap { Move(rawValue: $0) }
    }

    /// 转动索引 → 逆转动索引（0(U)→2(U')，1(U2)→1，2(U')→0）
    private static func inverseMove(_ m: Int) -> Int {
        let kind = m % 3
        let invKind = (kind == 0) ? 2 : (kind == 2 ? 0 : 1)
        return (m / 3) * 3 + invKind
    }
}
