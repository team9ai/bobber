#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Bobber Release Build Script
#
# 完整流程：编译 → 组装 .app → Developer ID 签名 → Apple 公证 → 打包 DMG
#
# 用法:
#   ./Scripts/build-release.sh                 # 完整流程（含公证）
#   ./Scripts/build-release.sh --skip-notarize # 跳过公证（本地测试用）
#
# 前置条件:
#   1. 安装 Xcode Command Line Tools (xcode-select --install)
#   2. Keychain 中有 Developer ID 证书（见下方 SIGNING_IDENTITY）
#   3. 已配置公证凭据（见 docs/release.md）
#
# 输出:
#   .build/Bobber.dmg  — 可直接分发给用户的安装包
###############################################################################

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── 配置 ────────────────────────────────────────────────────────────────────
APP_NAME="Bobber"
BUNDLE_DIR="$PROJECT_DIR/.build/$APP_NAME.app"                         # .app 包路径
RELEASE_BINARY="$PROJECT_DIR/.build/arm64-apple-macosx/release/$APP_NAME"  # swift build 输出
DMG_PATH="$PROJECT_DIR/.build/$APP_NAME.dmg"                           # 最终 DMG
ZIP_PATH="$PROJECT_DIR/.build/$APP_NAME-notarize.zip"                  # 公证上传用的临时 zip
SIGNING_IDENTITY="Developer ID Application: WENRUI MA (LVFB9KHUD7)"   # 签名证书
KEYCHAIN_PROFILE="bobber-notarize"  # notarytool 存储的凭据名（见 docs/release.md）
# ────────────────────────────────────────────────────────────────────────────

SKIP_NOTARIZE=false
if [[ "${1:-}" == "--skip-notarize" ]]; then
    SKIP_NOTARIZE=true
fi

echo "=== Bobber Release Build ==="

# ── Step 1: 编译 Release 二进制 ──────────────────────────────────────────────
echo ""
echo "[1/5] Building release binary..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -3

# ── Step 2: 组装 .app Bundle ────────────────────────────────────────────────
# macOS .app 结构:
#   Bobber.app/
#     Contents/
#       Info.plist        ← Resources/Info.plist (版本管理)
#       MacOS/Bobber      ← release 二进制
#       Resources/AppIcon.icns
echo ""
echo "[2/5] Assembling app bundle..."
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
cp "$RELEASE_BINARY" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# ── Step 3: Developer ID 签名 ──────────────────────────────────────────────
# --options runtime: 启用 Hardened Runtime（公证必需）
# --deep: 递归签名所有嵌套内容
echo ""
echo "[3/5] Signing with Developer ID..."
codesign --force --deep --options runtime -s "$SIGNING_IDENTITY" "$BUNDLE_DIR"
codesign -v --deep --strict "$BUNDLE_DIR"
echo "Signature valid."

# ── Step 4: Apple 公证 (Notarization) ──────────────────────────────────────
# 公证后 macOS Gatekeeper 会信任此 app，用户双击即可打开
# staple 将公证票据嵌入 .app，离线也能验证
if [[ "$SKIP_NOTARIZE" == false ]]; then
    echo ""
    echo "[4/5] Submitting for notarization (this may take a few minutes)..."
    rm -f "$ZIP_PATH"
    # notarytool 要求上传 zip 格式
    ditto -c -k --keepParent "$BUNDLE_DIR" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$BUNDLE_DIR"
    rm -f "$ZIP_PATH"  # 清理临时 zip
else
    echo ""
    echo "[4/5] Skipping notarization (--skip-notarize)"
fi

# ── Step 5: 打包 DMG ────────────────────────────────────────────────────────
# 创建包含 .app 和 Applications 快捷方式的 DMG，方便用户拖拽安装
# UDZO: zlib 压缩格式，兼容性最好
echo ""
echo "[5/5] Creating DMG..."
DMG_STAGE="$PROJECT_DIR/.build/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$BUNDLE_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGE"

echo ""
echo "=== Done! ==="
echo "DMG: $DMG_PATH"
echo ""
echo "Distribute this DMG — users can double-click to install."
