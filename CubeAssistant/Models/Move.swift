import Foundation

/// 转动枚举。rawValue 与 movePerms 数组下标严格对应：
/// 0 U,1 U2,2 U',3 R,4 R2,5 R',6 F,7 F2,8 F',9 D,10 D2,11 D',12 L,13 L2,14 L',15 B,16 B2,17 B'
public enum Move: Int, CaseIterable, Codable, Equatable, Hashable {
    case U = 0, U2, Up    // Up = U'
    case R = 3, R2, Rp
    case F = 6, F2, Fp
    case D = 9, D2, Dp
    case L = 12, L2, Lp
    case B = 15, B2, Bp

    /// 对应的面
    public var face: Face {
        switch self {
        case .U, .U2, .Up: return .U
        case .R, .R2, .Rp: return .R
        case .F, .F2, .Fp: return .F
        case .D, .D2, .Dp: return .D
        case .L, .L2, .Lp: return .L
        case .B, .B2, .Bp: return .B
        }
    }

    /// 转动量：1 = 顺时针90°，2 = 180°，3 = 逆时针90°
    public var turn: Int {
        switch self {
        case .U, .R, .F, .D, .L, .B: return 1
        case .U2, .R2, .F2, .D2, .L2, .B2: return 2
        case .Up, .Rp, .Fp, .Dp, .Lp, .Bp: return 3
        }
    }

    /// 标准记号，如 "R", "U2", "L'"
    public var notation: String {
        let base: String
        switch face {
        case .U: base = "U"; case .R: base = "R"; case .F: base = "F"
        case .D: base = "D"; case .L: base = "L"; case .B: base = "B"
        }
        switch turn {
        case 1: return base
        case 2: return base + "2"
        default: return base + "'"
        }
    }

    /// 逆转动
    public func inverted() -> Move {
        switch self {
        case .U: return .Up; case .Up: return .U; case .U2: return .U2
        case .R: return .Rp; case .Rp: return .R; case .R2: return .R2
        case .F: return .Fp; case .Fp: return .F; case .F2: return .F2
        case .D: return .Dp; case .Dp: return .D; case .D2: return .D2
        case .L: return .Lp; case .Lp: return .L; case .L2: return .L2
        case .B: return .Bp; case .Bp: return .B; case .B2: return .B2
        }
    }

    /// 解析如 "R", "U2", "L'" 的字符串
    public static func parse(_ s: String) -> Move? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return nil }
        let face: Face
        switch first {
        case "U": face = .U; case "R": face = .R; case "F": face = .F
        case "D": face = .D; case "L": face = .L; case "B": face = .B
        default: return nil
        }
        let rest = String(t.dropFirst())
        switch rest {
        case "": return moveFor(face, 1)
        case "2": return moveFor(face, 2)
        case "'": return moveFor(face, 3)
        default: return nil
        }
    }

    private static func moveFor(_ f: Face, _ turn: Int) -> Move? {
        switch (f, turn) {
        case (.U, 1): return .U; case (.U, 2): return .U2; case (.U, 3): return .Up
        case (.R, 1): return .R; case (.R, 2): return .R2; case (.R, 3): return .Rp
        case (.F, 1): return .F; case (.F, 2): return .F2; case (.F, 3): return .Fp
        case (.D, 1): return .D; case (.D, 2): return .D2; case (.D, 3): return .Dp
        case (.L, 1): return .L; case (.L, 2): return .L2; case (.L, 3): return .Lp
        case (.B, 1): return .B; case (.B, 2): return .B2; case (.B, 3): return .Bp
        default: return nil
        }
    }
}

public enum Face: Int, CaseIterable {
    case U = 0, R, F, D, L, B
    public var colorIndex: Int { rawValue }
    public var name: String {
        ["U","R","F","D","L","B"][rawValue]
    }
}
