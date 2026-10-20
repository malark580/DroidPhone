#!/usr/bin/env bash
# scripts/build_ipa.sh
# Build DroidPhone.ipa for distribution (no-signing / ad-hoc sideloading)

set -euo pipefail

PROJECT="DroidPhone.xcodeproj"
SCHEME="DroidPhone"
ARCHIVE_PATH="build/DroidPhone.xcarchive"
EXPORT_PATH="build/ipa"

echo "==> Building DroidPhone IPA"

# ── Ensure libqemu-ios.a exists ───────────────────────────────────────────────
if [ ! -f "DroidPhone/QEMU/lib/libqemu-ios.a" ]; then
    echo "--> libqemu-ios.a not found; building engine library first..."
    ./scripts/build_qemu_ios.sh
fi

# ── Archive ───────────────────────────────────────────────────────────────────
echo "--> Creating Xcode Archive..."
xcodebuild archive \
    -project "${PROJECT}" \
    -scheme  "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=iOS" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | xcbeautify || true

# ── Export IPA (Payload zip packaging for AltStore/TrollStore/Sideloadly) ──────
echo "--> Packaging IPA for sideloading..."
rm -rf "${EXPORT_PATH}"
mkdir -p "${EXPORT_PATH}/Payload"

APP_PATH=$(find "${ARCHIVE_PATH}/Products/Applications" -name "*.app" -maxdepth 1 | head -n 1)
if [ -z "${APP_PATH}" ]; then
    echo "❌ Error: Could not locate built .app bundle in ${ARCHIVE_PATH}"
    exit 1
fi

echo "    Copying ${APP_PATH} -> ${EXPORT_PATH}/Payload/"
cp -r "${APP_PATH}" "${EXPORT_PATH}/Payload/"

cd "${EXPORT_PATH}"
zip -qry "DroidPhone.ipa" Payload
rm -rf Payload

echo ""
echo "✅ IPA created successfully:"
ls -lh "DroidPhone.ipa"
