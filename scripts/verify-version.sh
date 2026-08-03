#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"
project_file="${repo_dir}/project.yml"
plist_file="${repo_dir}/App/Info.plist"

marketing_version="$(awk -F "'" '/MARKETING_VERSION:/ { print $2; exit }' "${project_file}")"
build_number="$(awk -F "'" '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "${project_file}")"

if [[ -z "${marketing_version}" || -z "${build_number}" ]]; then
  echo "Version metadata is missing from project.yml" >&2
  exit 1
fi

grep -Fq '<string>$(MARKETING_VERSION)</string>' "${plist_file}"
grep -Fq '<string>$(CURRENT_PROJECT_VERSION)</string>' "${plist_file}"

if [[ -n "${EXPECTED_TAG:-}" && "${EXPECTED_TAG}" != "v${marketing_version}" ]]; then
  echo "Tag mismatch: expected v${marketing_version}, received ${EXPECTED_TAG}" >&2
  exit 1
fi

if [[ -n "${APP_PATH:-}" ]]; then
  app_plist="${APP_PATH}/Contents/Info.plist"
  if [[ ! -f "${app_plist}" ]]; then
    echo "App Info.plist not found: ${app_plist}" >&2
    exit 1
  fi
  app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_plist}")"
  app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_plist}")"
  if [[ "${app_version}" != "${marketing_version}" || "${app_build}" != "${build_number}" ]]; then
    echo "Bundle mismatch: project=${marketing_version} (${build_number}), app=${app_version} (${app_build})" >&2
    exit 1
  fi
fi

echo "RiceBarMac version verified: ${marketing_version} (${build_number})"
