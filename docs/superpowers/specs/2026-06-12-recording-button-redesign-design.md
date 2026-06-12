# 录音按钮重做 — 设计文档（2026-06-12）

## 背景与目标

现状：键盘扩展里的波形是 `KeyboardWaveformView`（`VoxInputKeyboard/KeyboardView.swift`）——程序化 sin/cos 假动画、彩色、与真实声音无关；主 App 用 `WaveformView`（真实电平）。用户反馈：**丑、审美差**。目标是做一个**干净、克制、纯灰阶**的统一录音按钮，"不说话时是一条直线，说话时动起来"，并把按钮自身 + 周围氛围当成一个整体来设计。

## 范围

**In**
- 一个统一的「录音按钮」SwiftUI 组件，键盘扩展与主 App 共用。
- 四个状态的视觉与动画：待命 / 录音 / 识别中 / 完成。
- 替换键盘的 `KeyboardWaveformView`，以及主 App 录音按钮 + 波形区域的视觉。

**Out（本次不做）**
- 不接入真实麦克风电平到键盘（波形是装饰动画，键盘端**不新增 IPC**）。
- 不改录音/IPC/ASR 等后端逻辑。
- 灵动岛 / 画中画 / 智能文本整理是**另外的功能**，各有独立 spec。

## 组件：统一 `RecordButton`

- 一个 SwiftUI 视图，输入一个「阶段」枚举（`idle / recording / processing / done`，可直接映射键盘的 `KeyboardPhase` 和主 App 的 `RecordingState`），自己负责呈现与动画。
- **同一个按钮原地形变**走完四态——不弹出/替换成别的控件，位置不跳（键盘那一行空间紧，按钮一跳就难按）。
- **纯灰阶**，跟随系统深/浅色模式（浅色模式用近黑 `#1c1c1e` 系，深色模式自动取白）。不引入任何彩色。
- **形状 = 圆形**（涟漪向外扩散最自然）。

## 状态机（同一按钮原地形变）

| 阶段 | 呈现 |
|---|---|
| **待命 idle** | 浅色圆（浅灰填充 + 1px 描边）+ 灰色麦克风图标。克制、往后退。键盘中若守护进程休眠，此按钮同时承担"唤醒"点击（沿用现有 `shouldWakeMainApp` 逻辑）。 |
| **录音 recording** | 按钮**墨色加深**（浅→深，纯色过渡）；麦克风图标淡出、**波形淡入**；按钮轻微放大（~1.05）；周围**柔和晕开**：低透明度灰色径向渐变圆，模糊边缘，从按钮向外 scale + fade，多层错时循环（"墨在水里晕开"的感觉，呼吸式）。 |
| **识别中 processing** | 深色按钮 + 三个白点呼吸（错相 `opacity/scale` 脉冲）。 |
| **完成 done** | 深色按钮 + 白色对勾，短暂停留后回到待命。 |

## 动画细节

**波形（直线 ↔ 竖条 的连续过渡）**
- 波形 = 一排**密排的细竖条**（同一批元素始终存在）。
- 静止：所有竖条压扁到极低高度（`scaleY ≈ 0.06`），密排即连成**一条直线**。
- 说话：竖条升起并**错相**上下跳动（每根 `animation-delay` 按下标递增），形成流动波；纯装饰、与录音状态绑定（录音期间一直动），**不反映真实音量**。
- 停止：竖条缓缓压回 → 直线。因为够密，压扁即是干净直线（稀疏竖条压扁是短点，故选密排）。

**晕开 bloom（"扩音感"）**
- 仅录音态出现。淡灰色径向渐变圆（中心 ~15% 透明、向外渐隐），`filter: blur`，从按钮尺寸 `scale → ~2.3` 同时 `opacity → 0`，2.8s 循环，多层（延迟 0 / 0.95s / 1.9s）形成连续一圈圈外散。叠加按钮自身极轻微的"呼吸"光晕。整体**淡**、若隐若现，不抢戏。

## 接入点

- **键盘**：删除/替换 `KeyboardWaveformView`（`VoxInputKeyboard/KeyboardView.swift:215-261`），录音区改用 `RecordButton(phase:)`。`KeyboardPhase`（idle/recording/processing/done/error）映射到组件阶段（error 可暂用 idle 呈现 + 现有错误文案）。保留休眠时的唤醒点击行为。
- **主 App**：`MainView` 的录音按钮 + `WaveformView` 区域改用同一 `RecordButton`，由 `AppState.recordingState` 驱动。
- 组件放在 `Shared/`（两 target 共用）或各自 UI 层引用同一实现；倾向放 `Shared/UI/RecordButton.swift`，注意只用两端都可用的 SwiftUI API。新增文件后需 `xcodegen generate`。

## 行为与约束

- 装饰动画随阶段开/关，**不新增 App Group IPC**（符合用户选择）。
- 灰阶、跟随深浅色，无彩色。
- 性能：键盘扩展 ~60MB 预算，动画用 SwiftUI 原生（`TimelineView`/隐式动画）即可，避免持续重布局；沿用 `KeyboardWaveformView` 用 `TimelineView(.animation)` 自驱动以防"杀后台后冻结"（beta.58 的经验）。

## 未决 / 未来增强

- **主 App 真实电平（可选）**：主 App 本就有 `AudioRecorder.levelHistory`，将来可让主 App 端的波形高度由真实电平驱动（键盘仍装饰）。本次不做，保持两端一致的装饰动画。
- 形状若在键盘横条里显挤，可退化为胶囊（容纳更长波形）；当前默认圆形。
