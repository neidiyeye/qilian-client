#!/usr/bin/env bash

# 重新生成 iOS 工程并安装 Flutter 依赖。每次修改 project.yml 后执行。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_DIR="$(cd "$IOS_DIR/../mobile-flutter" && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"

if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "找不到 Flutter，请先将 flutter 加入 PATH，或通过 FLUTTER_BIN 指定可执行文件。"
  exit 1
fi

cd "$FLUTTER_DIR"
"$FLUTTER_BIN" pub get

cd "$IOS_DIR"
xcodegen generate
pod install

echo "Flutter iOS 宿主已生成：$IOS_DIR/LanbridgeIOS.xcworkspace"
