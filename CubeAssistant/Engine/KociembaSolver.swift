import Foundation

/// Kociemba 两阶段求解器（Swift 移植自已验证的 Python 实现 / 权威 muodov/kociemba 坐标系）。
///
/// 坐标系约定与魔方学院/标准一致：
/// - 面顺序 U,R,F,D,L,B；每面 9 贴纸，索引 0..53（U0-8, R9-17, F18-26, D27-35, L36-44, B45-53）。
/// - 颜色 id：0=U(白) 1=R(红) 2=F(绿) 3=D(黄) 4=L(橙) 5=B(蓝)。
/// - 转动索引 0..17 与 `Move` 枚举严格对应（0 U,1 U2,2 U',3 R,4 R2,5 R',6 F,7 F2,8 F',9 D,10 D2,11 D',12 L,13 L2,14 L',15 B,16 B2,17 B'）。
///
/// 校验 `verify2.py` 已确认：同态/守恒 0 不符、转移表一致性 0、30 例长打乱端到端失败=0、最长 26 步。
public struct KociembaSolver {

    // MARK: - 立方体 cubie 模型
    public struct Cubie: Equatable {
        public var cp: [Int]   // 8 个角块的位置排列
        public var co: [Int]   // 8 个角块的方向（0/1/2）
        public var ep: [Int]   // 12 个棱块的位置排列
        public var eo: [Int]   // 12 个棱块的方向（0/1）
        public init(cp: [Int], co: [Int], ep: [Int], eo: [Int]) {
            self.cp = cp; self.co = co; self.ep = ep; self.eo = eo
        }
        public static let solved = Cubie(
            cp: Array(0..<8), co: Array(repeating: 0, count: 8),
            ep: Array(0..<12), eo: Array(repeating: 0, count: 12))
    }

    // MARK: - 几何定义（贴纸 → cubie）
    // cornerFacelet：每个角块的 3 个贴纸索引（顺序对应 U/D、次级、再次级）
    static let cornerFacelet: [[Int]] = [
        [8, 9, 20], [6, 18, 38], [0, 36, 47], [2, 45, 11],
        [29, 26, 15], [27, 44, 24], [33, 53, 42], [35, 17, 51],
    ]
    // cornerColor：每个角块的规范颜色顺序 [U/D面色, 顺时, 逆时]
    static let cornerColor: [[Int]] = [
        [0, 1, 2], [0, 2, 4], [0, 4, 5], [0, 5, 1],
        [3, 2, 1], [3, 4, 2], [3, 5, 4], [3, 1, 5],
    ]
    // edgeFacelet：每个棱块的 2 个贴纸索引
    static let edgeFacelet: [[Int]] = [
        [5, 10], [7, 19], [3, 37], [1, 46], [32, 16], [28, 25],
        [30, 43], [34, 52], [23, 12], [21, 41], [50, 39], [48, 14],
    ]
    // edgeColor：每个棱块的规范颜色顺序
    static let edgeColor: [[Int]] = [
        [0, 1], [0, 2], [0, 4], [0, 5], [3, 1], [3, 2],
        [3, 4], [3, 5], [2, 1], [2, 4], [5, 4], [5, 1],
    ]

    // MARK: - 基础转动表（权威实现）
    // 角排列
    static let cpU = [3,0,1,2,4,5,6,7], cpR = [4,1,2,0,7,5,6,3]
    static let cpF = [1,5,2,3,0,4,6,7], cpD = [0,1,2,3,5,6,7,4]
    static let cpL = [0,2,6,3,4,1,5,7], cpB = [0,1,3,7,4,5,2,6]
    // 角方向
    static let coU = [0,0,0,0,0,0,0,0], coR = [2,0,0,1,1,0,0,2]
    static let coF = [1,2,0,0,2,1,0,0], coD = [0,0,0,0,0,0,0,0]
    static let coL = [0,1,2,0,0,2,1,0], coB = [0,0,1,2,0,0,2,1]
    // 棱排列
    static let epU = [3,0,1,2,4,5,6,7,8,9,10,11], epR = [8,1,2,3,11,5,6,7,4,9,10,0]
    static let epF = [0,9,2,3,4,8,6,7,1,5,10,11], epD = [0,1,2,3,5,6,7,4,8,9,10,11]
    static let epL = [0,1,10,3,4,5,9,7,8,2,6,11], epB = [0,1,2,11,4,5,6,10,8,9,3,7]
    // 棱方向（仅 F/B 四分之一转翻棱，U/D/R/L 不翻 —— 标准 Kociemba 关键约定）
    static let eoU = [Int](repeating: 0, count: 12), eoR = [Int](repeating: 0, count: 12)
    static let eoF = [0,1,0,0,0,1,0,0,1,1,0,0], eoD = [Int](repeating: 0, count: 12)
    static let eoL = [Int](repeating: 0, count: 12), eoB = [0,0,0,1,0,0,0,1,0,0,1,1]

    static let MID_EDGES = [8, 9, 10, 11]

    // MARK: - 18 个转动 cubie（6 基础 + 双转 + 逆转）
    static let moveCube: [Cubie] = {
        var mc = [Cubie](repeating: Cubie.solved, count: 18)
        mc[0]  = Cubie(cp: cpU, co: coU, ep: epU, eo: eoU)   // U
        mc[3]  = Cubie(cp: cpR, co: coR, ep: epR, eo: eoR)   // R
        mc[6]  = Cubie(cp: cpF, co: coF, ep: epF, eo: eoF)   // F
        mc[9]  = Cubie(cp: cpD, co: coD, ep: epD, eo: eoD)   // D
        mc[12] = Cubie(cp: cpL, co: coL, ep: epL, eo: eoL)   // L
        mc[15] = Cubie(cp: cpB, co: coB, ep: epB, eo: eoB)   // B
        func twice(_ m: Int) -> Cubie { multiply(mc[m], mc[m]) }
        func inv3(_ m: Int) -> Cubie { multiply(twice(m), mc[m]) }
        mc[1] = twice(0);  mc[2] = inv3(0)
        mc[4] = twice(3);  mc[5] = inv3(3)
        mc[7] = twice(6);  mc[8] = inv3(6)
        mc[10] = twice(9); mc[11] = inv3(9)
        mc[13] = twice(12); mc[14] = inv3(12)
        mc[16] = twice(15); mc[17] = inv3(15)
        return mc
    }()

    /// cubie 乘法：result = multiply(a, b)，与本仓库 Python 验证版完全一致。
    static func multiply(_ a: Cubie, _ b: Cubie) -> Cubie {
        var ncp = [Int](repeating: 0, count: 8)
        var nco = [Int](repeating: 0, count: 8)
        var nep = [Int](repeating: 0, count: 12)
        var neo = [Int](repeating: 0, count: 12)
        for i in 0..<8 {
            ncp[i] = a.cp[b.cp[i]]
            nco[i] = (b.co[i] + a.co[b.cp[i]]) % 3
        }
        for i in 0..<12 {
            nep[i] = a.ep[b.ep[i]]
            neo[i] = (b.eo[i] + a.eo[b.ep[i]]) % 2
        }
        return Cubie(cp: ncp, co: nco, ep: nep, eo: neo)
    }

    static func applyMove(_ c: Cubie, _ m: Int) -> Cubie {
        multiply(c, moveCube[m])
    }

    // MARK: - 坐标索引辅助
    static let pow3 = [1, 3, 9, 27, 81, 243, 729, 2187]
    static let pow2 = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
    static let fact = [1, 1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800, 39916800]
    static let ALL_COMBOS: [[Int]] = {
        var out = [[Int]]()
        func comb(_ start: Int, _ depth: Int, _ cur: inout [Int]) {
            if depth == 4 { out.append(cur); return }
            for i in start..<12 {
                cur.append(i); comb(i + 1, depth + 1, &cur); cur.removeLast()
            }
        }
        var cur = [Int](); comb(0, 0, &cur)
        return out
    }()
    static let SLICE_SOLVED: Int = {
        // 复原态：中间棱在 8,9,10,11
        ALL_COMBOS.firstIndex(of: [8, 9, 10, 11])!
    }()

    static func coIndex(_ co: [Int]) -> Int {
        var v = 0
        for i in 0..<7 { v = v * 3 + co[i] }
        return v
    }
    static func coUnrank(_ v: Int) -> [Int] {
        var co = [Int](repeating: 0, count: 8)
        var x = v
        for i in 0..<7 { co[i] = (x / pow3[6 - i]) % 3; x = x % pow3[6 - i] }
        co[7] = ((-co[0..<7].reduce(0, +)) % 3 + 3) % 3
        return co
    }
    static func eoIndex(_ eo: [Int]) -> Int {
        var v = 0
        for i in 0..<11 { v = v * 2 + eo[i] }
        return v
    }
    static func eoUnrank(_ v: Int) -> [Int] {
        var eo = [Int](repeating: 0, count: 12)
        var x = v
        for i in 0..<11 { eo[i] = (x / pow2[10 - i]) % 2; x = x % pow2[10 - i] }
        eo[11] = (eo[0..<11].reduce(0, +)) % 2
        return eo
    }
    static func sliceIndex(_ ep: [Int]) -> Int {
        var pos = [Int]()
        for p in 0..<12 where MID_EDGES.contains(ep[p]) { pos.append(p) }
        pos.sort()
        return ALL_COMBOS.firstIndex(of: pos)!
    }
    static func sliceSetIdx(_ v: Int) -> [Int] {
        let combo = ALL_COMBOS[v]
        var ep = [Int](repeating: 0, count: 12)
        var mid = MID_EDGES.makeIterator()
        var oth = (0..<12).filter { !MID_EDGES.contains($0) }.makeIterator()
        for p in 0..<12 {
            ep[p] = combo.contains(p) ? mid.next()! : oth.next()!
        }
        return ep
    }
    static func permRank(_ perm: [Int]) -> Int {
        let n = perm.count
        var used = [Bool](repeating: false, count: n)
        var rank = 0
        for i in 0..<n {
            let c = perm[i]
            var cnt = 0
            for j in 0..<c where !used[j] { cnt += 1 }
            used[c] = true
            rank += cnt * fact[n - 1 - i]
        }
        return rank
    }
    static func permUnrank(_ rankIn: Int, _ n: Int) -> [Int] {
        var rank = rankIn
        var perm = [Int](repeating: 0, count: n)
        var used = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let w = fact[n - 1 - i]
            let cnt = rank / w
            rank %= w
            var k = 0, c = 0
            while true {
                if !used[k] {
                    if c == cnt { break }
                    c += 1
                }
                k += 1
            }
            perm[i] = k; used[k] = true
        }
        return perm
    }
    static func cpIndex(_ cp: [Int]) -> Int { permRank(cp) }
    static func cpUnrank(_ v: Int) -> [Int] { permUnrank(v, 8) }
    static func epUDIndex(_ ep: [Int]) -> Int {
        permRank(Array(ep[0..<8]))
    }
    static func epUDSetIdx(_ v: Int) -> [Int] {
        let perm = permUnrank(v, 8)
        var ep = [Int](repeating: 0, count: 12)
        for i in 0..<8 { ep[i] = perm[i] }
        for i in 8..<12 { ep[i] = i }
        return ep
    }
    static func epSliceIndex(_ ep: [Int]) -> Int {
        permRank([ep[8] - 8, ep[9] - 8, ep[10] - 8, ep[11] - 8])
    }
    static func epSliceSetIdx(_ v: Int) -> [Int] {
        let perm = permUnrank(v, 4)
        var ep = [Int](repeating: 0, count: 12)
        for i in 0..<8 { ep[i] = i }
        for i in 0..<4 { ep[8 + i] = 8 + perm[i] }
        return ep
    }

    // MARK: - 转动/剪枝表（构建一次）
    private struct Tables {
        let coMove: [[Int]], eoMove: [[Int]], sliceMove: [[Int]]
        let cpMove: [[Int]], epUDMove: [[Int]], epSliceMove: [[Int]]
        let coTable: [Int], eoTable: [Int], sliceTable: [Int]
        let cpTable: [Int], epUDTable: [Int], epSliceTable: [Int]
    }

    static let PHASE1_MOVES: [Int] = Array(0..<18)
    static let PHASE2_MOVES: [Int] = [0, 1, 2, 9, 10, 11, 4, 7, 13, 16]
    static let MOVE_FACE: [Int] = [0,0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5,5]

    private static let tables: Tables = buildTables()

    private static func buildTables() -> Tables {
        func buildTrans(getIdx: @escaping (Cubie) -> Int,
                        setIdx: @escaping (Int) -> Cubie,
                        n: Int, moves: [Int]) -> [[Int]] {
            var T = [[Int]](repeating: [Int](repeating: 0, count: moves.count), count: n)
            for v in 0..<n {
                let cube = setIdx(v)
                for (mi, m) in moves.enumerated() {
                    T[v][mi] = getIdx(applyMove(cube, m))
                }
            }
            return T
        }
        let coMove = buildTrans(getIdx: { coIndex($0.co) }, setIdx: { Cubie(cp: Array(0..<8), co: coUnrank($0), ep: Array(0..<12), eo: [Int](repeating: 0, count: 12)) }, n: 2187, moves: PHASE1_MOVES)
        let eoMove = buildTrans(getIdx: { eoIndex($0.eo) }, setIdx: { Cubie(cp: Array(0..<8), co: [Int](repeating: 0, count: 8), ep: Array(0..<12), eo: eoUnrank($0)) }, n: 2048, moves: PHASE1_MOVES)
        let sliceMove = buildTrans(getIdx: { sliceIndex($0.ep) }, setIdx: { Cubie(cp: Array(0..<8), co: [Int](repeating: 0, count: 8), ep: sliceSetIdx($0), eo: [Int](repeating: 0, count: 12)) }, n: 495, moves: PHASE1_MOVES)
        let cpMove = buildTrans(getIdx: { cpIndex($0.cp) }, setIdx: { Cubie(cp: cpUnrank($0), co: [Int](repeating: 0, count: 8), ep: Array(0..<12), eo: [Int](repeating: 0, count: 12)) }, n: 40320, moves: PHASE2_MOVES)
        let epUDMove = buildTrans(getIdx: { epUDIndex($0.ep) }, setIdx: { Cubie(cp: Array(0..<8), co: [Int](repeating: 0, count: 8), ep: epUDSetIdx($0), eo: [Int](repeating: 0, count: 12)) }, n: 40320, moves: PHASE2_MOVES)
        let epSliceMove = buildTrans(getIdx: { epSliceIndex($0.ep) }, setIdx: { Cubie(cp: Array(0..<8), co: [Int](repeating: 0, count: 8), ep: epSliceSetIdx($0), eo: [Int](repeating: 0, count: 12)) }, n: 24, moves: PHASE2_MOVES)

        func bfsTable(getIdx: @escaping (Cubie) -> Int, n: Int, moves: [Int]) -> [Int] {
            var dist = [Int](repeating: -1, count: n)
            dist[getIdx(Cubie.solved)] = 0
            var queue = [Cubie.solved]
            var head = 0
            while head < queue.count {
                let cube = queue[head]; head += 1
                let d = dist[getIdx(cube)]
                for m in moves {
                    let nc = applyMove(cube, m)
                    let idx = getIdx(nc)
                    if dist[idx] == -1 {
                        dist[idx] = d + 1
                        queue.append(nc)
                    }
                }
            }
            return dist
        }
        let coTable = bfsTable(getIdx: { coIndex($0.co) }, n: 2187, moves: PHASE1_MOVES)
        let eoTable = bfsTable(getIdx: { eoIndex($0.eo) }, n: 2048, moves: PHASE1_MOVES)
        let sliceTable = bfsTable(getIdx: { sliceIndex($0.ep) }, n: 495, moves: PHASE1_MOVES)
        let cpTable = bfsTable(getIdx: { cpIndex($0.cp) }, n: 40320, moves: PHASE2_MOVES)
        let epUDTable = bfsTable(getIdx: { epUDIndex($0.ep) }, n: 40320, moves: PHASE2_MOVES)
        let epSliceTable = bfsTable(getIdx: { epSliceIndex($0.ep) }, n: 24, moves: PHASE2_MOVES)

        return Tables(coMove: coMove, eoMove: eoMove, sliceMove: sliceMove,
                      cpMove: cpMove, epUDMove: epUDMove, epSliceMove: epSliceMove,
                      coTable: coTable, eoTable: eoTable, sliceTable: sliceTable,
                      cpTable: cpTable, epUDTable: epUDTable, epSliceTable: epSliceTable)
    }

    // MARK: - facelet → cubie 提取
    /// 输入 54 个颜色 id（0..5，顺序 U0-8,R9-17,F18-26,D27-35,L36-44,B45-53）。
    public static func toCubie(_ f: [Int]) -> Cubie {
        var cp = [Int](repeating: 0, count: 8)
        var co = [Int](repeating: 0, count: 8)
        var ep = [Int](repeating: 0, count: 12)
        var eo = [Int](repeating: 0, count: 12)
        let ud = Set([0, 3])
        for i in 0..<8 {
            var ori = -1
            for o in 0..<3 where ud.contains(f[cornerFacelet[i][o]]) { ori = o; break }
            let col1 = f[cornerFacelet[i][(ori + 1) % 3]]
            let col2 = f[cornerFacelet[i][(ori + 2) % 3]]
            for j in 0..<8 where col1 == cornerColor[j][1] && col2 == cornerColor[j][2] {
                cp[i] = j; co[i] = ori % 3; break
            }
        }
        for i in 0..<12 {
            let a = f[edgeFacelet[i][0]], b = f[edgeFacelet[i][1]]
            for j in 0..<12 {
                if a == edgeColor[j][0] && b == edgeColor[j][1] { ep[i] = j; eo[i] = 0; break }
                if a == edgeColor[j][1] && b == edgeColor[j][0] { ep[i] = j; eo[i] = 1; break }
            }
        }
        return Cubie(cp: cp, co: co, ep: ep, eo: eo)
    }

    // MARK: - 两阶段 IDA*
    public static func phase1(_ cube: Cubie) -> [Int]? {
        let t = tables
        let ci = coIndex(cube.co), ei = eoIndex(cube.eo), si = sliceIndex(cube.ep)
        if ci == 0 && ei == 0 && si == SLICE_SOLVED { return [] }
        var best: [Int]? = nil
        func dfs(_ c: Int, _ e: Int, _ s: Int, _ depth: Int, _ last: Int, _ path: [Int]) -> Bool {
            if c == 0 && e == 0 && s == SLICE_SOLVED { best = path; return true }
            let h = max(t.coTable[c], t.eoTable[e], t.sliceTable[s])
            if depth <= 0 || h > depth { return false }
            for m in PHASE1_MOVES {
                if MOVE_FACE[m] == last { continue }
                let nc = t.coMove[c][m], ne = t.eoMove[e][m], ns = t.sliceMove[s][m]
                if dfs(nc, ne, ns, depth - 1, MOVE_FACE[m], path + [m]) { return true }
            }
            return false
        }
        for d in 1...20 {
            if dfs(ci, ei, si, d, -1, []) { break }
        }
        return best
    }

    public static func phase2(_ cube: Cubie) -> [Int]? {
        let t = tables
        let ci = cpIndex(cube.cp), ui = epUDIndex(cube.ep), si = epSliceIndex(cube.ep)
        if ci == 0 && ui == 0 && si == 0 { return [] }
        var best: [Int]? = nil
        func dfs(_ c: Int, _ u: Int, _ s: Int, _ depth: Int, _ last: Int, _ path: [Int]) -> Bool {
            if c == 0 && u == 0 && s == 0 { best = path; return true }
            let h = max(t.cpTable[c], t.epUDTable[u], t.epSliceTable[s])
            if depth <= 0 || h > depth { return false }
            for (mi, m) in PHASE2_MOVES.enumerated() {
                if MOVE_FACE[m] == last { continue }
                // 关键：转移表按 PHASE2_MOVES 列号 mi 索引，输出用真实转动 m
                let nc = t.cpMove[c][mi], nu = t.epUDMove[u][mi], ns = t.epSliceMove[s][mi]
                if dfs(nc, nu, ns, depth - 1, MOVE_FACE[m], path + [m]) { return true }
            }
            return false
        }
        for d in 1...21 {
            if dfs(ci, ui, si, d, -1, []) { break }
        }
        return best
    }

    public static func solveCubie(_ cube: Cubie) -> [Int]? {
        guard let p1 = phase1(cube) else { return nil }
        var c1 = cube
        for m in p1 { c1 = applyMove(c1, m) }
        guard let p2 = phase2(c1) else { return nil }
        return p1 + p2
    }

    // MARK: - 公开 API
    /// 输入 54 颜色 id 的魔方，返回转动索引序列（0..17），无解返回 nil。
    public static func solve(facelets: [Int]) -> [Int]? {
        guard facelets.count == 54 else { return nil }
        let cube = toCubie(facelets)
        return solveCubie(cube)
    }

    /// 返回 `Move` 序列（便于 UI 使用）。
    public static func solve(facelets: [Int]) -> [Move]? {
        guard facelets.count == 54 else { return nil }
        let cube = toCubie(facelets)
        guard let seq = solveCubie(cube) else { return nil }
        return seq.compactMap { Move(rawValue: $0) }
    }
}
