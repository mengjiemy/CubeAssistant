# 内购（IAP）实施说明 · 魔方学院

> **状态**：骨架预留，尚未实现真实内购。
> **原因**：内购（StoreKit）必须配合苹果开发者账号、App Store Connect 配置、真机 + 沙盒测试账号，且 **unsigned ipa 无法通过内购验证**。当前阶段无法真机测内购，故只留设计骨架与接入步骤。

## 一、内购方案（已与杰哥拍板）

- **免费下载** + **2 阶免费体验** + **3~7 阶内购解锁**（说明：Kociemba 只能解 3 阶，2 阶已实现，4-7 阶需降阶法引擎——见「高阶引擎」）。
- 定价建议（可调整）：
  - 单阶解锁：¥10 / 阶
  - 全部阶数（3-7）：¥50（买断）
  - 首单促销：¥7（首次单阶）
- 类型：**非消耗型内购**（Non-Consumable），必须提供「恢复购买」入口。

## 二、技术接入步骤（未来启用时）

1. **Xcode → Target → Signing & Capabilities → + In-App Purchase**，启用 StoreKit。
2. **App Store Connect** 配置内购项目（Product ID），如：
   - `com.you.cube.unlock3`（3 阶）
   - `com.you.cube.unlock_all`（全阶买断）
3. 新建 `StoreManager.swift`（StoreKit 2，iOS 15+）：
   ```swift
   import StoreKit

   @MainActor
   final class StoreManager: ObservableObject {
       @Published var products: [Product] = []
       @Published var purchasedOrder: Set<Int> = []   // 已解锁阶数

       static let orderProductIDs: [Int: String] = [
           3: "com.you.cube.unlock3", 4: "com.you.cube.unlock4",
           5: "com.you.cube.unlock5", 6: "com.you.cube.unlock6",
           7: "com.you.cube.unlock7",
       ]

       func loadProducts() async {
           let ids = Self.orderProductIDs.values
           products = try? await Product.products(for: ids)
       }

       func purchase(_ product: Product) async -> Bool {
           guard let result = try? await product.purchase() else { return false }
           switch result {
           case .success(let verification):
               if case .verified(let t) = verification {
                   await updatePurchased(from: t)
                   return true
               }
           default: break
           }
           return false
       }

       func restore() async {
           for await result in Transaction.currentEntitlements {
               if case .verified(let t) = result {
                   await updatePurchased(from: t)
               }
           }
       }

       private func updatePurchased(from t: Transaction) async {
           guard t.revocationDate == nil else { return }
           if t.productID == "com.you.cube.unlock_all" {
               purchasedOrder = Set(3...7)
           } else if let (order, _) = Self.orderProductIDs.first(where: { $0.value == t.productID }) {
               purchasedOrder.insert(order)
           }
           await t.finish()
       }
   }
   ```
4. 阶数选择 UI 里：未购买阶数显示「锁 + 价格」，点击走 `purchase`；「设置」里加「恢复购买」按钮。
5. **本地持久化购买状态**（UserDefaults），同时用 `Transaction.currentEntitlements` 校验（防越狱/篡改）。

## 三、合规要点（过审关键）

- 非消耗型必须有「恢复购买」入口（App Store 审核强制）。
- 内购项目描述必须清晰（不能含糊「解锁更多」）。
- 价格需在 App Store Connect 设置，App 内显示用 `product.displayPrice`，不硬编码。
- 记得申请 **App Store Small Business Program**（年流水 <$1M → 抽成 30%→15%）。

## 四、当前代码预留

- `CubeModel.order` 字段已预留（默认 3，注释明确「UI/数据预留」）。
- `CubeGeometry` 已按阶数推导几何量，架构上支持 2~10 阶。
- 2 阶引擎 `Cube2x2` + `Solver2x2` 已实现（本轮 v14）。
- 4-7 阶引擎（降阶法）是内购的价值核心，**尚未实现**，是下一步最大工作量。
