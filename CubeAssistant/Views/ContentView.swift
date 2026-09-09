import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// App 主题常量（集中管理，避免各处硬编码色值/间距）。
/// 深空黑底 + 系统蓝强调（对应原型「深空黑玻璃」风格基准）。
enum AppTheme {
    /// 主强调蓝（品牌交互色）
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)
    /// 亮蓝（渐变/次级强调）
    static let accentLight = Color(red: 0.4, green: 0.7, blue: 1.0)
    /// 深空黑底渐变（两档）
    static let bgTop = Color(red: 0.04, green: 0.04, blue: 0.08)
    static let bgBottom = Color(red: 0.01, green: 0.01, blue: 0.03)
    /// 全页深空渐变背景（用作页面/Sheet 底色）
    static let spaceGradient = LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
}

/// 主界面：4-Tab 框架（主页 / 扫描 / 学习 / 我的）。
/// 主题：深空黑底 + iOS 系统蓝 + 玻璃卡片 + SF Symbols。
///
/// 主页 = 3D 魔方 + 计时卡（暂停/继续/完成三态） + 打乱/重置 + 转层控件（选层 + 4 向转）。
struct ContentView: View {
    @StateObject private var session = CubeSession()
    @State private var selectedTab: Tab = .home

    init() {}

    enum Tab: String, CaseIterable {
        case home = "主页"
        case scan = "扫描"
        case learn = "学习"
        case mine = "我的"

        var icon: String {
            switch self {
            case .home: return "cube.fill"
            case .scan: return "viewfinder"
            case .learn: return "book.fill"
            case .mine: return "person.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08),
                         Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .home: HomeView(session: session)
                    case .scan: CameraScanView(session: session)
                    case .learn: LearnView(session: session)
                    case .mine: MineView(session: session)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                tabBar
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tabBar: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .medium))
                        Text(tab.rawValue)
                            .font(.caption2)
                    }
                    .foregroundColor(selectedTab == tab ? AppTheme.accent : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 主页
struct HomeView: View {
    @ObservedObject var session: CubeSession
    @State private var selectedFace: Face = .U
    @State private var timingState: TimingState = .idle

    /// 计时三态：未开始 → 进行中 → 暂停
    enum TimingState: Equatable {
        case idle        // 未开始
        case running     // 进行中
        case paused      // 已暂停（用户点击想结束 / 完成复原）
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("魔方学院")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                Spacer()
                // 阶数切换（2~10 阶）。4~10 为高阶：可打乱/手动转/判定还原，暂无自动求解。
                Menu {
                    ForEach(2...10, id: \.self) { o in
                        Button {
                            session.setOrder(o)
                        } label: {
                            if o == session.order {
                                Label("\(o) 阶", systemImage: "checkmark")
                            } else {
                                Text("\(o) 阶")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.caption2)
                        Text("\(session.order)阶")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.accent.opacity(0.25)))
                }
                Button {
                    session.setIdentity(session.identity == .physical ? .virtual : .physical)
                } label: {
                    Label(session.identity == .physical ? "真魔方" : "虚拟魔方",
                          systemImage: session.identity == .physical ? "cube" : "laptopcomputer")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppTheme.accent.opacity(0.25)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // 转动方式切换（按钮 / 手势）—— 短横条切换器
            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Picker("转动方式", selection: Binding(
                    get: { session.turnMode },
                    set: { session.setTurnMode($0) }
                )) {
                    Text("按钮").tag(TurnMode.buttons)
                    Text("手势").tag(TurnMode.gestures)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .tint(AppTheme.accent)
                if session.turnMode == .gestures {
                    Label("点击选面，滑动转动", systemImage: "hand.draw")
                        .font(.caption2)
                        .foregroundColor(AppTheme.accent)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 14) {
                    timingCard

                    ZStack(alignment: .topTrailing) {
                        Cube3DView(
                            session: session,
                            selectedFace: selectedFace,
                            onFaceSelected: { selectedFace = $0 },
                            onTurnRequest: { move in
                                _ = session.apply(move)
                            }
                        )
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)

                        // 回正视角按钮（浮动于魔方右上角）
                        Button {
                            session.resetCamera()
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.ultraThinMaterial))
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }

                    // 提示语固定占位，避免出现/消失导致界面跳动
                    Text(session.message ?? " ")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 20)
                        .frame(height: 20)

                    if session.turnMode == .buttons {
                        turnControls
                    }
                    actionRow
                }
                .padding(.bottom, 40)
            }
        }
        // 虚拟模式：转完自动停表结算后，本地计时态需同步复位（否则仍显示「暂停」）
        .onChange(of: session.isTiming) { nowTiming in
            if !nowTiming && timingState == .running { timingState = .idle }
        }
    }

    // MARK: 计时卡（三态）
    private var timingCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.formatTime(displayedElapsed))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(timingStateLabel)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.history.first.map { Self.formatTime($0.duration) } ?? "—")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("最近")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            // 主操作按钮（随状态切换文案）
            timingPrimaryButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 20)
    }

    /// 主操作按钮的文案与动作：未开始→开始 / 进行中→暂停 / 暂停→继续
    @ViewBuilder
    private var timingPrimaryButton: some View {
        switch timingState {
        case .idle:
            Button {
                timingState = .running
                session.startTiming()
            } label: {
                Label("开始", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppTheme.accent))
            }
            .buttonStyle(.plain)
        case .running:
            Button {
                timingState = .paused
                session.pauseTiming()
            } label: {
                Label("暂停", systemImage: "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        case .paused:
            HStack(spacing: 8) {
                Button {
                    timingState = .running
                    session.startTiming()  // 从累计值继续（accumulatedElapsed 保留）
                } label: {
                    Label("继续", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.accent))
                }
                .buttonStyle(.plain)
                Button {
                    session.finishManualSolve()
                    timingState = .idle
                } label: {
                    Label("完成", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.green.opacity(0.55)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 显示的计时（进行中 → live；其他 → 0）
    private var displayedElapsed: TimeInterval {
        switch timingState {
        case .running: return session.liveElapsed
        case .paused:  return session.liveElapsed
        case .idle:    return 0
        }
    }

    private var timingStateLabel: String {
        switch timingState {
        case .idle:    return session.history.isEmpty ? "本次用时" : "上次已记录"
        case .running: return "进行中…点击暂停"
        case .paused:  return "已暂停 · 继续或完成"
        }
    }

    // MARK: 转层控件（选面 + 顺/逆时针，方向固定正确）
    private var turnControls: some View {
        VStack(spacing: 10) {
            // 6 面选层（选中蓝框高亮），两排：上左前 / 下右后，字母+中文对照公式
            HStack(spacing: 8) {
                ForEach([Face.U, Face.L, Face.F], id: \.self) { f in
                    faceButton(f)
                }
            }
            HStack(spacing: 8) {
                ForEach([Face.D, Face.R, Face.B], id: \.self) { f in
                    faceButton(f)
                }
            }

            // 顺 / 逆时针
            HStack(spacing: 8) {
                turnButton("逆时针", "arrow.counterclockwise") { applyTurn(clockwise: false) }
                turnButton("顺时针", "arrow.clockwise") { applyTurn(clockwise: true) }
            }
        }
        .padding(.horizontal, 20)
    }

    private func faceButton(_ f: Face) -> some View {
        let selected = selectedFace == f
        return Button {
            selectedFace = f
        } label: {
            VStack(spacing: 1) {
                Text(faceLetter(f))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(faceName(f))
                    .font(.caption2)
            }
            .foregroundColor(selected ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(selected ? AppTheme.accent : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(selected ? Color(red: 0.3, green: 0.7, blue: 1.0) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func faceLetter(_ f: Face) -> String {
        switch f {
        case .U: return "U"
        case .D: return "D"
        case .L: return "L"
        case .R: return "R"
        case .F: return "F"
        case .B: return "B"
        }
    }

    private func faceName(_ f: Face) -> String {
        switch f {
        case .U: return "上"
        case .D: return "下"
        case .L: return "左"
        case .R: return "右"
        case .F: return "前"
        case .B: return "后"
        }
    }

    private func turnButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())   // 扩大点击区
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { session.scramble() } label: {
                Label("打乱", systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .background(Capsule().fill(AppTheme.accent))
            }
            .buttonStyle(.plain)

            Button { session.undo() } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .disabled(!session.canUndo)
            .opacity(session.canUndo ? 1.0 : 0.35)

            Button { session.reset() } label: {
                Label("还原", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private func applyTurn(clockwise: Bool) {
        let move = resolveMove(face: selectedFace, clockwise: clockwise)
        _ = session.apply(move)
    }

    /// 选面 + 顺/逆时针 → 标准 Move。方向与标准魔方记号一致（固定世界坐标）。
    private func resolveMove(face: Face, clockwise: Bool) -> Move {
        switch (face, clockwise) {
        case (.U, true):  return .U
        case (.U, false): return .Up
        case (.D, true):  return .D
        case (.D, false): return .Dp
        case (.L, true):  return .L
        case (.L, false): return .Lp
        case (.R, true):  return .R
        case (.R, false): return .Rp
        case (.F, true):  return .F
        case (.F, false): return .Fp
        case (.B, true):  return .B
        case (.B, false): return .Bp
        }
    }

    static func formatTime(_ t: TimeInterval) -> String { formatSolveTime(t) }
}

// MARK: - 学习页
struct LearnView: View {
    @ObservedObject var session: CubeSession
    /// 当前点开的课程（点开弹课程详情 sheet）
    @State private var selectedCourse: CourseStage? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("学习")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 16) {
                    if session.isIn2x2Solve {
                        guide2x2Content
                    } else if let sol = session.solveSession {
                        guideContent(sol)
                    } else {
                        studyCenter
                    }
                }
                .padding(.bottom, 12)
            }

            // 底部固定「求解」按钮（保持可见；按阶数走对应求解器）
            Button {
                if !session.isSolving {
                    if session.isOrder2 {
                        session.solve2x2()
                    } else {
                        session.solve()
                    }
                }
            } label: {
                Label(session.isSolving ? "计算中…" : "求解", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(AppTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(session.isSolving)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .padding(.top, 8)
    }

    // MARK: 2 阶指引（极简：Solver2x2 秒解 → 照做 → 手动点下一步）

    /// 2 阶还原指引内容（相对 SolveSession 简单：无轨道对齐校验，步数短≤11）
    @ViewBuilder
    private var guide2x2Content: some View {
        let current = session.current2x2Move()
        let total = session.solve2x2Steps.count
        let isLastDone = current == nil && total > 0   // 已全部转完(advance 已清)或用完

        VStack(spacing: 14) {
            // 内嵌 2 阶 3D 预览（展示当前实际状态，用户在虚拟魔方上照转）
            Cube3DView(session: session, order: 2)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            if isLastDone {
                Label("2 阶已还原，太棒了！", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)
            } else if let move = current {
                Text("第 \(session.solve2x2StepIndex + 1) / \(total) 步")
                    .font(.headline)
                    .foregroundColor(.white)
                VStack(spacing: 6) {
                    Text(move.chineseInstruction)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(move.notation)
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .foregroundColor(AppTheme.accentLight)
                }
                .padding(.vertical, 6)
                Text("在下方魔方上转这一层，转完点「下一步」")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    session.advance2x2Step()
                } label: {
                    Label("我转好了，下一步", systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(AppTheme.accent))
                }
                .buttonStyle(.plain)
            } else {
                Text("准备就绪")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: 学习中心（§5：帮助 FAQ + 课程入口）

    /// 无进行中指引时展示：引导语 + 基础课程入口 + 帮助 FAQ（手风琴）
    private var studyCenter: some View {
        VStack(spacing: 14) {
            // 引导语
            VStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("先打乱一个虚拟魔方，点「求解」\n就会一步步教你怎么还原")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 16)

            // 课程入口（骨架，分阶段）
            courseSection

            // 帮助 FAQ
            faqSection
        }
        .padding(.horizontal, 20)
    }

    /// 当前阶数对应的课程（原型：学习中心课程跟随阶数）
    private var currentCourses: [CourseStage] { CourseStage.courses(for: session.order) }

    /// 基础课程骨架：分阶段标题 + 说明（图文教学后续版本完善）。课程按当前阶数切换。
    private var courseSection: some View {
        let courses = currentCourses
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .foregroundColor(AppTheme.accent)
                Text("\(session.order) 阶课程")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            Text(session.isHighOrder || session.isOrder2
                 ? "高阶先「降阶」再按 \(session.order) 阶公式还原，边看边在虚拟魔方上练"
                 : "按阶段学习还原，打乱后配合「求解」边看边练")
                .font(.caption)
                .foregroundColor(.secondary)

            // 进度摘要（按原型："已学 N/N 课 · 推荐继续：XXX"）
            HStack(spacing: 4) {
                Text("已学 ").font(.caption).foregroundColor(.secondary)
                Text("\(finishedCount)").font(.caption.weight(.bold)).foregroundColor(AppTheme.accent)
                Text("/ \(courses.count) 课").font(.caption).foregroundColor(.secondary)
                if let next = nextCourse {
                    Text(" · 推荐继续：").font(.caption).foregroundColor(.secondary)
                    Text(next.title).font(.caption.weight(.semibold)).foregroundColor(AppTheme.accent)
                }
            }
            .padding(.bottom, 2)

            if courses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("\(session.order) 阶教程制作中，先用「求解 / 手动转」练手感吧")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }

            ForEach(courses, id: \.id) { stage in
                Button {
                    selectedCourse = stage
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(stage.color.opacity(0.15))
                            Image(systemName: stage.icon)
                                .foregroundColor(stage.color)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("第 \(stage.id) 课")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(stage.statusColor)
                                if stage.progress >= 1 {
                                    Text("· 已完成 ✓")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                } else if stage.progress > 0 {
                                    Text("· 进行中")
                                        .font(.caption2)
                                        .foregroundColor(stage.statusColor)
                                }
                            }
                            Text(stage.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text(stage.goal)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            // 进度条（按原型）
                            HStack(spacing: 8) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.08))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(stage.statusColor)
                                            .frame(width: geo.size.width * CGFloat(stage.progress))
                                    }
                                }
                                .frame(height: 4)
                                Text("\(Int(stage.progress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
        .sheet(item: $selectedCourse) { stage in
            CourseDetailSheet(stage: stage) { newProgress in
                // 写入进度（持久化到 UserDefaults，按课程 id 存）
                var map = (UserDefaults.standard.dictionary(forKey: "cube_course_progress") as? [String: Double]) ?? [:]
                map[stage.idKey] = newProgress
                UserDefaults.standard.set(map, forKey: "cube_course_progress")
            }
        }
    }

    /// 已学完的课数（progress >= 1，按当前阶数课程）
    private var finishedCount: Int {
        currentCourses.filter { $0.progress >= 1 }.count
    }

    /// 下一节推荐课程（第一个未完成的）
    private var nextCourse: CourseStage? {
        currentCourses.first { $0.progress < 1 }
    }

    /// 帮助 FAQ：可折叠手风琴
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(AppTheme.accent)
                Text("常见问题")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            ForEach(FAQItem.all, id: \.question) { item in
                FAQRow(item: item)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
    }

    // MARK: 指引内容（§4.2 手动放行轨道）

    @ViewBuilder
    private func guideContent(_ sol: SolveSession) -> some View {
        let isComplete = session.alignedStep >= sol.totalSteps

        VStack(spacing: 12) {
            // 顶部：进度 + 完成态
            if isComplete {
                Label("已还原，太棒了！", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)
            } else {
                Text("第 \(session.alignedStep + 1) / \(sol.totalSteps) 步")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            // 内嵌 3D 魔方预览：实时渲染「当前进度对应的状态」（逐步高亮模式的视觉锚点）
            Cube3DView(session: session, overrideFacelets: sol.facelets(afterStep: session.alignedStep))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
            Text("上图为走完当前步后的状态，跟着转即可")
                .font(.caption2)
                .foregroundColor(.secondary)

            // 当前步大字指令（按档位切换：新手=大白话 / 中文=中文+公式 / 专业=纯公式）
            if !isComplete, let move = sol.move(at: session.alignedStep) {
                VStack(spacing: 6) {
                    switch session.profile.guideTier {
                    case .beginner:
                        // 新手：大白话 + 高亮强调
                        Text(move.chineseInstruction)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(AppTheme.accent.opacity(0.25))
                            )
                    case .chinese:
                        // 中文：中文指令 + 公式字母
                        Text(move.chineseInstruction)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                        Text(move.notation)
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .foregroundColor(AppTheme.accentLight)
                    case .pro:
                        // 专业：纯公式大字
                        Text(move.notation)
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .foregroundColor(AppTheme.accentLight)
                    }
                }
                .padding(.vertical, 8)
            }

            // 脱轨提示（转错了）
            if let off = session.offTrackMessage {
                Label(off, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // 步骤轨道（横向滚动，当前步高亮、已完成步打勾）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(sol.orbit.enumerated()), id: \.offset) { i, m in
                        stepChip(m, index: i, total: sol.totalSteps)
                    }
                }
                .padding(.horizontal, 4)
            }

            // 上一步 / 下一步（手动放行）
            HStack(spacing: 12) {
                guideNavButton("上一步", "arrow.backward", disabled: session.alignedStep <= 0) {
                    session.retreatStep()
                }
                guideNavButton(isComplete ? "完成" : "下一步", "arrow.forward", disabled: isComplete) {
                    session.advanceStep()
                }
            }

            // 模式提示
            Text(session.identity == .virtual
                 ? "虚拟模式：直接转魔方，转对会自动前进；转错会有提示"
                 : "真魔方模式：跟着做，每转完一步点「下一步」")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        .padding(.horizontal, 20)
    }

    private func stepChip(_ m: Move, index: Int, total: Int) -> some View {
        let done = index < session.alignedStep
        let current = index == session.alignedStep
        return VStack(spacing: 2) {
            Text(m.notation)
                .font(.system(.body, design: .monospaced).weight(current ? .bold : .regular))
                .foregroundColor(done ? .green : (current ? AppTheme.accent : .white.opacity(0.6)))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(current ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(current ? AppTheme.accent : Color.clear, lineWidth: 2)
                )
        }
    }

    private func guideNavButton(_ title: String, _ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(disabled ? Color.white.opacity(0.06) : AppTheme.accent))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }
}

/// 课程阶段（骨架定义）
struct CourseStage: Identifiable {
    let id: Int
    let order: Int
    let title: String
    let goal: String
    let icon: String
    let color: Color
    /// 课程正文（多行段落，按原型分步讲解）
    let content: String

    /// 进度（0..1），从 UserDefaults 读，按 (阶数, id) 存 → 每阶独立进度。
    /// 兼容旧版无阶数 key（course_2…course_5 = 3 阶），迁移读回不丢。
    var progress: Double {
        let map = (UserDefaults.standard.dictionary(forKey: "cube_course_progress") as? [String: Double]) ?? [:]
        if let v = map[idKey] { return v }
        if order == 3, let legacy = map["course_\(id)"] { return legacy }   // 旧版 3 阶进度
        return 0
    }

    /// 用于持久化的 key（带阶数，跨阶不串）
    var idKey: String { "course_\(order)_\(id)" }

    /// 状态色（进度对应状态的颜色）
    var statusColor: Color {
        if progress >= 1 { return .green }
        if progress > 0 { return .orange }
        return .secondary
    }

    /// 是否已收藏（UserDefaults 持久化，key 与进度同源）
    var isFavorite: Bool {
        let map = (UserDefaults.standard.dictionary(forKey: CourseStage.favoriteKey) as? [String: Bool]) ?? [:]
        return map[idKey] ?? false
    }

    /// 切换收藏状态（返回新状态）
    @discardableResult
    func toggleFavorite() -> Bool {
        var map = (UserDefaults.standard.dictionary(forKey: CourseStage.favoriteKey) as? [String: Bool]) ?? [:]
        let newVal = !(map[idKey] ?? false)
        map[idKey] = newVal
        UserDefaults.standard.set(map, forKey: CourseStage.favoriteKey)
        return newVal
    }

    /// 收藏持久化 key
    static let favoriteKey = "cube_favorite_formulas"

    /// 取所有已收藏的课程（按阶 + 课号排序）
    static func allFavorites() -> [CourseStage] {
        let map = (UserDefaults.standard.dictionary(forKey: favoriteKey) as? [String: Bool]) ?? [:]
        var result: [CourseStage] = []
        for order in 2...10 {
            result += courses(for: order).filter { map[$0.idKey] ?? false }
        }
        return result
    }

    /// 某阶对应的课程（学习中心课程跟随阶数）。
    /// order 2 = 角块法；order 3 = 层先法；order 4 = 偶数阶降阶；order 5 = 奇数阶降阶；6-10 共享高阶降阶总览。
    static func courses(for order: Int) -> [CourseStage] {
        switch order {
        case 2: return course2
        case 3: return course3
        case 4: return course4
        case 5: return course5
        default: return highOrderCourses(order)
        }
    }

    private static func s(_ id: Int, _ order: Int, _ title: String, _ goal: String, _ icon: String, _ color: Color, _ content: String) -> CourseStage {
        CourseStage(id: id, order: order, title: title, goal: goal, icon: icon, color: color, content: content)
    }

    // MARK: 2 阶（角块法，4 课）
    private static var course2: [CourseStage] {
        [
            s(1, 2, "认识二阶结构", "角块、方位、转法记号与三阶的关联", "cube", .blue,
              """
              二阶魔方（口袋魔方）本质是「只有 8 个角块的三阶」——它没有中心块、没有棱块，只剩角。

              • 每个角块 3 张贴纸，决定它该回哪个角落。
              • 因为没有中心块，颜色相对关系靠经验：白对黄、红对橙、蓝对绿。
              • 记号与三阶完全通用：U/D/L/R/F/B + ' 逆时针 + 2 转半圈。

              好消息：二阶的每个转动，都等价于三阶的某个转动，公式也能平移着用。
              """),
            s(2, 2, "还原底层", "先拼出白色底面四角，让侧面颜色也对齐", "square.grid.2x2.fill", .green,
              """
              目标：让底面 4 个含白色的角块都归位，且侧面颜色与相邻角对得上。

              步骤要点：
              1. 任取一个白角块，放到底面某个角（先不管其余）。
              2. 把它对应的同色角块转到目标正上方（用 U/U'/U2）。
              3. 做 R U R' U'（或 L' U' L U）让它滚进底面，直到归位。
              4. 逐个放完 4 个白角 → 底面完成且侧面颜色自成规律。

              提示：这一步和三阶「底层角块」一模一样，熟了手感通用。
              """),
            s(3, 2, "顶层角块朝向", "让顶面 4 个角块全部翻成黄色朝上", "arrow.up.arrow.down.circle", .yellow,
              """
              目标：不管位置对不对，先把顶面四个角都翻成黄面朝上。

              口诀公式（右手小鱼）：
              R U R' U R U2 R' —— 连做 1~2 次，每次把「一个黄角在左前上」的状态摆好。

              步骤要点：
              1. 找一个「黄面朝左」的角摆在左前，做一遍公式。
              2. 若顶面还不是全黄，转动整体（y）换角再重复，直到顶面 4 角全黄。

              常见错误：做完公式魔方没到位——多半是起始朝向摆错。
              """),
            s(4, 2, "顶层角块归位", "交换顶层 4 角位置，二阶完成", "checkmark.circle.fill", .purple,
              """
              目标：顶面已全黄，只需把 4 个角交换到正确位置即可还原二阶。

              三循环公式（角块定位）：
              U R U' L' U R' U' L —— 会让三个角循环交换。

              步骤要点：
              1. 找到一个「已归位」的角固定住，把它放右下。
              2. 做上面的三循环公式 1~2 次，观察其余角是否到位。
              3. 全到位即还原完成。

              若 4 个角都没归位：先随便做一次公式制造一个归位角，再回到第 1 步。
              """),
        ]
    }

    // MARK: 3 阶（层先法，5 课）
    private static var course3: [CourseStage] {
        [
            s(1, 3, "认识魔方结构", "中心块、棱块、角块的区别与转动方式", "cube", .blue,
              """
              魔方由 6 个中心块、12 条棱块、8 个角块共 26 块组成（不计内核）。

              • 中心块：每个面正中 1 块，相对位置固定，决定这一面的颜色。
              • 棱块：两个面之间的块，每块 2 个贴纸；3 阶共 12 条。
              • 角块：三个面交汇处的块，每块 3 个贴纸；3 阶共 8 个。

              记号：U 上 / D 下 / L 左 / R 右 / F 前 / B 后。U 指顶面（面对你时最上），其他类推。

              不带后缀=顺时针 90°（从该面对外看），' 表示逆时针，2 表示转 180°。
              """),
            s(2, 3, "底层十字", "在底面拼出十字形（白色对黄色中心）", "plus", .green,
              """
              目标：把底面（这里指 D 面，本课设白色为底色）拼出十字，并让十字的 4 条棱都和侧面中心同色。

              步骤要点：
              1. 先找带白色的棱块（4 条），把它们逐一翻到底面。
              2. 每条翻到底后，转两次 D（D2）或配 U'/U 让它对齐侧面中心色。
              3. 反复 4 次，直到 4 个白棱全部到底且侧面颜色对齐 → 底层十字完成。

              常见错误：翻下去时没注意侧面颜色 → 十字虽然成型但和侧面中心对不上。
              """),
            s(3, 3, "底层角块还原", "把四个底层角块归位（白色+两种侧面色）", "square.grid.2x2.fill", .yellow,
              """
              目标：把 4 个底层角块（含白色）逐一放到底层对应位置，使三面颜色全部对齐中心。

              步骤要点：
              1. 找底层任一不在位的角块（看顶面或底层，含白色）。
              2. 把角块转到目标位置正上方（用 U/U'/U2 调整）。
              3. 做公式 R' D' R D（俗称「右勾」），直到角块归位。
              4. 重复直到 4 个角块全部归位。

              标记完成 → 进入下一课。
              """),
            s(4, 3, "中层棱块归位", "把 4 个中层棱块归位（无黄无白）", "square.grid.3x2.fill", .orange,
              """
              目标：把不含黄/白的 4 个棱块归位到中层，使两面颜色都对齐对应中心。

              步骤要点：
              1. 顶层找无黄无白的棱块（4 个），看顶色应和某侧面中心一致。
              2. 用 U/U'/U2 把顶色对齐到对应侧面正上方。
              3. 看棱块的「左色」对的是 L 还是 R：
                 • 左对 L：做 U' L' U L U F U' F'
                 • 左对 R：做 U R U' R' U' F' U F
              4. 4 个棱块逐一完成。

              这一步练熟了中层的手筋就有了。
              """),
            s(5, 3, "顶层还原", "顶面十字 + 顶面还原 + 顶层全部归位", "star.fill", .purple,
              """
              目标：把顶层（含黄色面）从「鱼眼」/「一字」/「拐角」逐步还原到完全归位。

              步骤要点：
              1. 顶面十字：F R U R' U' F'（小鱼→一字→十字）
              2. 顶面还原（黄面全黄）：R U R' U R U2 R'（左手法 / 右手法）
              3. 顶层棱块归位：R U R' U R U2 R'（顶棱定位）
              4. 顶层角块归位：U R U' L' U R' U' L（角块互换）

              完成后 → 全部还原，撒花 🎉

              提示：每个公式连做多次观察变化，是最快的记忆方法。
              """),
        ]
    }

    // MARK: 4 阶（偶数阶降阶法，5 课）——含特殊情况 parity
    private static var course4: [CourseStage] {
        [
            s(1, 4, "认识四阶与降阶思路", "偶数阶无固定中心，先降阶成三阶再解", "cube", .blue,
              """
              四阶（4×4×4）比三阶多一层核心难点：它没有固定中心块。
              三阶的中心定了整面颜色，四阶的「中心」是 24 个可移动的小块。

              全世界统一的思路叫「降阶法」：
              1. 先把每面 4 个中心小块拼成 1 个大中心 → 6 个面各就各位。
              2. 再把同色的棱两两配对成 1 条粗棱 → 12 条粗棱。
              3. 此时四阶看外表已经等同于三阶，用你会的三阶公式收尾。
              4. 偶数阶最后可能冒出特殊情况（parity），有两个专有公式解决。

              一句话：中心 + 棱配对 → 三阶还原 → 特殊情况收尾。
              """),
            s(2, 4, "合并中心块", "把每面 4 个中心小块拼成 6 个大中心", "square.grid.2x2", .green,
              """
              目标：先拼出 6 个 2×2 的同色大中心。四阶中心没有固定色位，但对面关系仍固定。

              步骤要点：
              1. 先定第一对对面（如白/黄），拼好这 2 个面中心。
              2. 再拼第二对对面（如红/橙），拼的时候用「暂存区」技巧不破坏已拼面。
              3. 拼中心用「两条同色在中间 → 用 F/U 方向把它插进面心」的平移小操作。

              核心手法：
              • 让同色两块水平相邻后，用转动把这对滚进目标面心。
              • 主色面拼好后，一律用未完成面当缓冲，别碰已拼好的大中心。

              四阶中心拼完，等于拿到了「谁是什么颜色」的答案。
              """),
            s(3, 4, "配对棱块", "把 24 条小棱两两配对成 12 条粗棱", "square.grid.3x2.fill", .orange,
              """
              目标：把颜色相同的两个棱块凑成一对，当作三阶的一条棱用。

              步骤要点：
              1. 用一个未配对的棱块当工作位，去找同色伙伴。
              2. 伙伴在顶层/底层时，用「转动 + 翻棱」让它贴到自己旁边。
              3. 配对完成后把它放到完成的棱堆里，再引入下一个未配对棱。

              遇到「最后一对」两棱颜色对不上（顺序不对）时，用「最后两棱公式」交换内部贴纸再配对。

              配对全部完成 → 四阶从结构上已经可以被当作三阶来解。
              """),
            s(4, 4, "按三阶还原", "用三阶层先/CFOP 公式还原整个四阶", "layers.fill", .teal,
              """
              中心拼好、棱配对好之后，把每个「大中心」当一个三阶中心、每条「粗棱」当一条三阶棱。

              这时直接套用你在「3 阶课程」里学的全部公式：
              1. 底层十字（注意对侧面中心色）。
              2. 底层角块、中层棱块。
              3. 顶面还原（OLL）。
              4. 顶层排列（PLL）。

              唯一提醒：转动的「层」不再是一格，而是完整的一层（厚度 = 四阶的半层宽 = 外层单层）。
              所以三阶的 U/R/F 在四阶上一样成立。

              走完这些，绝大多数情况下四阶已经还原。剩下极少数会触发 parity。
              """),
            s(5, 4, "特殊情况（parity）", "用两个专用公式处理单边翻棱与 PLL 特殊情况", "exclamationmark.triangle.fill", .purple,
              """
              偶数阶（4/6/8/10）在按三阶还原到最后时，会出现三阶不可能出现的情况，叫特殊情况。

              OLL 特殊情况（单边翻棱）：顶面只剩一条棱翻不过来。
              公式（把这条棱放 F 面正前）：
              r U2 x r U2 r U2 r' U2 l U2 r' U2 r U2 r' U2 r'
              （r = 靠右两层同时转；做完顶面朝向即可正常。）

              PLL 特殊情况（两对角或两对棱需交换）：
              先用「对棱互换」公式把顶层理顺：
              r2 U2 r2 Uw2 r2 u2（u = 上下两层一起转）
              交换后回到普通 PLL，用三阶公式收尾。

              记不住没事：先会认「触发前状态长什么样」，等需要时再查这两个公式。
              """),
        ]
    }

    // MARK: 5 阶（奇数阶降阶法，5 课）——有固定中心，无 parity
    private static var course5: [CourseStage] {
        [
            s(1, 5, "认识五阶与奇数阶优势", "五阶有固定中心，比四阶少了中心色位难点", "cube", .blue,
              """
              五阶（5×5×5）是奇数阶，和三阶一样有一个固定中心块。
              这点让五阶比四阶好入门：颜色方位不用自己定，中心固定即知哪面对哪色。

              降阶思路与四阶类似但更直观：
              1. 中心：每面要拼成一个「固定中心 + 周围一圈」的同色 3×3 中心区。
              2. 棱：同色棱按 3 个一组配对成粗棱（共 12 条 × 每组 3 小块）。
              3. 之后完全等同于三阶还原。

              奇数阶在按三阶还原阶段基本不触发 parity。
              """),
            s(2, 5, "还原中心块", "每面拼出 3×3 同色中心（含固定中心）", "square.grid.3x3.fill", .green,
              """
              目标：把每面 9 个中心小块（1 个固定 + 8 个活动）拼成整片同色。

              步骤要点：
              1. 先做一条 3 格的中心条，再补齐另两条 → 拼成一个 3×3。
              2. 固定中心决定本面颜色，先把它周围的 8 块靠拢它。
              3. 用「条平移」手法：把同色小块合成竖/横条，再用空面插进目标面。

              常见顺序：先拼白/黄两面对立面，再拼侧面对。
              每次只动一个正在拼的面，其它已拼好的面当禁地别碰。

              中心拼完 → 五阶的颜色坐标系就定死了。
              """),
            s(3, 5, "配对棱块", "同色棱 3 块一组，配成 12 条粗棱", "square.grid.3x2.fill", .orange,
              """
              目标：把每一条「三格同色棱」凑齐（比四阶多一格，逻辑相同）。

              步骤要点：
              1. 用未配对棱当工作位，找齐 3 个同色块。
              2. 先凑好第 1、2 格，再用一次「翻棱/插棱」把第 3 格并进来。
              3. 配好后整体放到完成的棱堆，引入下一组。

              最后一组对不齐时，用「最后两棱交换公式」调整组内贴纸顺序。

              五阶棱配对因多一格，比四阶稍繁琐，但方法完全可平移。
              """),
            s(4, 5, "按三阶还原", "把五阶当三阶，用三阶公式还原", "layers.fill", .teal,
              """
              中心 3×3、棱 3 块一组完成后，五阶从结构上就等于三阶。

              直接套用三阶层先法或 CFOP：
              1. 底层十字。
              2. 底层角块 + 中层棱块。
              3. 顶面还原。
              4. 顶层排列。

              注意：降阶后的「一层」厚度 = 五阶整层宽，外层单层转动即对应三阶单面转动。

              奇数阶走到这通常直接还原，极少需要 parity 公式。
              """),
            s(5, 5, "高阶手筋与提速", "中心/棱的连做、观察与转法提速", "gauge", .purple,
              """
              当你能稳定还原 5 阶后，试着压缩时间。

              中心提速：
              • 一次拼一整条而非逐格搬，减少转动次数。
              • 预判下一个该拼哪条，减少停顿。

              棱提速：
              • 学会「中途配对」：转一面时顺带把另一组棱也带上。
              • 熟练后 6-10 阶的棱配对只是更多组 + 更多层，方法零新增。

              手筋都是练出来的肌肉记忆，每天刷 5-10 分钟即可稳步变快。
              """),
        ]
    }

    // MARK: 6-10 阶（高阶降阶法总览，共享一套方法论，按阶参数化）
    private static func highOrderCourses(_ order: Int) -> [CourseStage] {
        let even = order % 2 == 0
        let edgeCount = order - 2   // 每组棱的小块数
        return [
            s(1, order, "认识 \(order) 阶与降阶共性", "无论几阶都走「中心→棱→三阶还原」", "cube", .blue,
              """
              \(order) 阶（\(order)×\(order)×\(order)）块数多，但解法和 4/5 阶是完全同一套降阶法，只是量变：

              • 中心：每面要拼出 \(order) 行 × \(order) 列的整片同色中心区（\(even ? "偶数阶无固定中心，先定对面色位" : "奇数阶有固定中心，方位自带")）。
              • 棱：每条棱 \(edgeCount) 个同色小块为一组，共 12 条大棱要配齐。
              • 降完阶 → 整个魔方等价于一个三阶，用三阶公式还原。

              差异只在块数变多、层数变多，手法零新增。这一课先建立整体心智模型。
              """),
            s(2, order, "合并中心块（更大规模）", "逐面拼出 \(order)×\(order) 大中心", "square.grid.2x2.fill", .green,
              """
              目标：把每面 \(order)×\(order) 个中心小块拼成整片，6 面完成即定死颜色坐标系。

              步骤要点：
              1. 从某一对面开始（如白/黄），先拼它的一整条中心条，再逐条补齐整面。
              2. \(even ? "偶数阶无固定中心：先把第一对对立面中心拼好当作基准，再确定其它四面方位" : "奇数阶有固定中心：绕固定中心一圈圈往外拼，由中心色确定本面")。
              3. 用「条状平移」手法把同色小块汇成整条，再插进目标面；已拼好的面当禁地。

              规模越大越要一次搬一条，别一块一块挪，否则转动数爆炸。
              """),
            s(3, order, "配对棱块", "每组 \(edgeCount) 个同色棱配成 12 条大棱", "square.grid.3x2.fill", .orange,
              """
              目标：把每条大棱的 \(edgeCount) 个同色小块全部凑齐，当作三阶一条棱。

              步骤要点：
              1. 用一条未配对的大棱当工作位。
              2. 逐格补齐同色块，凑到 \(edgeCount) 个后整体放下，再引入下一条。
              3. 组内顺序错了就用「最后两棱交换」公式调整。

              纯配棱阶段无特殊困难，纯粹是量的累积。
              """),
            s(4, order, "按三阶还原", "降阶完成后用三阶公式整体还原", "layers.fill", .teal,
              """
              中心、棱全部降阶完成后，\(order) 阶就从结构上等价于三阶：
              把每个大中心当一个三阶中心、每条大棱当一条三阶棱，直接套三阶层先/CFOP。

              1. 底层十字（对侧面中心色）。
              2. 底层角块 + 中层棱块。
              3. 顶面还原。
              4. 顶层排列。

              高阶的「一层」厚度很宽，外层单层转动对应三阶单面转动，公式逐个成立。
              """),
            s(5, order, "特殊情况与收官", even ? "偶数阶用 parity 公式收尾" : "奇数阶复核后即还原", "exclamationmark.triangle.fill", .purple,
              even
              ? """
              高阶偶数阶（4/6/8/10）最后常出现三阶不可能的「特殊情况（parity）」，成因：偶数阶没有固定中心，配对后的棱/层在坐标上可能错一层。

              OLL 特殊情况（单边翻棱，把该棱放正前）：
              r U2 x r U2 r U2 r' U2 l U2 r' U2 r U2 r' U2 r'

              PLL 特殊情况（对棱/对角需互换）：
              r2 U2 r2 Uw2 r2 u2

              两个公式各做一遍理顺后，回普通 PLL 收尾。本阶已属偶数阶，请备好这两个公式。
              """
              : """
              奇数阶（5/7/9）没有偶数阶那类「单边翻棱 / 对棱互换」的 parity，走到三阶还原通常直接完成。

              若个别状态看起来不对劲，多半是降阶阶段某组中心或棱配对没对齐——回头检查那组，用「最后两棱交换」或重拼该中心即可。

              因为少了 parity，奇数高阶反而比同尺寸的偶数高阶更顺。恭喜你能驾驭 \(order) 阶 🎉
              """),
        ]
    }
}

/// 课程详情 Sheet（点开某课后展示）
struct CourseDetailSheet: View {
    let stage: CourseStage
    /// 标记完成回调（写进度）
    let onProgressUpdate: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var currentProgress: Double = 0
    @State private var isFavorited: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 顶部彩色头图
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [stage.color.opacity(0.6), stage.color.opacity(0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        HStack(spacing: 12) {
                            Image(systemName: stage.icon)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(.ultraThinMaterial))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("第 \(stage.id) 课").font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.85))
                                Text(stage.title).font(.title2.weight(.bold)).foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(16)
                    }

                    // 学习目标
                    VStack(alignment: .leading, spacing: 6) {
                        Label("学习目标", systemImage: "target")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(stage.goal)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))

                    // 课程正文
                    VStack(alignment: .leading, spacing: 8) {
                        Label("课程内容", systemImage: "text.alignleft")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(stage.content)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.85))
                            .lineSpacing(4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))

                    // 进度条 + 标记完成按钮
                    VStack(spacing: 10) {
                        HStack {
                            Text("学习进度").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(currentProgress * 100))%").font(.caption.weight(.semibold)).foregroundColor(stage.statusColor)
                        }
                        ProgressView(value: currentProgress)
                            .tint(stage.statusColor)
                        HStack(spacing: 10) {
                            Button {
                                currentProgress = max(0, currentProgress - 0.1)
                                onProgressUpdate(currentProgress)
                            } label: {
                                Label("退一格", systemImage: "arrow.uturn.backward")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(.ultraThinMaterial))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            Button {
                                if currentProgress < 1 { currentProgress = 1 } else { currentProgress = 0 }
                                onProgressUpdate(currentProgress)
                                if currentProgress >= 1 {
                                    // 完成后自动关闭
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
                                }
                            } label: {
                                Label(currentProgress >= 1 ? "重学" : "标记完成",
                                      systemImage: currentProgress >= 1 ? "arrow.counterclockwise" : "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(stage.statusColor))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))

                    Color.clear.frame(height: 16)
                }
                .padding(20)
            }
            .background(LinearGradient(colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isFavorited = stage.toggleFavorite()
                    } label: {
                        Image(systemName: isFavorited ? "star.fill" : "star")
                            .foregroundColor(isFavorited ? .yellow : .white)
                    }
                    .accessibilityLabel(isFavorited ? "取消收藏" : "收藏本课")
                }
            }
            .onAppear {
                currentProgress = stage.progress
                isFavorited = stage.isFavorite
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// FAQ 条目（帮助页）
struct FAQItem {
    let question: String
    let answer: String

    static var all: [FAQItem] {
        [
            FAQItem(question: "怎么让 App 教我还原一个乱掉的魔方？",
                    answer: "切到「主页」，把魔方打乱（虚拟魔方点「打乱」，真魔方用「扫描」录入），再切到「学习」点「求解」。App 会给出一步步的还原指引，跟着转即可。"),
            FAQItem(question: "扫描识别错了怎么办？",
                    answer: "在扫描的「确认魔方」页面点有问题的色块，会弹出取色盘，直接选正确的颜色即可，不用整面重拍。"),
            FAQItem(question: "虚拟魔方和真魔方有什么区别？",
                    answer: "虚拟魔方在屏幕里，App 能看见你转的每一步，会检测是否还原、自动停表，也会在你转错指引时提醒。真魔方需要你跟着指引在实体上拧，App 看不见你的操作，进度靠「下一步」手动推进。"),
            FAQItem(question: "我的成绩存在哪里？能保留吗？",
                    answer: "成绩存在本机（UserDefaults），卸载或换机前记得后续可用的「备份导出」。同一台设备上不会丢失。"),
            FAQItem(question: "公式里的 R / U' / F2 是什么意思？",
                    answer: "每个字母代表一个面：U顶 R右 F前 D底 L左 B后。不带后缀=顺时针90°，带'（如R'）=逆时针90°，带2（如F2）=转180°。"),
        ]
    }
}

/// FAQ 折叠行（手风琴）
struct FAQRow: View {
    let item: FAQItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(item.question)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(item.answer)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}



// MARK: - 我的页（按原型 v4 重构）
struct MineView: View {
    @ObservedObject var session: CubeSession
    /// 当前编辑的资料草稿（编辑弹层用）
    @State private var editingNickname = ""
    @State private var editingSignature = ""
    @State private var editingTier: GuideTier = .chinese
    @State private var showEditProfile = false
    /// 子页 sheet 控制
    @State private var showHistorySheet = false
    @State private var showAchievementSheet = false
    @State private var showBackupSheet = false
    @State private var showAboutSheet = false
    @State private var showFeedbackSheet = false
    @State private var showFavoriteSheet = false
    @State private var backupMessage: String? = nil
    @State private var showImportPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("我的")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 14) {
                    profileCard         // 资料卡（按原型：头像+昵称+Lv+已学N课）
                    statsCard           // 3 卡统计（还原次数/最佳成绩/学习天数）
                    menuList            // 菜单列表（设置/历史/成就/备份/分享/反馈/关于）
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 8)
        .sheet(isPresented: $showEditProfile) { editProfileSheet }
        .sheet(isPresented: $showHistorySheet) { historySheet }
        .sheet(isPresented: $showAchievementSheet) { achievementSheet }
        .sheet(isPresented: $showBackupSheet) { backupSheet }
        .sheet(isPresented: $showAboutSheet) { aboutSheet }
        .sheet(isPresented: $showFeedbackSheet) { feedbackSheet }
        .sheet(isPresented: $showFavoriteSheet) { favoriteSheet }
        .sheet(isPresented: $showExportShare) {
            if let data = session.exportBackupData() {
                ShareSheet(items: [backupFileURL(from: data)])
            }
        }
        .sheet(isPresented: $showImportPicker) {
            DocumentPicker { url in
                handleImport(url)
            }
        }
        .alert("数据备份", isPresented: Binding(
            get: { backupMessage != nil },
            set: { if !$0 { backupMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
    }

    // MARK: 资料卡（按原型：头像+昵称+Lv级别+已解锁N课+›）
    private var profileCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [AppTheme.accent,
                                                  Color(red: 0.6, green: 0.2, blue: 1.0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(session.profile.nickname.prefix(1)))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.profile.nickname)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(currentLevelTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.accent)
                    Text("· 已学 \(finishedCourseCount)/\(totalCourseCount) 课")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !session.profile.signature.isEmpty {
                    Text(session.profile.signature)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                editingNickname = session.profile.nickname
                editingSignature = session.profile.signature
                editingTier = session.profile.guideTier
                showEditProfile = true
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        .padding(.horizontal, 20)
    }

    /// 当前等级标题（按总还原次数定档）
    private var currentLevelTitle: String {
        let n = session.totalSolves
        if n >= 50 { return "Lv.4 速度之星" }
        if n >= 10 { return "Lv.3 小有所成" }
        if n >= 1 { return "Lv.2 初出茅庐" }
        return "Lv.1 新手"
    }

    /// 已学完的课数（从 UserDefaults 读进度，按当前阶数课程）
    private var finishedCourseCount: Int {
        CourseStage.courses(for: session.order).filter { $0.progress >= 1 }.count
    }
    private var totalCourseCount: Int { CourseStage.courses(for: session.order).count }

    // MARK: 3 卡片统计（按原型：还原次数/最佳成绩/学习天数）
    private var statsCard: some View {
        HStack(spacing: 10) {
            statItem("\(session.totalSolves)", "还原次数")
            statItem(session.bestTime.map(Self.timeText) ?? "--", "最佳成绩")
            statItem("\(uniqueSolveDays)", "学习天数")
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        .padding(.horizontal, 20)
    }

    /// 有成绩的天数（按 YYYY-MM-DD 去重）
    private var uniqueSolveDays: Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var days = Set<String>()
        for r in session.history { days.insert(f.string(from: r.date)) }
        return days.count
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 菜单列表（按原型：设置/历史/收藏/成就/分享/反馈/关于）
    private var menuList: some View {
        VStack(spacing: 8) {
            menuRow(icon: "gearshape.fill", title: "设置", desc: "档位、资料、主题", action: { showEditProfile = true })
            menuRow(icon: "clock.arrow.circlepath", title: "还原历史", desc: "\(session.history.count) 条记录", action: { showHistorySheet = true })
            menuRow(icon: "bookmark.fill", title: "我的收藏公式", desc: favoriteDesc, action: { showFavoriteSheet = true })
            menuRow(icon: "trophy.fill", title: "成就", desc: "已解锁 \(unlockedAchievementCount)/\(Achievement.all.count) 项", action: { showAchievementSheet = true })
            menuRow(icon: "square.and.arrow.up", title: "数据备份", desc: "导出/导入 JSON", action: { showBackupSheet = true })
            menuRow(icon: "bubble.left.and.bubble.right.fill", title: "意见反馈", desc: "告诉我们哪里需要改进", action: { showFeedbackSheet = true })
            menuRow(icon: "info.circle.fill", title: "关于魔方学院", desc: "v0.5 · 本地数据 · 无需联网", action: { showAboutSheet = true })
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func menuRow(icon: String, title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accent.opacity(0.18))
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.accent)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(desc)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 已解锁的成就数
    private var unlockedAchievementCount: Int {
        Achievement.all.filter { $0.state(for: session) == .unlocked }.count
    }

    /// 收藏公式菜单行描述
    private var favoriteDesc: String {
        let n = CourseStage.allFavorites().count
        return n > 0 ? "已收藏 \(n) 条公式" : "暂无收藏"
    }

    // MARK: - 备份数据子页 sheet
    @State private var showExportShare: Bool = false
    @State private var showClearConfirm: Bool = false
    private var backupSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("导出或导入 JSON 备份，换机/重装后可恢复")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    HStack(spacing: 10) {
                        Button {
                            showExportShare = true
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Capsule().fill(AppTheme.accent))
                        }.buttonStyle(.plain)
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("导入", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Capsule().fill(.ultraThinMaterial))
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 20)
                    if !session.history.isEmpty {
                        Button("清空全部还原记录", role: .destructive) {
                            showClearConfirm = true
                        }
                        .padding(.top, 20)
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 20)
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("数据备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showBackupSheet = false }
                }
            }
            .alert("清空全部还原记录？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { session.clearHistory() }
            } message: { Text("此操作不可恢复") }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 还原历史子页 sheet
    private var historySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if session.history.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "trophy").font(.largeTitle).foregroundColor(.secondary)
                            Text("还没有成绩").foregroundColor(.secondary)
                            Text("完成一次复原会自动记录").font(.caption).foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 32)
                    } else {
                        ForEach(session.history) { rec in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Self.timeText(rec.duration))
                                        .font(.system(.headline, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text("\(rec.moves) 步 · \(Self.chineseDate(rec.date))")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    session.deleteHistory(rec.id)
                                } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.gray.opacity(0.6)) }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                            .padding(.horizontal, 20)
                        }
                    }
                    if session.history.count >= 2 {
                        // 内嵌趋势图
                        VStack(alignment: .leading, spacing: 8) {
                            Text("成绩趋势（最近 20 次）").font(.caption).foregroundColor(.secondary)
                            TrendChart(durations: session.history.prefix(20).map(\.duration).reversed())
                                .frame(height: 100)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                        .padding(.horizontal, 20)
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 8)
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("还原历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showHistorySheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 成就子页 sheet（含进度条）
    private var achievementSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // 成就概览
                    HStack(spacing: 10) {
                        summaryItem("\(unlockedAchievementCount)", "已解锁", color: AppTheme.accent)
                        summaryItem("\(Achievement.all.count)", "全部成就", color: .white)
                        summaryItem(currentLevelTitle, "当前等级", color: .yellow)
                    }
                    .padding(.horizontal, 20)
                    ForEach(Achievement.all, id: \.self) { ach in
                        let state = ach.state(for: session)
                        let progress = achievementProgress(ach)
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(state == .unlocked ? ach.color.opacity(0.25) : Color.white.opacity(0.05))
                                Image(systemName: ach.icon)
                                    .font(.title3)
                                    .foregroundColor(state == .unlocked ? ach.color : .gray)
                            }
                            .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ach.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(ach.subtitle(for: session))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                // 进度条（按原型：部分成就显示进度）
                                if state != .unlocked, progress > 0 {
                                    HStack(spacing: 6) {
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                                                RoundedRectangle(cornerRadius: 2).fill(ach.color)
                                                    .frame(width: geo.size.width * progress)
                                            }
                                        }
                                        .frame(height: 3)
                                        Text("\(Int(progress * 100))%").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            if state == .unlocked {
                                Text("已解锁 ✓")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.green)
                            } else {
                                Text("未解锁").font(.caption2).foregroundColor(.gray)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        .padding(.horizontal, 20)
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 8)
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("成就")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showAchievementSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func summaryItem(_ value: String, _ label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
    }

    // MARK: - 收藏公式子页 sheet（按阶分组，空态提示，可跳课程详情）
    private var favoriteSheet: some View {
        NavigationStack {
            ScrollView {
                let favs = CourseStage.allFavorites()
                if favs.isEmpty {
                    // 空态
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(.gray)
                        Text("还没有收藏任何公式")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("在「学习」里点开任意一课，右上角点星标即可收藏")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .padding(.horizontal, 40)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(favs, id: \.idKey) { stage in
                            favoriteRow(stage)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                Color.clear.frame(height: 20)
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("我的收藏公式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showFavoriteSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// 单条收藏行：阶数 tag + 标题 + 目标 + 取消收藏
    private func favoriteRow(_ stage: CourseStage) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(stage.color.opacity(0.25))
                Image(systemName: stage.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(stage.color)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(stage.order) 阶").font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.accent.opacity(0.2)))
                        .foregroundColor(AppTheme.accent)
                    Text("第 \(stage.id) 课 · \(stage.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(stage.goal)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                _ = stage.toggleFavorite()
                // 触发 sheet 重建以刷新列表
                showFavoriteSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showFavoriteSheet = true }
            } label: {
                Image(systemName: "star.fill")
                    .font(.subheadline)
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
    }

    /// 成就进度（0..1）— 累计还原类按比例，进度类的为 1
    private func achievementProgress(_ ach: Achievement) -> Double {
        switch ach {
        case .firstSolve: return min(1, Double(session.totalSolves))
        case .tenSolves:  return min(1, Double(session.totalSolves) / 10.0)
        case .fiftySolves: return min(1, Double(session.totalSolves) / 50.0)
        case .underMinute:
            if let best = session.bestTime { return best < 60 ? 1 : min(1, 60.0 / best) }
            return 0
        }
    }

    // MARK: - 关于子页 sheet
    private var aboutSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text("魔方学院")
                            .font(.title.weight(.bold))
                            .foregroundColor(.white)
                        Text("v0.5 · 一夜冲刺版")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 24)
                    Group {
                        infoRow("定位", "魔方练习者的私人教练")
                        infoRow("支持阶数", "2 阶 - 10 阶")
                        infoRow("数据", "本地存储，不联网")
                        infoRow("识别", "拍照 + HSV 颜色识别")
                        infoRow("求解", "Kociemba 两阶段（3 阶） / 角块 BFS（2 阶）· 高阶求解规划中")
                        infoRow("开发", "杰哥 + 助手")
                    }
                    .padding(.horizontal, 20)
                    Color.clear.frame(height: 20)
                }
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showAboutSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(v).font(.subheadline).foregroundColor(.white)
            Spacer()
        }.padding(.vertical, 6)
    }

    // MARK: - 反馈子页 sheet
    private var feedbackSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("感谢你愿意反馈！这会直接帮到我们改进 App。")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("反馈方式").font(.caption).foregroundColor(.secondary)
                        Text("1) 加 WorkBuddy 内置客服 1v1")
                        Text("2) 邮箱: feedback@...")
                        Text("3) 公众号「杰哥有话说」留言")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .padding(.horizontal, 20)
                    Color.clear.frame(height: 20)
                }
                .padding(.top, 12)
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("意见反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showFeedbackSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 资料编辑 sheet（与原 MineView 行为兼容）
    private var editProfileSheet: some View {
        VStack(spacing: 20) {
            Text("编辑资料")
                .font(.headline)
            TextField("昵称", text: $editingNickname)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)
            TextField("签名", text: $editingSignature)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("转动提示档位")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("档位", selection: $editingTier) {
                    ForEach(GuideTier.allCases, id: \.self) { tier in
                        Text(tier.rawValue).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                Text(editingTier.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
            }

            Button("保存") {
                let nick = editingNickname.trimmingCharacters(in: .whitespaces)
                if nick.isEmpty || nick.count > 16 {
                    // 简单提示用占位
                } else {
                    session.profile.nickname = nick
                    session.profile.signature = editingSignature.trimmingCharacters(in: .whitespaces)
                    session.profile.guideTier = editingTier
                    session.saveProfile()
                    showEditProfile = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(editingNickname.trimmingCharacters(in: .whitespaces).isEmpty
                      || editingNickname.count > 16)
            Spacer()
        }
        .padding(.top, 30)
        .presentationDetents([.height(340)])
    }

    /// 把导出数据写到临时文件，便于分享到「文件」App
    private func backupFileURL(from data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("魔方学院备份_\(Self.fileTimestamp()).json")
        try? data.write(to: url)
        return url
    }
    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
    private func handleImport(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            backupMessage = "读取文件失败"; return
        }
        if let err = session.importBackupData(data) {
            backupMessage = err
        } else {
            backupMessage = "导入成功，成绩与资料已恢复"
        }
    }

    static func chineseDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: d)
    }
    static func timeText(_ t: TimeInterval) -> String { formatSolveTime(t) }
}

/// 成就定义（三态：已解锁 / 未解锁；当前用两态，进度后续迭代）
enum Achievement: String, CaseIterable {
    case firstSolve = "firstSolve"
    case tenSolves = "tenSolves"
    case fiftySolves = "fiftySolves"
    case underMinute = "underMinute"

    var title: String {
        switch self {
        case .firstSolve: return "初次还原"
        case .tenSolves: return "还原 10 次"
        case .fiftySolves: return "还原 50 次"
        case .underMinute: return "一分钟内"
        }
    }

    var icon: String {
        switch self {
        case .firstSolve: return "sparkles"
        case .tenSolves: return "number.circle.fill"
        case .fiftySolves: return "flame.fill"
        case .underMinute: return "timer"
        }
    }

    var color: Color {
        switch self {
        case .firstSolve: return .yellow
        case .tenSolves: return .green
        case .fiftySolves: return .orange
        case .underMinute: return .red
        }
    }

    static var all: [Achievement] { [.firstSolve, .tenSolves, .fiftySolves, .underMinute] }

    enum UnlockState { case unlocked, locked }

    @MainActor
    func state(for session: CubeSession) -> UnlockState {
        switch self {
        case .firstSolve: return session.totalSolves >= 1 ? .unlocked : .locked
        case .tenSolves: return session.totalSolves >= 10 ? .unlocked : .locked
        case .fiftySolves: return session.totalSolves >= 50 ? .unlocked : .locked
        case .underMinute:
            return (session.bestTime.map { $0 < 60 } ?? false) ? .unlocked : .locked
        }
    }

    @MainActor
    func subtitle(for session: CubeSession) -> String {
        switch self {
        case .firstSolve: return "完成你的第一次复原"
        case .tenSolves: return "累计完成 10 次（当前 \(session.totalSolves)）"
        case .fiftySolves: return "累计完成 50 次（当前 \(session.totalSolves)）"
        case .underMinute:
            return session.bestTime.map { "最快 \(MineView.timeText($0))" } ?? "单次用时进 60 秒"
        }
    }
}

// MARK: - 系统分享 / 文件导入（UIKit 包装）

/// 成绩趋势折线图（纯 SwiftUI 原生绘制，无第三方依赖）。
struct TrendChart: View {
    let durations: [TimeInterval]  // 旧 → 新

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad: CGFloat = 12
            let minD = durations.min() ?? 0
            let maxD = durations.max() ?? 1
            let range = max(maxD - minD, 0.5)  // 至少 0.5s 范围，避免除零/线太平

            ZStack {
                // 网格线（3 条横向参考线）
                ForEach(0..<3, id: \.self) { i in
                    let y = pad + (h - 2 * pad) * CGFloat(i) / 2
                    Path { p in
                        p.move(to: CGPoint(x: pad, y: y))
                        p.addLine(to: CGPoint(x: w - pad, y: y))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

                // 折线
                if durations.count >= 2 {
                    let step = (w - 2 * pad) / CGFloat(durations.count - 1)
                    Path { p in
                        for (i, d) in durations.enumerated() {
                            let x = pad + step * CGFloat(i)
                            let y = pad + (h - 2 * pad) * (1 - CGFloat((d - minD) / range))
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [AppTheme.accent,
                                                AppTheme.accentLight],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )

                    // 数据点
                    ForEach(Array(durations.enumerated()), id: \.offset) { i, d in
                        let x = pad + step * CGFloat(i)
                        let y = pad + (h - 2 * pad) * (1 - CGFloat((d - minD) / range))
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 5, height: 5)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

/// 分享面板（导出备份 JSON 到「文件」App / AirDrop 等）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// 文件选择器（导入备份 JSON）。
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // 需先请求安全作用域访问
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            onPick(url)
        }
    }
}
