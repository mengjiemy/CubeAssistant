import Foundation

// ============================================================
// CubeGeometry · 魔方几何常量（按阶数推导，集中管理魔数）
//
// 目的：当前 App 固定 3 阶，但代码里散落着 54 / 9 / 26 / -1...1 等
// 3 阶魔数。把它们收敛成「由 order 推导」的集中定义：
// - 现在：order 恒为 3，行为零变化（3 阶照跑）；
// - 未来：支持 2~10 阶时，引擎只需把 order 变成可变 + 生成对应
//   转动表，UI / 状态层引用本类型即可，不必逐处改魔数。
//
// 依赖：Foundation only（纯逻辑，本地 swiftc 可测）。
// ============================================================

/// N 阶魔方的几何参数（N = 每边块数，2 阶起）。
struct CubeGeometry: Equatable {
    /// 阶数（每边块数）。App 现固定 3；架构上 2~10 可扩。
    let order: Int

    init(order: Int) {
        precondition(order >= 2, "魔方阶数至少为 2")
        self.order = order
    }

    /// 默认几何（3 阶 = 标准魔方）。现版本唯一实例。
    static let three = CubeGeometry(order: 3)

    // MARK: - 面片（facelet）相关

    /// 每个面的格数 = N²（3 阶 → 9）
    var perFace: Int { order * order }

    /// 总面片数 = 6N²（3 阶 → 54）
    var totalFacelets: Int { 6 * order * order }

    /// 面数（始终 6）
    var faceCount: Int { 6 }

    /// 第 f 面在 facelets 数组中的起始下标 = f × perFace
    func faceOffset(_ f: Int) -> Int { f * perFace }

    /// 面片索引属于哪个面（0..5）
    func faceOf(_ index: Int) -> Int { index / perFace }

    /// 该面片在所属面内的序号（0..N²-1，row-major）
    func positionInFace(_ index: Int) -> Int { index % perFace }

    // MARK: - 3D 块（cubelet）相关

    /// 每维块坐标范围：奇数阶为 -(N-1)/2 ... (N-1)/2（3 阶 → -1...1）。
    /// 注意：偶数阶无中心层，坐标应为半整数（2 阶 → -0.5/0.5），
    /// 未来支持偶数阶时需在此扩展（当前版本只做 3 阶，返回整数范围）。
    var coordHalf: Int { (order - 1) / 2 }

    /// 可见块总数 = N³ - 1（去掉中心；3 阶 → 26）
    var visibleCubelets: Int { order * order * order - 1 }

    /// 判断 (x,y,z) 是否属于本阶的可见块（非中心）
    func isVisibleCubelet(x: Int, y: Int, z: Int) -> Bool {
        let h = coordHalf
        func inRange(_ v: Int) -> Bool { (-h...h).contains(v) }
        guard inRange(x), inRange(y), inRange(z) else { return false }
        // 中心块仅当 N 为奇数且位于正中心才被挖掉
        if order % 2 == 1 {
            if x == 0 && y == 0 && z == 0 { return false }
        }
        return true
    }
}
