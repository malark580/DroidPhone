#!/usr/bin/env bash
# scripts/build_ipa.sh
# Build DroidPhone.ipa for distribution (no-signing / ad-hoc)

set -euo pipefail

PROJECT="DroidPhone.xcodeproj"
SCHEME="DroidPhone"
ARCHIVE_PATH="build/DroidPhone.xcarchive"
EXPORT_PATH="build/ipa"

echo "==> Building DroidPhone IPA"

# ── Archive ───────────────────────────────────────────────────────────────────
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

# ── Export IPA ────────────────────────────────────────────────────────────────
mkdir -p "${EXPORT_PATH}"

# Create export options plist (ad-hoc, no signing)
cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>compileBitcode</key>
    <false/>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath  "${EXPORT_PATH}" \
    -exportOptionsPlist build/ExportOptions.plist \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO

echo ""
echo "✅ IPA → ${EXPORT_PATH}/DroidPhone.ipa"
