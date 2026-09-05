import Foundation
import CloudKit

/// CloudKit 成绩存储。
/// - 记录每次复原的用时 / 步数 / 打乱公式 / 日期，跨设备同步。
/// - 需要在 Signing & Capabilities 里开启 **iCloud → CloudKit**；未开启/无 iCloud 账号时所有操作 no-op（不影响主流程）。
public final class CloudStore {
    public static let shared = CloudStore()

    private let recordType = "SolveRecord"
    private let database: CKDatabase?

    private init() {
        // 未配置 iCloud entitlements 或模拟器无 iCloud 账号时 CKContainer.default() 会抛
        // 'containerIdentifier can not be nil' 异常，整个 app 会闪退。这里降级为 no-op。
        database = (try? CKContainer.default().privateCloudDatabase)
    }

    /// 保存一次成绩。CloudKit 不可用时静默跳过。
    public func save(duration: TimeInterval, moves: Int, scramble: String) {
        guard let database else { return }
        let record = CKRecord(recordType: recordType)
        record["duration"] = duration
        record["moves"] = Int64(moves)
        record["scramble"] = scramble
        database.save(record) { _, error in
            if let error { print("[CloudStore] save failed: \(error.localizedDescription)") }
        }
    }

    /// 拉取历史成绩（按时间倒序，最多 100 条）。CloudKit 不可用时返回空。
    public func fetch(completion: @escaping ([SolveRecord]) -> Void) {
        guard let database else { completion([]); return }
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