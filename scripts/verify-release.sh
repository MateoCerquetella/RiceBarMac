#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/RiceBarMac.app" >&2
  exit 1
fi

app_path="$1"
if [[ ! -d "${app_path}" ]]; then
  echo "Application bundle not found: ${app_path}" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${app_path}" EXPECTED_TAG="${EXPECTED_TAG:-}" "${script_dir}/verify-version.sh"

architectures="$(lipo -archs "${app_path}/Contents/MacOS/RiceBarMac")"
for required_architecture in arm64 x86_64; do
  if [[ " ${architectures} " != *" ${required_architecture} "* ]]; then
    echo "Missing ${required_architecture} slice: ${architectures}" >&2
    exit 1
  fi
done

codesign --verify --deep --strict --verbose=2 "${app_path}"
signature_details="$(codesign --display --verbose=4 "${app_path}" 2>&1)"
grep -Fq 'Authority=Developer ID Application:' <<<"${signature_details}"
grep -Eq 'flags=.*runtime' <<<"${signature_details}"

entitlements_file="$(mktemp -t ricebarmac-entitlements).plist"
trap 'rm -f "${entitlements_file}"' EXIT
codesign --display --entitlements :- "${app_path}" >"${entitlements_file}" 2>/dev/null
plutil -lint "${entitlements_file}"
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${entitlements_file}" >/dev/null 2>&1; then
  sandbox_value="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${entitlements_file}")"
  if [[ "${sandbox_value}" == "true" ]]; then
    echo "Release unexpectedly enables App Sandbox" >&2
    exit 1
  fi
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "${entitlements_file}" >/dev/null 2>&1; then
  get_task_allow="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "${entitlements_file}")"
  if [[ "${get_task_allow}" == "true" ]]; then
    echo "Release unexpectedly enables get-task-allow" >&2
    exit 1
  fi
fi

xcrun stapler validate "${app_path}"
spctl --assess --type execute --verbose=4 "${app_path}"

echo "Release verified: architectures=${architectures}, signature=Developer ID, hardened runtime, stapled notarization, Gatekeeper accepted"
