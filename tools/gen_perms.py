#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
魔方 N 阶（2-10）movePerms 表生成器（Swift 数组字面量输出）。

几何约定（与 3 阶 CubeState.swift 一致）：
- 面顺序 U,R,F,D,L,B；面片索引 0..6*N²-1
- facelets[i] 存颜色 id（0..5）
- 置换语义：new[i] = old[perm[i]]（与 3 阶一致）

生成的置换表与 3 阶 movePerms 用同一套数学：6 个基础转动（U,R,F,D,L,B）+ 双转 + 逆转 = 18 转动。

实现策略：
- 不用 Kociemba cubie 模型（那是 3 阶特有的：固定中心 + 独立棱）
- 改用「面片网格」直接代数：每个面是 N×N 网格（row-major），U 转 = 顶层 U 块自身轮换
  + U 上面那一行 U/R/F/B/L 顶行面片置换
- D/R/F/L/B 转 类似推导

测试：每个基础转动应用 4 次应回原态 + 与现有 3 阶 CubeState.movePerms 完全一致
"""

import json
import sys
from typing import List, Tuple

# 面顺序: U=0, R=1, F=2, D=3, L=4, B=5
# 每个面 N×N 网格，row-major

def per_face(N: int) -> int:
    return N * N

def face_offset(face: int, N: int) -> int:
    return face * per_face(N)

def face_index(face: int, row: int, col: int, N: int) -> int:
    """face: 0..5; row/col: 0..N-1"""
    return face_offset(face, N) + row * N + col

# 3 阶权威 movePerms（来自 v15 CubeState.swift，已与 Kociemba 坐标系对齐）
MOVE_PERMS_3 = [
    [6, 3, 0, 7, 4, 1, 8, 5, 2, 45, 46, 47, 12, 13, 14, 15, 16, 17, 9, 10, 11, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 18, 19, 20, 39, 40, 41, 42, 43, 44, 36, 37, 38, 48, 49, 50, 51, 52, 53],
    [8, 7, 6, 5, 4, 3, 2, 1, 0, 36, 37, 38, 12, 13, 14, 15, 16, 17, 45, 46, 47, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 9, 10, 11, 39, 40, 41, 42, 43, 44, 18, 19, 20, 48, 49, 50, 51, 52, 53],
    [2, 5, 8, 1, 4, 7, 0, 3, 6, 18, 19, 20, 12, 13, 14, 15, 16, 17, 36, 37, 38, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 45, 46, 47, 39, 40, 41, 42, 43, 44, 9, 10, 11, 48, 49, 50, 51, 52, 53],
    [0, 1, 20, 3, 4, 23, 6, 7, 26, 15, 12, 9, 16, 13, 10, 17, 14, 11, 18, 19, 29, 21, 22, 32, 24, 25, 35, 27, 28, 51, 30, 31, 48, 33, 34, 45, 36, 37, 38, 39, 40, 41, 42, 43, 44, 8, 46, 47, 5, 49, 50, 2, 52, 53],
    [0, 1, 29, 3, 4, 32, 6, 7, 35, 17, 16, 15, 14, 13, 12, 11, 10, 9, 18, 19, 51, 21, 22, 48, 24, 25, 45, 27, 28, 2, 30, 31, 5, 33, 34, 8, 36, 37, 38, 39, 40, 41, 42, 43, 44, 26, 46, 47, 23, 49, 50, 20, 52, 53],
    [0, 1, 51, 3, 4, 48, 6, 7, 45, 11, 14, 17, 10, 13, 16, 9, 12, 15, 18, 19, 2, 21, 22, 5, 24, 25, 8, 27, 28, 20, 30, 31, 23, 33, 34, 26, 36, 37, 38, 39, 40, 41, 42, 43, 44, 35, 46, 47, 32, 49, 50, 29, 52, 53],
    [0, 1, 2, 3, 4, 5, 44, 41, 38, 6, 10, 11, 7, 13, 14, 8, 16, 17, 24, 21, 18, 25, 22, 19, 26, 23, 20, 15, 12, 9, 30, 31, 32, 33, 34, 35, 36, 37, 27, 39, 40, 28, 42, 43, 29, 45, 46, 47, 48, 49, 50, 51, 52, 53],
    [0, 1, 2, 3, 4, 5, 29, 28, 27, 44, 10, 11, 41, 13, 14, 38, 16, 17, 26, 25, 24, 23, 22, 21, 20, 19, 18, 8, 7, 6, 30, 31, 32, 33, 34, 35, 36, 37, 15, 39, 40, 12, 42, 43, 9, 45, 46, 47, 48, 49, 50, 51, 52, 53],
    [0, 1, 2, 3, 4, 5, 9, 12, 15, 29, 10, 11, 28, 13, 14, 27, 16, 17, 20, 23, 26, 19, 22, 25, 18, 21, 24, 38, 41, 44, 30, 31, 32, 33, 34, 35, 36, 37, 8, 39, 40, 7, 42, 43, 6, 45, 46, 47, 48, 49, 50, 51, 52, 53],
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 24, 25, 26, 18, 19, 20, 21, 22, 23, 42, 43, 44, 33, 30, 27, 34, 31, 28, 35, 32, 29, 36, 37, 38, 39, 40, 41, 51, 52, 53, 45, 46, 47, 48, 49, 50, 15, 16, 17],
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 42, 43, 44, 18, 19, 20, 21, 22, 23, 51, 52, 53, 35, 34, 33, 32, 31, 30, 29, 28, 27, 36, 37, 38, 39, 40, 41, 15, 16, 17, 45, 46, 47, 48, 49, 50, 24, 25, 26],
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 51, 52, 53, 18, 19, 20, 21, 22, 23, 15, 16, 17, 29, 32, 35, 28, 31, 34, 27, 30, 33, 36, 37, 38, 39, 40, 41, 24, 25, 26, 45, 46, 47, 48, 49, 50, 42, 43, 44],
    [53, 1, 2, 50, 4, 5, 47, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 0, 19, 20, 3, 22, 23, 6, 25, 26, 18, 28, 29, 21, 31, 32, 24, 34, 35, 42, 39, 36, 43, 40, 37, 44, 41, 38, 45, 46, 33, 48, 49, 30, 51, 52, 27],
    [27, 1, 2, 30, 4, 5, 33, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 53, 19, 20, 50, 22, 23, 47, 25, 26, 0, 28, 29, 3, 31, 32, 6, 34, 35, 44, 43, 42, 41, 40, 39, 38, 37, 36, 45, 46, 24, 48, 49, 21, 51, 52, 18],
    [18, 1, 2, 21, 4, 5, 24, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 27, 19, 20, 30, 22, 23, 33, 25, 26, 53, 28, 29, 50, 31, 32, 47, 34, 35, 38, 41, 44, 37, 40, 43, 36, 39, 42, 45, 46, 6, 48, 49, 3, 51, 52, 0],
    [11, 14, 17, 3, 4, 5, 6, 7, 8, 9, 10, 35, 12, 13, 34, 15, 16, 33, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 36, 39, 42, 2, 37, 38, 1, 40, 41, 0, 43, 44, 51, 48, 45, 52, 49, 46, 53, 50, 47],
    [35, 34, 33, 3, 4, 5, 6, 7, 8, 9, 10, 42, 12, 13, 39, 15, 16, 36, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 2, 1, 0, 17, 37, 38, 14, 40, 41, 11, 43, 44, 53, 52, 51, 50, 49, 48, 47, 46, 45],
    [42, 39, 36, 3, 4, 5, 6, 7, 8, 9, 10, 0, 12, 13, 1, 15, 16, 2, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 17, 14, 11, 33, 37, 38, 34, 40, 41, 35, 43, 44, 47, 50, 53, 46, 49, 52, 45, 48, 51],
]


def generate_N_order_perms(N: int) -> List[List[int]]:
    """
    生成 N 阶 6N² 长度的 18 个置换表（与 3 阶语义一致）。

    算法：基础转动（U, R, F, D, L, B）= 顶层 N 个面片自身轮换 + 邻面顶行/底行/左列/右列置换。
    双转 = 基础 × 2，逆转 = 基础 × 3。
    """
    total = 6 * N * N
    face_size = N * N

    def idx(face: int, row: int, col: int) -> int:
        return face * face_size + row * N + col

    def perm_identity() -> List[int]:
        return list(range(total))

    def compose(p_after_p_before: List[int], p: List[int]) -> List[int]:
        """p_after_p_before[p[i]] 的复合：先 apply p 再 apply p_after_p_before"""
        return [p_after_p_before[p[i]] for i in range(total)]

    def U_face_rotation() -> List[int]:
        """U 面 N×N 网格顺时针 90° 旋转（只看 U 面片位置）"""
        p = perm_identity()
        for r in range(N):
            for c in range(N):
                # (r, c) → (c, N-1-r) 顺时针
                src = idx(0, r, c)
                dst = idx(0, c, N - 1 - r)
                p[dst] = src
        return p

    def R_face_rotation() -> List[int]:
        """R 面 N×N 网格顺时针 90° 旋转"""
        p = perm_identity()
        for r in range(N):
            for c in range(N):
                src = idx(1, r, c)
                dst = idx(1, c, N - 1 - r)
                p[dst] = src
        return p

    def F_face_rotation() -> List[int]:
        p = perm_identity()
        for r in range(N):
            for c in range(N):
                src = idx(2, r, c)
                dst = idx(2, c, N - 1 - r)
                p[dst] = src
        return p

    def D_face_rotation() -> List[int]:
        """D 面 N×N 网格顺时针 90° 旋转（从 D 面对外看）"""
        p = perm_identity()
        for r in range(N):
            for c in range(N):
                src = idx(3, r, c)
                dst = idx(3, c, N - 1 - r)
                p[dst] = src
        return p

    def L_face_rotation() -> List[int]:
        p = perm_identity()
        for r in range(N):
            for c in range(N):
                src = idx(4, r, c)
                dst = idx(4, c, N - 1 - r)
                p[dst] = src
        return p

    def B_face_rotation() -> List[int]:
        p = perm_identity()
        for r in range(N):
            for c in range(N):
                src = idx(5, r, c)
                dst = idx(5, c, N - 1 - r)
                p[dst] = src
        return p

    # 邻面环置换：4 个面（顶行/底行/左列/右列）的某一行或一列循环
    def ring_perm_U() -> List[int]:
        """U 转 90°（顺时针，从上往下看）：值流 R→F→L→B→R（邻面顶行循环）
        验证 3 阶：new[R[0,0]] = old[B[0,0]] / new[F[0,0]] = old[R[0,0]] / new[L[0,0]] = old[F[0,0]] / new[B[0,0]] = old[L[0,0]]
        即 perm[R] = B, perm[F] = R, perm[L] = F, perm[B] = L
        """
        p = perm_identity()
        for c in range(N):
            p[idx(1, 0, c)] = idx(5, 0, c)  # R 顶行 ← B 顶行
            p[idx(2, 0, c)] = idx(1, 0, c)  # F 顶行 ← R 顶行
            p[idx(4, 0, c)] = idx(2, 0, c)  # L 顶行 ← F 顶行
            p[idx(5, 0, c)] = idx(4, 0, c)  # B 顶行 ← L 顶行
        return p

    def ring_perm_D() -> List[int]:
        """D 转 90°（顺时针从底面看 = 上面看逆时针）：值流 F→R→B→L→F（底行）
        验证 3 阶：new[F 底行] = old[L 底行] / new[R 底行] = old[F 底行] / new[B 底行] = old[R 底行] / new[L 底行] = old[B 底行]
        即 perm[F] = L, perm[R] = F, perm[B] = R, perm[L] = B
        """
        p = perm_identity()
        for c in range(N):
            p[idx(2, N - 1, c)] = idx(4, N - 1, c)  # F 底行 ← L 底行
            p[idx(1, N - 1, c)] = idx(2, N - 1, c)  # R 底行 ← F 底行
            p[idx(5, N - 1, c)] = idx(1, N - 1, c)  # B 底行 ← R 底行
            p[idx(4, N - 1, c)] = idx(5, N - 1, c)  # L 底行 ← B 底行
        return p

    def ring_perm_R() -> List[int]:
        """R 转 90°：F 右列 → U 右列 → B 左列（反向）→ D 右列 → F 右列
        验证 3 阶 R 转：F[0,2]=20, U[0,2]=2, B[0,0]=45, D[0,2]=27
                 new[F[0,2]] = D[0,2] 即 perm[20] = 27 ✓ (3 阶 MOVE_PERMS_3[3][20]=29? 让我看 3 阶)
                 3 阶 MOVE_PERMS_3[3] = [0, 1, 20, 3, 4, 23, 6, 7, 26, 15, 12, 9, 16, 13, 10, 17, 14, 11,
                                          18, 19, 29, 21, 22, 32, 24, 25, 35, 27, 28, 51, 30, 31, 48, 33, 34, 45, 36, 37, 38, 39, 40, 41, 42, 43, 44, 8, 46, 47, 5, 49, 50, 2, 52, 53]
                 perm[20] = 29 = D[2,0]
                 perm[29] = 51 = B[2,0]
                 perm[51] = 2  = U[0,2]
                 perm[2] = 20  = F[0,2]
                 所以 R 转：F[0,2] ← D[2,0]? 不对称。B 是反面，左列和右列映射有方向。
                 实际：B 面网格在 3 阶坐标系中，B[0,0] 在 U[0,2] 对面，B[2,0] 在 D[0,0] 对面。
                 因此 R 转 90° = U右列(从上到下) → B左列(从下到上) → D右列(从下到上) → F右列(从上到下) → U右列
                 也就是：new[U[c, N-1]] = F[c, N-1] / new[F[c, N-1]] = D[c, N-1] / new[D[c, N-1]] = B[N-1-c, 0] / new[B[N-1-c, 0]] = U[c, N-1]
                 验证 3 阶：perm[U[0,2]=2] = 20 = F[0,2] ✓
                           perm[F[0,2]=20] = 29 = D[2,0]
                           perm[D[2,0]=29] = 51 = B[2,0] = B[N-1-0, 0] ✓
                           perm[B[2,0]=51] = 2 = U[0,2] ✓
        """
        p = perm_identity()
        for r in range(N):
            p[idx(0, r, N - 1)] = idx(2, r, N - 1)            # U 右列 ← F 右列
            p[idx(2, r, N - 1)] = idx(3, r, N - 1)            # F 右列 ← D 右列
            p[idx(3, r, N - 1)] = idx(5, N - 1 - r, 0)        # D 右列 ← B 左列（反向）
            p[idx(5, N - 1 - r, 0)] = idx(0, r, N - 1)        # B 左列 ← U 右列
        return p

    def ring_perm_L() -> List[int]:
        """L 转 90°：F 左列 → D 左列 → B 右列（反向）→ U 左列 → F 左列
        验证 3 阶 L 转：new[F 左列] = U 左列
        """
        p = perm_identity()
        for r in range(N):
            p[idx(0, r, 0)] = idx(5, N - 1 - r, N - 1)        # U 左列 ← B 右列（反向）
            p[idx(5, N - 1 - r, N - 1)] = idx(3, r, 0)        # B 右列 ← D 左列（反向）
            p[idx(3, r, 0)] = idx(2, r, 0)                    # D 左列 ← F 左列
            p[idx(2, r, 0)] = idx(0, r, 0)                    # F 左列 ← U 左列
        return p

    def ring_perm_F() -> List[int]:
        """F 转 90°：U 底行 → R 左列 → D 顶行（反向）→ L 右列（反向）→ U 底行
        验证 3 阶 F 转：new[U 底行] = L 右列
        """
        p = perm_identity()
        for c in range(N):
            p[idx(0, N - 1, c)] = idx(4, N - 1 - c, N - 1)     # U 底行 ← L 右列（反向）
            p[idx(4, N - 1 - c, N - 1)] = idx(3, 0, N - 1 - c) # L 右列 ← D 顶行（反向）
            p[idx(3, 0, N - 1 - c)] = idx(1, c, 0)            # D 顶行 ← R 左列
            p[idx(1, c, 0)] = idx(0, N - 1, c)                # R 左列 ← U 底行
        return p

    def ring_perm_B() -> List[int]:
        """B 转 90°（顺时针从后看 = 从前看逆时针）：邻面环 = U 顶行 / R 右列 / D 底行 / L 左列
        值流（从前看逆时针）：U 顶行 → R 右列 → D 底行 → L 左列 → U 顶行
        验证 3 阶（ref MOVE_PERMS_3[15]）：
          U 顶行 ← R 右列反向：U[0,0]←R[0,2], U[0,1]←R[1,2], U[0,2]←R[2,2]
          R 右列 ← D 底行反向：R[0,2]←D[2,2], R[1,2]←D[2,1], R[2,2]←D[2,0]
          D 底行 ← L 左列同向：D[2,0]←L[0,0], D[2,1]←L[1,0], D[2,2]←L[2,0]
          L 左列 ← U 顶行反向：L[0,0]←U[0,2], L[1,0]←U[0,1], L[2,0]←U[0,0]
        """
        p = perm_identity()
        for i in range(N):
            p[idx(0, 0, i)] = idx(1, i, N - 1)              # U 顶行 ← R 右列反向（按 col 顺序）
            p[idx(1, i, N - 1)] = idx(3, N - 1, N - 1 - i)  # R 右列 ← D 底行反向
            p[idx(3, N - 1, i)] = idx(4, i, 0)              # D 底行 ← L 左列同向
            p[idx(4, i, 0)] = idx(0, 0, N - 1 - i)          # L 左列 ← U 顶行反向
        return p

    # 组合：6 个基础转动 = 邻面环置换 + 该面自身旋转
    U1 = compose(ring_perm_U(), U_face_rotation())
    R1 = compose(ring_perm_R(), R_face_rotation())
    F1 = compose(ring_perm_F(), F_face_rotation())
    D1 = compose(ring_perm_D(), D_face_rotation())
    L1 = compose(ring_perm_L(), L_face_rotation())
    B1 = compose(ring_perm_B(), B_face_rotation())

    # 双转 / 逆转
    def twice(p: List[int]) -> List[int]:
        return compose(p, p)

    def thrice(p: List[int]) -> List[int]:
        return compose(compose(p, p), p)

    moves = [U1, twice(U1), thrice(U1),
             R1, twice(R1), thrice(R1),
             F1, twice(F1), thrice(F1),
             D1, twice(D1), thrice(D1),
             L1, twice(L1), thrice(L1),
             B1, twice(B1), thrice(B1)]
    return moves


def test_perm(perm: List[int], total: int, name: str) -> bool:
    """每个基础转动应用 4 次应回原态；置换必须是双射（permutation）"""
    if sorted(perm) != list(range(total)):
        print(f"  ❌ {name}: 不是置换（双射）")
        return False
    # 4 次回原
    p = list(range(total))
    for _ in range(4):
        p = [perm[i] for i in p]
    if p != list(range(total)):
        print(f"  ❌ {name}: 4 次未回原")
        return False
    return True


def test_3_compat(N: int, generated: List[List[int]]) -> bool:
    """N=3 时，生成的 movePerms 必须与 v15 CubeState.swift 中的权威表完全一致。"""
    if N != 3: return True
    for i, gen in enumerate(generated):
        if gen != MOVE_PERMS_3[i]:
            print(f"  ❌ 3 阶兼容失败: movePerms[{i}] 不一致")
            # 找出第一个差异
            for j in range(len(gen)):
                if gen[j] != MOVE_PERMS_3[i][j]:
                    print(f"    差异在 index {j}: gen={gen[j]} ref={MOVE_PERMS_3[i][j]}")
                    break
            return False
    print("  ✅ 3 阶 movePerms 与 v15 CubeState.swift 权威表完全一致")
    return True


def main():
    print("=" * 60)
    print("N 阶魔方 movePerms 生成（按 3 阶语义）")
    print("=" * 60)

    for N in [2, 3, 4, 5, 6, 7, 8, 9, 10]:
        print(f"\n=== N = {N} ===")
        perms = generate_N_order_perms(N)
        total = 6 * N * N
        print(f"  totalFacelets = {total}, 18 个置换表")
        names = ["U", "U2", "U'", "R", "R2", "R'", "F", "F2", "F'",
                 "D", "D2", "D'", "L", "L2", "L'", "B", "B2", "B'"]
        all_ok = True
        for i, (name, p) in enumerate(zip(names, perms)):
            if not test_perm(p, total, f"{N} 阶 {name}"):
                all_ok = False
        if not all_ok:
            print(f"  ❌ N={N} 校验失败")
            sys.exit(1)
        if not test_3_compat(N, perms):
            sys.exit(1)
        print(f"  ✅ N={N} 所有 18 个置换：双射 + 4 次回原")
        # 输出 Swift 源码（MovePerms{N}.swift，引擎可直接 import）
        names_swift = ["U", "U2", "Up", "R", "R2", "Rp", "F", "F2", "Fp",
                       "D", "D2", "Dp", "L", "L2", "Lp", "B", "B2", "Bp"]
        swift_path = f"/Users/mengjie/WorkBuddy/Claw/CubeAssistant/CubeAssistant/Engine/_gen/MovePerms{N}.swift"
        with open(swift_path, "w") as f:
            f.write(f"// Auto-generated by tools/gen_perms.py — DO NOT EDIT BY HAND\n")
            f.write(f"// {N} 阶魔方 18 个面片置换（{total} 面片），与 v15 CubeState.movePerms 语义一致\n")
            f.write(f"// 几何约定：U=0,R=1,F=2,D=3,L=4,B=5；new[i] = old[perm[i]]\n\n")
            f.write(f"import Foundation\n\n")
            f.write(f"public enum MovePerms{N} {{\n")
            f.write(f"    public static let count = {total}\n")
            for name, p in zip(names_swift, perms):
                p_str = "[" + ", ".join(str(x) for x in p) + "]"
                f.write(f"    public static let {name}: [Int] = {p_str}\n")
            f.write("}\n")
        print(f"  → 写入 {swift_path}（Swift 常量，可直接编译）")

    print("\n" + "=" * 60)
    print("✅ 全部 N=2..10 通过（双射+4次回原+3阶兼容权威表）")
    print("=" * 60)


if __name__ == "__main__":
    main()
