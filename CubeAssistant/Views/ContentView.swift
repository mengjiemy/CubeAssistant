import SwiftUI

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
                    .foregroundColor(selectedTab == tab ? Color(red: 0.04, green: 0.52, blue: 1.0) : .white.opacity(0.5))
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
                Button {
                    session.setIdentity(session.identity == .physical ? .virtual : .physical)
                } label: {
                    Label(session.identity == .physical ? "真魔方" : "虚拟魔方",
                          systemImage: session.identity == .physical ? "cube" : "laptopcomputer")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.25)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 14) {
                    timingCard

                    ZStack(alignment: .topTrailing) {
                        Cube3DView(session: session)
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

                    turnControls
                    actionRow
                }
                .padding(.bottom, 40)
            }
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
                    .background(Capsule().fill(Color(red: 0.04, green: 0.52, blue: 1.0)))
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
                        .background(Capsule().fill(Color(red: 0.04, green: 0.52, blue: 1.0)))
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
                Capsule().fill(selected ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color.white.opacity(0.06))
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
                    .background(Capsule().fill(Color(red: 0.04, green: 0.52, blue: 1.0)))
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

    static func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}

// MARK: - 学习页
struct LearnView: View {
    @ObservedObject var session: CubeSession

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
                    if let sol = session.solveSession {
                        guideContent(sol)
                    } else {
                        studyCenter
                    }
                }
                .padding(.bottom, 12)
            }

            // 底部固定「求解」按钮（保持可见）
            Button {
                if !session.isSolving {
                    session.solve()
                }
            } label: {
                Label(session.isSolving ? "计算中…" : "求解", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color(red: 0.04, green: 0.52, blue: 1.0)))
            }
            .buttonStyle(.plain)
            .disabled(session.isSolving)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .padding(.top, 8)
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

    /// 基础课程骨架：分阶段标题 + 说明（图文教学后续版本完善）
    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
                Text("三阶课程")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            Text("按阶段学习还原，打乱后配合「求解」边看边练")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(CourseStage.all, id: \.id) { stage in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(stage.color.opacity(0.15))
                        Image(systemName: stage.icon)
                            .foregroundColor(stage.color)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(stage.goal)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
    }

    /// 帮助 FAQ：可折叠手风琴
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1.0))
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

            // 当前步大字指令（中文 + 公式）
            if !isComplete, let move = sol.move(at: session.alignedStep) {
                VStack(spacing: 6) {
                    Text(move.chineseInstruction)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text(move.notation)
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .foregroundColor(Color(red: 0.4, green: 0.7, blue: 1.0))
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
                .foregroundColor(done ? .green : (current ? Color(red: 0.04, green: 0.52, blue: 1.0) : .white.opacity(0.6)))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(current ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(current ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color.clear, lineWidth: 2)
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
                .background(Capsule().fill(disabled ? Color.white.opacity(0.06) : Color(red: 0.04, green: 0.52, blue: 1.0)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }
}

/// 课程阶段（骨架定义）
struct CourseStage: Identifiable {
    let id: Int
    let title: String
    let goal: String
    let icon: String
    let color: Color

    static var all: [CourseStage] {
        [
            CourseStage(id: 1, title: "认识魔方", goal: "结构、面、转动记号入门", icon: "cube", color: .blue),
            CourseStage(id: 2, title: "底层十字", goal: "拼出白色十字并对齐中心", icon: "plus", color: .green),
            CourseStage(id: 3, title: "第一层", goal: "还原底层角块", icon: "square.grid.2x2.fill", color: .yellow),
            CourseStage(id: 4, title: "第二层", goal: "还原中间层棱块", icon: "square.grid.3x2.fill", color: .orange),
            CourseStage(id: 5, title: "顶层还原", goal: "顶面 + 顶层全部归位", icon: "star.fill", color: .purple),
        ]
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



// MARK: - 我的页
struct MineView: View {
    @ObservedObject var session: CubeSession
    /// 当前编辑的资料草稿（编辑弹层用）
    @State private var editingNickname = ""
    @State private var editingSignature = ""
    @State private var showEditProfile = false
    /// 历史管理弹确认
    @State private var showClearConfirm = false

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
                    profileCard
                    statsCard
                    achievementsSection
                    historySection
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 8)
        .sheet(isPresented: $showEditProfile) {
            editProfileSheet
        }
        .alert("清空全部还原记录？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { session.clearHistory() }
        } message: {
            Text("此操作不可恢复")
        }
    }

    // MARK: 资料卡
    private var profileCard: some View {
        HStack(spacing: 14) {
            // 头像占位：渐变圆 + 首字
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.04, green: 0.52, blue: 1.0),
                                                  Color(red: 0.6, green: 0.2, blue: 1.0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(session.profile.nickname.prefix(1)))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(session.profile.nickname)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                Text(session.profile.signature)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 编辑资料
            Button {
                editingNickname = session.profile.nickname
                editingSignature = session.profile.signature
                showEditProfile = true
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        .padding(.horizontal, 20)
    }

    // MARK: 战绩摘要
    private var statsCard: some View {
        HStack(spacing: 0) {
            statItem("\(session.totalSolves)", "还原次数")
            divider
            statItem(session.bestTime.map(Self.timeText) ?? "--", "最快")
            divider
            statItem(session.averageTime.map(Self.timeText) ?? "--", "平均")
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 34)
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 成就
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("成就")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            ForEach(Achievement.all, id: \.self) { ach in
                let state = ach.state(for: session)
                HStack(spacing: 12) {
                    Image(systemName: ach.icon)
                        .font(.title3)
                        .foregroundColor(state == .locked ? .gray : ach.color)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ach.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(ach.subtitle(for: session))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    switch state {
                    case .unlocked:
                        Text("已解锁")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green)
                    case .locked:
                        Text("未解锁")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                .padding(.horizontal, 20)
                .opacity(state == .locked ? 0.55 : 1.0)
            }
        }
        .padding(.top, 4)
    }

    // MARK: 还原历史
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("还原历史")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if !session.history.isEmpty {
                    Button("清空") {
                        showClearConfirm = true
                    }
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)

            if session.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("还没有成绩")
                        .foregroundColor(.secondary)
                    Text("完成一次复原会自动记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                .padding(.horizontal, 20)
            } else {
                ForEach(session.history) { rec in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Self.timeText(rec.duration))
                                .font(.system(.headline, design: .monospaced))
                                .foregroundColor(.white)
                            Text("\(rec.moves) 步 · \(Self.chineseDate(rec.date))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            session.deleteHistory(rec.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: 编辑资料弹层
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
            Button("保存") {
                let nick = editingNickname.trimmingCharacters(in: .whitespaces)
                if nick.isEmpty || nick.count > 16 {
                    // 简单提示用占位
                } else {
                    session.profile.nickname = nick
                    session.profile.signature = editingSignature.trimmingCharacters(in: .whitespaces)
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
        .presentationDetents([.height(260)])
    }

    /// 中文日期格式，如「2026年9月8日 15:32」
    static func chineseDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: d)
    }

    /// 时间文本（mm:ss.cc）
    static func timeText(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }
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
