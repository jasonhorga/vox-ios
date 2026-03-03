#!/bin/bash
set -euo pipefail

echo "=== Vox Input 项目配置 ==="
echo ""

# 检查 xcodegen 是否安装
if ! command -v xcodegen &> /dev/null; then
    echo "❌ 未检测到 xcodegen，请先安装："
    echo ""
    echo "   brew install xcodegen"
    echo ""
    echo "安装完成后重新运行此脚本。"
    exit 1
fi

echo "✅ 检测到 xcodegen: $(xcodegen --version)"
echo ""

# 运行 xcodegen 生成 .xcodeproj
echo "🔧 正在生成 Xcode 项目..."
xcodegen generate

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ VoxInput.xcodeproj 已成功生成！"
    echo ""
    echo "=== 后续步骤 ==="
    echo ""
    echo "1. 打开项目:"
    echo "   open VoxInput.xcodeproj"
    echo ""
    echo "2. 在 Xcode 中配置 Signing:"
    echo "   - 选择 VoxInput target → Signing & Capabilities"
    echo "   - 选择你的 Team（开发者账号）"
    echo "   - 对 VoxInputKeyboard target 重复以上操作"
    echo ""
    echo "3. 连接 iPhone 并运行（键盘扩展需要真机测试）"
    echo ""
else
    echo ""
    echo "❌ xcodegen 生成失败，请检查 project.yml 配置。"
    exit 1
fi
