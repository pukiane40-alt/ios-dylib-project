#!/usr/bin/env bash
# build.sh — Compile PoolHelperMenu.dylib for ARM64 iOS
#
# Requirements:
#   • macOS host with Xcode Command Line Tools installed
#   • Xcode iPhone SDK (iPhoneOS.sdk)
#
# Usage:
#   chmod +x build.sh
#   ./build.sh
#
# Output:
#   build/PoolHelperMenu.dylib

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
if [ -z "$SDK_PATH" ]; then
    echo "[ERROR] iPhone SDK not found. Make sure Xcode is installed."
    echo "        Run: xcode-select --install"
    exit 1
fi

ARCH="arm64"
MIN_IOS="14.0"
SRC="src/PoolHelperMenu.m"
OUT_DIR="build"
OUT_BIN="$OUT_DIR/PoolHelperMenu.dylib"

mkdir -p "$OUT_DIR"

# ── Compile ───────────────────────────────────────────────────────────────────
echo "[build] Compiling $SRC → $OUT_BIN"
echo "[build] SDK: $SDK_PATH"
echo "[build] Arch: $ARCH  Min iOS: $MIN_IOS"

clang \
    -arch "$ARCH" \
    -isysroot "$SDK_PATH" \
    -miphoneos-version-min="$MIN_IOS" \
    -framework UIKit \
    -framework Foundation \
    -framework QuartzCore \
    -dynamiclib \
    -install_name "@rpath/PoolHelperMenu.dylib" \
    -fmodules \
    -fobjc-arc \
    -O2 \
    -Wall \
    -Wextra \
    -o "$OUT_BIN" \
    "$SRC"

echo "[build] Done → $OUT_BIN"

# Optional: strip debug symbols for a leaner binary
if command -v strip &>/dev/null; then
    strip -x "$OUT_BIN"
    echo "[build] Stripped debug symbols"
fi

echo ""
echo "To load into a target app:"
echo "  1. Copy PoolHelperMenu.dylib to your app bundle's Frameworks/ folder."
echo "  2. Add it under Link Binary With Libraries AND Embed Frameworks."
echo "  3. The overlay initialises automatically when the dylib loads."
