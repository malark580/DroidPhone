// QEMUBridge.h  (also installed as qemu_ios_backend.h inside QEMU source tree)
// DroidPhone — C interface declarations for libqemu-ios

#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Framebuffer callback type
// Called by QEMU each time a full frame is rendered.
// pixels  — pointer to BGRA pixel data
// width   — framebuffer width in pixels
// height  — framebuffer height in pixels
// ─────────────────────────────────────────────────────────────────────────────
typedef void (*qemu_framebuffer_cb)(const void *pixels, uint32_t width, uint32_t height);

// Register the framebuffer callback (must be called before qemu_ios_main)
void qemu_ios_set_framebuffer_callback(qemu_framebuffer_cb cb);

// ─────────────────────────────────────────────────────────────────────────────
// QEMU Main Entry
// Equivalent to qemu-system-x86_64's main(); blocks until VM halts.
// ─────────────────────────────────────────────────────────────────────────────
int qemu_ios_main(int argc, char * _Nullable * _Nullable argv);

// ─────────────────────────────────────────────────────────────────────────────
// VM Control
// ─────────────────────────────────────────────────────────────────────────────
void qemu_ios_stop(void);
void qemu_ios_pause(void);
void qemu_ios_resume(void);

// ─────────────────────────────────────────────────────────────────────────────
// Input Events
// ─────────────────────────────────────────────────────────────────────────────

/// Send an absolute pointer (touch) event.
/// x, y are in screen-space pixels (0..width-1, 0..height-1).
/// buttons: bit 0 = left button (touch down), 0 = release.
void qemu_ios_send_pointer(uint32_t x, uint32_t y, uint32_t buttons);

/// Send a key event.
/// keycode  — Android HID key code
/// down     — 1 = key down, 0 = key up
void qemu_ios_send_key(uint32_t keycode, int down);

// ─────────────────────────────────────────────────────────────────────────────
// Disk Image Utilities
// ─────────────────────────────────────────────────────────────────────────────

/// Create a blank qcow2 disk image at the given path with size bytes capacity.
/// Returns 0 on success, non-zero on error.
int qemu_ios_create_qcow2(const char *path, uint64_t size);

#ifdef __cplusplus
}
#endif
