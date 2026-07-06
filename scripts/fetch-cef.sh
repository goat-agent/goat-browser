#!/usr/bin/env bash
#
# fetch-cef.sh — 고정 버전 CEF Standard 배포(macOS ARM64)를 다운로드/검증/배치.
#
# - 버전은 scripts/cef-version.txt 에 고정(재현성).
# - Spotify CDN 에서 standard 배포(.tar.bz2)와 .sha1 을 받아 해시 검증.
# - 압축 해제 후 ThirdParty/CEF/current 로 심볼릭(고정 경로)으로 노출.
#
# Standard 배포를 쓰는 이유: cefclient 샘플 소스와 libcef_dll_wrapper 소스가
# 들어있어야 부트스트랩 포팅 / wrapper 빌드가 가능. (minimal 엔 둘 다 없음.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CEF_DIR="${ROOT_DIR}/ThirdParty/CEF"
PLATFORM="macosarm64"
CDN="https://cef-builds.spotifycdn.com"

VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/cef-version.txt")"
if [[ -z "${VERSION}" ]]; then
  echo "error: scripts/cef-version.txt 가 비어있음" >&2
  exit 1
fi

# CDN 파일명은 '+' 를 '%2B' 로 URL 인코딩해야 함.
ARCHIVE="cef_binary_${VERSION}_${PLATFORM}.tar.bz2"
ARCHIVE_URL_ENCODED="$(printf '%s' "${ARCHIVE}" | sed 's/+/%2B/g')"
URL="${CDN}/${ARCHIVE_URL_ENCODED}"

EXTRACT_NAME="cef_binary_${VERSION}_${PLATFORM}"
DEST="${CEF_DIR}/${EXTRACT_NAME}"

echo "==> CEF ${VERSION} (${PLATFORM}, standard)"

if [[ -d "${DEST}" ]]; then
  echo "    이미 존재: ${DEST}"
else
  mkdir -p "${CEF_DIR}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT

  echo "==> 다운로드: ${URL}"
  curl -fSL --retry 3 -o "${TMP}/${ARCHIVE}" "${URL}"

  echo "==> sha1 다운로드/검증"
  curl -fSL --retry 3 -o "${TMP}/${ARCHIVE}.sha1" "${URL}.sha1"
  EXPECTED="$(tr -d '[:space:]' < "${TMP}/${ARCHIVE}.sha1")"
  ACTUAL="$(shasum -a 1 "${TMP}/${ARCHIVE}" | awk '{print $1}')"
  if [[ "${EXPECTED}" != "${ACTUAL}" ]]; then
    echo "error: sha1 불일치" >&2
    echo "  expected: ${EXPECTED}" >&2
    echo "  actual:   ${ACTUAL}" >&2
    exit 1
  fi
  echo "    sha1 OK: ${ACTUAL}"

  echo "==> 압축 해제"
  tar -xjf "${TMP}/${ARCHIVE}" -C "${CEF_DIR}"
  if [[ ! -d "${DEST}" ]]; then
    echo "error: 압축 해제 후 ${DEST} 없음" >&2
    exit 1
  fi
fi

# 고정 경로 ThirdParty/CEF/current 로 노출 (project.yml/스크립트가 참조).
ln -sfn "${EXTRACT_NAME}" "${CEF_DIR}/current"
echo "==> 준비 완료: ${CEF_DIR}/current -> ${EXTRACT_NAME}"
echo "    framework: $(ls -d "${DEST}/Release/Chromium Embedded Framework.framework" 2>/dev/null || echo '(빌드 후 생성)')"
