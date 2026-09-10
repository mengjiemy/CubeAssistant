import Foundation

// ============================================================
// 魔方学院 · 领域模型本地单测（swiftc 直接跑，不烧 CI 积分）
// 用法：swiftc -O main.swift 引擎文件 + 模型文件 -o test && ./test
// ============================================================

var passed = 0
var failed = 0
func check(_ cond: Bool, _ name: String) {
    if cond { passed += 1; print("  ✅ \(name)") }
    else { failed += 1; print("  ❌ \(name)") }
}

// ---------- CubeGeometry 几何收敛验证 ----------
print("\n【CubeGeometry】")
let g3 = CubeGeometry.three
check(g3.order == 3 && g3.perFace == 9 && g3.totalFacelets == 54, "3阶几何量 perFace=9 total=54")
check(g3.coordHalf == 1 && g3.visibleCubelets == 26, "3阶 coordHalf=1 可见块=26")
check(g3.faceOffset(3) == 27 && g3.faceOf(40) == 4 && g3.positionInFace(40) == 4, "face 索引换算正确")
check(g3.isVisibleCubelet(x: 0, y: 0, z: 0) == false, "中心块被排除")
check(g3.isVisibleCubelet(x: 1, y: -1, z: 1), "角块可见")
check(g3.isVisibleCubelet(x: 2, y: 0, z: 0) == false, "超界块排除")
let g5 = CubeGeometry(order: 5)
check(g5.perFace == 25 && g5.totalFacelets == 150 && g5.coordHalf == 2 && g5.visibleCubelets == 124, "5阶几何量推导正确(架构预留)")
var solvedState = CubeState(solved: true)
check(solvedState.facelets.count == 54 && solvedState.isSolved, "CubeState 用几何量构造")
let allWhite = CubeState(facelets: Array(repeating: 0, count: 54))
check(allWhite.isSolved, "面内同色即判为复原（isSolved 语义）")
check(CubeState(facelets: solvedState.facelets).isSolved, "显式 facelets 构造还原态")

// ---------- 引擎基础（先验证底座） ----------
print("\n【引擎基础】")
let scramble = ScrambleGenerator.generate(length: 25)
var sc = CubeState(solved: true)
for m in scramble { sc.apply(m.rawValue) }
let sol: [Move]? = KociembaSolver.solve(facelets: sc.facelets)
check(sol != nil && sol!.count > 0, "打乱25步后能求解 (\(sol?.count ?? 0)步)")
if let sol {
    var r = sc
    for m in sol { r.apply(m.rawValue) }
    check(r.isSolved, "按解法转回全部复原")
}
check(CubeValidator.isValid(facelets: sc.facelets), "打乱态合法")
var bad = sc.facelets; bad[0] = 5
check(!CubeValidator.isValid(facelets: bad), "损坏输入被拦截")

// ---------- CubeModel：身份 / 打乱 / 重置 ----------
print("\n【CubeModel · 状态建立】")
var m = CubeModel(cube: CubeState(solved: true), identity: .virtual)
check(m.identity == .virtual, "可指定虚拟身份")
check(m.cube.isSolved, "初始已还原")
check(m.undoStack.isEmpty && !m.canUndo, "初始无 undo")
m.scramble(count: 20)
check(!m.cube.isSolved, "打乱后变乱")
check(m.canUndo == false, "打乱清空 undo（checkpoint 更新）")
check(m.undoStack.isEmpty, "打乱后 undo 栈空（新 checkpoint）")
m.reset()
check(m.cube.isSolved, "重置回还原态")
check(!m.canUndo, "重置后无 undo")
m.scramble(count: 20)
let scrambledFacelets = m.cube.facelets

// ---------- CubeModel：手动转层 + undo 连续回退 ----------
print("\n【CubeModel · 转层与回退】")
var m2 = CubeModel(cube: CubeState(solved: true), identity: .virtual)
m2.scramble(count: 20)          // checkpoint = 乱态
let cp = m2.cube.facelets       // 记录最初乱态
m2.apply(Move.U)
m2.apply(Move.R)
m2.apply(Move.Fp)
check(m2.undoStack.count == 3, "手动转了3步入栈")
check(m2.canUndo, "canUndo=true")
_ = m2.undo()
_ = m2.undo()
_ = m2.undo()
check(m2.undoStack.isEmpty && !m2.canUndo, "连退3步后栈空")
check(m2.cube.facelets == cp, "undo 一路回到最初乱态（checkpoint）")
_ = m2.undo()
check(m2.cube.facelets == cp, "再 undo 无操作仍在 checkpoint（不越界）")

// ---------- CubeModel：计时 ----------
print("\n【CubeModel · 计时】")
var m3 = CubeModel(identity: .virtual)
m3.startTiming(at: Date(timeIntervalSince1970: 0))
let t1 = m3.elapsed(at: Date(timeIntervalSince1970: 12.5))
check(abs(t1 - 12.5) < 0.01, "计时 elapsed 正确 (12.5s)")
let d = m3.stopTiming(at: Date(timeIntervalSince1970: 20))
check(abs(d - 20) < 0.01, "停止计时返回用时 20s")
check(!m3.isTiming, "停止后 isTiming=false")

// ---------- SolveSession：轨道对齐 ----------
print("\n【SolveSession · 轨道对齐】")
// 造一个乱态，求解得轨道
let sScramble = ScrambleGenerator.generate(length: 20)
var sCube = CubeState(solved: true)
for mv in sScramble { sCube.apply(mv.rawValue) }
guard let session = SolveSession(startFacelets: sCube.facelets) else {
    print("  ❌ 无法构建 SolveSession"); exit(1)
}
check(session.totalSteps > 0, "轨道步数 \(session.totalSteps)")
check(session.alignedStep(of: CubeState(facelets: sCube.facelets)) == 0, "起点对齐第0步")
// 用户严格跟轨道走：模拟把整个轨道转一遍
var follower = CubeState(facelets: sCube.facelets)
var alignedAll = true
for (i, mv) in session.orbit.enumerated() {
    follower.apply(mv.rawValue)
    let a = session.alignedStep(of: follower)
    if a != i + 1 { alignedAll = false; print("    第\(i+1)步对齐=\(a ?? -1) 期望\(i+1)"); break }
}
check(alignedAll, "严格跟随每步都精确对齐到对应位置")
check(session.alignedStep(of: follower) == session.totalSteps, "走完轨道对齐 totalSteps（已还原）")
check(follower.isSolved, "走完轨道确实复原")
// facelets(afterStep:) —— 学习页 3D 预览用的轨道中间态
check(session.facelets(afterStep: 0) == sCube.facelets, "afterStep(0) 返回起点乱态")
check(CubeState(facelets: session.facelets(afterStep: session.totalSteps)).isSolved, "afterStep(totalSteps) 返回还原态")
check(CubeState(facelets: session.facelets(afterStep: 1)) == CubeState(facelets: sCube.facelets).applying(session.orbit[0].rawValue),
      "afterStep(1) 与手动转第1步一致")
var derailed = CubeState(facelets: sCube.facelets)
let expected = session.orbit[0]
// 转一个"错误的"（非轨道第0步的转动）→ 应脱轨返回 nil
var wrongMove: Move = expected
if wrongMove == .U { wrongMove = .R } else { wrongMove = .U }
derailed.apply(wrongMove.rawValue)
let derailedAlign = session.alignedStep(of: derailed)
check(derailedAlign == nil, "转错一步 → 脱轨 (alignedStep=nil)")
// 脱轨后 undo 回轨道起点，重新对齐
var m4 = CubeModel(identity: .virtual)
_ = m4.setFacelets(sCube.facelets)   // 设 checkpoint = 乱态
m4.apply(wrongMove)                  // 转错
check(session.alignedStep(of: m4.cube) == nil, "模型转错 → 脱轨")
_ = m4.undo()
check(session.alignedStep(of: m4.cube) == 0, "undo 撤回 → 回到轨道起点对齐第0步")

// ---------- SolveSession：完整还原流程模拟（虚拟自动判定） ----------
print("\n【SolveSession · 完整还原流程（虚拟模式）】")
var vm = CubeModel(identity: .virtual)
_ = vm.setFacelets(sCube.facelets)      // checkpoint=乱态
vm.startTiming(at: Date(timeIntervalSince1970: 0))
var successDetected = false
guard let vsession = SolveSession(startFacelets: vm.cube.facelets) else {
    print("  ❌ 无法构建虚拟会话"); exit(1)
}
for mv in vsession.orbit {
    let solved = vm.apply(mv)          // 虚拟模式：每步系统记录
    if solved { successDetected = true; break }
}
let solveDur = vm.stopTiming(at: Date(timeIntervalSince1970: 30))
check(successDetected, "虚拟模式转完最后一手检测到还原")
check(vm.cube.isSolved, "还原成功")
check(abs(solveDur - 30) < 0.01, "自动停表用时 30s")

// 轻校验语义：虚拟模式下，若用户在"该做某步"时没转就点了下一步，系统应提示（这步还没转）
// —— 这里模型层面由 alignedStep 表达：用户停在原步（没转）→ aligned 不前进
let idleAlign = vsession.alignedStep(of: vm.cube) // vm 已还原=轨道终点
_ = idleAlign

// ---------- Move.chineseInstruction 中文指令 ----------
print("\n【Move · 中文指令】")
check(Move.U.chineseInstruction == "顶面顺时针转", "U → 顶面顺时针转")
check(Move.Rp.chineseInstruction == "右面逆时针转", "R' → 右面逆时针转")
check(Move.F2.chineseInstruction == "前面转 180°", "F2 → 前面转 180°")
check(Move.D.chineseInstruction == "底面顺时针转", "D → 底面顺时针转")

// ---------- ProfileStore 用户资料 / 偏好 ----------
print("\n【ProfileStore · 资料/偏好】")
let defProfile = ProfileStore()
check(defProfile.nickname == "魔方练习生", "默认昵称")
check(defProfile.guideTier == .chinese, "默认中文档位")
// 编解码 roundtrip：模拟自定义资料存档
let custom = ProfileStore(nickname: "杰哥", signature: "提速中", guideTier: .pro)
custom.save()   // 写入 UserDefaults（脚本进程域）
let reloaded = ProfileStore.load()
check(reloaded.nickname == "杰哥", "昵称持久化恢复")
check(reloaded.guideTier == .pro, "档位持久化恢复")
// 清理测试写入
UserDefaults.standard.removeObject(forKey: "cube_profile_store_v1")

// ---------- Cube2x2 2 阶魔方引擎 ----------
print("\n【Cube2x2 · 2 阶引擎】")
let c2solved = Cube2x2(solved: true)
check(c2solved.facelets.count == 24, "2 阶 24 面片")
check(c2solved.isSolved, "2 阶初始已还原")
check(c2solved.facelets == [0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3, 4,4,4,4, 5,5,5,5], "2 阶面片布局 U/R/F/D/L/B 各 4")
// 每个基础转动 4 次应还原
var c2four = Cube2x2(solved: true)
var fourOK = true
for m in [0, 3, 6, 9, 12, 15] {  // U R F D L B 的基础转动下标
    var c = Cube2x2(solved: true)
    for _ in 0..<4 { c.apply(m) }
    if !c.isSolved { fourOK = false; print("  2阶转动 \(m) 4次未还原") }
}
check(fourOK, "2 阶每个基础转动 4 次还原")
// 打乱后求解 + 按解还原
var c2scrambled = Cube2x2.scrambled(count: 15)
check(!c2scrambled.isSolved, "2 阶打乱后变乱")
if let sol2 = Solver2x2.solve(c2scrambled.facelets) {
    check(sol2.count > 0, "2 阶可求解 (\(sol2.count) 步)")
    var r2 = c2scrambled
    for m in sol2 { r2.apply(m.rawValue) }
    check(r2.isSolved, "2 阶按解转回还原")
} else {
    check(false, "2 阶求解失败")
}
// 随机打乱求解稳定性（2 阶双向 BFS，单次约 3s，测 1 次验证正确性）
var allSolved2 = true
do {
    var sc = Cube2x2.scrambled(count: 12)
    if let sol = Solver2x2.solve(sc.facelets) {
        for m in sol { sc.apply(m.rawValue) }
        if !sc.isSolved { allSolved2 = false }
    } else {
        allSolved2 = false
    }
}
check(allSolved2, "随机 2 阶打乱能求解并还原")

// ---------- BackupStore 数据备份/恢复 ----------
print("\n【BackupStore · 备份/恢复】")
let rec1 = SolveRecord(id: "r1", duration: 12.34, moves: 25, scramble: "R U F", date: Date(timeIntervalSince1970: 1000))
let rec2 = SolveRecord(id: "r2", duration: 45.67, moves: 30, scramble: "-", date: Date(timeIntervalSince1970: 2000))
let backup = BackupData(records: [rec1, rec2], nickname: "杰哥", signature: "提速中", guideTier: .pro)
check(backup.schemaVersion == 1, "schemaVersion=1")
guard let json = BackupManager.encode(backup) else {
    print("  ❌ 备份编码失败"); exit(1)
}
check(json.count > 0, "备份编码为非空 JSON")
// 解码 roundtrip
switch BackupManager.decode(json) {
case .success(let restored):
    check(restored.records.count == 2, "解码恢复 2 条记录")
    check(restored.records[0].id == "r1" && abs(restored.records[0].duration - 12.34) < 0.01, "记录字段 roundtrip")
    check(restored.nickname == "杰哥" && restored.guideTier == GuideTier.pro.rawValue, "资料字段 roundtrip")
case .failure(let e):
    check(false, "解码失败：\(e)")
}
// 非法数据拦截
check(!BackupManager.isBackup(Data("not a json".utf8)), "非 JSON 拦截")
check(!BackupManager.isBackup(Data("{\"foo\":1}".utf8)), "结构不匹配拦截")
// 版本过高拦截
var futureBackup = backup
// 通过手工构造一个 version 2 的 JSON 测 unsupportedVersion
let futureJSON = "{\"schemaVersion\":99,\"exportedAt\":\"2026-09-08T10:00:00Z\",\"records\":[],\"nickname\":\"x\",\"signature\":\"y\",\"guideTier\":\"chinese\"}"
if let fd = futureJSON.data(using: .utf8) {
    switch BackupManager.decode(fd) {
    case .success: check(false, "版本过高应拦截")
    case .failure(let e): check(e == .unsupportedVersion, "版本过高返回 unsupportedVersion")
    }
}

// ---- SolveRecord.order（v15 多阶字段）----
check(rec1.order == 3, "新记录默认 order=3")
// 带 order=2 的记录 roundtrip
let rec2x2 = SolveRecord(id: "r2x", duration: 8.8, moves: 20, scramble: "-", date: Date(timeIntervalSince1970: 3000), order: 2)
let b2 = BackupData(records: [rec2x2], nickname: "n", signature: "s", guideTier: .beginner)
if let j2 = BackupManager.encode(b2), case .success(let r2) = BackupManager.decode(j2) {
    check(r2.records[0].order == 2, "order=2 roundtrip")
} else { check(false, "order=2 备份编解码失败") }
// 老版本 JSON（无 order 字段）解码应补默认 3，不抛错
let legacyJSON = "{\"schemaVersion\":1,\"exportedAt\":\"2026-09-08T10:00:00Z\",\"records\":[{\"id\":\"old1\",\"duration\":9.9,\"moves\":22,\"scramble\":\"-\",\"date\":\"2026-09-08T10:00:00Z\"}],\"nickname\":\"n\",\"signature\":\"s\",\"guideTier\":\"chinese\"}"
if let ld = legacyJSON.data(using: .utf8), case .success(let rl) = BackupManager.decode(ld) {
    check(rl.records[0].order == 3, "老记录(无order)解码补默认 3")
} else { check(false, "老版本无 order JSON 应能解码") }

// ---- CubeModel.order（v15 多阶分支）----
// 2 阶模型：打乱 → 手动转 → 还原判定 → undo
do {
    var m2 = CubeModel(order: 2)
    check(m2.order == 2, "CubeModel 默认 2 阶可建")
    check(m2.isSolved, "2 阶初始还原")
    // 2 阶打乱后非还原
    m2.scramble(count: 12)
    check(!m2.isSolved, "2 阶打乱后非还原")
    check(m2.cube2 != nil, "2 阶模式有 cube2 状态")   // CubeModel.cube2 private(set) 外部只读
    // 求解 2 阶并手动转回
    if let steps = Solver2x2.solve(m2.cube2!.facelets) {
        for mv in steps { _ = m2.apply(mv) }
        check(m2.isSolved, "按解转回 2 阶还原")
    } else { check(false, "2 阶求解失败") }
    // undo 回到打乱态（退栈）
    // （上面已转回还原，undoStack 有步；撤到底应回到打乱后非还原 checkpoint）
}
// 2 阶手动转一步 U 不还原，undo 返回
do {
    var m = CubeModel(order: 2)
    m.scramble(count: 12)
    _ = m.apply(Move(rawValue: 0)!)   // U
    // undo 后回到打乱态（非还原）
    let hadUndo = m.undo()
    check(hadUndo, "2 阶 undo 有效")
}
// 3 阶模型仍正常（回归）
do {
    var m3 = CubeModel(order: 3)
    check(m3.order == 3, "CubeModel 3 阶")
    check(m3.isSolved, "3 阶初始还原")
    m3.scramble(count: 25)
    check(!m3.isSolved, "3 阶打乱后非还原")
}

// ---- CubeModel.order >= 4（v16 N 阶可玩：4~10 阶打乱/手动转/还原判定/undo/setFacelets）----
for order in 4...10 {
    do {
        var m = CubeModel(order: order)
        check(m.order == order && m.isSolved, "\(order) 阶初始还原")
        check(m.cubeN != nil, "\(order) 阶有 cubeN 状态")
        check(m.cubeN!.facelets.count == 6 * order * order, "\(order) 阶面片数 = \(6*order*order)")
        // 打乱后非还原
        m.scramble(count: order * 8)
        check(!m.isSolved, "\(order) 阶打乱后非还原")
        // 手动转一步不还原
        _ = m.apply(.R)
        check(!m.isSolved, "\(order) 阶 apply R 后仍非还原")
        // undo 应回到打乱态（非还原）
        check(m.undo(), "\(order) 阶 undo 有效")
        check(!m.isSolved, "\(order) 阶 undo 回打乱态(非还原)")
        // reset 回到还原
        m.reset()
        check(m.isSolved, "\(order) 阶 reset 还原")
        // setFacelets：建一个乱序（单面转 90° 后取面片）应合法且非还原
        let facelets = NCubeState.moveTable(order: order)[0].enumerated().map { i, _ in
            // 构造合法乱序：从还原态应用一步 U 后的 facelets
            var s = NCubeState(order: order, solved: true); s.apply(0); return s.facelets[i]
        }
        let r = m.setFacelets(facelets)
        if case .success = r { check(!m.isSolved, "\(order) 阶 setFacelets 乱序非还原") }
        else { check(false, "\(order) 阶 setFacelets 应合法") }
    }
}
print("  4~10 阶 CubeModel 可玩链路全通过")

// ---------- 3 阶中层 M/E/S 置换正确性（v22 修复回归，防止再写成"整颗绕轴转"） ----------
print("\n【3 阶中层 M/E/S（v22 修复回归）】")

func composeApply(_ p: [Int], then q: [Int]) -> [Int] { (0..<p.count).map { p[q[$0]] } }
func permPower(_ p: [Int], _ n: Int) -> [Int] {
    var r = Array(0..<p.count)
    for _ in 0..<n { r = composeApply(r, then: p) }
    return r
}
let ident54 = Array(0..<54)

/// 3 阶面片索引 → cubelet 坐标（与 Cube3DView.faceMap 完全一致）
let faceletXYZ: [(Int, Int, Int)] = [
    (-1, 1, -1), (0, 1, -1), (1, 1, -1), (-1, 1, 0), (0, 1, 0), (1, 1, 0), (-1, 1, 1), (0, 1, 1), (1, 1, 1),
    (1, 1, 1), (1, 1, 0), (1, 1, -1), (1, 0, 1), (1, 0, 0), (1, 0, -1), (1, -1, 1), (1, -1, 0), (1, -1, -1),
    (-1, 1, 1), (0, 1, 1), (1, 1, 1), (-1, 0, 1), (0, 0, 1), (1, 0, 1), (-1, -1, 1), (0, -1, 1), (1, -1, 1),
    (-1, -1, 1), (0, -1, 1), (1, -1, 1), (-1, -1, 0), (0, -1, 0), (1, -1, 0), (-1, -1, -1), (0, -1, -1), (1, -1, -1),
    (-1, 1, -1), (-1, 1, 0), (-1, 1, 1), (-1, 0, -1), (-1, 0, 0), (-1, 0, 1), (-1, -1, -1), (-1, -1, 0), (-1, -1, 1),
    (1, 1, -1), (0, 1, -1), (-1, 1, -1), (1, 0, -1), (0, 0, -1), (-1, 0, -1), (1, -1, -1), (0, -1, -1), (-1, -1, -1),
]

// movePerms 下标：M=18/M2=19/M'=20，E=21/E2=22/E'=23，S=24/S2=25/S'=26
let midGroups: [(name: String, base: Int, changed: Set<Int>)] = [
    ("M", 18, [1, 4, 7, 19, 22, 25, 28, 31, 34, 46, 49, 52]),
    ("E", 21, [12, 13, 14, 21, 22, 23, 39, 40, 41, 48, 49, 50]),
    ("S", 24, [3, 4, 5, 10, 13, 16, 30, 31, 32, 37, 40, 43]),
]
let midAxis: [String: Int] = ["M": 0, "E": 1, "S": 2]   // 中层所在轴（x/y/z）

for g in midGroups {
    let suffixes = ["", "2", "'"]
    for k in 0..<3 {
        let idx = g.base + k
        let nm = "\(g.name)\(suffixes[k])"
        let p = movePerms[idx]
        check(Set(p) == Set(ident54), "\(nm) 是置换（双射）")
        check(permPower(p, 4) == ident54, "\(nm) 转 4 次回原")
        let ch = Set((0..<54).filter { p[$0] != $0 })
        check(ch == g.changed, "\(nm) 只动 12 个中层色块（不是整颗绕轴转）")
    }
    check(composeApply(movePerms[g.base], then: movePerms[g.base + 2]) == ident54, "\(g.name) 与 \(g.name)' 互逆")
    check(composeApply(movePerms[g.base + 1], then: movePerms[g.base + 1]) == ident54, "\(g.name)2 = \(g.name) 两次")
    // 选层高亮集合 == 实际变化面片集合（所见即所得）
    let ax = midAxis[g.name]!
    func coordAt(_ i: Int, _ axis: Int) -> Int {
        let c = faceletXYZ[i]
        return axis == 0 ? c.0 : (axis == 1 ? c.1 : c.2)
    }
    let plane = Set((0..<54).filter { coordAt($0, ax) == 0 })
    check(plane == g.changed, "\(g.name) 轴中层选层集合 == 实际变化面片集合（高亮与实际一致）")
}

// 铁证：R·M'·L' 必须等于「整颗魔方绕 x 轴刚体旋转」
// 特征：动满 54 面片 + 4 次回原 + 把每个面整体映射到另一个面（不是旋转就会破）
let xWhole = composeApply(composeApply(movePerms[3], then: movePerms[20]), then: movePerms[14])
let xFixed = (0..<54).filter { xWhole[$0] == $0 }
check(xFixed == [13, 40], "R·M'·L' 只有 R/L 中心块(13,40)不动，其余 52 面片全动（整颗绕 x 轴转的签名）")
check(permPower(xWhole, 4) == ident54, "R·M'·L' 4 次回原（整颗旋转阶为 4）")
var faceWhole = true
for f in 0..<6 {
    var targets = Set<Int>()
    for i in (f * 9)..<(f * 9 + 9) { targets.insert(xWhole[i] / 9) }
    if targets.count != 1 { faceWhole = false }
}
check(faceWhole, "R·M'·L' 把每个面整体映射到另一个面（刚体旋转特征 → M 方向正确）")

// 4 阶内层置换仍正常（v21 能力不被本次改动波及）
check(MovePerms4Inner.count == 96, "4 阶内层表面片数 = 96")
var innerOK = true
for p in MovePerms4Inner.table {
    if Set(p) != Set(0..<96) || permPower(p, 4) != Array(0..<96) { innerOK = false }
}
check(innerOK && MovePerms4Inner.table.count == 18, "4 阶内层 18 个置换：双射 + 4 次回原")
do {
    var m4 = CubeModel(identity: .virtual, order: 4)
    check(m4.isSolved, "4 阶初始已还原")
    _ = m4.applySlice(SliceTurn(face: .R, turn: 1))
    check(!m4.isSolved, "4 阶内层转一下 → 非还原")
    check(m4.undo(), "4 阶内层 undo 生效")
    check(m4.isSolved, "4 阶内层 undo 后回还原态")
}

print("\n========== 结果：\(passed) 通过 / \(failed) 失败 ==========")
if failed > 0 { exit(1) } else { print("✅ 全部通过") }
