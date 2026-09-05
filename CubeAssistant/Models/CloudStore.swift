import Foundation

/// CloudKit 成绩存储接口（iCloud 同步）。
///
/// **当前实现：完全本地 no-op**。
///
/// 原因：CKContainer.default() 在首次访问时会在 `dispatch_once` 注册
/// `CKAccountChangedNotification`，该路径会抛 Objective-C NSException
///（reason: 'containerIdentifier can not be nil'）。Swift 的 `try?` 抓不住
/// NSException（只接 Swift-style error），App 启动即崩。
///
/// **未配置 iCloud entitlements 时绝不能调用 CKContainer 任何 API。**
///
/// 启用 iCloud 同步步骤：
///   1. Xcode → Target → Signing & Capabilities → + Capability → iCloud
///   2. 勾选 "CloudKit"，新建或选择 Container
///   3. 取消本文件中的 iCloud 启用块注释（标有 `// ICloud:`），并把 save/fetch
///      中的占位实现替换为 CKContainer + CKRecord/CKQuery 真实调用
///
/// 接口保留：调用方（Session / ViewModel）零改动，启用时只动本文件。
public final class CloudStore {
    public static let shared = CloudStore()

    private init() {}

    /// 保存一次成绩。iCloud 未启用时 no-op。
    public func save(duration: TimeInterval, moves: Int, scramble: String) {
        // ICloud: 启用时替换为下面这段
        //
        //   let record = CKRecord(recordType: "SolveRecord")
        //   record["duration"] = duration
        //   record["moves"] = Int64(moves)
        //   record["scramble"] = scramble
        //   CKContainer.default().privateCloudDatabase.save(record) { _, error in
        //       if let error { print("[CloudStore] save failed: \(error.localizedDescription)") }
        //   }
    }

    /// 拉取历史成绩（按时间倒序，最多 100 条）。iCloud 未启用时返回空。
    public func fetch(completion: @escaping ([SolveRecord]) -> Void) {
        // ICloud: 启用时替换为下面这段
        //
        //   let query = CKQuery(recordType: "SolveRecord", predicate: NSPredicate(value: true))
        //   query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        //   CKContainer.default().privateCloudDatabase.fetch(
        //       withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100
        //   ) { result in
        //       switch result {
        //       case .success(let tuple):
        //           let records = tuple.matchResults.compactMap { try? $1.get() }
        //           completion(self.map(records))
        //       case .failure(let error):
        //           print("[CloudStore] fetch failed: \(error.localizedDescription)")
        //           completion([])
        //       }
        //   }
        completion([])
    }
}