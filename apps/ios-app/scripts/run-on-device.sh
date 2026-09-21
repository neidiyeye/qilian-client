#!/usr/bin/env bash

set -euo pipefail

# 真机联调默认只允许使用 iPhone SE，避免 Xcode 沿用上次选中的其他设备。
readonly DEFAULT_DEVICE_NAME="iPhone SE"
readonly DEFAULT_DEVICE_UDID="00008030-000E40EC1183802E"

# iPhone 15 Pro Max 被明确排除；只有用户主动指定并开启覆盖开关时才允许使用。
readonly EXCLUDED_DEVICE_NAME="iPhone 15 Pro Max"
readonly EXCLUDED_DEVICE_UDID="00008130-001475D81A90001C"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly IOS_APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT="$(cd "${IOS_APP_DIR}/../.." && pwd)"
readonly DERIVED_DATA_DIR="${REPO_ROOT}/runtime/ios-derived-data"
readonly APP_PATH="${DERIVED_DATA_DIR}/Build/Products/Profile-iphoneos/FireLink.app"
readonly BUNDLE_ID="com.ssyoo.vpn"

device_udid="${DBAO_IOS_DEVICE_UDID:-${DEFAULT_DEVICE_UDID}}"
device_name="${DEFAULT_DEVICE_NAME}"

if [[ "${device_udid}" == "${EXCLUDED_DEVICE_UDID}" ]]; then
  device_name="${EXCLUDED_DEVICE_NAME}"
  if [[ "${DBAO_ALLOW_EXCLUDED_IOS_DEVICE:-0}" != "1" ]]; then
    printf '已拒绝使用排除的测试机：%s (%s)\n' "${device_name}" "${device_udid}" >&2
    printf '只有用户明确要求时，才可设置 DBAO_ALLOW_EXCLUDED_IOS_DEVICE=1 后重试。\n' >&2
    exit 64
  fi
fi

printf '目标测试机：%s (%s)\n' "${device_name}" "${device_udid}"

# devicectl 独立启动 Flutter Debug 包会因缺少 Flutter 调试服务而退出。
# Profile 保留原生 NSLog 和 Tunnel 日志，同时可以像正式 App 一样从桌面独立启动。
# 使用固定 destination 构建，避免依赖 Xcode 图形界面保存的上次运行设备。
xcodebuild \
  -workspace "${IOS_APP_DIR}/LanbridgeIOS.xcworkspace" \
  -scheme Lanbridge \
  -configuration Profile \
  -destination "platform=iOS,id=${device_udid}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  build

# Flutter native assets may be copied into the finished app with an ad-hoc
# signature. iOS devices reject those frameworks even though macOS codesign's
# local deep verification accepts them, so replace only ad-hoc signatures with
# the same Apple Development identity used to sign the containing app.
# Extract the leaf certificate from the already signed app and use its SHA-1
# identity. A keychain can contain multiple renewed certificates with the same
# display name, while the fingerprint always selects the exact build identity.
signing_cert_dir="$(mktemp -d)"
codesign \
  --display \
  --extract-certificates="${signing_cert_dir}/cert" \
  "${APP_PATH}" >/dev/null 2>&1
app_signing_identity="$(
  shasum -a 1 "${signing_cert_dir}/cert0" \
    | awk '{ print toupper($1) }'
)"
rm -rf "${signing_cert_dir}"

if [[ -z "${app_signing_identity}" ]]; then
  printf '无法读取 App 的签名证书，已停止安装。\n' >&2
  exit 65
fi

resigned_native_asset=0
while IFS= read -r framework_path; do
  # Capture the complete output before matching it. With pipefail enabled,
  # grep -q can otherwise close the pipe early and make codesign report SIGPIPE.
  framework_signature="$(codesign --display --verbose=4 "${framework_path}" 2>&1)"
  if grep -q '^Signature=adhoc$' <<<"${framework_signature}"; then
    printf '修复 Flutter 原生组件签名：%s\n' "$(basename "${framework_path}")"
    codesign \
      --force \
      --sign "${app_signing_identity}" \
      --preserve-metadata=identifier,entitlements,flags,runtime \
      "${framework_path}"
    resigned_native_asset=1
  fi
done < <(find "${APP_PATH}/Frameworks" -maxdepth 1 -type d -name '*.framework' -print)

if [[ "${resigned_native_asset}" == "1" ]]; then
  # Updating a nested framework changes the app bundle seal, so refresh the
  # outer signature while preserving the provisioning entitlements.
  codesign \
    --force \
    --sign "${app_signing_identity}" \
    --preserve-metadata=identifier,entitlements,flags,runtime \
    "${APP_PATH}"
fi

# Strict verification catches signature defects before devicectl modifies the
# installed app or leaves an unusable VPN extension on the test device.
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

# devicectl 会在安装完成后直接启动 App，便于收集真机桥接和 Tunnel 日志。
xcrun devicectl device install app --device "${device_udid}" "${APP_PATH}"
xcrun devicectl device process launch --device "${device_udid}" "${BUNDLE_ID}"
