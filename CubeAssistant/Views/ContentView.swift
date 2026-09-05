import SwiftUI

/// 主界面：3D 魔方演示 + 计时 + 扫描入口 + 求解回放 + 历史入口。
/// 直接作为 `WindowGroup` 的根视图即可（见 `CubeAssistantApp`）。
public struct ContentView: View {
    @StateObject private var session = CubeSession()
    @State private var showScan = false
    @State private var showHistory = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // 计时区
                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text(session.liveElapsed > 0 ? formatTime(session.liveElapsed)
                             : (session.lastDuration > 0 ? formatTime(session.lastDuration) : "00:00.00"))
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        Text(session.liveElapsed > 0 ? "进行中" : "本次用时")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Divider().frame(height: 36)
                    VStack(spacing: 2) {
                        Text(session.bestTime > 0 ? formatTime(session.bestTime) : "—")
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                        Text("最佳")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)

                Cube3DView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: 340)

                if let msg = session.message {
                    Text(msg).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }

                // 操作按钮
                HStack(spacing: 10) {
                    Button { showScan = true } label: { Label("扫描", systemImage: "viewfinder.circle") }
                    Button { session.scramble() } label: { Label("打乱", systemImage: "shuffle") }
                    Button { session.solve() } label: { Label("求解", systemImage: "lightbulb") }
                        .disabled(session.isSolving)
                    Button { session.stepBackward() } label: { Image(systemName: "backward.fill") }
                        .disabled(session.currentStep == 0)
                    Button { session.stepForward() } label: { Image(systemName: "forward.fill") }
                        .disabled(session.currentStep >= session.playbackSequence.count)
                    Button { session.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                }
                .buttonStyle(.bordered)
                .font(.footnote)
                .padding(.horizontal, 4)

                if !session.solution.isEmpty {
                    let played = max(0, session.currentStep - session.solutionBase)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(session.solution.enumerated()), id: \.offset) { i, m in
                                Text(m.notation)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(6)
                                    .background(i < played ? Color.accentColor.opacity(0.25) : Color.clear)
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    Text("进度 \(played)/\(session.solution.count)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("魔方助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: { Image(systemName: "trophy.fill") }
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
    }

    /// 预览模式：云端模拟器截图用。正常启动（无 --preview 参数）时完全不触发。
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
