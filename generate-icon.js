// generate-icon.js
// beta.58: 绝对居中、深邃纯黑背景、Apple 官方风格极简麦克风图标
// 所有元素数学中心对齐于 (512, 512)，无 alpha 通道

const sharp = require('sharp');
const path = require('path');

const ICON_DIR = path.join(__dirname, 'VoxInput/Assets.xcassets/AppIcon.appiconset');

async function generate() {
    // 所有坐标基于 1024x1024 画布
    // 光学居中修正：capsule 是视觉重量最大的部分，需要将整体
    // 包围盒的几何中心略微下移 30px 来补偿光学重心偏上
    //
    // 组件尺寸（自上而下）：
    //   capsule: 高 260, 宽 150, rx=75
    //   U弧: 弧底比 capsule 底再低 ~100
    //   竖杆: 高 80
    //   底座: 高 28
    //   总高 ≈ 468
    //
    // 几何居中 top = (1024-468)/2 = 278
    // 光学修正 +15 → top = 293（在几何中心和光学中心之间取平衡）
    //
    // capsule: top=293, bottom=553
    // U弧起点 y=503, 弧底 y=653
    // 竖杆: 653-733
    // 底座: 733-761
    // 几何中心 = 293 + 234 = 527（比 512 略低，光学修正到位）

    const svg = `<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <!-- 深邃纯黑背景 -->
  <rect width="1024" height="1024" fill="#0A0A0A"/>

  <!-- 微妙的径向渐变，增加层次和深度 -->
  <defs>
    <radialGradient id="glow" cx="50%" cy="50%" r="40%">
      <stop offset="0%" stop-color="#161618"/>
      <stop offset="100%" stop-color="#0A0A0A"/>
    </radialGradient>
  </defs>
  <circle cx="512" cy="512" r="410" fill="url(#glow)"/>

  <!-- 麦克风头部 capsule: 150w x 260h, cx=512 -->
  <rect x="437" y="293" width="150" height="260" rx="75" ry="75" fill="#E5E5EA"/>

  <!-- U 型支架弧线 -->
  <path d="M367 503 Q367 653 512 653 Q657 653 657 503"
        fill="none" stroke="#E5E5EA" stroke-width="30" stroke-linecap="round"/>

  <!-- 竖直支柱 -->
  <rect x="497" y="653" width="30" height="80" rx="15" fill="#E5E5EA"/>

  <!-- 底座 -->
  <rect x="432" y="733" width="160" height="28" rx="14" fill="#E5E5EA"/>
</svg>`;

    // 必须匹配 Contents.json 中的文件名
    const sizes = [
        { name: 'Icon-iphone-20x20@2x.png', size: 40 },
        { name: 'Icon-iphone-20x20@3x.png', size: 60 },
        { name: 'Icon-iphone-29x29@2x.png', size: 58 },
        { name: 'Icon-iphone-29x29@3x.png', size: 87 },
        { name: 'Icon-iphone-40x40@2x.png', size: 80 },
        { name: 'Icon-iphone-40x40@3x.png', size: 120 },
        { name: 'Icon-iphone-60x60@2x.png', size: 120 },
        { name: 'Icon-iphone-60x60@3x.png', size: 180 },
        { name: 'Icon-ipad-20x20@1x.png', size: 20 },
        { name: 'Icon-ipad-20x20@2x.png', size: 40 },
        { name: 'Icon-ipad-29x29@1x.png', size: 29 },
        { name: 'Icon-ipad-29x29@2x.png', size: 58 },
        { name: 'Icon-ipad-40x40@1x.png', size: 40 },
        { name: 'Icon-ipad-40x40@2x.png', size: 80 },
        { name: 'Icon-ipad-76x76@1x.png', size: 76 },
        { name: 'Icon-ipad-76x76@2x.png', size: 152 },
        { name: 'Icon-ipad-83_5x83_5@2x.png', size: 167 },
        { name: 'Icon-AppStore-1024.png', size: 1024 },
    ];

    for (const s of sizes) {
        await sharp(Buffer.from(svg))
            .resize(s.size, s.size)
            .removeAlpha()
            .png({ force: true })
            .toFile(path.join(ICON_DIR, s.name));
        console.log(`✅ ${s.name} (${s.size}x${s.size})`);
    }

    console.log(`\n🎉 All ${sizes.length} icons generated in ${ICON_DIR}`);
}

generate().catch(err => {
    console.error('❌ Icon generation failed:', err);
    process.exit(1);
});
