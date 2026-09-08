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

                    Cube3DView(session: session)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)

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
            // 6 面选层（选中蓝框高亮），顺序「上下左右前后」，一排放下
            HStack(spacing: 6) {
                ForEach([Face.U, Face.D, Face.L, Face.R, Face.F, Face.B], id: \.self) { f in
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
            Text(faceLabel(f))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selected ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(selected ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(selected ? Color(red: 0.3, green: 0.7, blue: 1.0) : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func faceLabel(_ f: Face) -> String {
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
        VStack(spacing: 16) {
            Text("学习")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            Spacer()

            if let sol = session.solveSession {
                VStack(spacing: 12) {
                    Text("还原指引（共 \(sol.totalSteps) 步）")
                        .font(.headline)
                        .foregroundColor(.white)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(sol.orbit.enumerated()), id: \.offset) { i, m in
                                Text(m.notation)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 9)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("扫描或打乱后，点下方「求解」生成还原指引")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                if session.isSolving {
                    // 计算中
                } else {
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
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
    }
}

// MARK: - 我的页
struct MineView: View {
    @ObservedObject var session: CubeSession

    var body: some View {
        VStack(spacing: 16) {
            Text("我的")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            Spacer()

            if session.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trophy")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("还没有成绩")
                        .foregroundColor(.secondary)
                    Text("完成一次复原会自动记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(session.history) { rec in
                            HStack {
                                Text(HomeView.formatTime(rec.duration))
                                    .font(.system(.headline, design: .monospaced))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(rec.moves) 步")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(Self.chineseDate(rec.date))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, 8)
    }

    /// 中文日期格式，如「2026年9月8日 15:32」
    static func chineseDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: d)
    }
}