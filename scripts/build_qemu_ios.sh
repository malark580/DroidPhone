#!/usr/bin/env bash
# scripts/build_qemu_ios.sh
# Build QEMU for iOS (arm64) — produces libqemu-ios.a
# Must be run on macOS with Xcode installed.

set -euo pipefail

QEMU_VERSION="8.2.0"
QEMU_SRC_DIR="$(pwd)/build/qemu-${QEMU_VERSION}"
OUTPUT_DIR="$(pwd)/DroidPhone/QEMU/lib"
PATCH_DIR="$(pwd)/scripts/patches"

echo "==> Building QEMU ${QEMU_VERSION} for iOS (arm64)"

# ── 1. Dependencies ──────────────────────────────────────────────────────────
echo "--> Installing build dependencies via Homebrew..."
brew install ninja pixman glib pkg-config meson || true

# ── 2. Download QEMU source ───────────────────────────────────────────────────
mkdir -p build
if [ ! -d "${QEMU_SRC_DIR}" ]; then
    echo "--> Downloading QEMU ${QEMU_VERSION}..."
    curl -L "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz" \
         -o "build/qemu-${QEMU_VERSION}.tar.xz"
    tar -xf "build/qemu-${QEMU_VERSION}.tar.xz" -C build
fi

cd "${QEMU_SRC_DIR}"

# ── 3. Apply iOS patches ──────────────────────────────────────────────────────
echo "--> Applying iOS patches..."
# Patch 1: Disable JIT (required — iOS does not allow W^X without entitlement)
patch -p1 < "${PATCH_DIR}/0001-disable-jit-use-tcg.patch" || echo "  (already applied)"
# Patch 2: Add ios-fb display backend
patch -p1 < "${PATCH_DIR}/0002-ios-fb-display.patch"       || echo "  (already applied)"
# Patch 3: Disable POSIX signals that are blocked on iOS
patch -p1 < "${PATCH_DIR}/0003-ios-signal-compat.patch"    || echo "  (already applied)"

# ── 4. Configure ─────────────────────────────────────────────────────────────
echo "--> Configuring QEMU..."
mkdir -p build-ios && cd build-ios

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CLANG=$(xcrun --sdk iphoneos --find clang)

../configure \
    --target-list="x86_64-softmmu" \
    --cross-prefix="" \
    --cc="${CLANG}" \
    --host-cc="$(xcrun --find clang)" \
    --cflags="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=14.0 -DIOS_BUILD" \
    --ldflags="-arch arm64 -isysroot ${IOS_SDK}" \
    --disable-cocoa \
    --disable-sdl \
    --disable-gtk \
    --disable-vnc \
    --disable-curses \
    --disable-kvm \
    --disable-hvf \
    --enable-tcg \
    --static \
    --prefix="${OUTPUT_DIR}"

# ── 5. Build ──────────────────────────────────────────────────────────────────
echo "--> Building (this takes ~15–30 min)..."
ninja -j"$(sysctl -n hw.logicalcpu)"

# ── 6. Install ────────────────────────────────────────────────────────────────
echo "--> Installing to ${OUTPUT_DIR}..."
ninja install

# ── 7. Combine into single static library ────────────────────────────────────
echo "--> Combining into libqemu-ios.a..."
find "${OUTPUT_DIR}" -name "*.a" -exec libtool -static -o "${OUTPUT_DIR}/libqemu-ios.a" {} +

echo ""
echo "✅ Done! libqemu-ios.a → ${OUTPUT_DIR}/libqemu-ios.a"
