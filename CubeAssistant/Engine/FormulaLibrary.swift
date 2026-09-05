import Foundation

public enum FormulaCategory: String, CaseIterable, Codable {
    case oll, pll, f2l
    public var title: String {
        switch self {
        case .oll: return "OLL（顶层朝向，57 个）"
        case .pll: return "PLL（顶层排列，21 个）"
        case .f2l: return "F2L（前两层，41 组）"
        }
    }
}

/// 一条公式：名称 + 算法记号 + 识别特征
public struct Formula: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var category: FormulaCategory
    public var notation: String        // 标准 CFOP 算法记号
    public var recognition: String     // 识别特征 / 口诀
}

/// CFOP 公式库。算法记号以社区标准为准，可在 Mac 上校对本文件补全 OLL/F2L 全部条目。
public struct FormulaLibrary {
    // MARK: - PLL（21 个，完整）
    public static let pll: [Formula] = [
        Formula(id:"PLL-Aa", name:"Aa Perm", category:.pll, notation:"x L2 D2 L' U' L D2 L' U L'", recognition:"三点+两点错位"),
        Formula(id:"PLL-Ab", name:"Ab Perm", category:.pll, notation:"x L2 D2 L U L' D2 L U' L'", recognition:"Aa 镜像"),
        Formula(id:"PLL-E", name:"E Perm", category:.pll, notation:"x' R U' R' D R U R' D' R U R' D R U' R' D' R", recognition:"四边错位"),
        Formula(id:"PLL-F", name:"F Perm", category:.pll, notation:"R' U R' U' R2 U' R' U R U R' U' R2 U R'", recognition:"两点+三点"),
        Formula(id:"PLL-Ga", name:"Ga Perm", category:.pll, notation:"R2 u R' U R' U' R u' R2 y' R' U R", recognition:"单点+两点"),
        Formula(id:"PLL-Gb", name:"Gb Perm", category:.pll, notation:"R' U' R y R2 u R' U R U' R' u' R2", recognition:"单点+两点"),
        Formula(id:"PLL-Gc", name:"Gc Perm", category:.pll, notation:"R2 u' R U' R U R' u R2 y R U' R'", recognition:"单点+两点"),
        Formula(id:"PLL-Gd", name:"Gd Perm", category:.pll, notation:"R U R' y' R2 u' R U' R' U R' u R2", recognition:"单点+两点"),
        Formula(id:"PLL-H", name:"H Perm", category:.pll, notation:"M2 U M2 U2 M2 U M2", recognition:"两侧对面互换"),
        Formula(id:"PLL-Ja", name:"Ja Perm", category:.pll, notation:"R U R' F' R U R' U' R' F R2 U' R' U'", recognition:"两点相邻"),
        Formula(id:"PLL-Jb", name:"Jb Perm", category:.pll, notation:"R' U L' U2 R U' R' U2 R L", recognition:"两点相邻(镜像)"),
        Formula(id:"PLL-L", name:"L Perm", category:.pll, notation:"x R2 D2 R U R' D2 R U' R", recognition:"两点相对"),
        Formula(id:"PLL-Na", name:"Na Perm", category:.pll, notation:"R U R' U R U R' F' R U R' U' R' F R2 U' R' U2 R U' R'", recognition:"四点错位"),
        Formula(id:"PLL-Nb", name:"Nb Perm", category:.pll, notation:"R' U R U' R' F' U' F R U R' F R' F' R U' R", recognition:"四点错位(镜像)"),
        Formula(id:"PLL-Pa", name:"Pa Perm", category:.pll, notation:"R' U R' D' R U' R' D R U' R' D' R U R' D R2 U' R2", recognition:"两点+两点"),
        Formula(id:"PLL-Pb", name:"Pb Perm", category:.pll, notation:"R U' R' U R' D' R U R' D R U' R' D' R U R' D R2 U R2", recognition:"两点+两点(镜像)"),
        Formula(id:"PLL-Ra", name:"Ra Perm", category:.pll, notation:"R U R' U R' F R2 U' R' U' R U R' F'", recognition:"三点+两点"),
        Formula(id:"PLL-Rb", name:"Rb Perm", category:.pll, notation:"R' F R U R' U' R' F' R2 U' R' U R U R' U' R", recognition:"三点+两点(镜像)"),
        Formula(id:"PLL-T", name:"T Perm", category:.pll, notation:"R U R' U' R' F R2 U' R' U' R U R' F'", recognition:"两点对角"),
        Formula(id:"PLL-Ua", name:"Ua Perm", category:.pll, notation:"R2 U R U R' U' R' U' R' U R'", recognition:"三点顺时针"),
        Formula(id:"PLL-Ub", name:"Ub Perm", category:.pll, notation:"R' U' R U R U R' U' R' U' R2", recognition:"三点逆时针"),
        Formula(id:"PLL-V", name:"V Perm", category:.pll, notation:"R' U R' U' R' F' R F R U R' U' R' F R F'", recognition:"四点错位"),
        Formula(id:"PLL-Y", name:"Y Perm", category:.pll, notation:"F R U' R' U' R U R' F' R U R' U' R' F R F'", recognition:"四点错位"),
        Formula(id:"PLL-Z", name:"Z Perm", category:.pll, notation:"M2 U M2 U M' U2 M2 U2 M' U2", recognition:"两侧相邻互换"),
    ]

    // MARK: - OLL（代表条目，可补全至 57）
    public static let oll: [Formula] = [
        Formula(id:"OLL-1", name:"Sune", category:.oll, notation:"R U R' U R U2 R'", recognition:"三点鱼形(右上角)"),
        Formula(id:"OLL-2", name:"Anti-Sune", category:.oll, notation:"R' U' R U' R' U2 R", recognition:"三点鱼形(镜像)"),
        Formula(id:"OLL-27", name:"T", category:.oll, notation:"R U R' U' R' F R F'", recognition:"三点呈 T 形"),
        Formula(id:"OLL-33", name:"L", category:.oll, notation:"R U R' U' R' F R2 U R' U' F'", recognition:"三点呈 L 形"),
        Formula(id:"OLL-45", name:"Bowtie", category:.oll, notation:"R U R2 U' R' F R U R U' F'", recognition:"两点对称"),
        Formula(id:"OLL-21", name:"H", category:.oll, notation:"r U R' U R U' r' R2 F R F'", recognition:"两层横条"),
        Formula(id:"OLL-26", name:"C", category:.oll, notation:"R U2 R' U' R U' R'", recognition:"一点+两点"),
    ]

    // MARK: - F2L（按情景分组，代表条目，可补全至 41）
    public static let f2l: [Formula] = [
        Formula(id:"F2L-1", name:"标准对（角块入槽）", category:.f2l, notation:"R U R'", recognition:"角块与棱块已配对，直接入槽"),
        Formula(id:"F2L-2", name:"拆分重做", category:.f2l, notation:"R U' R' U R U2 R'", recognition:"角块在内、棱块在外，先拆再组"),
        Formula(id:"F2L-3", name:"翻棱", category:.f2l, notation:"U R U' R' U' R U R'", recognition:"棱块翻面后入槽"),
        Formula(id:"F2L-4", name:"慢入", category:.f2l, notation:"y' R' U R", recognition:"角块在左，翻到右侧处理"),
    ]

    public static func all() -> [Formula] { pll + oll + f2l }
    public static func `for`(_ c: FormulaCategory) -> [Formula] {
        switch c {
        case .pll: return pll
        case .oll: return oll
        case .f2l: return f2l
        }
    }
}
