# Building DroidPhone from Source

## Prerequisites

- macOS 12+ (Monterey or later)
- Xcode 14+
- Homebrew
- GitHub CLI (`brew install gh`)

## Step 1 — Clone

```bash
git clone https://github.com/malark580/DroidPhone.git
cd DroidPhone
```

## Step 2 — Build QEMU for iOS

```bash
./scripts/build_qemu_ios.sh
```

This script:
- Downloads QEMU source
- Applies iOS patches (disables JIT, uses TCG only)
- Cross-compiles for `arm64-apple-ios`
- Outputs static libraries to `DroidPhone/QEMU/lib/`

## Step 3 — Open Xcode Project

```bash
open DroidPhone.xcodeproj
```

Set your **Team** and **Bundle ID** in Signing & Capabilities.

## Step 4 — Build & Run

Select your connected iPhone as the target and press ▶.

## Step 5 — (Optional) Create IPA for distribution

```bash
./scripts/build_ipa.sh
```

Output: `build/DroidPhone.ipa`
