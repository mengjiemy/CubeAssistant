import Foundation

/// 打乱生成器：生成一段合法、无相邻抵消的随机转动序列
public struct ScrambleGenerator {
    /// 生成长度为 count 的打乱序列（默认 25 步，WCA 风格）
    /// 规则：相邻不走同一面；单/逆转为主，偶尔 180°
    public static func generate(length count: Int = 25) -> [Move] {
        var rng = SystemRandomNumberGenerator()
        var result: [Move] = []
        var lastFace: Face? = nil
        while result.count < count {
            let face = Face.allCases.randomElement(using: &rng)!
            if face == lastFace { continue }
            // 90% 单/逆，10% 180°
            let turn = (Int.random(in: 0..<10, using: &rng) == 0) ? 2 : (Bool.random(using: &rng) ? 1 : 3)
            guard let m = Move.parse(face.name + (turn == 2 ? "2" : (turn == 3 ? "'" : ""))) else { continue }
            result.append(m)
            lastFace = face
        }
        return result
    }

    /// 把转动序列转成可读记号，如 "R U2 F' D"
    public static func notation(of moves: [Move]) -> String {
        moves.map { $0.notation }.joined(separator: " ")
    }

    /// 把记号字符串解析回转动序列
    public static func parse(_ notation: String) -> [Move]? {
        let parts = notation.split(separator: " ").map { String($0) }
        var out: [Move] = []
        for p in parts {
            guard let m = Move.parse(p) else { return nil }
            out.append(m)
        }
        return out
    }
}
