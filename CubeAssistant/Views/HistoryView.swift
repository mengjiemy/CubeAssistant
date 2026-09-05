import SwiftUI

/// 历史成绩页：展示 CloudKit 中保存的历次复原记录。
public struct HistoryView: View {
    @ObservedObject var session: CubeSession
    @Environment(\.dismiss) private var dismiss

    public init(session: CubeSession) { self.session = session }

    private static var df: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    public var body: some View {
        NavigationStack {
            Group {
                if session.history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy").font(.largeTitle).foregroundColor(.secondary)
                        Text("还没有成绩").foregroundColor(.secondary)
                        Text("开启 iCloud 后，每次复原会自动记录").font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(session.history) { rec in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(formatTime(rec.duration))
                                        .font(.system(.headline, design: .monospaced))
                                    Spacer()
                                    Text("\(rec.moves) 步").foregroundColor(.secondary)
                                }
                                if !rec.scramble.isEmpty {
                                    Text("打乱：\(rec.scramble)")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                Text(Self.df.string(from: rec.date))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .refreshable { session.loadHistory() }
                }
            }
            .navigationTitle("历史成绩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { session.loadHistory() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let cs = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}
