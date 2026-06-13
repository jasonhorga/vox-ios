# 智能整理（LLM 文本后处理）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development（或 executing-plans）逐任务实现。步骤用 `- [ ]`。

**Goal:** 加一个「智能整理」开关（默认开）：开启后每段听写经 LLM 整理（去填充词/助词、去重、自我更正合并、自动排版、语法顺序、保守的口述意图格式化），与翻译共用一次 LLM 调用；断网/失败自动跳过且绝不丢弃已识别文本。

**Architecture:** 扩展现有 `PostProcessor`（H2 已让模型按 provider 选）：`process(text:cleanup:translation:config:)` 用一个合并 system prompt 做「整理(+可选翻译)」一次调用；system prompt 的拼装抽成纯函数 `systemPrompt(cleanup:translation:)` 便于单测。开关存 `SharedConfigStore.smartCleanup`（默认 `true`）。主 App（`AppState.processPipeline`）与键盘/daemon（`AudioDaemonService.processAudio`）两条路都接，失败回退原文（沿用 H2）。

**Tech Stack:** Swift 5.9 / SwiftUI；现有 App Group `UserDefaults` 配置；DashScope/OpenAI 兼容 Chat Completions。

> ⚠️ **本地无 Xcode**：验证靠 push→CI。可测纯逻辑（prompt 拼装）写真 XCTest；其余以 CI 编译+测试为门。各任务提交，最后开 PR 跑 CI。
> 注：键盘 `resultTimeout` 已在 beta.62 提到 25s，覆盖整理增加的延迟。整理只在**云端**（`networkMonitor.isConnected`）进行，离线跳过。

---

## File Structure

- **Modify** `Shared/SharedConfigStore.swift` — 加 `smartCleanup: Bool`（默认 true，App Group 持久化，`didSet` 受 `isLoading` 守卫；Key、init、reload、resetAll 同步）。
- **Modify** `VoxInput/Storage/ConfigStore.swift` — 代理 `smartCleanup`。
- **Modify** `Shared/PostProcessor.swift` — 新 `process(text:cleanup:translation:config:)` + 纯函数 `systemPrompt(cleanup:translation:)` + 整理 system prompt 常量。
- **Modify** `VoxInput/UI/SettingsView.swift` — 「后处理」区加「智能整理」Toggle + 说明。
- **Modify** `VoxInput/App/AppState.swift` — `processPipeline` 改用新接口 + `needsLLM` 门控。
- **Modify** `VoxInput/App/AudioDaemonService.swift` — `processAudio` 同样门控（键盘路径）。
- **Create** `VoxInputTests/SmartCleanupPromptTests.swift` — 测 `systemPrompt(cleanup:translation:)` 各组合（纯逻辑，CI 跑）。
- 无 `project.yml` 改动；新增测试文件后 `xcodegen generate`（CI 做）。

---

## Task 1: 配置开关 `smartCleanup`（默认开）

**Files:** Modify `Shared/SharedConfigStore.swift`、`VoxInput/Storage/ConfigStore.swift`

- [ ] **Step 1: SharedConfigStore 加属性**

在 `translationMode` 属性下方加（仿照现有 `didSet` 守卫模式）：
```swift
    /// beta.63: 智能整理（LLM 后处理）开关，默认开
    var smartCleanup: Bool {
        didSet {
            guard !isLoading else { return }
            saveBool(smartCleanup, forKey: .smartCleanup)
        }
    }
```
在 `private enum Key: String` 中加：
```swift
        case smartCleanup = "vox.postprocess.smartCleanup"
```
在 `init()` 中，于 `translationMode` 加载之后加（**默认 true**：键不存在时取 true）：
```swift
        // 默认开：键不存在时 object(forKey:) 为 nil → 取 true
        self.smartCleanup = defaults.object(forKey: Key.smartCleanup.rawValue) as? Bool ?? true
```
在 `reload()` 中对应位置加同样一行（赋值；`isLoading` 守卫会阻止写回）：
```swift
        smartCleanup = defaults.object(forKey: Key.smartCleanup.rawValue) as? Bool ?? true
```
在 `resetAll()` 中加：
```swift
        smartCleanup = true
```

- [ ] **Step 2: ConfigStore 代理**

在 `VoxInput/Storage/ConfigStore.swift` 的 `translationMode` 代理下方加：
```swift
    /// 智能整理开关
    var smartCleanup: Bool {
        get { store.smartCleanup }
        set { store.smartCleanup = newValue }
    }
```

- [ ] **Step 3: 提交**
```bash
git add Shared/SharedConfigStore.swift VoxInput/Storage/ConfigStore.swift
git commit -m "feat(config): add smartCleanup toggle (default on)"
```

---

## Task 2: PostProcessor 整理 + 合并调用（含纯函数单测）

**Files:** Modify `Shared/PostProcessor.swift`；Create `VoxInputTests/SmartCleanupPromptTests.swift`

- [ ] **Step 1: 加整理 prompt 常量 + 纯拼装函数 + 新 process 接口**

在 `enum PostProcessor {` 内（`process(text:mode:config:)` 之外）加：
```swift
    /// 整理（cleanup）的 system prompt 主体
    static let cleanupInstruction = """
    你是语音听写整理助手。把下面这段「语音转写的原始文字」整理成干净、可直接使用的文本，遵守：
    1. 删除口头禅/填充词（嗯、那个、就是说、um、uh、like 等）与重复啰嗦。
    2. 说话中途自我更正时只保留最终意思（如“周一—不对周三”→ 周三）。
    3. 把口述的清单/步骤/要点整理成项目符号或编号列表。
    4. 修语法、理顺语序，但贴合原文用词风格、保留原意。
    5. 仅当原文明确含“指令”时才据此调整格式/语气（如“发邮件…/列成要点/改正式/改简短”）；否则一律当正文内容，不要把内容误当命令。邮件类意图只输出润色后的正文，不要自动添加称呼或落款。
    绝不臆造事实；拿不准时尽量少改。
    """

    /// 根据 cleanup/translation 组合拼装最终 system prompt（纯函数，可单测）
    static func systemPrompt(cleanup: Bool, translation: TranslationMode) -> String {
        var parts: [String] = []
        if cleanup { parts.append(cleanupInstruction) }
        switch translation {
        case .none: break
        case .toEnglish:
            parts.append(cleanup ? "然后把整理后的文本翻译成英文。" : "把下面的文本翻译成英文。")
        case .toChinese:
            parts.append(cleanup ? "然后把整理后的文本翻译成中文。" : "把下面的文本翻译成中文。")
        }
        parts.append("只输出最终文本，不要任何解释、注释或额外说明。")
        return parts.joined(separator: "\n\n")
    }

    /// 整理（+可选翻译）。两者都关 → 原样返回，不发起调用。
    static func process(
        text: String,
        cleanup: Bool,
        translation: TranslationMode,
        config: SharedConfigStore = .shared
    ) async throws -> String {
        guard cleanup || translation != .none else { return text }

        let apiKey: String
        let baseURL: String
        let model: String
        switch config.asrProvider {
        case .qwen:
            apiKey = config.qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            baseURL = Constants.Network.qwenBaseURL
            model = "qwen-plus"
        case .whisper:
            apiKey = config.whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            baseURL = config.whisperBaseURL
                .replacingOccurrences(of: "/v1/audio/transcriptions", with: "/v1/chat/completions")
                .replacingOccurrences(of: "/audio/transcriptions", with: "/chat/completions")
            model = "gpt-4o-mini"
        }
        guard !apiKey.isEmpty else { throw VoxError.apiKeyMissing }

        return try await callLLM(
            text: text,
            systemPrompt: systemPrompt(cleanup: cleanup, translation: translation),
            apiKey: apiKey,
            baseURL: baseURL,
            model: model
        )
    }
```
（保留现有 `process(text:mode:config:)` 不动，以免影响其它调用方；新代码用新接口。`callLLM` 已存在，签名 `callLLM(text:systemPrompt:apiKey:baseURL:model:)`。）

- [ ] **Step 2: 写纯函数单测**

`VoxInputTests/SmartCleanupPromptTests.swift`：
```swift
import XCTest
@testable import VoxInput

final class SmartCleanupPromptTests: XCTestCase {
    func testCleanupOnly() {
        let p = PostProcessor.systemPrompt(cleanup: true, translation: .none)
        XCTAssertTrue(p.contains("填充词"))
        XCTAssertFalse(p.contains("翻译"))
        XCTAssertTrue(p.contains("只输出最终文本"))
    }
    func testCleanupPlusTranslate() {
        let p = PostProcessor.systemPrompt(cleanup: true, translation: .toEnglish)
        XCTAssertTrue(p.contains("填充词"))
        XCTAssertTrue(p.contains("翻译成英文"))
    }
    func testTranslateOnly() {
        let p = PostProcessor.systemPrompt(cleanup: false, translation: .toChinese)
        XCTAssertFalse(p.contains("填充词"))
        XCTAssertTrue(p.contains("翻译成中文"))
    }
}
```

- [ ] **Step 3: 提交**
```bash
git add Shared/PostProcessor.swift VoxInputTests/SmartCleanupPromptTests.swift
git commit -m "feat(postprocess): cleanup system prompt + combined cleanup/translate call"
```

---

## Task 3: 设置页加开关

**Files:** Modify `VoxInput/UI/SettingsView.swift`

- [ ] **Step 1: 在「后处理」Section 加 Toggle**

在 `SettingsView` 的「后处理」Section（含翻译 Picker）里，翻译 Picker 上方或下方加：
```swift
                    Toggle("智能整理", isOn: $config.smartCleanup)
```
并把该 Section 的 footer 文案补充（替换或追加）：
```swift
                } footer: {
                    Text("智能整理：用 AI 去掉口头禅、顺语序、按口述意图排版（需联网、消耗 API 调用，离线自动跳过）。翻译：识别完成后翻成目标语言。")
                }
```
（`config` 已是 `@Bindable private var config = ConfigStore.shared`，`$config.smartCleanup` 可绑定。）

- [ ] **Step 2: 提交**
```bash
git add VoxInput/UI/SettingsView.swift
git commit -m "feat(settings): smart cleanup toggle + footer"
```

---

## Task 4: 接入两条识别管线

**Files:** Modify `VoxInput/App/AppState.swift`、`VoxInput/App/AudioDaemonService.swift`

- [ ] **Step 1: 主 App（AppState.processPipeline）**

把 beta.61 加的「仅翻译」块（`var processedText = rawText` ... 那段 `if translationMode != .none ...`）整体替换为：
```swift
            var processedText = rawText
            let cleanup = config.smartCleanup
            let translationMode = config.translationMode
            if (cleanup || translationMode != .none) && networkMonitor.isConnected {
                statusMessage = cleanup ? "正在整理..." : "正在翻译..."
                do {
                    processedText = try await PostProcessor.process(
                        text: rawText,
                        cleanup: cleanup,
                        translation: translationMode
                    )
                } catch {
                    // beta.63: 整理/翻译失败不丢弃已识别文本，降级为原文（沿用 H2）
                    SharedLogger.error("智能整理/翻译失败，降级为原文: \(error.localizedDescription)")
                    processedText = rawText
                }
            }
```

- [ ] **Step 2: 键盘/daemon（AudioDaemonService.processAudio）**

把 beta.61 加的 daemon 翻译块（`var processed = rawText` ... `if config.translationMode != .none ...`）整体替换为：
```swift
            var processed = rawText
            if (config.smartCleanup || config.translationMode != .none) && networkMonitor.isConnected {
                do {
                    processed = try await PostProcessor.process(
                        text: rawText,
                        cleanup: config.smartCleanup,
                        translation: config.translationMode
                    )
                } catch {
                    SharedLogger.error("daemon 智能整理/翻译失败，降级为原文: \(error.localizedDescription)")
                    processed = rawText
                }
            }
            let formatted = TextFormatter.format(processed)
```
（`config` 在 daemon 是 `ConfigStore.shared`，有 `smartCleanup`/`translationMode`；`PostProcessor.process` 默认 `config: .shared`(SharedConfigStore) 同底层存储。）

- [ ] **Step 3: 提交**
```bash
git add VoxInput/App/AppState.swift VoxInput/App/AudioDaemonService.swift
git commit -m "feat(pipeline): route ASR through smart cleanup (+translate) on both paths"
```

---

## Task 5: 重生工程 + CI

- [ ] **Step 1:** （有 Mac 时）`xcodegen generate`；本地无 Xcode 则跳过（CI 会做）。
- [ ] **Step 2:** 开分支 push：
```bash
git checkout -b feat/smart-cleanup
git push -u origin feat/smart-cleanup
```
对 main 开 PR。
- [ ] **Step 3:** 读 CI：`Build & Test` ✅（含 `SmartCleanupPromptTests`）+ `Swift Lint` ✅。
- [ ] **Step 4:** CI 红按日志修（常见：SettingsView Section 语法/footer 重复、行宽、`process` 调用方参数；`process(text:mode:)` 旧接口若已无调用方可由 lint 提示）。
- [ ] **Step 5:** 绿了征得用户同意再合。

---

## Self-Review

- **Spec coverage**：开关默认开 = Task 1（`?? true`）；五类整理 = Task 2 `cleanupInstruction`；保守意图 + 邮件不加落款 = prompt 第 5 条；与翻译单次合并 = `process(cleanup:translation:)` 一次 `callLLM`；模型按 provider = 沿用 H2；断网跳过 = Task 4 `&& networkMonitor.isConnected`；失败回退原文 = Task 4 catch；两条路径 = AppState + AudioDaemonService。✅
- **Placeholder scan**：无 TODO；每步有完整代码/命令。✅
- **Type consistency**：`process(text:cleanup:translation:config:)` 在 Task 2 定义、Task 4 调用一致；`systemPrompt(cleanup:translation:)` 同；`smartCleanup: Bool` 在 SharedConfigStore/ConfigStore/SettingsView 一致。✅
- **风险**：`process(text:mode:)` 旧接口保留未删（避免触碰其它调用方）；若全仓库已无调用方，可后续清理（非本计划）。整理 prompt 的"意图理解"是行为风险点，需真机调；CI 只验编译+纯逻辑。
