#!/usr/bin/env bash

set -euo pipefail

# Ad Hoc 真机包默认只允许安装到 iPhone SE，避免误用其他已注册设备。
readonly DEFAULT_DEVICE_NAME="iPhone SE"
readonly DEFAULT_DEVICE_UDID="00008030-000E40EC1183802E"

# iPhone 15 Pro Max 被明确排除，只有用户主动要求时才能开启覆盖开关。
readonly EXCLUDED_DEVICE_NAME="iPhone 15 Pro Max"
readonly EXCLUDED_DEVICE_UDID="00008130-001475D81A90001C"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly IOS_APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT="$(cd "${IOS_APP_DIR}/../.." && pwd)"
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

# 每次生成独立产物目录，不复用旧 IPA 或解包目录，避免残留签名混入新包。
readonly RUN_ID="$(date '+%Y%m%d-%H%M%S')"
readonly OUTPUT_DIR="${REPO_ROOT}/runtime/ios-ad-hoc/${RUN_ID}"
readonly ARCHIVE_PATH="${OUTPUT_DIR}/Lanbridge.xcarchive"
readonly EXPORT_DIR="${OUTPUT_DIR}/export"
readonly UNPACK_DIR="${OUTPUT_DIR}/unpacked"

printf '目标测试机：%s (%s)\n' "${device_name}" "${device_udid}"
printf '开始生成 Ad Hoc 真机包。\n'

# Archive 使用自动签名，允许 Xcode 更新主 App 与 Tunnel Extension 的签名资源。
xcodebuild \
  -workspace "${IOS_APP_DIR}/LanbridgeIOS.xcworkspace" \
  -scheme Lanbridge \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE_PATH}" \
  -allowProvisioningUpdates \
  archive

# release-testing 是新版 Xcode 对 Ad Hoc 分发方式的名称。
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${IOS_APP_DIR}/ExportOptions.release-testing.plist" \
  -allowProvisioningUpdates

ipa_path="$(find "${EXPORT_DIR}" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
if [[ -z "${ipa_path}" ]]; then
  printf 'Ad Hoc 导出完成，但没有找到 IPA。\n' >&2
  exit 65
fi

# devicectl 接收 .app，因此先解开 IPA，再安装并启动签名后的 App Bundle。
mkdir -p "${UNPACK_DIR}"
ditto -x -k "${ipa_path}" "${UNPACK_DIR}"
app_path="$(find "${UNPACK_DIR}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "${app_path}" ]]; then
  printf 'IPA 中没有找到可安装的 App Bundle。\n' >&2
  exit 66
fi

xcrun devicectl device install app --device "${device_udid}" "${app_path}"
xcrun devicectl device process launch --device "${device_udid}" "${BUNDLE_ID}"

printf 'Ad Hoc 真机包已安装并启动：%s\n' "${app_path}"
