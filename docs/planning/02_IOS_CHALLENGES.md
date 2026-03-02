# 02 — iOS 移植核心技术挑战

> 日期：2026-03-02
> 每个挑战包括：问题描述、macOS 做法、iOS 限制/差异、可能解决方案、影响评级

---

## 挑战 1：全局触发机制

### 问题描述
Mac Vox 的核心交互是"在任何 App 中按一个快捷键就开始录音"。iOS 完全没有全局快捷键机制，用户不可能像 macOS 那样无感触发录音。需要找到一种尽可能低摩擦的替代触发方式。

### macOS 做法
- Carbon RegisterEventHotKey API 注册全局快捷键
- 支持 toggle 模式（按一次开始，再按停止）和 hold-to-talk 模式（按住说话，松开停止）
- 用户可自定义快捷键组合
- 菜单栏图标提供状态指示（绿色 = idle，红色 = recording）

### iOS 的限制/差异
- iOS 无全局快捷键 API，应用无法拦截系统级按键事件
- 即使 iPhone 15 Pro+ 的 Action Button 也只能打开 App 或运行快捷指令，不能直接触发 App 内录音
- 切换 App 有较高的上下文切换成本
- 系统键盘不可定制按键（只能做自定义键盘扩展）

### 可能的解决方案

| 方案 | 优点 | 缺点 | 适用阶段 |
|------|------|------|---------|
| **A. 主 App 大按钮** | 实现最简，零额外权限 | 需要切到 Vox App，不能跨 App | P0 MVP |
| **B. 自定义键盘扩展** | 唯一合法的跨 App 方式，可直接注入文字 | 需要用户一次性设置键盘 + 开启完全访问 | P1 核心 |
| **C. Siri Shortcut** | 语音触发，不需要手动操作 | Siri 延迟高，只能写剪贴板不能注入文字 | P2 |
| **D. Action Button** (iPhone 15 Pro+) | 物理按键，接近 macOS 体验 | 仅限新机型，只能启动 App 不能注入文字 | P2 |
| **E. 控制中心 Widget** (iOS 18+) | 一键触发，任何界面可达 | 仅限 iOS 18+，只能启动 App | P2 |
| **F. Live Activity / 灵动岛** | 常驻状态，一触即发 | 只能回到 App，不能跨 App 注入 | P2 |

### 影响评级：**高** ⚠️
这是 iOS 移植的最核心挑战。键盘扩展是唯一能跨 App 注入文字的方案，但引入了大量复杂度（App Group、Open Access 审核、内存限制等）。

---

## 挑战 2：沙箱限制（文件访问与进程通信）

### 问题描述
macOS App 可以自由读写文件系统、调用子进程（Process()）、访问其他 App 信息。iOS 的严格沙箱让这些操作全部不可行。

### macOS 做法
- 配置文件存储在 `~/.vox/config.json`，用户可直接编辑
- 历史记录存储在 `~/.vox/history.json`
- 自定义 prompt 存储在 `~/.vox/prompt.txt`
- 调试日志存储在 `~/.vox/debug.log`
- 通过 Process() 调用 osascript（AppleScript 脚本）
- 通过 Process() 调用 whisper-cli（本地 ASR）
- 从 `~/.voiceinput` 到 `~/.vox` 的配置迁移

### iOS 的限制/差异
- 每个 App 只能访问自己的沙箱目录
- 主 App 和键盘扩展是独立进程，不共享文件系统
- 无法调用 Process()（没有 shell 环境）
- 无法直接编辑配置文件（需要 App 内 UI）
- App Group 是主 App 和扩展共享数据的唯一桥梁

### 可能的解决方案

| 问题 | 解决方案 |
|------|---------|
| 主 App 与键盘扩展共享配置 | App Group + 共享 UserDefaults(suiteName:) |
| API Key 安全共享 | **Keychain Sharing**（`keychain-access-groups` entitlement），access group 格式为 `$(TeamID).com.xxx.vox.shared`。注意：这与 App Group 是**两套独立机制**，需分别配置 |
| 非敏感文件共享 | App Group 共享容器（`com.apple.security.application-groups`） |
| 配置文件路径 | FileManager.containerURL(forSecurityApplicationGroupIdentifier:) |
| 无法调用 Process | 本地 ASR 用 whisper.cpp SPM 直接链接；osascript 功能不需要 |
| 用户无法手动编辑文件 | App 内设置页面提供所有可配置项 |

> ⚠️ **关键区分**：App Group（共享文件/UserDefaults）和 Keychain Sharing（共享密钥）是两套独立的 entitlement 机制。必须在 Xcode 的 Signing & Capabilities 中分别添加，缺一不可。只配了 App Group 而遗漏 Keychain Sharing 会导致键盘扩展无法读取 API Key。

### 影响评级：**高** ⚠️
App Group 和 Keychain Sharing 配置是键盘扩展能否正常工作的基础。配置不当会导致键盘扩展无法读取 API Key，从而无法调用 ASR 服务。

---

## 挑战 3：后台录音权限

### 问题描述
macOS 的 Vox 作为菜单栏 App 始终在"前台"。iOS App 切到后台后会被暂停，录音功能随即失效。

### macOS 做法
- NSApplication 的 LSUIElement = true（无 Dock 图标）
- 菜单栏 App 始终运行，不存在"后台"概念
- 用户可以在任何 App 前台时通过快捷键触发 Vox 录音

### iOS 的限制/差异
- App 切到后台后几秒内被暂停
- UIBackgroundModes: audio 可以保持后台运行，但 App Store 审核要求有充分理由（音乐播放、导航等），纯语音输入工具很难通过
- 键盘扩展在使用时天然处于"前台状态"（作为当前输入法时 extension 进程活跃）
- 键盘扩展切换到其他键盘后进程可能被系统 kill

### 可能的解决方案

| 方案 | 说明 | 审核风险 |
|------|------|---------|
| **A. 不申请后台权限** | 主 App 仅前台录音；键盘扩展作为输入法天然前台 | 无风险 |
| **B. 申请 Background Audio** | 允许切到后台继续录音 | 高风险：审核大概率被拒 |
| **C. Live Activity 配合** | 灵动岛保持活跃状态，但仍需切回 App 操作 | 中等风险 |

**推荐方案 A**：不申请后台录音权限。理由：
- 键盘扩展在使用时就是活跃的，不需要后台权限
- 主 App 录音时用户应该能看到反馈，后台录音反而容易误操作
- 避免 App Store 审核风险

### 影响评级：**中** ⚠️
只要不做后台录音，这个挑战的影响可控。键盘扩展方案天然回避了后台问题。

---

## 挑战 4：文字注入（键盘扩展 vs Accessibility）

### 问题描述
Mac Vox 通过模拟按键（CGEvent Cmd+V）将文字粘贴到当前应用。iOS 需要找到合法的跨 App 文字注入方式。

### macOS 做法
- NSPasteboard 写入剪贴板
- CGEvent 创建键盘事件模拟 Cmd+V
- 需要 Accessibility 权限（System Settings → Privacy → Accessibility）
- 失败时通过 osascript 兜底

### iOS 的限制/差异
- iOS 无 CGEvent，无法模拟按键
- iOS 无 Accessibility 注入 API（辅助功能 API 是为辅助阅读设计的，不能注入文字）
- iOS 14+ 从其他 App 读取剪贴板会弹"已粘贴"横幅
- UIPasteboard.general 写入后用户需要手动粘贴
- 键盘扩展的 textDocumentProxy.insertText() 是唯一合法的跨 App 文字注入 API

### 可能的解决方案

| 方案 | 能跨 App | 能直接注入 | 限制 |
|------|---------|-----------|------|
| **A. UIPasteboard + 手动粘贴** | ✅ | ❌（需手动） | iOS 14+ 弹"已粘贴"横幅 |
| **B. 键盘扩展 insertText** | ✅ | ✅ | 需添加键盘 + 开启完全访问 |
| **C. App 内 UITextView** | ❌ | ✅ | 只能在 Vox App 内使用 |

**推荐组合**：P0 用方案 A（剪贴板），P1 用方案 B（键盘扩展），方案 C 作为辅助展示。

### 影响评级：**高** ⚠️
键盘扩展的 textDocumentProxy.insertText() 是 iOS 版 Vox 的核心差异化价值，也是实现复杂度最高的部分。

---

## 挑战 5：键盘扩展技术限制

### 问题描述
iOS 自定义键盘扩展（Keyboard Extension）虽然是唯一的跨 App 文字注入方案，但自身有大量技术限制。

### macOS 做法
不适用（macOS 不通过输入法实现）。

### iOS 的限制/差异

| 限制 | 详细说明 | 影响 |
|------|---------|------|
| **内存限制** | 实测约 48-70MB 被系统 kill（iOS 18+ 放宽到 ~80MB） | 无法加载大模型（whisper-cpp large-v3 需 ~150-800MB） |
| **无权限弹窗** | 键盘扩展不能调用 requestRecordPermission 等系统弹窗 | 必须在主 App 预先授权麦克风 |
| **Open Access 审核** | RequestsOpenAccess = YES 触发额外隐私审核 | 需要准备详细隐私说明和演示视频 |
| **App Group 必需** | 键盘扩展与主 App 是独立进程 | 必须配置 App Group 共享配置 |
| **无 UIApplication** | 键盘扩展中无法使用 UIApplication.shared | 不能调用 openURL、openSettings 等 |
| **hasFullAccess 可变** | 用户可随时关闭完全访问 | 每次操作前必须检查权限状态 |
| **textDocumentProxy 有限** | 只能读取光标前后部分文字（通常几百字符） | 上下文信息有限 |
| **进程生命周期不可控** | 切换到其他键盘时进程可能被杀 | 网络请求要快，避免长轮询 |
| **调试困难** | 需要 Attach to Process by PID 调试扩展 | 开发效率降低 |
| **secureTextEntry 禁用** | 密码框/安全输入框会强制切回系统键盘，第三方键盘被禁用 | 部分场景不可用 |
| **宿主 App 可拒绝** | 宿主 App 可通过 `shouldAllowExtensionPointIdentifier` 拒绝所有第三方键盘 | 银行/金融类 App 常见 |

### 不可用场景矩阵

| 场景 | 原因 | 影响 | UX 处理 |
|------|------|------|---------|
| 密码输入框（secureTextEntry） | iOS 系统强制切换到系统键盘 | 自动切换，用户无法选择 | 无需处理，系统行为，密码输入后自动切回 |
| 银行/金融类 App | 宿主 App 通过 shouldAllowExtensionPointIdentifier 拒绝第三方键盘 | 整个 App 内无法使用 Vox 键盘 | 无法检测，建议在帮助文档中说明 |
| 验证码/OTP 输入框 | 通常设置为 secureTextEntry 或 oneTimeCode | 自动切回系统键盘 | 同密码框处理 |
| 部分企业 MDM 管控设备 | MDM 策略可能禁用第三方键盘 | 所有 App 内不可用 | 在帮助文档中说明 |
| Spotlight 搜索 | 系统 UI 不支持第三方键盘 | 不可用 | 无需处理 |

> 📌 **用户影响说明**：以上不可用场景是 iOS 平台限制，所有第三方键盘都有同样的限制（包括搜狗、百度输入法等）。需要在 App 内帮助页面和首次使用引导中提前告知用户，避免误认为功能失效。

### 可能的解决方案

| 限制 | 应对策略 |
|------|---------|
| 内存限制 | 只用云端 ASR，不加载本地模型 |
| 无权限弹窗 | 主 App 首次引导完成所有权限申请 + TipKit 提示 |
| Open Access 审核 | 准备详细的隐私标签 + App 审核说明 + 操作演示视频 |
| App Group | 正确配置 Signing & Capabilities，测试共享读写 |
| 无 UIApplication | 用 extensionContext 替代部分功能 |
| hasFullAccess | 每次操作前检查，未授权显示内联引导 |
| textDocumentProxy | 利用有限上下文作为 LLM hint |
| 进程被杀 | 确保网络请求有合理超时，状态可恢复 |
| secureTextEntry 禁用 | 无需处理（系统行为），在帮助文档中说明 |
| 宿主 App 拒绝 | 无法检测，在帮助文档中列出已知不兼容 App |
| 调试 | 建立完善的共享 debug.log 日志机制 |

### 扩展进程生命周期约束

键盘扩展作为 extension 进程，生命周期受系统严格管控：

| 约束 | 详细说明 | 影响 |
|------|---------|------|
| **系统随时回收** | 系统可在内存压力下回收 extension 进程，不等待网络请求完成 | 长请求（ASR 25s + LLM 12s）有被中途 kill 的风险 |
| **切换键盘即挂起** | 用户切换到其他输入法时，Vox 键盘进程可能被立即暂停或终止 | 正在进行的请求丢失 |
| **无后台执行** | extension 不能申请 `beginBackgroundTask`，没有后台执行窗口 | 必须在前台（键盘活跃时）完成所有操作 |
| **冷启动开销** | 每次切到 Vox 键盘可能是冷启动，需要重新加载进程 | 首帧延迟敏感 |

**短事务策略**（应对措施）：
1. 键盘扩展内录音时长建议上限 **60 秒**（减少长请求风险）
2. ASR 请求超时缩短到 **15 秒**（相比主 App 的 25 秒），快速失败
3. LLM 后处理超时 **8 秒**（相比主 App 的 12 秒）
4. 如果请求在进行中键盘被切走，下次激活时清理残留状态并提示用户重试
5. 请求失败立即回退到"复制音频到主 App 处理"的降级路径

### 影响评级：**高** ⚠️
键盘扩展的限制直接影响核心功能的可行性和用户体验，是项目最复杂的技术挑战。

---

## 挑战 6：系统菜单栏替代

### 问题描述
Mac Vox 是一个菜单栏 App（LSUIElement），通过 NSStatusBar 提供状态指示和菜单操作。iOS 没有菜单栏概念。

### macOS 做法
- NSStatusItem 显示在系统菜单栏
- 图标颜色变化指示状态（绿色 idle，红色 recording）
- 右键菜单提供设置、历史记录、退出等操作
- App 不出现在 Dock 中

### iOS 的限制/差异
- iOS 无系统菜单栏
- App 没有常驻状态指示位（除了 Live Activity / 灵动岛）
- 用户需要打开 App 才能看到状态和设置

### 可能的解决方案

| 方案 | 说明 | 优先级 |
|------|------|--------|
| **A. SwiftUI 主界面** | 大按钮 + 状态指示 + 设置入口 | P0 |
| **B. 键盘扩展内嵌 UI** | 键盘界面内显示录音状态 | P1 |
| **C. Live Activity** | 灵动岛显示录音状态 | P2 |
| **D. 主屏幕 Widget** | 快捷入口 + 上次结果 | P2 |
| **E. 控制中心按钮** (iOS 18+) | 快捷触发按钮 | P2 |

### 影响评级：**低** ✅
这个挑战影响较低——SwiftUI 主界面 + 键盘扩展 UI 可以完全替代菜单栏的功能，不影响核心使用流程。

---

## 挑战 7：应用间通信

### 问题描述
macOS 上 Vox 可以通过多种方式与其他 App 交互（NSWorkspace 获取前台 App、AppleScript 获取 URL、CGEvent 注入按键）。iOS 的 App 间通信能力极其有限。

### macOS 做法
- NSWorkspace.shared.frontmostApplication 获取前台 App
- AppleScript（osascript）获取 Safari/Chrome 的 URL
- CGEvent 向任意 App 注入按键事件
- NSPasteboard 作为通用数据交换通道

### iOS 的限制/差异
- 无法获取其他 App 的任何信息
- 无法向其他 App 发送事件
- App 间通信仅限：URL Scheme、Universal Links、UIPasteboard、App Group（同开发者 App 间）
- 键盘扩展只能通过 textDocumentProxy 与宿主 App 交互（且功能有限）

### 可能的解决方案

| 需求 | macOS 方式 | iOS 替代 |
|------|-----------|---------|
| 了解当前场景 | 自动检测前台 App | 手动场景选择 + textDocumentProxy 上下文 |
| 输出文字到其他 App | CGEvent Cmd+V | 键盘扩展 insertText / UIPasteboard |
| 数据交换 | 文件系统 + NSPasteboard | UIPasteboard + App Group |
| 触发录音 | 全局快捷键 | 键盘扩展按钮 / Siri Shortcut |

### 影响评级：**中** ⚠️
对核心功能有影响（自动上下文检测无法实现），但通过手动场景选择和 textDocumentProxy 可以达到可接受的体验。

---

## 挑战 8：AVAudioSession 与宿主 App 冲突

### 问题描述
键盘扩展中启动录音时，可能与宿主 App 的音频播放产生冲突（如用户正在听音乐时使用 Vox 键盘）。

### macOS 做法
macOS 的音频系统允许多个 App 同时使用麦克风和扬声器，不存在"category 抢占"问题。

### iOS 的限制/差异
- iOS AVAudioSession 是抢占式的：设置新 category 会中断其他 App 的音频
- 如果键盘扩展使用 .record category，会中断宿主 App 的音乐播放
- 录音结束后需要正确 deactivate session 让宿主 App 恢复音频

### 可能的解决方案

| 方案 | 说明 | 推荐 |
|------|------|------|
| **A. .playAndRecord + .mixWithOthers** | 允许与其他 App 音频共存 | ✅ 推荐 |
| **B. .record** | 独占麦克风，中断其他音频 | ❌ 体验差 |
| **C. 录音后 .notifyOthersOnDeactivation** | 通知其他 App 恢复音频 | 配合 A 使用 |

**推荐**：键盘扩展使用 `.playAndRecord` + `.mixWithOthers` + `.defaultToSpeaker` + `.allowBluetooth`，录音结束后用 `.notifyOthersOnDeactivation` 释放。

### 影响评级：**中** ⚠️
配置正确即可解决，但配置错误会导致用户体验严重下降（突然中断音乐）。需要充分测试。

---

## 挑战 9：ASR 音频上传在弱网下的体验

### 问题描述
macOS 通常使用 WiFi 或有线网络，带宽充裕。iOS 用户经常在 4G/5G 环境下使用，上传大体积音频文件会有明显延迟。

### macOS 做法
- 直接上传 WAV 文件（16kHz/16bit/Mono，约 32KB/s）
- Qwen ASR 使用 base64 编码（体积增加约 33%）
- 30 秒音频 ≈ 960KB WAV → 1.28MB base64
- 有线/WiFi 上传几乎无感

### iOS 的限制/差异
- 4G 网络上传 1.28MB ≈ 2-3 秒额外延迟
- 60 秒音频 base64 约 2.56MB，弱网可能超时
- 用户对手机 App 的延迟容忍度比桌面 App 更低

### 可能的解决方案

| 方案 | 体积减少 | 实现复杂度 | 推荐阶段 |
|------|---------|-----------|---------|
| **A. 维持 WAV + base64** | 0% | 低 | P0 |
| **B. AVAudioConverter 转 Opus/AAC** | ~80-90% | 中 | P1 |
| **C. 流式上传（分片）** | N/A | 高 | P2 |
| **D. 限制最大录音时长** | 间接减少 | 低 | P0 |

**推荐路径**：P0 先用 WAV + base64（验证 pipeline），P1 引入 Opus 压缩（30s 音频从 1.28MB 降到 ~80KB）。

### 影响评级：**中** ⚠️
不影响功能可行性，但影响用户体验。弱网场景是 iOS 的常见使用环境，需要在 P1 阶段优化。

---

## 挑战 10：App Store 审核

### 问题描述
Vox iOS 涉及多个 App Store 敏感审核点：键盘扩展请求完全访问、麦克风权限、音频数据上传到第三方服务器。

### macOS 做法
macOS 版通过 build.sh 编译，xattr -cr 绕过 Gatekeeper，不经过 App Store 审核。

### iOS 的限制/差异
- 键盘扩展的 RequestsOpenAccess = YES 会触发额外隐私审核
- 麦克风权限必须提供合理的使用描述
- 音频数据发送到第三方 API（Qwen/Whisper）需要在隐私标签中声明
- 键盘扩展收集用户输入可能被视为"keystroke logging"
- 审核指南对"替代输入法"有特别关注

### 可能的解决方案

| 审核风险点 | 应对策略 |
|-----------|---------|
| Open Access 隐私审核 | 详细的隐私标签 + App 审核附注说明"Open Access 仅用于联网进行语音识别" |
| 麦克风权限 | NSMicrophoneUsageDescription 清晰说明"用于语音输入转文字" |
| 第三方数据传输 | 隐私标签声明"音频数据"发送到第三方（阿里云 DashScope）用于语音识别 |
| Keystroke logging 嫌疑 | 说明键盘扩展不记录按键，仅进行语音输入 |
| 演示视频 | 准备操作演示视频给审核团队 |
| 初期回避 | P0/P1 用 TestFlight 内测，绕过正式审核；App Store 上架放到 P2 |

### 影响评级：**高** ⚠️
审核被拒会直接阻塞发布。需要提前准备充分的审核材料，并考虑 TestFlight 作为初期分发方案。

---

## 挑战总结

| # | 挑战 | 影响评级 | 核心风险 |
|---|------|---------|---------|
| 1 | 全局触发机制 | 高 | 键盘扩展是唯一跨 App 方案，但引入大量复杂度 |
| 2 | 沙箱限制 | 高 | App Group 配置不当会导致键盘扩展无法工作 |
| 3 | 后台录音 | 中 | 不申请后台权限即可回避 |
| 4 | 文字注入 | 高 | 键盘扩展 insertText 是核心差异化 |
| 5 | 键盘扩展限制 | 高 | 内存限制、权限限制、调试困难 |
| 6 | 菜单栏替代 | 低 | SwiftUI 主界面完全替代 |
| 7 | 应用间通信 | 中 | 手动场景选择可接受 |
| 8 | 音频会话冲突 | 中 | 正确配置即可解决 |
| 9 | 弱网 ASR 上传 | 中 | P1 Opus 压缩可解决 |
| 10 | App Store 审核 | 高 | TestFlight 可初期回避 |
