import SwiftUI

/// 主界面：3D 魔方演示 + 计时 + 扫描入口 + 求解回放 + 历史入口。
/// 主题：深空黑底 + iOS 系统蓝 + 玻璃卡片 + SF Symbols（对标苹果官网高级感）。
public struct ContentView: View {
    @StateObject private var session = CubeSession()
    @State private var showScan = false
    @State private var showHistory = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // 深空黑渐变底（带轻微垂直渐变，避免死黑）
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.04, blue: 0.08),
                             Color(red: 0.01, green: 0.01, blue: 0.03)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    // 计时玻璃卡
                    timingCard

                    // 3D 魔方
                    Cube3DView(session: session)
                        .frame(maxWidth: .infinity, maxHeight: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)

                    if let msg = session.message {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }

                    // 操作栏（胶囊按钮组）
                    controlBar

                    // 解法步骤条
                    if !session.solution.isEmpty {
                        solutionStrip
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationTitle("魔方学院")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.04))
                    }
                }
            }
            .sheet(isPresented: $showScan) { CameraScanView(session: session) }
            .sheet(isPresented: $showHistory) { HistoryView(session: session) }
            .onAppear {
                session.loadHistory()
                if let mode = Self.previewArgument() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        applyPreview(mode)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 计时玻璃卡
    private var timingCard: some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(session.liveElapsed > 0 ? formatTime(session.liveElapsed)
                     : (session.lastDuration > 0 ? formatTime(session.lastDuration) : "00:00.00"))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(session.liveElapsed > 0 ? "进行中" : "本次用时")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            Divider().frame(height: 44).overlay(Color.white.opacity(0.12))
            VStack(spacing: 4) {
                Text(session.bestTime > 0 ? formatTime(session.bestTime) : "—")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("最佳")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - 操作栏
    private var controlBar: some View {
        HStack(spacing: 10) {
            primaryButton("扫描", "viewfinder") { showScan = true }
            iconButton("shuffle") { session.scramble() }
            iconButton("lightbulb", disabled: session.isSolving) { session.solve() }
            iconButton("backward.fill", disabled: session.currentStep == 0) { session.stepBackward() }
            iconButton("forward.fill", disabled: session.currentStep >= session.playbackSequence.count) { session.stepForward() }
            iconButton("arrow.counterclockwise") { session.reset() }
        }
        .padding(.horizontal, 6)
    }

    private func primaryButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(Color(red: 0.04, green: 0.52, blue: 1.0))
                )
        }
    }

    private func iconButton(_ systemName: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                )
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
    }

    // MARK: - 解法步骤条
    private var solutionStrip: some View {
        VStack(spacing: 8) {
            let played = max(0, session.currentStep - session.solutionBase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(session.solution.enumerated()), id: \.offset) { i, m in
                        Text(m.notation)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(i < played ? .semibold : .regular)
                            .foregroundColor(i < played ? Color(red: 0.04, green: 0.52, blue: 1.0) : .white.opacity(0.7))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(i < played ? Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.22) : Color.white.opacity(0.06))
                            )
                    }
                }
                .padding(.horizontal, 4)
            }
            Text("进度 \(played)/\(session.solution.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - 预览模式（模拟器截图用）
    private static func previewArgument() -> String? {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "--preview"), i + 1 < a.count { return a[i + 1] }
        return nil
    }

    private func applyPreview(_ mode: String) {
        switch mode {
        case "scramble": session.scramble()
        case "solve":
            session.scramble()
            session.solve()
        case "scan": showScan = true
        case "history": showHistory = true
        default: break
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}
