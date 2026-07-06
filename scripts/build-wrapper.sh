#!/usr/bin/env bash
#
# build-wrapper.sh — libcef_dll_wrapper.a (Release, arm64) 를 CMake/Ninja 로 빌드.
# fetch-cef.sh 이후 실행. Xcode 메인/헬퍼 타겟이 이 정적 라이브러리에 링크한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CEF_ROOT="${ROOT_DIR}/ThirdParty/CEF/current"

if [[ ! -d "${CEF_ROOT}" ]]; then
  echo "error: ${CEF_ROOT} 없음 — 먼저 scripts/fetch-cef.sh 실행" >&2
  exit 1
fi

BUILD_DIR="${CEF_ROOT}/build_wrapper"
ART="${BUILD_DIR}/libcef_dll_wrapper/libcef_dll_wrapper.a"

if [[ -f "${ART}" ]]; then
  echo "==> wrapper 이미 빌드됨: ${ART}"
  exit 0
fi

command -v cmake >/dev/null || { echo "error: cmake 필요 (brew install cmake)" >&2; exit 1; }
command -v ninja >/dev/null || { echo "error: ninja 필요 (brew install ninja)" >&2; exit 1; }

mkdir -p "${BUILD_DIR}"
( cd "${BUILD_DIR}" && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 .. && ninja libcef_dll_wrapper )

echo "==> wrapper 빌드 완료: ${ART}"
