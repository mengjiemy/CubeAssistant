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
// 脱轨：走错一步
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

print("\n========== 结果：\(passed) 通过 / \(failed) 失败 ==========")
if failed > 0 { exit(1) } else { print("✅ 全部通过") }
