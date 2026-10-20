// QEMUBridge.swift
// DroidPhone — Swift wrapper around the QEMU C library (libqemu-ios)

import Foundation
import CoreVideo

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Types
// ─────────────────────────────────────────────────────────────────────────────

enum AndroidKey: UInt32 {
    case home      = 0xAC
    case back      = 0xAB
    case appSwitch = 0xAD
    case power     = 0xA9
    case volumeUp  = 0xA7
    case volumeDown = 0xA8
}

struct QEMUConfig {
    var imagePath:  String
    var ramMB:      Int
    var cpuCores:   Int
    var androidAPI: Int
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - QEMUBridge
// ─────────────────────────────────────────────────────────────────────────────

/// High-level Swift interface to the QEMU emulation engine.
/// The actual QEMU C functions are declared in QEMUBridge.h and linked via libqemu-ios.a
class QEMUBridge {

    // Callback invoked on the main thread each time a new frame is ready
    var onFrameReady: ((CVPixelBuffer) -> Void)?

    private let config: QEMUConfig
    private var running = false
    private var qemuThread: Thread?
    private var pixelBuffer: CVPixelBuffer?

    // Screen resolution passed to QEMU framebuffer
    static let screenWidth  = 1080
    static let screenHeight = 1920

    init(config: QEMUConfig) {
        self.config = config
        setupPixelBuffer()
    }

    // MARK: - Pixel Buffer

    private func setupPixelBuffer() {
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String:           Self.screenWidth,
            kCVPixelBufferHeightKey as String:          Self.screenHeight,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferCreate(kCFAllocatorDefault,
                            Self.screenWidth,
                            Self.screenHeight,
                            kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary,
                            &pixelBuffer)
    }

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }
        running = true

        qemuThread = Thread {
            self.runQEMULoop()
        }
        qemuThread?.name = "com.droidphone.qemu"
        qemuThread?.qualityOfService = .userInteractive
        qemuThread?.start()
    }

    func stop() {
        running = false
        qemu_ios_stop()          // C function from libqemu-ios
    }

    // MARK: - QEMU Main Loop (runs on background thread)

    private func runQEMULoop() {
        // Build QEMU argv
        let argv = buildArgv()
        let cArgv = argv.map { strdup($0) }
        defer { cArgv.forEach { free($0) } }

        // Install our framebuffer callback
        qemu_ios_set_framebuffer_callback { [weak self] (pixels, width, height) in
            self?.handleFrame(pixels: pixels, width: Int(width), height: Int(height))
        }

        // Launch QEMU (blocks until VM exits)
        var cArgs = cArgv.map { Optional($0) }
        qemu_ios_main(Int32(argv.count), &cArgs)
    }

    // MARK: - Argument Builder

    private func buildArgv() -> [String] {
        // Choose machine type based on Android API
        let machine = config.androidAPI >= 29 ? "q35" : "pc-i440fx-2.12"
        let cpu     = "qemu64,+ssse3,+sse4.1,+sse4.2,+x2apic"

        return [
            "qemu-system-x86_64",
            "-machine", machine,
            "-cpu",     cpu,
            "-m",       "\(config.ramMB)",
            "-smp",     "\(min(config.cpuCores, 4))",

            // Use Android-x86 ISO as CD-ROM bootable disk
            "-cdrom",   config.imagePath,
            "-boot",    "d",

            // Persistent data disk (created on first boot)
            "-drive",   "file=\(dataImagePath()),if=virtio,format=qcow2,cache=unsafe",

            // Framebuffer device (our custom iOS display backend)
            "-display", "ios-fb",

            // USB tablet for absolute pointer (touch) events
            "-device",  "usb-ehci",
            "-device",  "usb-tablet",

            // Audio (no-op on iOS for now)
            "-audiodev", "none,id=audio0",

            // Networking via user-mode NAT
            "-netdev",  "user,id=net0",
            "-device",  "virtio-net-pci,netdev=net0",

            // Serial console (for debugging)
            "-serial",  "none",
            "-monitor", "none",

            // No graphical SDL/GTK window — we handle display ourselves
            "-nographic",

            // Enable KVM if entitlement allows (Apple chip only, iOS 16+)
            // "-enable-kvm",   // uncomment if hypervisor entitlement is granted
        ]
    }

    // MARK: - Data Disk

    private func dataImagePath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "android-\(config.androidAPI)-data.qcow2"
        let url  = docs.appendingPathComponent(name)

        if !FileManager.default.fileExists(atPath: url.path) {
            // Create a blank qcow2 data disk on first run
            qemu_ios_create_qcow2(url.path, 8 * 1024 * 1024 * 1024)  // 8 GB
        }
        return url.path
    }

    // MARK: - Frame Handler

    private func handleFrame(pixels: UnsafeRawPointer?, width: Int, height: Int) {
        guard let pixels = pixels, let pb = pixelBuffer else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let srcStride   = width * 4
            // Copy row by row (handles stride differences)
            for row in 0..<min(height, Self.screenHeight) {
                let src = pixels.advanced(by: row * srcStride)
                let dst = base.advanced(by: row * bytesPerRow)
                memcpy(dst, src, min(srcStride, bytesPerRow))
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        DispatchQueue.main.async {
            self.onFrameReady?(pb)
        }
    }

    // MARK: - Input

    func sendPointerEvent(x: Float, y: Float, buttons: UInt32) {
        let absX = UInt32(x * Float(Self.screenWidth))
        let absY = UInt32(y * Float(Self.screenHeight))
        qemu_ios_send_pointer(absX, absY, buttons)
    }

    func sendKey(_ key: AndroidKey) {
        qemu_ios_send_key(key.rawValue, 1)   // press
        qemu_ios_send_key(key.rawValue, 0)   // release
    }
}
