# 魔方助手 CubeAssistant

iOS 原生魔方求解 App。输入或扫描魔方六面状态，Kociemba 两阶段算法秒出最短解法，并用 3D 演示每一步转动。

## 技术栈
- SwiftUI + Swift 5
- Kociemba 两阶段求解器（已跟 Python 验证版对齐，端到端 30 例失败 0）
- SceneKit 3D 演示、AVFoundation 相机扫描识别
- CloudKit 成绩云同步（可选能力，未开启时静默失败、不影响求解主流程）

## 现阶段：不花钱真机测试（免费侧载）
1. 本仓库用 GitHub Actions 在云端 macOS（Xcode 26）构建**未签名 IPA**，每次 push `main` 自动产出。
2. 下载 IPA → 用 [AltStore](https://altstore.io) + 免费 Apple ID 签名安装到 iPhone。
3. Mac 端开着 AltServer，每 7 天自动重签，基本无感。

> 免费侧载下 CloudKit 成绩云同步不可用（需开启 iCloud 能力 + 开发者账号），求解 / 3D / 计时 / 扫描等主流程完全正常。

## 上架（验证可行后）
购买 Apple Developer 账号（¥688 / 年）→ 切换正式签名 workflow → 推送 App Store Connect 审核。

## 本地开发说明
本项目面向「旧 Mac 无法装 Xcode」场景：本地只做代码编辑，编译 / 签名 / 出包全部上云。
如需本地直接运行，需 macOS Sequoia 15.6+ 与 Xcode 26。
