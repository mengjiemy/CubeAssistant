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
    @State private var selectedLayer: Layer = .top
    @State private var timingState: TimingState = .idle

    enum Layer: String, CaseIterable {
        case top = "顶层", middle = "中层", bottom = "底层"
        var icon: String {
            switch self {
            case .top: return "arrow.up.circle"
            case .middle: return "equal.circle"
            case .bottom: return "arrow.down.circle"
            }
        }
    }

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

                    if let msg = session.message {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    turnControls
                    actionRow
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: 计时卡（三态）
    private var timingCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.formatTime(displayedElapsed))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(timingStateLabel)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.history.first.map { Self.formatTime($0.duration) } ?? "—")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("最近")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            // 主操作按钮（随状态切换文案）
            timingPrimaryButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
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
                    // 继续：从最近 elapsed 重新启动计时器（用当前暂停时刻重启）
                    session.startTiming()
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
        case .idle:    return session.history.isEmpty ? "本次用时" : "上次成绩已记录"
        case .running: return "进行中…点击暂停"
        case .paused:  return "已暂停 · 继续或完成"
        }
    }

    // MARK: 转层控件
    private var turnControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Layer.allCases, id: \.self) { layer in
                    Button {
                        selectedLayer = layer
                    } label: {
                        Text(layer.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(selectedLayer == layer ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(selectedLayer == layer ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                turnButton("向左横转", "arrow.left") { applyMove(.horizontalLeft) }
                turnButton("向右横转", "arrow.right") { applyMove(.horizontalRight) }
                turnButton("向上竖转", "arrow.up") { applyMove(.verticalUp) }
                turnButton("向下竖转", "arrow.down") { applyMove(.verticalDown) }
            }
        }
        .padding(.horizontal, 20)
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
            .padding(.vertical, 12)
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
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.weight(.medium))
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
                Image(systemName: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
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

    private func applyMove(_ dir: TurnDirection) {
        let move: Move = resolveMove(layer: selectedLayer, direction: dir)
        _ = session.apply(move)
    }

    enum TurnDirection {
        case horizontalLeft, horizontalRight, verticalUp, verticalDown
    }

    /// 选层 + 方向 → 标准 Move。
    /// 横转=顶层/中层/底层水平转(U/U'，中层用U2)，竖转=前后竖转(F/F')
    private func resolveMove(layer: Layer, direction: TurnDirection) -> Move {
        switch (layer, direction) {
        case (.top, .horizontalLeft):    return .U
        case (.top, .horizontalRight):   return .Up
        case (.top, .verticalUp):       return .F
        case (.top, .verticalDown):     return .Fp
        case (.middle, .horizontalLeft): return .U2
        case (.middle, .horizontalRight):return .U2
        case (.middle, .verticalUp):    return .F
        case (.middle, .verticalDown):  return .Fp
        case (.bottom, .horizontalLeft): return .D
        case (.bottom, .horizontalRight):return .Dp
        case (.bottom, .verticalUp):    return .F
        case (.bottom, .verticalDown):  return .Fp
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
                                Text(rec.date, style: .date)
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
}