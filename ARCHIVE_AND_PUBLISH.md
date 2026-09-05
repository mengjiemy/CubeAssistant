# 打包、Archive 与发布步骤（魔方助手）

> 本机无 Xcode/iOS SDK，以下脚本与步骤需你在 Mac 上执行。代码已放到
> `CubeAssistant/CubeAssistant/` 对应目录，建好工程拖进去即可。

## 1. 新建工程
- Xcode → New Project → iOS → App。Product Name：`CubeAssistant`，
  Bundle Identifier：`com.<你的名>.CubeAssistant`，Interface：SwiftUI，
  Minimum Deployments：**iOS 16.0**（用到了 `@MainActor`/并发与 `NavigationStack`）。
- 把 `CubeAssistant/CubeAssistant/` 下的 `Engine/`、`Models/`、`Views/` 及 `CubeAssistantApp.swift`
  按目录拖进 Target（勾选 Add to target）。**确保只有 `CubeAssistantApp.swift` 一个 `@main`**。

## 2. 开启 CloudKit（成绩云同步）
- 选中 Target → Signing & Capabilities → 点 `+ Capability` → 搜 **iCloud** 添加。
- 勾选 **CloudKit**，Container 选默认的 `iCloud.<你的 Bundle ID>`（与代码里 `CKContainer.default()` 对应）。
- 未开启也不影响主流程：成绩仍可本地计时显示，云端保存会静默失败。

## 3. 相机权限（Info.plist）
扫描用到相机，需添加用途描述。在 `Info.plist` 增加：
```
NSCameraUsageDescription = "用于拍摄魔方六面，自动识别贴纸颜色（照片不会上传）"
```
（用相册时系统会另行请求「照片」权限。）

## 4. App 图标
在 `Assets.xcassets` 的 AppIcon 里放入：
- iPhone：60pt@2x (120×120)、60pt@3x (180×180)
- iPad（如支持）：76pt@1x/@2x、83.5pt@2x
- App Store：1024×1024（直角、无 alpha 通道）
- 没美术资源可用 Xcode 的 SF Symbols 临时生成，或我后续帮你做一版。

## 5. Archive（命令行模板）
```bash
# 进入工程目录（含 .xcodeproj / .xcworkspace）
cd /path/to/CubeAssistant

# 归档
xcodebuild archive \
  -scheme CubeAssistant \
  -archivePath ./build/CubeAssistant.xcarchive \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates

# 导出 IPA（需 exportOptions.plist）
xcodebuild -exportArchive \
  -archivePath ./build/CubeAssistant.xcarchive \
  -exportPath ./build/ipa \
  -exportOptionsPlist exportOptions.plist \
  -allowProvisioningUpdates
```
`exportOptions.plist` 示例（App Store 发布）：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>method</key>        <string>app-store</string>
    <key>teamID</key>        <string>你的团队ID(10位)</string>
    <key>signingStyle</key>  <string>automatic</string>
    <key>uploadBitcode</key> <false/>
</dict>
</plist>
```
- `app-store` 用于上传 TestFlight / App Store；内部测试可改 `enterprise` 或 `ad-hoc`。

## 6. 上传与提交
- 方式 A：`xcodebuild` 归档后在 Xcode → Organizer → Distribute App → App Store Connect。
- 方式 B：用 Transporter App 上传第 5 步导出的 IPA。
- 在 App Store Connect 填名称、截图、隐私政策网址（见 `PRIVACY_POLICY.md`）、年龄分级（4+，无数据收集争议）。

## 7. 截图
提交需不同尺寸截图（如 6.7"、6.5"、5.5"、iPad 12.9"）。用 Simulator 跑起来后
`File → Save Screen Shot` 或 `xcrun simctl io booted screenshot`。建议覆盖：主页/3D 演示、扫描识别、解法回放、历史成绩。

## 8. 真机必验项（本机无法验证）
- SceneKit 3D 旋转动画观感、六面旋转方向是否正确。
- 摄像头扫描：识别准确率、朝向约定（见 `CameraScanView.swift` 顶部注释），多试几台不同配色魔方。
- CloudKit 首次保存是否弹出 iCloud 授权、历史页能否拉取。
