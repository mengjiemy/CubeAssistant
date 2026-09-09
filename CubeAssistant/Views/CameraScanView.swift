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

    private let faceOrder: [Face] = [.U, .R, .F, .D, .L, .B]

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
                // 完成识别：把 faces 拼成 54 色，调 session.setFacelets。
                // 返回 true = 录入成功（sheet 自动关闭）；false = 失败（sheet 内显示原因）。
                var all: [Int] = []
                for f in faceOrder {
                    guard let arr = faces[f] else { return false }
                    all.append(contentsOf: arr)
                }
                if session.setFacelets(all) { return true }
                return false
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
    /// 极简引导：进度 + 一句话提示，不再按 U/R/F/D/L/B 分面拍。
    private var guideCard: some View {
        let doneCount = faceOrder.filter { faces[$0] != nil }.count
        let stepTag = "第 \(doneCount + (faces[currentFace] == nil ? 1 : 0)) / 6 面"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stepTag)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.accent)
                Spacer()
            }
            Text("拍魔方的一面")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            Text("任意一面都行，App 自动识别 9 个贴纸颜色；拍 6 张即可")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
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
                .aspectRatio(1, contentMode: .fit)   // 缩略图保持正方形
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(current ? AppTheme.accent : (done ? Color.green : Color.clear), lineWidth: 2)
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 拍摄/相册两个大卡片
    private var scanOptions: some View {
        VStack(spacing: 10) {
            scanOptionCard(icon: "camera.fill", iconGradient: [AppTheme.accent, AppTheme.accentLight],
                           title: "拍照",
                           desc: "打开相机拍魔方一面",
                           action: { showSourceChoice = true })
            scanOptionCard(icon: "photo.on.rectangle", iconGradient: [Color.purple, Color.pink],
                           title: "从相册选择",
                           desc: "从已有照片选一面",
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
    /// 完成识别回调：返回 true = 录入成功（外部会自动关闭 sheet），false = 失败（外部会在 errorMessage 显示原因）
    let onFinish: () -> Bool

    @State private var currentFace: Face = .U
    @State private var draft: [Int]? = nil   // 当前面草稿（编辑态）
    @State private var editingCell: Int? = nil   // 正在编辑的格子 idx
    @State private var errorMessage: String? = nil   // 校验/识别失败时的提示
    @State private var note: String = "扫描完成，先点要改的方块，再点下方颜色"

    private let faceOrder: [Face] = [.U, .R, .F, .D, .L, .B]
    private let faceLabel: [Face: String] = [.U: "上", .R: "右", .F: "前", .D: "下", .L: "左", .B: "后"]

    init(session: CubeSession, faces: Binding<[Face: [Int]]>, currentFace: Face, onFinish: @escaping () -> Bool) {
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
                                    let isEditing = (editingCell == idx)
                                    Button {
                                        editingCell = idx
                                    } label: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(stickerColor(d[idx]))
                                            .frame(height: 64)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isEditing ? AppTheme.accent : Color.white.opacity(0.2),
                                                            lineWidth: isEditing ? 3 : 1)
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

                Text(editingCell == nil
                     ? "先点要改的方块，再点下方颜色"
                     : "已选 1 格，点下方颜色应用")
                    .font(.caption2)
                    .foregroundColor(editingCell == nil ? .secondary : AppTheme.accent)

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
                            } else {
                                note = "先点 3×3 网格里要改的格子"
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // 失败提示（仅在 errorMessage 有值时显示）
                if let err = errorMessage {
                    Text(err)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }

                // 底部"完成识别"主按钮
                Button {
                    saveDraft()
                    if onFinish() {
                        dismiss()
                    } else {
                        // 检查 6 面是否都拍过，给出对应错误
                        let missing = faceOrder.filter { faces[$0] == nil }
                        if !missing.isEmpty {
                            errorMessage = "还有 \(missing.count) 个面没拍，回到上一步补拍"
                        } else {
                            errorMessage = "颜色校验未通过：每个面应有 9 个同色贴纸，且 6 色各 9 个"
                        }
                    }
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
        }
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
