# 📱 DroidPhone — Android Emulator for iPhone

Run **Android 4 through 11** on your iPhone using QEMU hardware emulation, packaged as a native iOS app.

> **No jailbreak required** — sideload via AltStore / Sideloadly or TrollStore (iOS 14–16).

---

## Features

- 🤖 Android 4.4 (KitKat) → Android 11 (R) support  
- ⚡ QEMU-based hardware-level ARM/x86 emulation  
- 🖥️ Full touch input forwarding to Android  
- 💾 Persistent disk images (survives reboots)  
- 📦 Pre-bundled Android-x86 images (auto-downloaded at first launch)  
- 🔊 Audio, camera, and network (Wi-Fi bridge) support  
- 🎨 Native SwiftUI interface  

## Architecture

```
┌────────────────────────────────────────┐
│             iPhone (iOS App)            │
│  ┌──────────────────────────────────┐  │
│  │     SwiftUI + UIKit Frontend     │  │
│  ├──────────────────────────────────┤  │
│  │       QEMUBridge (Swift)         │  │
│  ├──────────────────────────────────┤  │
│  │   libqemu-arm / libqemu-x86_64   │  │
│  ├──────────────────────────────────┤  │
│  │   Android-x86 System Image       │  │
│  │  (Android 4.4 / 7.1 / 9 / 11)   │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

## Installation

### Pre-built IPA (Recommended)
1. Go to **[Releases](../../releases)** and download the latest `DroidPhone.ipa`
2. Sideload with **AltStore**, **Sideloadly**, or **TrollStore**
3. On first launch, choose your Android version and download the image

### Build from Source
Requires macOS with Xcode 14+. See [BUILD.md](BUILD.md).

## Android Version Support

| Version | API Level | Codename | Status |
|---------|-----------|----------|--------|
| 4.4     | 19        | KitKat   | ✅ Stable |
| 5.1     | 22        | Lollipop | ✅ Stable |
| 6.0     | 23        | Marshmallow | ✅ Stable |
| 7.1     | 25        | Nougat   | ✅ Stable |
| 8.1     | 27        | Oreo     | ✅ Stable |
| 9.0     | 28        | Pie      | ✅ Stable |
| 10      | 29        | Q        | ✅ Stable |
| 11      | 30        | R        | ✅ Stable |

## How it Works

DroidPhone uses **QEMU** compiled for iOS (ARM64) to emulate an x86_64 PC running **Android-x86** — a port of AOSP that runs natively on x86 hardware/emulators. QEMU translates x86 instructions to ARM64 on the fly via its Tiny Code Generator (TCG).

The QEMU framebuffer output is captured and rendered to a Metal texture at ~30fps. Touch inputs are translated to QEMU USB tablet events.

## Credits

- [QEMU](https://www.qemu.org/) — emulation engine  
- [Android-x86](https://www.android-x86.org/) — Android port  
- [UTM](https://getutm.app/) — inspiration for iOS QEMU packaging  

## License

GPL-2.0 (inherited from QEMU)
