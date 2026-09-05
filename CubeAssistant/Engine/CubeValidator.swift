import Foundation

/// 魔方状态合法性校验。
///
/// 一个 54 贴纸的魔方「可被还原」当且仅当满足：
/// 1. 每种颜色恰好出现 9 次；
/// 2. 8 个角的方向之和 ≡ 0 (mod 3)；
/// 3. 12 个棱的方向之和 ≡ 0 (mod 2)；
/// 4. 角排列奇偶性与棱排列奇偶性一致（同为偶或同为奇）。
///
/// 配合 `KociembaSolver.toCubie` 使用，可在求解前拦截非法输入（如识别错误、手填错误）。
public struct CubeValidator {

    public enum ValidationError: Error, Equatable {
        case wrongLength          // 不是 54 个贴纸
        case colorCountMismatch   // 某种颜色数量不是 9
        case cornerOrientation    // 角方向和不被 3 整除
        case edgeOrientation      // 棱方向和不是偶数
        case permutationParity    // 角排列与棱排列奇偶性不一致
    }

    /// 返回所有不合法项（空数组表示合法、可求解）。
    public static func validate(facelets: [Int]) -> [ValidationError] {
        var errors: [ValidationError] = []
        guard facelets.count == 54 else { return [.wrongLength] }

        // 1) 颜色计数
        var counts = [Int](repeating: 0, count: 6)
        for c in facelets where c >= 0 && c < 6 { counts[c] += 1 }
        if counts != [9, 9, 9, 9, 9, 9] { errors.append(.colorCountMismatch) }

        let cube = KociembaSolver.toCubie(facelets)

        // 2) 角方向
        if cube.co.reduce(0, +) % 3 != 0 { errors.append(.cornerOrientation) }
        // 3) 棱方向
        if cube.eo.reduce(0, +) % 2 != 0 { errors.append(.edgeOrientation) }
        // 4) 排列奇偶性
        if permParity(cube.cp) != permParity(cube.ep) { errors.append(.permutationParity) }

        return errors
    }

    public static func isValid(facelets: [Int]) -> Bool {
        validate(facelets: facelets).isEmpty
    }

    /// 排列的奇偶性：逆序数为偶 → 0，奇 → 1。
    private static func permParity(_ p: [Int]) -> Int {
        var inv = 0
        for i in 0..<p.count {
            for j in (i + 1)..<p.count where p[i] > p[j] { inv += 1 }
        }
        return inv % 2
    }
}
