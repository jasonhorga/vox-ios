// RecordButton.swift
// Shared/UI
//
// 统一录音按钮的呈现阶段 + 视图（键盘与主 App 共用）。纯呈现，不含点击逻辑。

import SwiftUI

/// 录音按钮的呈现阶段
enum RecordButtonPhase: Equatable {
    case idle        // 待命：浅色圆 + 麦克风
    case recording   // 录音：墨色 + 波形 + 柔和晕开
    case processing  // 识别中：墨色 + 三点
    case done        // 完成：墨色 + 对勾
}

/// 统一录音按钮：纯灰阶、圆形、同一按钮原地走四态。装饰动画（不接真实电平）。
/// 仅负责呈现；点击/唤醒逻辑由调用方包裹。
struct RecordButton: View {
    let phase: RecordButtonPhase
    var size: CGFloat = 96

    @Environment(\.colorScheme) private var scheme

    private var ink: Color { scheme == .dark ? .white : Color(white: 0.10) }
    private var idleFill: Color { scheme == .dark ? Color(white: 0.22) : Color(white: 0.91) }
    private var activeFill: Color { scheme == .dark ? Color(white: 0.95) : Color(white: 0.09) }
    /// 录音/识别/完成态按钮上的内容色（与 activeFill 反相）
    private var onActive: Color { scheme == .dark ? Color(white: 0.09) : .white }

    var body: some View {
        ZStack {
            if phase == .recording { bloom }
            Circle()
                .fill(phase == .idle ? idleFill : activeFill)
                .frame(width: size, height: size)
                .overlay {
                    if phase == .idle {
                        Circle().strokeBorder(ink.opacity(0.12), lineWidth: 1)
                    }
                }
                .overlay { content }
                .scaleEffect(phase == .recording ? 1.04 : 1.0)
                .shadow(color: .black.opacity(phase == .idle ? 0 : 0.18), radius: 12, y: 6)
        }
        .frame(width: size * 1.9, height: size * 1.9)   // 给 bloom 留扩散空间
        .animation(.easeInOut(duration: 0.35), value: phase)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle: return "录音"
        case .recording: return "录音中，点击结束"
        case .processing: return "识别中"
        case .done: return "完成"
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.34))
                .foregroundStyle(ink.opacity(0.55))
        case .recording:
            waveform
        case .processing:
            dots
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(onActive)
        }
    }

    /// 密排细条波形：TimelineView 自驱动，杀后台重开不冻结（beta.58 经验）
    private var waveform: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<11, id: \.self) { i in
                    Capsule()
                        .fill(onActive)
                        .frame(width: 2.5, height: barHeight(i: i, t: t))
                }
            }
            .frame(height: size * 0.44)
        }
    }

    private func barHeight(i: Int, t: Double) -> CGFloat {
        let maxH = size * 0.44
        let v = sin(t * 6.0 + Double(i) * 0.5) * 0.5 + 0.5   // 0...1
        return max(maxH * 0.18, maxH * CGFloat(0.2 + 0.8 * v))
    }

    /// 识别中：三个白点呼吸
    private var dots: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.08) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(onActive)
                        .frame(width: size * 0.10, height: size * 0.10)
                        .opacity(0.3 + 0.7 * (sin(t * 4.0 + Double(i) * 0.6) * 0.5 + 0.5))
                }
            }
        }
    }

    /// 录音态柔和晕开：低透明灰圆向外 scale + fade，多层错相
    private var bloom: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = ((t / 2.6) + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0) // 0...1
                    Circle()
                        .fill(ink.opacity(0.12 * (1.0 - p)))
                        .frame(width: size, height: size)
                        .scaleEffect(0.6 + 1.7 * p)
                        .blur(radius: 5)
                }
            }
        }
    }
}

#Preview("RecordButton states") {
    VStack(spacing: 28) {
        RecordButton(phase: .idle)
        RecordButton(phase: .recording)
        RecordButton(phase: .processing)
        RecordButton(phase: .done)
    }
    .padding(40)
}
