#!/usr/bin/env node
/**
 * generate-icon-fix.js
 * 
 * Reads Contents.json, generates correctly-named opaque red icons
 * by resizing the 1024x1024 source icon, and removes old wrongly-named files.
 */

const sharp = require('/usr/local/lib/node_modules/openclaw/node_modules/sharp');
const fs = require('fs');
const path = require('path');

const APPICONSET_DIR = path.join(__dirname, 'VoxInput/Assets.xcassets/AppIcon.appiconset');
const CONTENTS_JSON = path.join(APPICONSET_DIR, 'Contents.json');
const SOURCE_ICON = path.join(APPICONSET_DIR, 'Icon-App-1024x1024@1x.png');

// Read Contents.json
const contents = JSON.parse(fs.readFileSync(CONTENTS_JSON, 'utf8'));
const images = contents.images;

console.log(`Found ${images.length} icon entries in Contents.json`);

// Collect filenames that Contents.json expects
const expectedFilenames = new Set(images.map(img => img.filename).filter(Boolean));

// Generate icons
async function generateIcons() {
  // Verify source icon exists and is opaque
  const srcMeta = await sharp(SOURCE_ICON).metadata();
  console.log(`Source icon: ${srcMeta.width}x${srcMeta.height}, channels=${srcMeta.channels}, hasAlpha=${srcMeta.hasAlpha}`);

  let generated = 0;
  let failed = 0;

  for (const img of images) {
    if (!img.filename || !img.size || !img.scale) {
      console.warn(`Skipping entry without filename/size/scale:`, img);
      continue;
    }

    const sizeStr = img.size; // e.g., "20x20", "83.5x83.5"
    const scaleStr = img.scale; // e.g., "1x", "2x", "3x"

    const baseDim = parseFloat(sizeStr.split('x')[0]);
    const scaleNum = parseInt(scaleStr.replace('x', ''), 10);
    const pixelSize = Math.round(baseDim * scaleNum);

    const destPath = path.join(APPICONSET_DIR, img.filename);

    try {
      await sharp(SOURCE_ICON)
        .resize(pixelSize, pixelSize, { fit: 'fill', kernel: sharp.kernel.lanczos3 })
        .flatten({ background: { r: 255, g: 255, b: 255 } }) // ensure no alpha
        .png({ compressionLevel: 9 })
        .toFile(destPath);

      console.log(`✅ Generated ${img.filename} (${pixelSize}x${pixelSize}px)`);
      generated++;
    } catch (err) {
      console.error(`❌ Failed to generate ${img.filename}:`, err.message);
      failed++;
    }
  }

  // Remove old wrongly-named files (those NOT in Contents.json)
  const allFiles = fs.readdirSync(APPICONSET_DIR);
  const pngFiles = allFiles.filter(f => f.endsWith('.png'));
  
  let removed = 0;
  for (const file of pngFiles) {
    if (!expectedFilenames.has(file)) {
      const filePath = path.join(APPICONSET_DIR, file);
      fs.unlinkSync(filePath);
      console.log(`🗑️  Removed old file: ${file}`);
      removed++;
    }
  }

  console.log(`\nSummary: ${generated} generated, ${failed} failed, ${removed} old files removed`);

  // Verify all expected files exist and are opaque
  console.log('\nVerification:');
  for (const img of images) {
    if (!img.filename) continue;
    const fp = path.join(APPICONSET_DIR, img.filename);
    if (!fs.existsSync(fp)) {
      console.error(`❌ MISSING: ${img.filename}`);
      continue;
    }
    const meta = await sharp(fp).metadata();
    const status = meta.hasAlpha ? '⚠️ HAS ALPHA' : '✅ opaque';
    console.log(`${status} ${img.filename} (${meta.width}x${meta.height})`);
  }
}

generateIcons().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
