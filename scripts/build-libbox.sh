#!/usr/bin/env bash

# Build the exact public sing-box core used by the iOS release.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/third_party/sing-box/source"
FRAMEWORK_SRC="$SOURCE_DIR/Libbox.xcframework"
FRAMEWORK_DST="$ROOT_DIR/third_party/sing-box/Libbox.xcframework"
SING_BOX_REPOSITORY="https://github.com/SagerNet/sing-box.git"
SING_BOX_COMMIT="0b8995879f29a9b98ee027bc17b75e101445b238"
GOMOBILE_VERSION="v0.1.13"

if [[ -f "$ROOT_DIR/.gitmodules" ]]; then
  git -C "$ROOT_DIR" submodule update --init --recursive third_party/sing-box/source
elif [[ ! -e "$SOURCE_DIR/.git" ]]; then
  git clone "$SING_BOX_REPOSITORY" "$SOURCE_DIR"
fi

cd "$SOURCE_DIR"
git fetch --tags origin
git checkout --detach "$SING_BOX_COMMIT"

actual_commit="$(git rev-parse HEAD)"
if [[ "$actual_commit" != "$SING_BOX_COMMIT" ]]; then
  echo "sing-box commit mismatch: $actual_commit"
  exit 1
fi

go install "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE_VERSION"
go install "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE_VERSION"
export PATH="$(go env GOPATH)/bin:$PATH"
gomobile init
go run ./cmd/internal/build_libbox -target apple -platform ios,iossimulator

if [[ ! -d "$FRAMEWORK_SRC" ]]; then
  echo "Libbox build did not produce $FRAMEWORK_SRC"
  exit 1
fi

if [[ -e "$FRAMEWORK_DST" ]]; then
  mv "$FRAMEWORK_DST" "$FRAMEWORK_DST.backup-$(date +%Y%m%d%H%M%S)"
fi
cp -R "$FRAMEWORK_SRC" "$FRAMEWORK_DST"

echo "Libbox ready: $FRAMEWORK_DST"
