#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
魔方学院 (Cube Academy) — App Store 上架图标生成器
等轴测 3×3 魔方 · 深空渐变背景 · iOS 系统色 · 1024×1024 RGB(无 Alpha)

用法: python3 gen_icon.py
改配色/比例直接改下方 CONFIG 区重跑即可。
依赖: Pillow (纯 PIL 实现, 无需 numpy)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

# ---------------- CONFIG ----------------
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'AppIcon_1024.png')

SIZE = 1024            # 最终输出尺寸
SS = 4                 # 超采样倍数(4x 抗锯齿)
W = SIZE * SS

CUBE_W_FRAC = 0.575    # 魔方剪影宽度 / 画面宽度
TILT_DEG = 4.0         # 顺时针微倾(动势)
CY_FRAC = 0.485        # 魔方中心垂直位置(居中偏上)

BG_TOP = (16, 24, 40)      # #101828 深空蓝黑
BG_BOT = (5, 7, 14)        # #05070E
GLOW_C = (10, 132, 255)    # #0A84FF 品牌蓝(光晕)
GLOW_ALPHA = 100           # 光晕峰值不透明度(/255)
GLOW_R = 1.45              # 光晕半径(×棱长)
GLOW_UP = 0.18             # 光晕中心相对魔方中心上移(×棱长)

GAP_C = (11, 13, 24)       # 贴纸缝隙/外圈包边(深色塑料)
WHITE = (245, 245, 247)    # #F5F5F7 顶面
BLUE = (10, 132, 255)      # #0A84FF 左面(品牌色, 视觉权重最大)
RED = (255, 69, 58)        # #FF453A 右面

SH_TOP = (1.00, 0.958)     # 顶面明暗: 亮端 -> 暗端(沿x, 左亮右微暗)
SH_LEFT = (0.96, 0.84)     # 左面(蓝): 上亮下暗
SH_RIGHT = (0.90, 0.76)    # 右面(红): 稍暗

MARGIN = 0.026             # 面外圈包边宽(×棱长)
GAPX = 0.024               # 贴纸间隙(×棱长)
RAD_FRAC = 0.16            # 贴纸圆角(×贴纸边长)

VIGNETTE = 80              # 四角暗角强度(/255)
NOISE_SIGMA = 5.0          # 背景微噪点幅度(防色带, SS 尺度)
SHADOW_ALPHA = 185         # 底部投影强度
# -----------------------------------------

c30 = math.cos(math.radians(30.0))
s30 = 0.5
S = CUBE_W_FRAC * W / (2 * c30)     # 立方体棱长(SS px)
cx, cy = W / 2.0, W * CY_FRAC
TILT = math.radians(TILT_DEG)


def proj(x, y, z):
    """立方体坐标 -> 屏幕 SS 坐标(等轴测 + 整体微倾)。"""
    sx = cx + (x - y) * c30
    sy = cy + (x + y) * s30 - z
    dx, dy = sx - cx, sy - cy
    return (cx + dx * math.cos(TILT) - dy * math.sin(TILT),
            cy + dx * math.sin(TILT) + dy * math.cos(TILT))


# 面: (原点3D, U棱3D, V棱3D, 贴纸色, 明暗, 渐变轴, 是否顶面反光)
FACES = [
    ((0, S, S), (S, 0, 0), (0, 0, -S), BLUE,  SH_LEFT,  'y', False),
    ((S, 0, S), (0, S, 0), (0, 0, -S), RED,   SH_RIGHT, 'y', False),
    ((0, 0, S), (S, 0, 0), (0, S, 0),  WHITE, SH_TOP,   'x', True),
]


def radial_mask(size_px, fn, small=256):
    """径向渐变 L 遮罩: fn(r) r∈[0,1](0=中心, 1=角落) -> 0..255。"""
    s = small
    m = Image.new('L', (s, s))
    px = m.load()
    c = (s - 1) / 2.0
    diag = c * math.sqrt(2.0)
    for j in range(s):
        for i in range(s):
            r = math.hypot(i - c, j - c) / diag
            v = fn(r)
            px[i, j] = 0 if v <= 0 else (255 if v >= 255 else int(round(v)))
    return m.resize((size_px, size_px), Image.BICUBIC)


def make_background():
    """垂直渐变 + 微噪点 + 蓝色径向光晕 + 暗角。"""
    bg = Image.new('RGB', (W, W))
    d = ImageDraw.Draw(bg)
    for y in range(W):
        t = y / (W - 1)
        col = tuple(int(round(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t))
                    for i in range(3))
        d.line([(0, y), (W, y)], fill=col)
    # 噪点防色带(零均值高斯噪声)
    noise = Image.effect_noise((W, W), NOISE_SIGMA).convert('RGB')
    bg = ImageChops.add(bg, noise, 1.0, -128)

    # 蓝色径向光晕(主体后方透出)
    gsz = int(round(2 * GLOW_R * S))
    gcy = cy - GLOW_UP * S
    gmask = radial_mask(gsz, lambda r: GLOW_ALPHA * max(0.0, 1.0 - r * 1.4142) ** 2)
    solid = Image.new('RGB', (gsz, gsz), GLOW_C)
    bg.paste(solid, (int(round(cx - gsz / 2)), int(round(gcy - gsz / 2))), gmask)

    # 暗角(四角轻微压暗)
    vmask = radial_mask(W, lambda r: VIGNETTE * max(0.0, (r - 0.45) / 0.55) ** 2)
    bg.paste((0, 0, 0), (0, 0, W, W), vmask)
    return bg


def add_shadow(img):
    """克制的底部椭圆投影。"""
    ov = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    ey = cy + S * 1.06
    ew, eh = 1.18 * S, 0.20 * S
    d.ellipse([cx - ew / 2, ey - eh / 2, cx + ew / 2, ey + eh / 2],
              fill=(0, 0, 0, SHADOW_ALPHA))
    ov = ov.filter(ImageFilter.GaussianBlur(S * 0.055))
    img.paste(ov, (0, 0), ov)


def face_texture(color, shade, axis, specular=False):
    """生成一个面的贴纸纹理(RGB): 深色包边 + 3x3 圆角贴纸 + 明暗渐变, 顶面可加反光。"""
    T = int(round(S))
    P = int(round(S * 0.02))          # 纹理外扩 padding(防采样越界)
    dim = T + 2 * P
    m = S * MARGIN
    g = S * GAPX
    st = (T - 2 * m - 2 * g) / 3.0    # 贴纸边长
    rad = st * RAD_FRAC

    stick = Image.new('RGB', (dim, dim), (0, 0, 0))
    smask = Image.new('L', (dim, dim), 0)
    ds, dm = ImageDraw.Draw(stick), ImageDraw.Draw(smask)
    for i in range(3):
        for j in range(3):
            x0 = P + m + i * (st + g)
            y0 = P + m + j * (st + g)
            box = [x0, y0, x0 + st, y0 + st]
            ds.rounded_rectangle(box, radius=rad, fill=color)
            dm.rounded_rectangle(box, radius=rad, fill=255)

    # 1D 明暗: 面级平滑渐变 × 贴纸级微锯齿(每张贴纸上缘微亮, 模拟倒角受光)
    lo, hi = shade
    fp = [hi + (lo - hi) * k / (dim - 1) for k in range(dim)]
    sp = [1.0] * dim
    for j in range(3):
        a0 = P + m + j * (st + g)
        i0, i1 = int(round(a0)), int(round(a0 + st))
        n = max(2, i1 - i0)
        for k in range(n):
            sp[i0 + k] = 1.032 + (0.972 - 1.032) * k / (n - 1)
    prof = [max(0.0, min(1.2, fp[k] * sp[k])) for k in range(dim)]
    p8 = [int(round(v * 255)) for v in prof]
    if axis == 'y':
        gimg = Image.new('L', (1, dim))
    else:
        gimg = Image.new('L', (dim, 1))
    gimg.putdata(p8)
    gimg = gimg.resize((dim, dim), Image.BILINEAR)
    stick = ImageChops.multiply(stick, gimg.convert('RGB'))

    tex = Image.new('RGB', (dim, dim), GAP_C)
    tex.paste(stick, (0, 0), smask)
    return tex


def paste_face(canvas, tex, o3, e1, e2):
    """把面纹理经仿射变换贴到画布对应平行四边形区域。"""
    add = lambda a, b: (a[0] + b[0], a[1] + b[1], a[2] + b[2])
    P0 = proj(*o3)
    P1 = proj(*add(o3, e1))
    P3 = proj(*add(o3, e2))
    P2 = proj(*add(add(o3, e1), e2))
    A = (P1[0] - P0[0], P1[1] - P0[1])     # U 方向整条棱向量
    B = (P3[0] - P0[0], P3[1] - P0[1])     # V 方向整条棱向量
    det = A[0] * B[1] - A[1] * B[0]
    Sx = float(S)
    a_ =  Sx * B[1] / det
    b_ = -Sx * B[0] / det
    d_ = -Sx * A[1] / det
    e_ =  Sx * A[0] / det
    P_tex = (tex.width - int(round(S))) // 2
    c_ = P_tex + Sx * (B[0] * P0[1] - B[1] * P0[0]) / det
    f_ = P_tex + Sx * (A[1] * P0[0] - A[0] * P0[1]) / det

    xs = [P0[0], P1[0], P2[0], P3[0]]
    ys = [P0[1], P1[1], P2[1], P3[1]]
    x0, y0 = int(math.floor(min(xs))), int(math.floor(min(ys)))
    x1, y1 = int(math.ceil(max(xs))), int(math.ceil(max(ys)))
    size = (x1 - x0 + 1, y1 - y0 + 1)

    # PIL transform 的 (X, Y) 是输出像素坐标; paste 到 (x0, y0) 后
    # 该像素落到画布 (x0+X, y0+Y). 要让画布 (x0+X, y0+Y) 采到
    # 我们用画布坐标算出的 input, 常数项需平移 a·x0 + b·y0.
    coeffs = (a_, b_, c_ + a_ * x0 + b_ * y0,
              d_, e_, f_ + d_ * x0 + e_ * y0)
    face = tex.transform(size, Image.AFFINE, coeffs, resample=Image.BILINEAR)
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).polygon(
        [(p[0] - x0, p[1] - y0) for p in (P0, P1, P2, P3)], fill=255)
    canvas.paste(face, (x0, y0), mask)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    canvas = make_background()
    add_shadow(canvas)
    for (o3, e1, e2, color, shade, axis, spec) in FACES:
        tex = face_texture(color, shade, axis, spec)
        paste_face(canvas, tex, o3, e1, e2)
    img = canvas.resize((SIZE, SIZE), Image.LANCZOS).convert('RGB')
    img.save(OUT, 'PNG')

    im = Image.open(OUT)
    print('saved :', OUT)
    print('size  :', im.size)
    print('mode  :', im.mode, '(RGB 无 Alpha)' if im.mode == 'RGB' else '!! 有问题 !!')


if __name__ == '__main__':
    main()
