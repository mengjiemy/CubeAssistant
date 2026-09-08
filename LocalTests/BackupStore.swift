import Foundation

// ============================================================
// 魔方学院 · 数据备份 / 恢复（纯 Foundation，可本地测试）
//
// 目的：把「成绩记录 + 用户资料」导出为单个 JSON 文件，支持换机/重装后导入。
// 对应功能说明书 §0.5「备份与跨阶」——数据不因换设备丢失。
//
// 设计要点：
// - 顶层带 schemaVersion，未来字段变化时靠迁移器兼容老备份。
// - 导出/导入是纯函数（Data <-> 结构），不碰文件系统（由 UI 层负责写文件/分享）。
//   这样本地 swiftc 可单测，也避免把文件 IO 混进逻辑层。
// ============================================================

/// 一次复原成绩记录（本地持久化）。
/// 原本定义在 CubeSession.swift，因 BackupStore（纯逻辑）需引用它，
/// 且 SolveRecord 本身是纯数据模型，遂迁至本文件（数据模型同层），
/// 消除纯逻辑层对 SwiftUI 依赖文件的反向引用。
struct SolveRecord: Identifiable, Codable, Equatable {
    let id: String
    let duration: TimeInterval
    let moves: Int
    let scramble: String
    let date: Date
}

/// 备份数据顶层结构（写入 JSON 的内容）。
/// 字段命名保持稳定，向后兼容；新增字段一律加默认值 + 提升 schemaVersion。
struct BackupData: Codable, Equatable {
    /// 备份格式版本号。当前 v1。
    var schemaVersion: Int
    /// 导出时间（ISO 8601）
    var exportedAt: Date
    /// 成绩记录（按时间倒序）
    var records: [SolveRecord]
    /// 用户资料
    var nickname: String
    var signature: String
    var guideTier: String

    static let currentVersion = 1

    /// 从当前会话数据打包（UI 层传入）。
    init(records: [SolveRecord], nickname: String, signature: String, guideTier: GuideTier) {
        self.schemaVersion = Self.currentVersion
        self.exportedAt = Date()
        self.records = records
        self.nickname = nickname
        self.signature = signature
        self.guideTier = guideTier.rawValue
    }
}

/// 备份编码 / 解码 + 版本迁移。
public enum BackupManager {
    /// 迁移结果：解码成功返回结构；失败返回错误（含可读原因）。
    public enum BackupError: Error, Equatable, LocalizedError {
        case invalidData          // 不是合法 JSON / 结构不匹配
        case unsupportedVersion   // schemaVersion 高于当前 App 支持（旧 App 读新备份）
        case emptyRecords         // 合法但无内容（可选，不算错误，见 decode 说明）

        public var errorDescription: String? {
            switch self {
            case .invalidData: return "备份文件损坏或格式不对"
            case .unsupportedVersion: return "这个备份来自更新版本的 App，请先升级再导入"
            case .emptyRecords: return "备份里没有数据"
            }
        }
    }

    /// 编码为 JSON Data（含漂亮格式，便于用户肉眼可读 / 排查）。
    static func encode(_ backup: BackupData) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(backup)
    }

    /// 从 JSON Data 解码，并做版本迁移。
    /// - 返回 `.success(BackupData)`：合法可导入。
    /// - 返回 `.failure(.unsupportedVersion)`：备份版本高于 App，需升级。
    /// - 返回 `.failure(.invalidData)`：损坏/结构不匹配。
    static func decode(_ data: Data) -> Result<BackupData, BackupError> {
        // 先试最新结构
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let b = try? decoder.decode(BackupData.self, from: data) {
            // 版本校验
            if b.schemaVersion > BackupData.currentVersion {
                return .failure(.unsupportedVersion)
            }
            return .success(migrateIfNeeded(b))
        }
        return .failure(.invalidData)
    }

    /// 老版本 → 新版本迁移（当前 v1 起步，无更老版本，预留钩子）。
    private static func migrateIfNeeded(_ b: BackupData) -> BackupData {
        // 未来若 schemaVersion 提升，在此补迁移逻辑（如 v1→v2 补字段默认值）。
        // 当前 v1，直接返回。
        b
    }

    /// 便捷：判断一段 JSON 是否是本 App 的合法备份。
    static func isBackup(_ data: Data) -> Bool {
        switch decode(data) {
        case .success: return true
        case .failure: return false
        }
    }
}
