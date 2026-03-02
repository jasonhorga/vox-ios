# 03 — Preliminary Requirements（开发前必须准备的东西）

> 日期：2026-03-02
> 在写任何代码之前，以下所有条件必须满足或确认

---

## 1. Apple Developer 账号

### 必需

| 项目 | 说明 | 状态 |
|------|------|------|
| Apple Developer Program 会员 | 年费 $99/¥688，用于真机调试、TestFlight、App Store | 待确认 |
| Apple ID 与 Team ID | 用于 Xcode 签名和 Provisioning Profile | 待确认 |
| 账号类型 | 个人账号或组织账号均可；个人账号足够 | 待确认 |

### 账号类型选型

| 类型 | 年费 | 适用场景 | App Store 分发 | 备注 |
|------|------|---------|---------------|------|
| **个人** | $99 | 独立开发者、个人项目 | ✅ | 发布者名称显示个人姓名 |
| **组织** | $99 | 公司/团队项目 | ✅ | 需要 D-U-N-S 编号，发布者名称显示组织名 |
| **企业** | $299 | 内部分发（不上 App Store） | ❌ 仅限内部 | **不适用于 Vox**——企业证书不能上 App Store |

**推荐**：个人账号。Vox 是个人开源项目，个人账号完全满足需求（TestFlight + App Store 分发）。组织账号需要法律实体和 D-U-N-S 编号，对个人项目来说门槛不必要。如果未来需要以品牌名义发布，可以从个人账号迁移到组织账号（Apple 支持账号类型转换）。

### 注意事项
- 免费的 Apple ID 可以在真机上调试（7 天有效期），但**不能使用 App Group**，也不能上传 TestFlight
- App Group 是键盘扩展的核心依赖，因此**必须有付费的 Developer Program 会员**
- 如果没有现成账号，注册到审核通过通常需要 1-3 个工作日

---

## 2. 证书和 Provisioning Profile

### 必需

| 项目 | 说明 |
|------|------|
| **Development Certificate** | 用于开发阶段真机调试 |
| **Distribution Certificate** | 用于 TestFlight / App Store 发布 |
| **App ID（主 App）** | 如 `com.justin7974.vox`（需要替换占位 Bundle ID） |
| **App ID（键盘扩展）** | 如 `com.justin7974.vox.keyboard`（主 App ID 的子标识） |
| **App Group** | 如 `group.com.justin7974.vox`（在 Apple Developer Portal 注册） |
| **Provisioning Profile（主 App）** | 包含 App Group capability |
| **Provisioning Profile（键盘扩展）** | 包含 App Group capability |

### 配置步骤概要
1. 在 Apple Developer Portal → Identifiers 中注册主 App 的 App ID
2. 为该 App ID 启用 **App Groups** capability
3. 在 App Groups 中注册 group identifier（如 `group.com.justin7974.vox`）
4. 为该 App ID 启用 **Keychain Sharing** capability
5. 配置 Keychain Access Group（如 `$(TeamID).com.justin7974.vox.shared`）
6. 注册键盘扩展的 App ID（必须是主 App ID 的前缀 + .keyboard）
7. 为键盘扩展 App ID 也启用 App Groups **和** Keychain Sharing（指向同一 group）
8. 生成对应的 Provisioning Profile
9. 在 Xcode 中配置两个 Target 的 Signing 和 Capabilities

> ⚠️ **双机制配置**：App Group（共享文件/UserDefaults）和 Keychain Sharing（共享 API Key）是两套独立的 entitlement，必须分别在 Portal 和 Xcode 中配置。遗漏 Keychain Sharing 会导致键盘扩展无法读取 API Key。

### 注意事项
- Xcode 的"Automatically manage signing"可以简化大部分流程，但 App Group 需要手动在 Portal 注册
- Bundle ID 一旦确定不能更改（影响 Keychain、App Group、用户数据）
- **horga 需要决策最终的 Bundle ID**（参见 08_OPEN_QUESTIONS.md）

---

## 3. API 密钥（语音识别服务）

### 必需（至少一个）

| 服务 | 用途 | 获取地址 | 备注 |
|------|------|---------|------|
| **阿里 Qwen ASR** | 首选 ASR（中英混合最佳） | bailian.console.aliyun.com | 开通 DashScope API 服务，获取 API Key |
| **Whisper 兼容 API** | 备选 ASR | 取决于服务商 | 如 Groq Whisper、OpenAI Whisper 等 |

### 可选（LLM 后处理）

| 服务 | 用途 | 获取地址 | 备注 |
|------|------|---------|------|
| **Kimi (Moonshot)** | LLM 后处理（推荐） | platform.moonshot.cn | API URL: api.moonshot.cn |
| **Qwen LLM** | LLM 后处理 | bailian.console.aliyun.com | 可与 ASR 共用同一个 API Key |
| **DeepSeek** | LLM 后处理 | platform.deepseek.com | — |
| **MiniMax** | LLM 后处理 | platform.minimaxi.com | — |
| **OpenRouter** | LLM 后处理（聚合） | openrouter.ai | 一个 Key 可调用多个模型 |

### 注意事项
- 开发阶段建议使用 Qwen（ASR 和 LLM 可共用一个阿里云 Key），降低配置复杂度
- API Key 的费用极低（Qwen ASR 约 0.002 元/次，LLM 约 0.001 元/次），日常使用几乎免费
- 需要确保 API Key 有足够的调用额度（建议开通按量付费，不设硬上限）
- 测试阶段需要验证 API 在中国大陆和海外的连通性

---

## 4. 开发设备

### 必需

| 设备 | 说明 |
|------|------|
| **Mac（Apple Silicon 或 Intel）** | 运行 Xcode，编译 iOS App |
| **iPhone（iOS 17+）** | 真机测试录音、键盘扩展（模拟器不支持麦克风、键盘扩展调试受限） |

### 推荐

| 设备 | 说明 |
|------|------|
| iPhone 15 Pro / Pro Max | 测试 Action Button 集成（P2），A17 Pro 性能最佳 |
| iPhone SE (3rd gen) | 最小屏幕测试，确保键盘 UI 适配 |
| iPad（iOS 17+） | 如果需要支持 iPad（待决策） |

### iOS 版本要求
- **最低支持：iOS 17.0**
- 理由：iOS 17 引入 @Observable 宏（简化状态管理）、onChange(of:) 改进、TipKit（引导提示）、键盘扩展内存限制放宽
- 截至 2026 年，iOS 17+ 覆盖率 > 90%

---

## 5. Xcode 版本

### 必需

| 工具 | 版本 | 说明 |
|------|------|------|
| **Xcode** | 15.2 或更高 | 支持 iOS 17 SDK、Swift 5.9+、@Observable 宏 |
| **Xcode Command Line Tools** | 与 Xcode 匹配 | xcodebuild 命令行构建 |
| **macOS** | Sonoma (14.0) 或更高 | Xcode 15.2 的最低要求 |

### 推荐
- Xcode 16.x（如果已稳定）：支持 iOS 18 SDK，可测试控制中心 Widget 等新特性
- 保持 Xcode 更新，获取最新的模拟器和真机调试支持

---

## 6. TestFlight 配置

### 开发前准备

| 步骤 | 说明 |
|------|------|
| App Store Connect 中创建 App | 填写 App 名称、Bundle ID、SKU |
| 设置 TestFlight 信息 | App 描述、测试说明、反馈邮箱 |
| 创建内部测试组 | 添加测试人员（最多 100 人） |
| 准备 Beta 版本描述 | 每次上传新版本时的更新说明 |

### 注意事项
- TestFlight 内部测试无需 Apple 审核，上传后几分钟即可安装
- TestFlight 外部测试需要 Beta App Review（通常 24-48 小时）
- 首次提交需要填写加密使用声明（HTTPS 属于加密，需声明为"标准加密"）
- TestFlight 版本 90 天后过期，需要定期更新

---

## 7. App Store 审核注意事项

### 键盘扩展相关

| 审核点 | 要求 | 准备工作 |
|--------|------|---------|
| **Open Access 说明** | 必须清楚说明为什么需要"完全访问"权限 | 审核附注：说明联网仅用于语音识别 API 调用 |
| **隐私标签** | 声明数据收集类型 | "音频数据"发送到第三方（阿里云 DashScope） |
| **使用描述** | NSMicrophoneUsageDescription 要清晰具体 | "Vox 使用麦克风将您的语音转换为文字" |
| **不能记录按键** | 键盘扩展不能做 keystroke logging | 代码审查确认无按键记录逻辑 |
| **操作演示** | 建议提供演示视频给审核团队 | 录制完整使用流程的屏幕录像 |

### 键盘扩展合规要求

| 审核点 | 要求 | 说明 |
|--------|------|------|
| **地球键（输入法切换）** | **必须实现**。检查 `needsInputModeSwitchKey` 属性，为 true 时显示地球图标按钮，调用 `advanceToNextInputMode()` 切换 | Apple HIG 和 Review Guidelines 硬性要求，不实现会被拒 |
| **不记录按键** | 键盘扩展不能做 keystroke logging | 代码审查确认无按键记录逻辑 |
| **Open Access 说明** | 必须清楚说明为什么需要"完全访问" | 审核附注说明联网仅用于语音识别 API 调用 |
| **隐私弹窗一致性** | Open Access 开启时的系统提示与 App 实际行为一致 | 不能声称"不联网"却实际发送数据 |
| **输入法切换不阻塞** | 用户必须能随时切回系统键盘或其他输入法 | 地球键 + 系统原生键盘列表 |

### 麦克风权限相关

| 审核点 | 要求 |
|--------|------|
| **合理用途** | 麦克风仅用于语音输入，不用于通话、录音等其他目的 |
| **用户可控** | 用户可以随时在设置中关闭权限 |
| **最小权限** | 不请求不需要的权限 |

### 隐私标签声明

| 数据类型 | 用途 | 是否关联用户 | 是否追踪 |
|---------|------|------------|---------|
| 音频数据 | App 功能 | 否 | 否 |
| 使用数据（调用次数） | App 功能 | 否 | 否 |

### 建议策略
- P0/P1 阶段使用 TestFlight 内测，完全回避 App Store 审核
- P2 阶段准备好所有审核材料后再提交 App Store
- 提交前做一次内部审核模拟，检查所有 Guideline 合规性

---

## 8. 第三方服务账号

### 必需

| 服务 | 用途 | 说明 |
|------|------|------|
| **阿里云账号** | Qwen ASR API + 可选 Qwen LLM | 需要实名认证，开通 DashScope 服务 |

### 可选

| 服务 | 用途 | 说明 |
|------|------|------|
| Moonshot 平台账号 | Kimi LLM API | 如果选择 Kimi 作为 LLM provider |
| DeepSeek 平台账号 | DeepSeek LLM API | 备选 LLM provider |
| GitHub 账号 | 源码托管 | 已有 |

### 注意事项
- 所有 API 服务都是 BYOK（Bring Your Own Key）模式，用户自带 Key
- 开发测试时使用开发者自己的 Key
- 需要测试不同 provider 的 API 可用性和延迟

---

## 9. 网络环境要求

### 开发阶段

| 需求 | 说明 |
|------|------|
| **稳定的互联网** | 调用 Qwen ASR / LLM API |
| **中国大陆网络** | Qwen ASR (aliyuncs.com) 在大陆直连最快 |
| **可选翻墙** | 如果需要访问 OpenAI / Anthropic API 测试 |

### 测试矩阵

| 网络环境 | 测试目的 |
|---------|---------|
| WiFi（高带宽） | 基准性能测试 |
| 4G/LTE | 移动网络下的延迟和成功率 |
| 弱网（模拟） | Network Link Conditioner 模拟弱网 |
| 无网络 | 离线降级（Apple Speech）和错误提示 |

### 注意事项
- Xcode 的 Network Link Conditioner 可以模拟各种网络条件
- 真机测试时建议在 4G 环境下跑完整 pipeline，确认延迟在可接受范围
- 如果目标用户包括海外用户，需要测试 Qwen ASR 在海外的延迟（DashScope 服务器在中国大陆）

---

## 10. 法律、隐私与元数据准备

### App Store Connect 必需元数据

| 项目 | 说明 | 状态 |
|------|------|------|
| **Privacy Policy URL** | 隐私政策页面（可托管在 GitHub Pages 或个人网站） | ⬜ 待创建 |
| **Support URL** | 技术支持/帮助页面 | ⬜ 待创建 |
| **联系人邮箱** | App Store Connect 要求的开发者联系邮箱 | ⬜ 待确认 |
| **App 描述** | App Store 展示的功能描述（简短 + 详细） | ⬜ P2 时准备 |
| **App 截图** | 6.7" / 6.5" / 5.5" 截图（App Store 要求） | ⬜ P2 时准备 |
| **加密声明** | HTTPS 属于标准加密，需要在提交时声明为"使用标准加密" | ⬜ 首次提交时 |

> 📌 Privacy Policy URL 和 Support URL 即使是 TestFlight 外部测试也是必需的。建议在 P0 阶段就准备好，避免卡在提交环节。

### 隐私合规准备清单

Vox 的 BYOK 模式意味着音频数据直接从用户设备发送到用户自己的 API 账号——Vox 本身不做数据中转和存储。但仍需准备以下合规文档：

| 项目 | 说明 | 优先级 |
|------|------|--------|
| **数据流图** | 说明音频从设备到 ASR API 的完整路径（用户设备 → 用户 API 账号 → ASR 服务商） | P1 |
| **隐私政策** | 声明 Vox 不收集/存储/传输用户数据，所有 API 调用使用用户自有 Key | P0 |
| **Open Access 用途说明** | 详细说明键盘扩展 Open Access 权限仅用于联网调用用户配置的语音识别 API | P1 |
| **Apple 隐私标签** | 按 App Store Connect 要求填写数据收集声明 | P2（App Store 提交前） |
| **用户告知文案** | App 内的隐私说明页面，解释数据如何被处理 | P1 |

> 📌 BYOK 模式下，Vox 更像是一个"工具"而非"数据处理者"。合规重点在于准确告知用户数据流向，而非建立完整的数据处理/删除基础设施。但如果 API Key 托管或服务端代理层在未来引入，合规要求会显著升级（见 08_OPEN_QUESTIONS.md 相关决策项）。

---

## 11. 前置依赖检查清单

开发前必须确认的最终清单：

| # | 项目 | 状态 | 负责人 |
|---|------|------|--------|
| 1 | Apple Developer Program 会员（付费） | ⬜ 待确认 | horga |
| 2 | 确定最终 Bundle ID（如 com.justin7974.vox） | ⬜ 待决策 | horga |
| 3 | Apple Developer Portal 注册 App ID + App Group + **Keychain Sharing** | ⬜ 待操作 | horga |
| 4 | Qwen ASR API Key 可用 | ⬜ 待确认 | horga |
| 5 | 至少一个 LLM API Key 可用（可选） | ⬜ 待确认 | horga |
| 6 | Xcode 15.2+ 安装就绪 | ⬜ 待确认 | horga |
| 7 | iPhone（iOS 17+）可用于真机测试 | ⬜ 待确认 | horga |
| 8 | Mac（可运行 Xcode）可用 | ⬜ 待确认 | horga |
| 9 | Git 仓库初始化（是否新建 repo 还是在现有 vox repo 中加 ios/ 目录） | ⬜ 待决策 | horga |
| 10 | 确定是否支持 iPad | ⬜ 待决策 | horga |
| 11 | 确定 App 名称（"Vox" 在 App Store 可能已被占用） | ⬜ 待检查 | horga |
| 12 | **Privacy Policy URL 准备** | ⬜ 待创建 | horga |
| 13 | **Support URL 准备** | ⬜ 待创建 | horga |
| 14 | **联系人邮箱确认** | ⬜ 待确认 | horga |
