import Foundation

/// 转动枚举。rawValue 与 movePerms 数组下标严格对应：
/// 0 U, 1 U2, 2 U', 3 R, 4 R2, 5 R',
/// 6 F, 7 F2, 8 F', 9 D, 10 D2, 11 D',
/// 12 L, 13 L2, 14 L', 15 B, 16 B2, 17 B',
/// 18 M, 19 M2, 20 M', 21 E, 22 E2, 23 E',
/// 24 S, 25 S2, 26 S'
///
/// M = 中层 (L↔R 之间)，E = 中层 (U↔D 之间)，S = 中层 (F↔B 之间)。
/// 注意：M 沿 +x 轴方向定义（从 L 面看为顺时针），E 沿 -y 轴（从 D 面看为顺时针），
/// S 沿 +z 轴（从 F 面看为顺时针）。这些定义与 Kociemba 标准一致。
public enum Move: Int, CaseIterable, Codable, Equatable, Hashable {
    case U = 0, U2, Up    // Up = U'
    case R = 3, R2, Rp
    case F = 6, F2, Fp
    case D = 9, D2, Dp
    case L = 12, L2, Lp
    case B = 15, B2, Bp
    case M = 18, M2, Mp
    case E = 21, E2, Ep
    case S = 24, S2, Sp

    /// 是否为内层转动（M/E/S）
    public var isSlice: Bool {
        switch self {
        case .M, .M2, .Mp, .E, .E2, .Ep, .S, .S2, .Sp: return true
        default: return false
        }
    }

    /// 对应的「轴」—— 用于选层 UI 映射
    /// 外层：U/D → y轴，R/L → x轴，F/B → z轴
    /// 内层：M → x轴中层（slice=0），E → y轴中层（slice=0），S → z轴中层（slice=0）
    public var axis: Int {
        switch self {
        case .U, .U2, .Up, .E, .E2, .Ep, .D, .D2, .Dp: return 1   // y
        case .R, .R2, .Rp, .M, .M2, .Mp, .L, .L2, .Lp: return 0   // x
        case .F, .F2, .Fp, .S, .S2, .Sp, .B, .B2, .Bp: return 2   // z
        default: return 1
        }
    }

    /// 该轴上的切片位置（外层 = ±1，内层 = 0）
    public var slice: Int {
        switch self {
        case .U, .U2, .Up, .E, .E2, .Ep: return 1
        case .D, .D2, .Dp: return -1
        case .R, .R2, .Rp: return 1
        case .L, .L2, .Lp: return -1
        case .F, .F2, .Fp, .S, .S2, .Sp: return 1
        case .B, .B2, .Bp: return -1
        case .M, .M2, .Mp: return 0
        default: return 0
        }
    }

    /// 对应的外层 face（用于 UI 显示）
    public var outerFace: Face {
        switch self {
        case .U, .U2, .Up, .E, .E2, .Ep, .D, .D2, .Dp: return .U
        case .R, .R2, .Rp, .M, .M2, .Mp, .L, .L2, .Lp: return .R
        case .F, .F2, .Fp, .S, .S2, .Sp, .B, .B2, .Bp: return .F
        default: return .U
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

    /// 标准记号，如 "R", "U2", "L'", "M'", "E2"
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
        let base: String
        switch self {
        case .U, .U2, .Up: base = "顶面"
        case .R, .R2, .Rp: base = "右面"
        case .F, .F2, .Fp: base = "前面"
        case .D, .D2, .Dp: base = "底面"
        case .L, .L2, .Lp: base = "左面"
        case .B, .B2, .Bp: base = "后面"
        case .M, .M2, .Mp: base = "中层(左右)"
        case .E, .E2, .Ep: base = "中层(上下)"
        case .S, .S2, .Sp: base = "中层(前后)"
        }
        switch turn {
        case 1: return "\(base)顺时针转"
        case 2: return "\(base)转 180°"
        default: return "\(base)逆时针转"
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

    /// 解析如 "R", "U2", "L'", "M'", "E2" 的字符串
    public static func parse(_ s: String) -> Move? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return nil }
        let rest = String(t.dropFirst())
        let turn: Int
        switch rest {
        case "":  turn = 1
        case "2": turn = 2
        case "'": turn = 3
        default: return nil
        }
        switch first {
        case "U": return moveOf(turn: turn, isSlice: false, axis: 1, sign:  1)
        case "D": return moveOf(turn: turn, isSlice: false, axis: 1, sign: -1)
        case "R": return moveOf(turn: turn, isSlice: false, axis: 0, sign:  1)
        case "L": return moveOf(turn: turn, isSlice: false, axis: 0, sign: -1)
        case "F": return moveOf(turn: turn, isSlice: false, axis: 2, sign:  1)
        case "B": return moveOf(turn: turn, isSlice: false, axis: 2, sign: -1)
        case "M": return moveOf(turn: turn, isSlice: true,  axis: 0, sign:  0)
        case "E": return moveOf(turn: turn, isSlice: true,  axis: 1, sign:  0)
        case "S": return moveOf(turn: turn, isSlice: true,  axis: 2, sign:  0)
        default: return nil
        }
    }

    private static func moveOf(turn: Int, isSlice: Bool, axis: Int, sign: Int) -> Move? {
        // turn: 1=CW, 2=180, 3=CCW
        switch (axis, sign, turn) {
        case (1,  1, 1): return .U;  case (1,  1, 2): return .U2; case (1,  1, 3): return .Up
        case (1, -1, 1): return .D;  case (1, -1, 2): return .D2; case (1, -1, 3): return .Dp
        case (0,  1, 1): return .R;  case (0,  1, 2): return .R2; case (0,  1, 3): return .Rp
        case (0, -1, 1): return .L;  case (0, -1, 2): return .L2; case (0, -1, 3): return .Lp
        case (2,  1, 1): return .F;  case (2,  1, 2): return .F2; case (2,  1, 3): return .Fp
        case (2, -1, 1): return .B;  case (2, -1, 2): return .B2; case (2, -1, 3): return .Bp
        case (0,  0, 1): return .M;  case (0,  0, 2): return .M2; case (0,  0, 3): return .Mp
        case (1,  0, 1): return .E;  case (1,  0, 2): return .E2; case (1,  0, 3): return .Ep
        case (2,  0, 1): return .S;  case (2,  0, 2): return .S2; case (2,  0, 3): return .Sp
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

/// 内层 slice 转动（高阶第二层，当前仅 4 阶支持）。
/// 独立于 `Move`（Move.rawValue 0..26 已占满且语义固定为最外层/3阶中层）。
/// face = 该内层所属的面（其第二层），turn 与 Move.turn 一致（1=CW/2=180/3=CCW）。
public struct SliceTurn: Equatable, Hashable, Codable {
    public let face: Face
    public let turn: Int   // 1/2/3

    public init(face: Face, turn: Int) {
        self.face = face
        self.turn = turn
    }

    /// 逆转动（undo 用）
    public func inverted() -> SliceTurn {
        switch turn {
        case 1: return SliceTurn(face: face, turn: 3)
        case 3: return SliceTurn(face: face, turn: 1)
        default: return self   // 180° 逆 = 自身
        }
    }

    /// 标准记号，如 "r", "u2", "f'"（小写表示内层）
    public var notation: String {
        let base = face.name.lowercased()
        switch turn {
        case 1: return base
        case 2: return base + "2"
        default: return base + "'"
        }
    }
}

/// undo 栈里的一步操作：要么是外层/3阶中层 Move，要么是 4 阶内层 SliceTurn。
/// 用枚举统一存储，让 CubeModel 的 undoStack 能混存两种转动并正确逆回退。
public enum TurnOp: Equatable, Hashable, Codable {
    case move(Move)
    case slice(SliceTurn)

    public func inverted() -> TurnOp {
        switch self {
        case .move(let m): return .move(m.inverted())
        case .slice(let s): return .slice(s.inverted())
        }
    }

    public var notation: String {
        switch self {
        case .move(let m): return m.notation
        case .slice(let s): return s.notation
        }
    }
}
