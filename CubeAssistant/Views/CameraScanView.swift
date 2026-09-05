import SwiftUI
import UIKit
import CoreGraphics

/// 摄像头 / 相册扫描：逐面拍照，自动识别 3×3 贴纸颜色，支持点击改色校正，
/// 6 面齐了组装成 54 颜色 id 写入会话。
///
/// 识别原理：把照片缩放到 270×270，按 3×3 把每格中心区域平均色归类到最近的
/// 标准色（白/红/绿/黄/橙/蓝）。归正拍摄（该面正对镜头、占满画面）时识别率高；
/// 识别错了可在下方网格点一下换色校正。
///
/// ⚠️ 朝向约定：网格从左上到右下按行优先映射到该面的 facelet 0..8，需与
/// KociembaSolver 的 facelet 朝向一致（U 面“上边”朝上、F 面“上边”朝上拍）。
/// 若整体朝向拿不准，用「点一下改色」把明显错的块改对即可，校验器会拦下非法状态。
public struct CameraScanView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: CubeSession

    /// 6 个面各自识别出的 9 个颜色 id（row-major）
    @State private var faces: [Face: [Int]] = [:]
    @State private var currentFace: Face = .U
    @State private var showPicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .camera
    @State private var draft: [Int]? = nil   // 当前面识别草稿（可编辑）
    @State private var showSourceChoice = false
    @State private var note = "选择一面，拍照识别 9 个贴纸"

    private let faceOrder: [Face] = [.U, .R, .F, .D, .L, .B]
    private let faceLabel: [Face: String] = [.U: "上 U", .R: "右 R", .F: "前 F", .D: "下 D", .L: "左 L", .B: "后 B"]

    public init(session: CubeSession) { self.session = session }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 面选择
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                        ForEach(faceOrder, id: \.self) { face in
                            let done = faces[face] != nil
                            Button {
                                currentFace = face
                                draft = faces[face]
                            } label: {
                                Text(faceLabel[face]!)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                .background(currentFace == face ? Color.accentColor : Color(.secondarySystemFill))
                                .foregroundColor(currentFace == face ? .white : .primary)
                                .cornerRadius(10)
                                .overlay {
                                    if done { RoundedRectangle(cornerRadius: 10).stroke(Color.green, lineWidth: 2) }
                                }
                            }
                        }
                    }

                    Text(note).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)

                    // 拍照 / 相册
                    HStack(spacing: 12) {
                        Button { showSourceChoice = true } label: { Label("拍照识别", systemImage: "camera") }
                            .buttonStyle(.borderedProminent)
                        if let d = draft {
                            Button { faces[currentFace] = d; note = "已保存 \(faceLabel[currentFace]!) 面" } label: { Label("保存此面", systemImage: "checkmark") }
                                .buttonStyle(.bordered)
                        }
                    }

                    // 编辑网格
                    if let d = draft {
                        VStack(spacing: 8) {
                            Text("点色块可改色校正").font(.caption).foregroundColor(.secondary)
                            ForEach(0..<3, id: \.self) { r in
                                HStack(spacing: 8) {
                                    ForEach(0..<3, id: \.self) { c in
                                        let idx = r * 3 + c
                                        Button { draft?[idx] = (draft![idx] + 1) % 6 } label: {
                                            Rectangle().fill(stickerColor(d[idx]))
                                                .frame(width: 64, height: 64).cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2)))
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                    }

                    // 进度
                    let doneCount = faceOrder.filter { faces[$0] != nil }.count
                    ProgressView(value: Double(doneCount), total: 6)
                        .padding(.horizontal)
                    Text("已完成 \(doneCount) / 6 面").font(.caption).foregroundColor(.secondary)

                    if doneCount == 6 {
                        Button {
                            finish()
                        } label: { Label("完成识别", systemImage: "wand.and.stars") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("扫描魔方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .confirmationDialog("选择来源", isPresented: $showSourceChoice) {
                Button("相机") { pickerSource = .camera; showPicker = true }
                Button("相册") { pickerSource = .photoLibrary; showPicker = true }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showPicker) {
                ImagePicker(sourceType: pickerSource) { img in
                    if let img {
                        let ids = recognize(img)
                        draft = ids
                        note = "识别完成，检查并校正后点「保存此面」"
                    }
                }
            }
        }
    }

    private func finish() {
        var facelets: [Int] = []
        for f in faceOrder {
            guard let ids = faces[f] else { return }
            facelets.append(contentsOf: ids)
        }
        if session.setFacelets(facelets) {
            dismiss()
        } else {
            note = "状态非法，请检查各面颜色是否准确（每色应 9 个）"
        }
    }

    // MARK: - 颜色识别

    /// 标准色参考 RGB（典型魔方配色）
    private let refColors: [(r: Int, g: Int, b: Int)] = [
        (235, 235, 235), // 0 白
        (200, 40, 40),   // 1 红
        (40, 160, 70),   // 2 绿
        (245, 215, 30),  // 3 黄
        (245, 140, 20),  // 4 橙
        (30, 80, 190),   // 5 蓝
    ]

    private func stickerColor(_ id: Int) -> Color {
        let c = refColors[id]
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// 把照片按 3×3 识别为 9 个颜色 id（行优先：左上→右下）
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
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        let capacity = w * h * bytesPerPixel
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { data.deallocate() }
        guard let ctx = CGContext(data: data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Array(repeating: 0, count: 9)
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var out: [Int] = []
        for r in 0..<3 {
            for c in 0..<3 {
                let cx = c * 90 + 45
                let cy = r * 90 + 45
                var sr = 0, sg = 0, sb = 0, n = 0
                for dy in -15..<15 {
                    for dx in -15..<15 {
                        let x = cx + dx, y = cy + dy
                        guard x >= 0, y >= 0, x < w, y < h else { continue }
                        let p = (y * w + x) * 4
                        sr += Int(data[p])
                        sg += Int(data[p + 1])
                        sb += Int(data[p + 2])
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
        var best = 0, bestDist = Int.max
        for (i, c) in refColors.enumerated() {
            let dr = r - c.r, dg = g - c.g, db = b - c.b
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDist { bestDist = dist; best = i }
        }
        return best
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
