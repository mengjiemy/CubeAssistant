import SwiftUI
import UIKit
import CoreGraphics

/// 摄像头 / 相册扫描（按原型 v4 重构）
///
/// 两屏结构（与原型一致）：
/// 1) **扫描魔方** 主屏：顶部引导卡（"第N面/共6面" + 面名 + 拍照提示 + 中心块mini-cube预览）+
///    进度条 + 6 面缩略预览（已完成/当前/+号）+ 两个大卡片选项（"拍摄XX面"/"从相册选择"）。
/// 2) **确认魔方** 编辑屏：6 面 Tab + 当前面 3×3 大色块网格 + 点色块改色 + 底部"完成识别"主按钮。
///
/// 识别原理同 v15：缩放到 270×270，按 3×3 每格中心区域平均色做 HSV 距离归类到 6 标准色。
/// 朝向约定：网格 row-major（左上→右下）映射到该面 facelet 0..8，与 Kociemba 坐标系一致。
struct CameraScanView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: CubeSession

    /// 6 个面各自识别出的 9 个颜色 id（row-major）
    @State private var faces: [Face: [Int]] = [:]
    /// 当前正在编辑/拍摄的面
    @State private var currentFace: Face = .U
    /// 当前面的草稿（拍照后未保存的可编辑状态）
    @State private var draft: [Int]? = nil
    /// 是否进入"确认魔方"编辑屏（拍照后）
    @State private var showConfirm: Bool = false
    /// 弹出来源选择（相机/相册）
    @State private var showSourceChoice: Bool = false
    /// 弹出色盘（编辑屏用）
    @State private var showColorSheet: Bool = false
    @State private var editingCell: Int? = nil
    /// 提示文案
    @State private var note: String = "选择一面，按提示拍/选照片，自动识别 9 个贴纸颜色"

    private let faceOrder: [Face] = [.U, .R, .F, .D, .L, .B]
    private let faceLabel: [Face: String] = [.U: "上 U", .R: "右 R", .F: "前 F", .D: "下 D", .L: "左 L", .B: "后 B"]
    private let faceHint: [Face: String] = [
        .U: "白色面朝上，让整个顶面进取景框",
        .R: "把右面正对镜头，与顶面交界朝上",
        .F: "绿色面朝你，白色面朝上",
        .D: "黄色面朝下（把魔方翻过来），拍摄底面",
        .L: "把左面正对镜头，与顶面交界朝上",
        .B: "蓝色面朝你（前面在对面），与顶面交界朝上"
    ]

    init(session: CubeSession) { self.session = session }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 顶部引导卡
                    guideCard

                    // 进度条
                    progressBar

                    // 6 面缩略预览
                    faceGrid

                    // 拍摄/相册两个大卡片
                    scanOptions
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("扫描魔方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .confirmationDialog("选择来源", isPresented: $showSourceChoice) {
                Button("相机") { showPicker(source: .camera) }
                Button("相册") { showPicker(source: .photoLibrary) }
                Button("取消", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPickerBinding) {
            ImagePicker(sourceType: pickerSource) { img in
                if let img {
                    let ids = recognize(img)
                    draft = ids
                    // 拍完直接保存为当前面的草稿（用户后续在 confirm 里可继续改）
                    faces[currentFace] = ids
                    draft = ids
                    showConfirm = true   // 拍照完进入"确认魔方"编辑屏
                }
            }
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmCubeView(session: session, faces: $faces, currentFace: currentFace) {
                // 完成识别：把 faces 拼成 54 色，调 session.setFacelets + 关闭
                var all: [Int] = []
                for f in faceOrder {
                    guard let arr = faces[f] else { return }
                    all.append(contentsOf: arr)
                }
                if session.setFacelets(all) {
                    showConfirm = false
                    dismiss()
                } else {
                    note = "状态非法，请检查各面颜色是否准确（每色应 9 个）"
                }
            }
        }
    }

    /// 弹出 ImagePicker（用 .fullScreenCover 但要支持 dismiss）
    @State private var showPickerBinding: Bool = false
    @State private var pickerSource: UIImagePickerController.SourceType = .camera
    private func showPicker(source: UIImagePickerController.SourceType) {
        pickerSource = source
        showPickerBinding = true
    }

    // MARK: - 顶部引导卡
    private var guideCard: some View {
        let doneCount = faceOrder.filter { faces[$0] != nil }.count
        let stepTag = "第 \(doneCount + (faces[currentFace] == nil ? 1 : 0)) 面 / 共 6 面"
        let next = faceOrder.first { faces[$0] == nil } ?? currentFace
        return VStack(alignment: .leading, spacing: 10) {
            // 步骤标
            HStack {
                Text(stepTag)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.accent)
                Spacer()
            }
            // 面名
            Text(faceLabel[next] ?? "")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            // 引导语
            Text(faceHint[next] ?? "")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            // 中心块 mini-cube（3×3 占位，中间"＋"标注中心块）
            miniCubePreview(face: next)
                .frame(maxWidth: .infinity)
            // 中心提示
            Text("中间「＋」是中心块，颜色以它为准")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
    }

    /// 3×3 mini-cube 占位（中间显示「＋」表示中心块）
    private func miniCubePreview(face: Face) -> some View {
        let stickerColor: (Int) -> Color = { id in
            let refs: [Color] = [
                Color(red: 0.92, green: 0.92, blue: 0.92),  // 白
                Color(red: 0.78, green: 0.16, blue: 0.16),  // 红
                Color(red: 0.16, green: 0.55, blue: 0.27),  // 绿
                Color(red: 0.96, green: 0.84, blue: 0.12),  // 黄
                Color(red: 0.96, green: 0.55, blue: 0.10),  // 橙
                Color(red: 0.12, green: 0.31, blue: 0.72)   // 蓝
            ]
            return refs[id]
        }
        // 已识别的面用真色块，否则用该面的标准色占位（中心块特殊处理）
        let faceSticker: Int? = (faces[face] != nil) ? faces[face]?[4] : FaceColorRef[face]
        let centerColor = stickerColor(faceSticker ?? 0)
        return VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { c in
                        let isCenter = (r == 1 && c == 1)
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(centerColor.opacity(isCenter ? 1.0 : 0.18))
                            if isCenter {
                                Image(systemName: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                        .frame(height: 30)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - 进度条
    private var progressBar: some View {
        let doneCount = faceOrder.filter { faces[$0] != nil }.count
        let frac = Double(doneCount) / 6.0
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [AppTheme.accent, AppTheme.accentLight],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 6)
            Text("已完成 \(doneCount) / 6 面")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 6 面缩略预览
    private var faceGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(faceOrder, id: \.self) { face in
                faceSlot(face)
            }
        }
    }

    @ViewBuilder
    private func faceSlot(_ face: Face) -> some View {
        let done = faces[face] != nil
        let current = (face == currentFace && !done)
        Button {
            currentFace = face
            if done { showConfirm = true }   // 已拍过的面再点 = 直接进确认
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                    if done, let arr = faces[face] {
                        // 9 格缩略
                        VStack(spacing: 1) {
                            ForEach(0..<3, id: \.self) { r in
                                HStack(spacing: 1) {
                                    ForEach(0..<3, id: \.self) { c in
                                        Rectangle()
                                            .fill(stickerColor(arr[r * 3 + c]))
                                            .frame(height: 14)
                                    }
                                }
                            }
                        }
                        .padding(2)
                    } else if current {
                        // 当前面：空 9 格 + 蓝框
                        VStack(spacing: 1) {
                            ForEach(0..<3, id: \.self) { r in
                                HStack(spacing: 1) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Rectangle()
                                            .fill(Color.white.opacity(0.10))
                                            .frame(height: 14)
                                    }
                                }
                            }
                        }
                        .padding(2)
                    } else {
                        // 未拍：+
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(current ? AppTheme.accent : (done ? Color.green : Color.clear), lineWidth: 2)
                )
                Text(faceLabel[face] ?? "")
                    .font(.caption2)
                    .foregroundColor(current ? AppTheme.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 拍摄/相册两个大卡片
    private var scanOptions: some View {
        VStack(spacing: 10) {
            scanOptionCard(icon: "camera.fill", iconGradient: [AppTheme.accent, AppTheme.accentLight],
                           title: "拍摄「\(faceLabel[currentFace] ?? "")」",
                           desc: "打开相机实时框选当前面",
                           action: { showSourceChoice = true })
            scanOptionCard(icon: "photo.on.rectangle", iconGradient: [Color.purple, Color.pink],
                           title: "从相册选择",
                           desc: "从已有照片选当前面",
                           action: { showSourceChoice = true })
        }
    }

    private func scanOptionCard(icon: String, iconGradient: [Color], title: String, desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    LinearGradient(colors: iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                    Text(desc).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 颜色识别（保留 v15 核心算法，仅内部调用）

    private let refColors: [(r: Int, g: Int, b: Int)] = [
        (235, 235, 235), (200, 40, 40), (40, 160, 70),
        (245, 215, 30), (245, 140, 20), (30, 80, 190)
    ]
    private func stickerColor(_ id: Int) -> Color {
        let c = refColors[max(0, min(id, refColors.count - 1))]
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
    private func recognize(_ image: UIImage) -> [Int] {
        let size = 270
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let flat = renderer.image { _ in
            let scale = min(Double(size) / image.size.width, Double(size) / image.size.height)
            let dw = image.size.width * CGFloat(scale)
            let dh = image.size.height * CGFloat(scale)
            let rect = CGRect(x: (CGFloat(size) - dw) / 2, y: (CGFloat(size) - dh) / 2, width: dw, height: dh)
            image.draw(in: rect)
        }
        guard let cg = flat.cgImage else { return Array(repeating: 0, count: 9) }
        let w = cg.width, h = cg.height
        let bpp = 4
        let bpr = bpp * w
        let cap = w * h * bpp
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { data.deallocate() }
        guard let ctx = CGContext(data: data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Array(repeating: 0, count: 9)
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out: [Int] = []
        for r in 0..<3 {
            for c in 0..<3 {
                let cx = c * 90 + 45, cy = r * 90 + 45
                var sr = 0, sg = 0, sb = 0, n = 0
                for dy in -15..<15 {
                    for dx in -15..<15 {
                        let x = cx + dx, y = cy + dy
                        guard x >= 0, y >= 0, x < w, y < h else { continue }
                        let p = (y * w + x) * 4
                        sr += Int(data[p]); sg += Int(data[p + 1]); sb += Int(data[p + 2])
                        n += 1
                    }
                }
                let ar = n > 0 ? sr / n : 0
                let ag = n > 0 ? sg / n : 0
                let ab = n > 0 ? sb / n : 0
                out.append(classify(ar, ag, ab))
            }
        }
        return out
    }
    private func classify(_ r: Int, _ g: Int, _ b: Int) -> Int {
        let hsv = Self.rgbToHSV(r: r, g: g, b: b)
        var best = 0, bestDist = Double.greatestFiniteMagnitude
        for (i, c) in refColors.enumerated() {
            let refHSV = Self.rgbToHSV(r: c.r, g: c.g, b: c.b)
            let dh = Self.hueDistance(hsv.h, refHSV.h)
            let ds = hsv.s - refHSV.s
            let dv = hsv.v - refHSV.v
            let dist = dh * dh * 2.5 + ds * ds * 1.5 + dv * dv * 4.0
            if dist < bestDist { bestDist = dist; best = i }
        }
        return best
    }
    private static func rgbToHSV(r: Int, g: Int, b: Int) -> (h: Double, s: Double, v: Double) {
        let rf = Double(r) / 255.0, gf = Double(g) / 255.0, bf = Double(b) / 255.0
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf), delta = mx - mn
        var h = 0.0
        if delta > 0 {
            if mx == rf { h = 60.0 * ((gf - bf) / delta).truncatingRemainder(dividingBy: 6.0) }
            else if mx == gf { h = 60.0 * ((bf - rf) / delta + 2.0) }
            else { h = 60.0 * ((rf - gf) / delta + 4.0) }
        }
        if h < 0 { h += 360.0 }
        let s = mx == 0 ? 0.0 : delta / mx
        return (h, s, mx)
    }
    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b); return d > 180 ? 360 - d : d
    }
}

/// 6 面标准色参考（U=0白 / R=1红 / F=2绿 / D=3黄 / L=4橙 / B=5蓝）
let FaceColorRef: [Face: Int] = [.U: 0, .R: 1, .F: 2, .D: 3, .L: 4, .B: 5]

// MARK: - 确认魔方编辑屏
/// 拍照后进入"确认魔方"：6 面 Tab + 当前面 3×3 大色块网格 + 点色块改色 + 底部"完成识别"主按钮。
struct ConfirmCubeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: CubeSession
    @Binding var faces: [Face: [Int]]
    let initialFace: Face
    let onFinish: () -> Void

    @State private var currentFace: Face = .U
    @State private var draft: [Int]? = nil   // 当前面草稿（编辑态）
    @State private var showColorSheet: Bool = false
    @State private var editingCell: Int? = nil
    @State private var note: String = "扫描完成，点方块可改色，改到和手里一样"

    private let faceOrder: [Face] = [.U, .R, .F, .D, .L, .B]
    private let faceLabel: [Face: String] = [.U: "上", .R: "右", .F: "前", .D: "下", .L: "左", .B: "后"]

    init(session: CubeSession, faces: Binding<[Face: [Int]]>, currentFace: Face, onFinish: @escaping () -> Void) {
        self.session = session
        self._faces = faces
        self.initialFace = currentFace
        self.onFinish = onFinish
    }

    private let refColors: [(r: Int, g: Int, b: Int)] = [
        (235, 235, 235), (200, 40, 40), (40, 160, 70),
        (245, 215, 30), (245, 140, 20), (30, 80, 190)
    ]
    private func stickerColor(_ id: Int) -> Color {
        let c = refColors[max(0, min(id, refColors.count - 1))]
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // 6 面切换 Tab
                HStack(spacing: 6) {
                    ForEach(faceOrder, id: \.self) { face in
                        Button {
                            saveDraft()
                            currentFace = face
                            draft = faces[face]
                        } label: {
                            VStack(spacing: 2) {
                                Text(faceLabel[face] ?? "")
                                    .font(.caption.weight(.semibold))
                                Rectangle().fill(faces[face] != nil ? Color.green : Color.clear).frame(height: 2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                currentFace == face
                                ? AppTheme.accent.opacity(0.25)
                                : Color.white.opacity(0.05)
                            )
                            .foregroundColor(currentFace == face ? .white : .white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                // 当前面 3×3 大色块
                if let d = draft {
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { r in
                            HStack(spacing: 6) {
                                ForEach(0..<3, id: \.self) { c in
                                    let idx = r * 3 + c
                                    Button {
                                        editingCell = idx
                                        showColorSheet = true
                                    } label: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(stickerColor(d[idx]))
                                            .frame(height: 64)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .padding(.horizontal, 20)
                }

                Text("点方块 → 选颜色")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // 6 色调色盘（始终显示，方便快速改色）
                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { id in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(stickerColor(id))
                                .frame(width: 36, height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2)))
                            Text(["白","红","绿","黄","橙","蓝"][id])
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .onTapGesture {
                            if let idx = editingCell {
                                draft?[idx] = id
                                editingCell = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // 底部"完成识别"主按钮
                Button {
                    saveDraft()
                    onFinish()
                } label: {
                    Label("完成识别", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(AppTheme.accent))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.08), Color(red: 0.01, green: 0.01, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea())
            .navigationTitle("确认魔方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                currentFace = initialFace
                draft = faces[currentFace]
            }
            .sheet(isPresented: $showColorSheet) {
                colorPickerSheet
                    .presentationDetents([.height(220)])
            }
        }
        .preferredColorScheme(.dark)
    }

    private var colorPickerSheet: some View {
        VStack(spacing: 16) {
            Text("选择颜色").font(.headline).foregroundColor(.white)
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { id in
                    Button {
                        if let idx = editingCell { draft?[idx] = id }
                        showColorSheet = false
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6).fill(stickerColor(id))
                                .frame(width: 44, height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2)))
                            Text(["白","红","绿","黄","橙","蓝"][id]).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.top, 20)
        .background(Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func saveDraft() {
        if let d = draft {
            faces[currentFace] = d
            draft = d
        }
    }
}

// MARK: - UIImagePickerController 包装
private struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = (UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage?) -> Void
        init(onPicked: @escaping (UIImage?) -> Void) { self.onPicked = onPicked }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) { self.onPicked(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { self.onPicked(nil) }
        }
    }
}
