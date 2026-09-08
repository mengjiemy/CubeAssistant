import SwiftUI

/// 历史成绩页（独立视图，可从任意入口调用）。
/// 展示本地持久化的复原成绩（`session.history`，UserDefaults 存储）。
struct HistoryView: View {
    @ObservedObject var session: CubeSession
    @Environment(\.dismiss) private var dismiss

    init(session: CubeSession) { self.session = session }

    var body: some View {
        NavigationStack {
            Group {
                if session.history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy").font(.largeTitle).foregroundColor(.secondary)
                        Text("还没有成绩").foregroundColor(.secondary)
                        Text("完成一次复原会自动记录").font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(session.history) { rec in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formatTime(rec.duration))
                                    .font(.system(.headline, design: .monospaced))
                                Spacer()
                                Text("\(rec.moves) 步").foregroundColor(.secondary)
                            }
                            Text(rec.date, style: .date)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("历史成绩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}
