#!/usr/bin/env bash
# scripts/build_qemu_ios.sh
# Build QEMU 8.2.0 for iOS (arm64) — produces libqemu-ios.a
# Must be run on macOS with Xcode installed.

set -euo pipefail

QEMU_VERSION="8.2.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QEMU_SRC_DIR="${REPO_ROOT}/build/qemu-${QEMU_VERSION}"
OUTPUT_DIR="${REPO_ROOT}/DroidPhone/QEMU/lib"
PATCH_DIR="${REPO_ROOT}/scripts/patches"

echo "==> Building QEMU ${QEMU_VERSION} for iOS (arm64)"
echo "    Repo root : ${REPO_ROOT}"
echo "    Output    : ${OUTPUT_DIR}"

# ── 1. Dependencies ──────────────────────────────────────────────────────────
echo "--> Installing build dependencies via Homebrew..."
brew install ninja pixman glib pkg-config meson || true

# ── 2. Resolve iOS SDK / toolchain ───────────────────────────────────────────
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
HOST_CLANG="$(xcrun --find clang)"

echo "    iOS SDK   : ${IOS_SDK}"
echo "    Clang     : ${CLANG}"

# ── 3. Download QEMU source ───────────────────────────────────────────────────
mkdir -p "${REPO_ROOT}/build"
if [ ! -d "${QEMU_SRC_DIR}" ]; then
    echo "--> Downloading QEMU ${QEMU_VERSION}..."
    curl -fL "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz" \
         -o "${REPO_ROOT}/build/qemu-${QEMU_VERSION}.tar.xz"
    tar -xf "${REPO_ROOT}/build/qemu-${QEMU_VERSION}.tar.xz" -C "${REPO_ROOT}/build"
fi

cd "${QEMU_SRC_DIR}"

# ── 4. Apply iOS patches ──────────────────────────────────────────────────────
echo "--> Applying iOS patches..."
for PATCH in "${PATCH_DIR}"/00*.patch; do
    echo "    Applying: $(basename "${PATCH}")"
    patch -p1 --forward --reject-file=- < "${PATCH}" || {
        echo "    (patch already applied or not applicable — continuing)"
    }
done

# Copy our backend source into QEMU source tree so it builds together
cp "${REPO_ROOT}/DroidPhone/QEMU/qemu_ios_backend.c" "${QEMU_SRC_DIR}/ui/"
cp "${REPO_ROOT}/DroidPhone/QEMU/QEMUBridge.h"       "${QEMU_SRC_DIR}/ui/qemu_ios_backend.h"

# ── 5. Configure (meson-based, QEMU >= 7.x) ─────────────────────────────────
echo "--> Configuring QEMU..."
BUILD_DIR="${QEMU_SRC_DIR}/build-ios"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# QEMU uses meson under the hood; pass cross-compile flags via env vars
export CC="${CLANG}"
export OBJC="${CLANG}"
export PKG_CONFIG_PATH="$(brew --prefix)/lib/pkgconfig"

# Cross-compile flags for arm64-apple-ios14
IOS_CFLAGS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=14.0 -DIOS_BUILD -fembed-bitcode-marker"
IOS_LDFLAGS="-arch arm64 -isysroot ${IOS_SDK}"

export CFLAGS="${IOS_CFLAGS}"
export LDFLAGS="${IOS_LDFLAGS}"
export OBJCFLAGS="${IOS_CFLAGS}"

# QEMU's configure script (wrapper around meson)
./configure \
    --target-list="x86_64-softmmu" \
    --host-cc="${HOST_CLANG}" \
    --cc="${CLANG}" \
    --objcc="${CLANG}" \
    --extra-cflags="${IOS_CFLAGS}" \
    --extra-ldflags="${IOS_LDFLAGS}" \
    --disable-cocoa \
    --disable-sdl \
    --disable-gtk \
    --disable-vnc \
    --disable-curses \
    --disable-kvm \
    --disable-hvf \
    --disable-werror \
    --disable-debug-info \
    --enable-tcg \
    --static \
    --prefix="${OUTPUT_DIR}" \
    2>&1 | tee "${REPO_ROOT}/build/configure.log"

# ── 6. Build ──────────────────────────────────────────────────────────────────
echo "--> Building QEMU ($(sysctl -n hw.logicalcpu) cores)..."
cd "${BUILD_DIR}"
ninja -j"$(sysctl -n hw.logicalcpu)" 2>&1 | tee "${REPO_ROOT}/build/build.log"

# ── 7. Install ────────────────────────────────────────────────────────────────
echo "--> Installing to ${OUTPUT_DIR}..."
mkdir -p "${OUTPUT_DIR}"
ninja install

# ── 8. Combine into single static library ────────────────────────────────────
echo "--> Combining into libqemu-ios.a..."
ALL_LIBS=$(find "${OUTPUT_DIR}" -name "*.a" | tr '\n' ' ')
if [ -n "${ALL_LIBS}" ]; then
    # shellcheck disable=SC2086
    libtool -static -o "${OUTPUT_DIR}/libqemu-ios.a" ${ALL_LIBS}
    echo "✅ Done! libqemu-ios.a → ${OUTPUT_DIR}/libqemu-ios.a"
    ls -lh "${OUTPUT_DIR}/libqemu-ios.a"
else
    echo "⚠️  No .a files found — check build.log"
    exit 1
fi
