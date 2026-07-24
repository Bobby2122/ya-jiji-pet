#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_NAME="鸭吉吉桌宠.app"
APP_DIR="$PROJECT_DIR/outputs/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$PROJECT_DIR/work/build"
ICONSET_DIR="$BUILD_DIR/DuckPet.iconset"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BUILD_DIR" "$ICONSET_DIR"
mkdir -p "$RESOURCES_DIR/Sprites"

export TMPDIR="$PROJECT_DIR/work/tmp"
export SWIFT_MODULECACHE_PATH="$PROJECT_DIR/work/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/work/clang-module-cache"
mkdir -p "$TMPDIR" "$SWIFT_MODULECACHE_PATH" "$CLANG_MODULE_CACHE_PATH"

swiftc \
  "$PROJECT_DIR/Sources/DuckPet/main.swift" \
  -o "$MACOS_DIR/DuckPet" \
  -framework AppKit \
  -framework ServiceManagement \
  -O

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/assets/sprites/frames/"adult-*.png "$RESOURCES_DIR/Sprites/"
cp "$PROJECT_DIR/assets/sprites/frames/"egg-*-v2.png "$RESOURCES_DIR/Sprites/"

sips -z 16 16 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$PROJECT_DIR/assets/sprites/frames/adult-idle.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
swiftc "$PROJECT_DIR/Tools/make_icns.swift" -o "$BUILD_DIR/make_icns"
"$BUILD_DIR/make_icns" "$ICONSET_DIR" "$RESOURCES_DIR/DuckPet.icns"

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "Built: $APP_DIR"
