import Foundation
import Security
#if canImport(CloudKit)
import CloudKit
#endif

/// CloudKit 成绩存储。
/// - 记录每次复原的用时 / 步数 / 打乱公式 / 日期，跨设备同步。
/// - 需要在 Signing & Capabilities 里开启 **iCloud → CloudKit**。
/// - **运行时检测 entitlements**：未配置 iCloud entitlements（CI/无 Team/未勾选 iCloud）时所有操作 no-op，
///   且 **完全不会触碰 CKContainer**，避免 `CKContainer.default()` 在 `dispatch_once` 注册
///   `CKAccountChangedNotification` 时抛 NSException（Swift `try?` 抓不住）导致 App 闪退。
public final class CloudStore {
    public static let shared = CloudStore()

    private let recordType = "SolveRecord"
    private let database: CKDatabase?
    private let isCloudEnabled: Bool

    private init() {
        // 用 SecTask 读 codesign 段里的 entitlement（CI 无 codesign → nil → 安全 no-op）
        isCloudEnabled = Self.hasICloudEntitlement()
        #if canImport(CloudKit)
        if isCloudEnabled {
            // 真的配了 entitlement 才 init CKContainer，触发 dispatch_once 注册
            database = CKContainer.default().privateCloudDatabase
        } else {
            database = nil
        }
        #else
        database = nil
        #endif
    }

    private static func hasICloudEntitlement() -> Bool {
        // 1. 优先看 codesign 注入的 entitlement（真机/正确签名时）
        if let task = SecTaskCreateFromSelf(nil) {
            let keys = [
                "com.apple.developer.icloud-container-identifiers",
                "com.apple.developer.icloud-services"
            ]
            for k in keys {
                if (SecTaskCopyValueForEntitlement(task, k as CFString, nil) != nil) {
                    return true
                }
            }
        }
        // 2. fallback：看 Info.plist（少数项目把 entitlement 透到 Info.plist）
        let entKeys = [
            "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.icloud-services"
        ]
        for k in entKeys {
            if let arr = Bundle.main.object(forInfoDictionaryKey: k) as? [String], !arr.isEmpty {
                return true
            }
        }
        return false
    }

    /// 保存一次成绩。CloudKit 不可用时静默跳过。
    public func save(duration: TimeInterval, moves: Int, scramble: String) {
        guard isCloudEnabled, let database else { return }
        #if canImport(CloudKit)
        let record = CKRecord(recordType: recordType)
        record["duration"] = duration
        record["moves"] = Int64(moves)
        record["scramble"] = scramble
        database.save(record) { _, error in
            if let error { print("[CloudStore] save failed: \(error.localizedDescription)") }
        }
        #endif
    }

    /// 拉取历史成绩（按时间倒序，最多 100 条）。CloudKit 不可用时返回空。
    public func fetch(completion: @escaping ([SolveRecord]) -> Void) {
        guard isCloudEnabled, let database else { completion([]); return }
        #if canImport(CloudKit)
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
        #else
        completion([])
        #endif
    }

    #if canImport(CloudKit)
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
    #endif
}