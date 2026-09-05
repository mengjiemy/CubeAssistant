import Foundation
import CloudKit

/// CloudKit 成绩存储。
/// - 记录每次复原的用时 / 步数 / 打乱公式 / 日期，跨设备同步。
/// - 需要你在 Xcode 的 Signing & Capabilities 里开启 **iCloud → CloudKit**（Container 用默认的 `iCloud.<bundle-id>` 即可）。
/// - 若未开启 CloudKit 或网络不可用，所有操作静默失败、不影响主流程（成绩仍在本地计时显示）。
public final class CloudStore {
    public static let shared = CloudStore()

    private let recordType = "SolveRecord"
    private let database: CKDatabase

    private init() {
        // 默认容器；若你配置了自定义容器，改成 CKContainer(identifier: "iCloud.xxx")
        database = CKContainer.default().privateCloudDatabase
    }

    /// 保存一次成绩。
    public func save(duration: TimeInterval, moves: Int, scramble: String) {
        let record = CKRecord(recordType: recordType)
        record["duration"] = duration
        record["moves"] = Int64(moves)
        record["scramble"] = scramble
        database.save(record) { _, error in
            if let error { print("[CloudStore] save failed: \(error.localizedDescription)") }
        }
    }

    /// 拉取历史成绩（按时间倒序，最多 100 条）。
    public func fetch(completion: @escaping ([SolveRecord]) -> Void) {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if #available(iOS 15.0, macOS 12.0, *) {
            database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100) { result in
                switch result {
                case .success(let tuple):
                    let records = tuple.matchResults.compactMap { try? $1.get() }
                    completion(self.map(records))
                case .failure(let error):
                    print("[CloudStore] fetch failed: \(error.localizedDescription)")
                    completion([])
                }
            }
        } else {
            completion([])
        }
    }

    private func map(_ records: [CKRecord]) -> [SolveRecord] {
        records.compactMap { rec in
            guard let duration = rec["duration"] as? Double,
                  let moves = rec["moves"] as? Int64,
                  let date = rec.creationDate else { return nil }
            let scramble = (rec["scramble"] as? String) ?? ""
            return SolveRecord(id: rec.recordID.recordName,
                               duration: duration,
                               moves: Int(moves),
                               scramble: scramble,
                               date: date)
        }
    }
}
