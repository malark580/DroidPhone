#!/usr/bin/env bash
# scripts/build_qemu_ios.sh
# Build QEMU & Android Emulation Engine for iOS (arm64) — produces libqemu-ios.a
# Must be run on macOS with Xcode installed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/DroidPhone/QEMU/lib"

echo "==> Building QEMU / Android Emulation Engine for iOS (arm64)"
echo "    Repo root : ${REPO_ROOT}"
echo "    Output    : ${OUTPUT_DIR}"

mkdir -p "${OUTPUT_DIR}"

# ── 1. Python dependencies (satisfy distlib / setuptools requirements) ────────
echo "--> Ensuring Python environment and distlib are installed..."
python3 -m pip install --break-system-packages distlib setuptools wheel 2>/dev/null || \
pip3 install --break-system-packages distlib setuptools wheel 2>/dev/null || \
pip install distlib setuptools wheel 2>/dev/null || true

# ── 2. Resolve iOS SDK / Clang Toolchain ──────────────────────────────────────
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"

echo "    iOS SDK   : ${IOS_SDK}"
echo "    Clang     : ${CLANG}"

# ── 3. Compile Android / QEMU Engine for arm64 iOS ────────────────────────────
echo "--> Compiling QEMU emulation backend for arm64-apple-ios14.0..."
"${CLANG}" -c -arch arm64 \
    -isysroot "${IOS_SDK}" \
    -miphoneos-version-min=14.0 \
    -O2 -Wall \
    -I"${REPO_ROOT}/DroidPhone/QEMU" \
    "${REPO_ROOT}/DroidPhone/QEMU/qemu_ios_backend.c" \
    -o "${OUTPUT_DIR}/qemu_ios_backend.o"

# ── 4. Package Static Library (libqemu-ios.a) ────────────────────────────────
echo "--> Packaging libqemu-ios.a static archive..."
libtool -static -o "${OUTPUT_DIR}/libqemu-ios.a" "${OUTPUT_DIR}/qemu_ios_backend.o"

# Clean up object file
rm -f "${OUTPUT_DIR}/qemu_ios_backend.o"

echo ""
echo "✅ Success! libqemu-ios.a is ready:"
ls -lh "${OUTPUT_DIR}/libqemu-ios.a"
xcrun lipo -info "${OUTPUT_DIR}/libqemu-ios.a" || file "${OUTPUT_DIR}/libqemu-ios.a"
