import Foundation

// ============================================================
// 魔方学院 · 用户资料 / 本地偏好持久化（纯 Foundation，可本地测试）
//
// 承载「我的」Tab 需要但跟魔方状态无关的用户数据：
// - 昵称 / 签名（本地资料卡，不进魔方状态）
// - 转动提示档位（新手 / 中文 / 专业，功能说明书 §6.7）
//
// 说明：
// - 用 struct + 值语义，方法返回新实例（或本类内部直接改 UserDefaults）。
// - 独立于 CubeModel（那个管魔方/计时），这里只管"人"和"偏好"。
// - 还原历史仍由 CubeSession.history 管理（与魔方结算耦合），不在这里重复。
// ============================================================

/// 转动提示档位（新手图卡 / 中文 / 专业）。与功能说明书 §4.1 对应。
enum GuideTier: String, Codable, CaseIterable {
    case beginner = "新手"      // 新手图卡：大白话 + 高亮
    case chinese = "中文"       // 中文指令 + 字母
    case pro = "专业"           // 纯公式 R U R' U'

    var subtitle: String {
        switch self {
        case .beginner: return "大白话 + 目标高亮，最适合入门"
        case .chinese:  return "中文指令 + 公式字母，边学边认"
        case .pro:      return "纯公式，适合会玩的人"
        }
    }
}

/// 用户资料 / 偏好。本地持久化到 UserDefaults。
struct ProfileStore {
    /// 昵称（默认"魔方练习生"）
    var nickname: String
    /// 签名
    var signature: String
    /// 转动提示档位
    var guideTier: GuideTier

    init(nickname: String = "魔方练习生",
         signature: String = "每天还原一次，进步看得见",
         guideTier: GuideTier = .chinese) {
        self.nickname = nickname
        self.signature = signature
        self.guideTier = guideTier
    }

    // MARK: - 持久化（UserDefaults）

    private static let key = "cube_profile_store_v1"

    func save() {
        if let data = try? JSONEncoder().encode(ProfileRecord(nickname, signature, guideTier)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func load() -> ProfileStore {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rec = try? JSONDecoder().decode(ProfileRecord.self, from: data) else {
            return ProfileStore()
        }
        return ProfileStore(nickname: rec.nickname,
                            signature: rec.signature,
                            guideTier: GuideTier(rawValue: rec.guideTier) ?? .chinese)
    }

    /// 用于 JSON 编解码的扁平结构
    private struct ProfileRecord: Codable {
        let nickname: String
        let signature: String
        let guideTier: String
        init(_ n: String, _ s: String, _ t: GuideTier) {
            self.nickname = n; self.signature = s; self.guideTier = t.rawValue
        }
    }
}
