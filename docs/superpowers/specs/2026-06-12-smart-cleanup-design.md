# 智能整理（LLM 文本后处理）v1 — 设计文档（2026-06-12）

## 背景与目标

现状：听写输出的是**逐字稿**——`ASR → TextFormatter（机械中英空格/标点）→ 输出`，`PostProcessor` 目前只做翻译。受 Typeless 启发，把口述变成**干净、顺、能直接用**的文字，而不是把每个"嗯/那个"都打出来。

## 范围

**In（v1）** —— 一个开关「智能整理」，**默认开**。开启后对每段听写做以下整理（保留原意与用户口吻）：
1. **去填充词/助词 + 去重冗**：删 嗯/那个/就是说 这类口头禅与重复啰嗦。
2. **自我更正合并**：说错改口时只保留最终意思（"周一—不对周三" → 周三）。
3. **自动排版**：口述的清单/步骤/要点 → 项目符号/编号。
4. **语法修正 + 顺语序**。
5. **意图格式化 / 口述指令（保守）**：识别口述里**明确**的指令（发邮件 / 列要点 / 改正式 / 改简短），据此调整输出；其余一律当内容。**邮件意图只产出润色后的正文，不自动加称呼/落款。**

**Out（不在 v1）**
- **真·执行动作**（在日历建事件、弹邮件撰写器等）→ 系统集成 + 权限、键盘扩展基本做不到，单独立项（agent 类，未来）。
- **按宿主 App 自动调语气** → iOS 键盘拿不到宿主 App 身份，做不了。
- **选中已有文本 + 语音命令改写** → v2。
- 不改 ASR / 录音 / IPC 后端。

## 配置

- 新增设置项 `smartCleanup: Bool`，**默认 `true`**。放在 `SharedConfigStore`（含 `ConfigStore` 代理）+ `SettingsView` 一个开关。
- 默认开会**改变现有逐字稿行为**并给每次听写加一次 LLM 调用（已与用户确认接受——这是核心价值）。

## 管线位置

`ASR → 智能整理(LLM，若开且在线) → TextFormatter(机械格式化) → 输出`

两条路都接：
- 主 App：`AppState.processPipeline`（`VoxInput/App/AppState.swift`）。
- 键盘/daemon：`AudioDaemonService.processAudio`（`VoxInput/App/AudioDaemonService.swift`）。

替换/扩展 beta.61(H2) 里刚加的"仅翻译"分支：

```
var processed = rawText
let needsLLM = (config.smartCleanup || config.translationMode != .none) && networkMonitor.isConnected
if needsLLM {
    do {
        processed = try await PostProcessor.process(
            text: rawText,
            cleanup: config.smartCleanup,
            translation: config.translationMode
        )
    } catch {
        // 失败绝不丢弃已识别文本，降级为原文（沿用 H2 的策略）
        processed = rawText
    }
}
let formatted = TextFormatter.format(processed)
```

## 与翻译组合（单次合并调用）

扩展 `PostProcessor.process(text:cleanup:translation:)`：
- 都开 → **一次 LLM 调用**同时整理 + 翻译（system prompt 拼接两段指令），省一次往返。
- 只整理 / 只翻译 → 对应单一指令。
- 都不需要 → 不发起调用，直接返回原文。

## 模型

- 复用 `PostProcessor` 的 LLM 通道（beta.61 已修：模型名按 provider 选）。整理用对话模型：Qwen→`qwen-plus`（要更高质量可 `qwen-max`）、OpenAI 兼容→`gpt-4o-mini` 起。
- **断网自动跳过整理**（`needsLLM` 含 `networkMonitor.isConnected`），回退逐字稿 + 机械格式化；离线 Apple 本地识别天然不整理。

## Prompt 设计要点

System prompt 要点（保留原意、最小改动、只输出结果）：
- 删填充词/助词与重复；合并自我更正，只留最终版；把清单/步骤排成项目符号/编号；修语法、顺语序；贴合原口吻。
- **保守的意图处理**：仅当出现**明确指令**（如"发邮件…/列成要点/改正式/改简短/翻译成…"）时才据此调整；否则全部当内容，**不要把内容误当命令**。
- **邮件意图**：产出适合邮件的润色正文，**不要自动添加称呼/落款**。
- 不臆造事实；拿不准时少改。**只输出整理后的文本**，不要解释。

## UX / 延迟

- 整理期间状态显示「整理中…」（键盘与主 App）。
- 多一次 LLM 调用（叠加翻译时仍是一次但更重）→ 键盘 `Constants.Keyboard.resultTimeout`（现 10s）需上调（建议 ~18–20s）；daemon 侧 ASR 超时也相应留余量。与 review **M4（超时对齐）** 一并考虑。

## 边界与风险

- **意图误判**：靠"仅明确指令才触发 + 保守 prompt"降低；仍是最微妙处，需真机调 prompt。
- **过度编辑/改变原意**：靠"保留原意、最小改动、只输出"约束；用户已确认示例力度合适。
- **成本/延迟**：每段听写一次 LLM。
- **长口述**：Typeless 单次约 6 分钟上限；Vox 长录音另有 M7 风险（整段进内存上传），长文整理/分片不在 v1。

## 测试

- LLM 输出不可确定性测，但可单测：开关 gating、断网跳过、失败回退原文（不丢弃）、`PostProcessor.process` 的 prompt 组装（cleanup/translation 组合）。

## 依赖 / 关联

- 建在 beta.61(review 修复) 的 `PostProcessor`（模型名按 provider）与 H2 "失败不丢结果" 之上。
- 与 review **M4**（超时）相关：本功能会显著拉长单次耗时，超时需统一上调。
