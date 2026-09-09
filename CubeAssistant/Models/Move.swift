import Foundation

/// 转动枚举。rawValue 与 movePerms 数组下标严格对应：
/// 0 U,1 U2,2 U',3 R,4 R2,5 R',6 F,7 F2,8 F',9 D,10 D2,11 D',12 L,13 L2,14 L',15 B,16 B2,17 B'
/// 18 M,19 M2,20 M',21 E,22 E2,23 E',24 S,25 S2,26 S'
public enum Move: Int, CaseIterable, Codable, Equatable, Hashable {
    case U = 0, U2, Up    // Up = U'
    case R = 3, R2, Rp
    case F = 6, F2, Fp
    case D = 9, D2, Dp
    case L = 12, L2, Lp
    case B = 15, B2, Bp
    // 内层切片转动（3 阶支持，2 阶/高阶不应用）
    case M = 18, M2, Mp
    case E = 21, E2, Ep
    case S = 24, S2, Sp

    /// 对应的面（外层）。内层 M/E/S 映射到其「观察面」：M→R, E→D, S→F。
    public var face: Face {
        switch self {
        case .U, .U2, .Up: return .U
        case .R, .R2, .Rp: return .R
        case .F, .F2, .Fp: return .F
        case .D, .D2, .Dp: return .D
        case .L, .L2, .Lp: return .L
        case .B, .B2, .Bp: return .B
        case .M, .M2, .Mp: return .R
        case .E, .E2, .Ep: return .D
        case .S, .S2, .Sp: return .F
        }
    }

    /// 转动量：1 = 顺时针90°，2 = 180°，3 = 逆时针90°
    public var turn: Int {
        switch self {
        case .U, .R, .F, .D, .L, .B, .M, .E, .S: return 1
        case .U2, .R2, .F2, .D2, .L2, .B2, .M2, .E2, .S2: return 2
        case .Up, .Rp, .Fp, .Dp, .Lp, .Bp, .Mp, .Ep, .Sp: return 3
        }
    }

    /// 标准记号，如 "R", "U2", "L'", "M"
    public var notation: String {
        let base: String
        switch self {
        case .U, .U2, .Up: base = "U"
        case .R, .R2, .Rp: base = "R"
        case .F, .F2, .Fp: base = "F"
        case .D, .D2, .Dp: base = "D"
        case .L, .L2, .Lp: base = "L"
        case .B, .B2, .Bp: base = "B"
        case .M, .M2, .Mp: base = "M"
        case .E, .E2, .Ep: base = "E"
        case .S, .S2, .Sp: base = "S"
        }
        switch turn {
        case 1: return base
        case 2: return base + "2"
        default: return base + "'"
        }
    }

    /// 中文指令（面向新手，§4.1「中文」档）。如「右面顺时针转」「顶面转 180°」。
    public var chineseInstruction: String {
        let faceName: String
        switch self {
        case .U, .U2, .Up: faceName = "顶面"
        case .D, .D2, .Dp: faceName = "底面"
        case .L, .L2, .Lp: faceName = "左面"
        case .R, .R2, .Rp: faceName = "右面"
        case .F, .F2, .Fp: faceName = "前面"
        case .B, .B2, .Bp: faceName = "后面"
        case .M, .M2, .Mp: faceName = "中层(左右)"
        case .E, .E2, .Ep: faceName = "中层(上下)"
        case .S, .S2, .Sp: faceName = "中层(前后)"
        }
        switch turn {
        case 1: return "\(faceName)顺时针转"
        case 2: return "\(faceName)转 180°"
        default: return "\(faceName)逆时针转"
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
        case .M: return .Mp; case .Mp: return .M; case .M2: return .M2
        case .E: return .Ep; case .Ep: return .E; case .E2: return .E2
        case .S: return .Sp; case .Sp: return .S; case .S2: return .S2
        }
    }

    /// 解析如 "R", "U2", "L'", "M" 的字符串
    public static func parse(_ s: String) -> Move? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return nil }
        let rest = String(t.dropFirst())
        switch rest {
        case "":
            switch first {
            case "U": return .U; case "R": return .R; case "F": return .F
            case "D": return .D; case "L": return .L; case "B": return .B
            case "M": return .M; case "E": return .E; case "S": return .S
            default: return nil
            }
        case "2":
            switch first {
            case "U": return .U2; case "R": return .R2; case "F": return .F2
            case "D": return .D2; case "L": return .L2; case "B": return .B2
            case "M": return .M2; case "E": return .E2; case "S": return .S2
            default: return nil
            }
        case "'":
            switch first {
            case "U": return .Up; case "R": return .Rp; case "F": return .Fp
            case "D": return .Dp; case "L": return .Lp; case "B": return .Bp
            case "M": return .Mp; case "E": return .Ep; case "S": return .Sp
            default: return nil
            }
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
