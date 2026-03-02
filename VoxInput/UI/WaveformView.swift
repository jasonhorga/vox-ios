// WaveformView.swift
// VoxInput
//
// 录音波形可视化：SwiftUI Canvas + TimelineView

import SwiftUI

/// 录音波形视图
/// 使用 TimelineView 驱动动画，Canvas 绘制波形条
struct WaveformView: View {
    
    /// 音频电平历史数据（0.0 ~ 1.0）
    let levels: [Float]
    
    /// 是否正在录音
    let isRecording: Bool
    
    /// 波形条颜色
    var barColor: Color = .red
    
    /// 波形条数量
    private let barCount = Constants.UI.waveformSampleCount
    
    /// 波形条最小高度比例
    private let minBarHeight: CGFloat = 0.05
    
    /// 波形条间距
    private let barSpacing: CGFloat = 2
    
    /// 波形条圆角
    private let barCornerRadius: CGFloat = 2
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isRecording)) { _ in
            Canvas { context, size in
                drawWaveform(context: context, size: size)
            }
        }
        .frame(height: 60)
    }
    
    // MARK: - 绘制
    
    /// 绘制波形
    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let totalBars = barCount
        let availableWidth = size.width - CGFloat(totalBars - 1) * barSpacing
        let barWidth = max(availableWidth / CGFloat(totalBars), 1)
        let maxHeight = size.height
        let centerY = size.height / 2
        
        for i in 0..<totalBars {
            // 获取对应位置的电平值
            let level: CGFloat
            if i < levels.count {
                level = CGFloat(levels[i])
            } else {
                level = 0
            }
            
            // 计算波形条高度（最小高度 + 电平驱动高度）
            let barHeight = max(maxHeight * minBarHeight, maxHeight * level)
            
            // 计算位置
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = centerY - barHeight / 2
            
            // 绘制圆角矩形
            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: barCornerRadius)
            
            // 根据电平设置透明度
            let opacity = isRecording ? (0.3 + 0.7 * Double(level)) : 0.2
            context.fill(path, with: .color(barColor.opacity(opacity)))
        }
    }
}

// MARK: - 预览

#Preview("录音中") {
    WaveformView(
        levels: (0..<40).map { _ in Float.random(in: 0...1) },
        isRecording: true
    )
    .padding()
}

#Preview("空闲") {
    WaveformView(
        levels: [],
        isRecording: false
    )
    .padding()
}
