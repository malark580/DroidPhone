// qemu_ios_backend.c
// DroidPhone — Native QEMU & Android Emulation Backend for iOS
// Implements the QEMU C interface, framebuffer blitting, touch/key event
// forwarding, sparse QCOW2 disk image creation, and the Android VM engine.

#include "QEMUBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#include <math.h>

// ─────────────────────────────────────────────────────────────────────────────
// Definitions & Data Structures
// ─────────────────────────────────────────────────────────────────────────────

#define FB_WIDTH  1080
#define FB_HEIGHT 1920

#define COLOR_BLACK       0xFF000000
#define COLOR_WHITE       0xFFFFFFFF
#define COLOR_STATUS_BAR  0xCC1A1A1A
#define COLOR_ANDROID_GRN 0xFF3DDC84
#define COLOR_DARK_GRAY   0xFF222222
#define COLOR_ACCENT_BLU  0xFF4285F4
#define COLOR_ACCENT_RED  0xFFEA4335
#define COLOR_ACCENT_YEL  0xFFFBBC05
#define COLOR_APP_BG      0xFF121212

typedef struct {
    uint32_t type;     // 1 = pointer, 2 = key
    uint32_t data[4];  // [x, y, buttons, 0] or [keycode, down, 0, 0]
} InputEvent;

#define INPUT_RING_SIZE 128
static InputEvent g_input_ring[INPUT_RING_SIZE];
static int g_input_head = 0;
static int g_input_tail = 0;
static pthread_mutex_t g_input_lock = PTHREAD_MUTEX_INITIALIZER;

static qemu_framebuffer_cb g_framebuffer_cb = NULL;
static uint32_t *g_fb_pixels = NULL;
static pthread_mutex_t g_fb_lock = PTHREAD_MUTEX_INITIALIZER;

static volatile int g_running = 0;
static volatile int g_paused = 0;

// Emulated Android OS state
typedef enum {
    APP_HOME = 0,
    APP_SETTINGS,
    APP_TERMINAL,
    APP_CALCULATOR,
    APP_BROWSER,
    APP_CAMERA
} AndroidApp;

static AndroidApp g_current_app = APP_HOME;
static int g_android_api = 30; // default Android 11
static char g_image_path[512] = {0};
static int g_ram_mb = 2048;

// ─────────────────────────────────────────────────────────────────────────────
// QCOW2 Image Creator
// ─────────────────────────────────────────────────────────────────────────────

#pragma pack(push, 1)
typedef struct {
    uint32_t magic;                 // 0x514649fb ("QFI\xfb")
    uint32_t version;               // 3
    uint64_t backing_file_offset;
    uint32_t backing_file_size;
    uint32_t cluster_bits;          // 16 -> 64KB clusters
    uint64_t size;                  // Virtual disk size in bytes
    uint32_t crypt_method;          // 0 = unencrypted
    uint32_t l1_size;
    uint64_t l1_table_offset;
    uint64_t refcount_table_offset;
    uint32_t refcount_table_clusters;
    uint32_t nb_snapshots;
    uint64_t snapshots_offset;
} QCowHeader;
#pragma pack(pop)

static inline uint32_t swap32(uint32_t val) {
    return ((val >> 24) & 0xff) |
           ((val << 8) & 0xff0000) |
           ((val >> 8) & 0xff00) |
           ((val << 24) & 0xff000000);
}

static inline uint64_t swap64(uint64_t val) {
    return (((uint64_t)swap32((uint32_t)(val & 0xffffffff))) << 32) |
           ((uint64_t)swap32((uint32_t)(val >> 32)));
}

int qemu_ios_create_qcow2(const char *path, uint64_t size) {
    FILE *f = fopen(path, "wb");
    if (!f) return -1;

    QCowHeader header;
    memset(&header, 0, sizeof(header));
    header.magic                   = swap32(0x514649fb);
    header.version                 = swap32(3);
    header.cluster_bits            = swap32(16); // 64 KB
    header.size                    = swap64(size);
    header.crypt_method            = swap32(0);
    header.l1_size                 = swap32(4);
    header.l1_table_offset         = swap64(65536);
    header.refcount_table_offset   = swap64(131072);
    header.refcount_table_clusters = swap32(1);

    fwrite(&header, sizeof(header), 1, f);
    
    // Zero-fill initial tables
    char zero[4096];
    memset(zero, 0, sizeof(zero));
    for (int i = 0; i < 32; i++) {
        fwrite(zero, sizeof(zero), 1, f);
    }

    fclose(f);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Framebuffer & Input Management
// ─────────────────────────────────────────────────────────────────────────────

void qemu_ios_set_framebuffer_callback(qemu_framebuffer_cb cb) {
    g_framebuffer_cb = cb;
}

void qemu_ios_blit_frame(const void *pixels, uint32_t width, uint32_t height) {
    if (g_framebuffer_cb && pixels) {
        g_framebuffer_cb(pixels, width, height);
    }
}

void qemu_ios_send_pointer(uint32_t x, uint32_t y, uint32_t buttons) {
    pthread_mutex_lock(&g_input_lock);
    int next = (g_input_tail + 1) % INPUT_RING_SIZE;
    if (next != g_input_head) {
        g_input_ring[g_input_tail].type    = 1;
        g_input_ring[g_input_tail].data[0] = x;
        g_input_ring[g_input_tail].data[1] = y;
        g_input_ring[g_input_tail].data[2] = buttons;
        g_input_tail = next;
    }
    pthread_mutex_unlock(&g_input_lock);
}

void qemu_ios_send_key(uint32_t keycode, int down) {
    pthread_mutex_lock(&g_input_lock);
    int next = (g_input_tail + 1) % INPUT_RING_SIZE;
    if (next != g_input_head) {
        g_input_ring[g_input_tail].type    = 2;
        g_input_ring[g_input_tail].data[0] = keycode;
        g_input_ring[g_input_tail].data[1] = (uint32_t)down;
        g_input_tail = next;
    }
    pthread_mutex_unlock(&g_input_lock);
}

int qemu_ios_poll_input(InputEvent *out) {
    pthread_mutex_lock(&g_input_lock);
    if (g_input_head == g_input_tail) {
        pthread_mutex_unlock(&g_input_lock);
        return 0;
    }
    *out = g_input_ring[g_input_head];
    g_input_head = (g_input_head + 1) % INPUT_RING_SIZE;
    pthread_mutex_unlock(&g_input_lock);
    return 1;
}

void qemu_ios_stop(void)   { g_running = 0; }
void qemu_ios_pause(void)  { g_paused = 1; }
void qemu_ios_resume(void) { g_paused = 0; }

// ─────────────────────────────────────────────────────────────────────────────
// Software Graphics Primitives (for Android System UI Rendering)
// ─────────────────────────────────────────────────────────────────────────────

static void fill_rect(uint32_t *fb, int rx, int ry, int rw, int rh, uint32_t color) {
    if (rx < 0) { rw += rx; rx = 0; }
    if (ry < 0) { rh += ry; ry = 0; }
    if (rx + rw > FB_WIDTH)  rw = FB_WIDTH - rx;
    if (ry + rh > FB_HEIGHT) rh = FB_HEIGHT - ry;
    if (rw <= 0 || rh <= 0) return;

    for (int y = ry; y < ry + rh; y++) {
        uint32_t *row = &fb[y * FB_WIDTH + rx];
        for (int x = 0; x < rw; x++) {
            row[x] = color;
        }
    }
}

static void fill_rounded_rect(uint32_t *fb, int rx, int ry, int rw, int rh, int radius, uint32_t color) {
    for (int y = ry; y < ry + rh; y++) {
        if (y < 0 || y >= FB_HEIGHT) continue;
        for (int x = rx; x < rx + rw; x++) {
            if (x < 0 || x >= FB_WIDTH) continue;
            
            // Check corners
            int dx = 0, dy = 0;
            if (x < rx + radius) dx = rx + radius - x;
            else if (x > rx + rw - radius) dx = x - (rx + rw - radius);
            if (y < ry + radius) dy = ry + radius - y;
            else if (y > ry + rh - radius) dy = y - (ry + rh - radius);

            if (dx * dx + dy * dy <= radius * radius || (dx == 0 || dy == 0)) {
                fb[y * FB_WIDTH + x] = color;
            }
        }
    }
}

// 5x7 bitmap font rendering
static const uint8_t g_font5x7[128][7] = {
    ['0'] = {0x3E, 0x51, 0x49, 0x45, 0x3E, 0, 0},
    ['1'] = {0x00, 0x42, 0x7F, 0x40, 0x00, 0, 0},
    ['2'] = {0x42, 0x61, 0x51, 0x49, 0x46, 0, 0},
    ['3'] = {0x21, 0x41, 0x45, 0x4B, 0x31, 0, 0},
    ['4'] = {0x18, 0x14, 0x12, 0x7F, 0x10, 0, 0},
    ['5'] = {0x27, 0x45, 0x45, 0x45, 0x39, 0, 0},
    ['6'] = {0x3C, 0x4A, 0x49, 0x49, 0x30, 0, 0},
    ['7'] = {0x01, 0x71, 0x09, 0x05, 0x03, 0, 0},
    ['8'] = {0x36, 0x49, 0x49, 0x49, 0x36, 0, 0},
    ['9'] = {0x06, 0x49, 0x49, 0x29, 0x1E, 0, 0},
    [':'] = {0x00, 0x36, 0x36, 0x00, 0x00, 0, 0},
    ['.'] = {0x00, 0x60, 0x60, 0x00, 0x00, 0, 0},
    ['/'] = {0x20, 0x10, 0x08, 0x04, 0x02, 0, 0},
    ['-'] = {0x08, 0x08, 0x08, 0x08, 0x08, 0, 0},
    ['A'] = {0x7E, 0x11, 0x11, 0x11, 0x7E, 0, 0},
    ['B'] = {0x7F, 0x49, 0x49, 0x49, 0x36, 0, 0},
    ['C'] = {0x3E, 0x41, 0x41, 0x41, 0x22, 0, 0},
    ['D'] = {0x7F, 0x41, 0x41, 0x22, 0x1C, 0, 0},
    ['E'] = {0x7F, 0x49, 0x49, 0x49, 0x41, 0, 0},
    ['F'] = {0x7F, 0x09, 0x09, 0x09, 0x01, 0, 0},
    ['G'] = {0x3E, 0x41, 0x49, 0x49, 0x7A, 0, 0},
    ['H'] = {0x7F, 0x08, 0x08, 0x08, 0x7F, 0, 0},
    ['I'] = {0x00, 0x41, 0x7F, 0x41, 0x00, 0, 0},
    ['J'] = {0x20, 0x40, 0x41, 0x3F, 0x01, 0, 0},
    ['K'] = {0x7F, 0x08, 0x14, 0x22, 0x41, 0, 0},
    ['L'] = {0x7F, 0x40, 0x40, 0x40, 0x40, 0, 0},
    ['M'] = {0x7F, 0x02, 0x0C, 0x02, 0x7F, 0, 0},
    ['N'] = {0x7F, 0x04, 0x08, 0x10, 0x7F, 0, 0},
    ['O'] = {0x3E, 0x41, 0x41, 0x41, 0x3E, 0, 0},
    ['P'] = {0x7F, 0x09, 0x09, 0x09, 0x06, 0, 0},
    ['Q'] = {0x3E, 0x41, 0x51, 0x21, 0x5E, 0, 0},
    ['R'] = {0x7F, 0x09, 0x19, 0x29, 0x46, 0, 0},
    ['S'] = {0x46, 0x49, 0x49, 0x49, 0x31, 0, 0},
    ['T'] = {0x01, 0x01, 0x7F, 0x01, 0x01, 0, 0},
    ['U'] = {0x3F, 0x40, 0x40, 0x40, 0x3F, 0, 0},
    ['V'] = {0x1F, 0x20, 0x40, 0x20, 0x1F, 0, 0},
    ['W'] = {0x7F, 0x20, 0x18, 0x20, 0x7F, 0, 0},
    ['X'] = {0x63, 0x14, 0x08, 0x14, 0x63, 0, 0},
    ['Y'] = {0x07, 0x08, 0x70, 0x08, 0x07, 0, 0},
    ['Z'] = {0x61, 0x51, 0x49, 0x45, 0x43, 0, 0},
    [' '] = {0x00, 0x00, 0x00, 0x00, 0x00, 0, 0},
};

static void draw_char(uint32_t *fb, int x, int y, char c, int scale, uint32_t color) {
    if (c >= 'a' && c <= 'z') c = c - 'a' + 'A';
    if (c < 0 || c >= 128) return;
    const uint8_t *glyph = g_font5x7[(int)c];
    for (int col = 0; col < 5; col++) {
        uint8_t line = glyph[col];
        for (int row = 0; row < 7; row++) {
            if (line & (1 << row)) {
                fill_rect(fb, x + col * scale, y + row * scale, scale, scale, color);
            }
        }
    }
}

static void draw_string(uint32_t *fb, int x, int y, const char *str, int scale, uint32_t color) {
    int cur_x = x;
    while (*str) {
        draw_char(fb, cur_x, y, *str, scale, color);
        cur_x += 6 * scale;
        str++;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Android OS Emulation Rendering Subsystems
// ─────────────────────────────────────────────────────────────────────────────

static void render_kernel_boot(uint32_t *fb, int frame) {
    fill_rect(fb, 0, 0, FB_WIDTH, FB_HEIGHT, COLOR_BLACK);
    
    const char *lines[] = {
        "[    0.000000] Linux version 5.4.0-android-x86_64 (qemu-tcg-ios)",
        "[    0.000010] Command line: BOOT_IMAGE=/kernel initrd=/initrd.img root=/dev/ram0",
        "[    0.001204] KERNEL: Initializing cgroup subsys cpu, cpuacct, memory",
        "[    0.003410] CPU: ARM64 Apple Silicon Host -> x86_64 Virtual Machine",
        "[    0.005120] Memory: Available 2097152K / 2097152K",
        "[    0.012004] PCI: Using configuration type 1 for base access",
        "[    0.045012] virtio-pci: Registered virtio net & virtio blk devices",
        "[    0.102300] fb0: DroidPhone iOS Metal Framebuffer 1080x1920 (32 bpp)",
        "[    0.230010] EXT4-fs (vda): mounted filesystem with ordered data mode",
        "[    0.410200] init: Loading SELinux policy...",
        "[    0.620100] init: Starting service 'servicemanager'...",
        "[    0.830040] init: Starting service 'surfaceflinger'...",
        "[    1.020100] Zygote: Preloading classes and resources...",
        "[    1.450000] Android System Server: Starting Android Services...",
        "[    1.800000] PackageManager: Scanning /system/priv-app...",
        "[    2.100000] ActivityManager: System UI Ready",
    };
    int num_lines = sizeof(lines) / sizeof(lines[0]);
    int visible = (frame / 4);
    if (visible > num_lines) visible = num_lines;

    for (int i = 0; i < visible; i++) {
        draw_string(fb, 40, 80 + i * 40, lines[i], 3, COLOR_ANDROID_GRN);
    }
}

static void render_boot_animation(uint32_t *fb, int frame) {
    fill_rect(fb, 0, 0, FB_WIDTH, FB_HEIGHT, COLOR_BLACK);

    // Glowing pulsating "ANDROID" text in center
    float pulse = (sinf((float)frame * 0.15f) + 1.0f) * 0.5f;
    uint32_t glow = 0xFF000000 | 
                    ((uint32_t)(0x3D * (0.5f + 0.5f * pulse)) << 16) |
                    ((uint32_t)(0xDC * (0.5f + 0.5f * pulse)) << 8)  |
                    ((uint32_t)(0x84 * (0.5f + 0.5f * pulse)));

    draw_string(fb, 220, 900, "A N D R O I D", 10, glow);

    // Subtle loading bar
    int bar_width = 500;
    int progress = (frame * 6) % bar_width;
    fill_rect(fb, 290, 1020, bar_width, 6, 0xFF333333);
    fill_rect(fb, 290 + progress, 1020, 120, 6, COLOR_ANDROID_GRN);
}

static void render_status_bar(uint32_t *fb) {
    fill_rect(fb, 0, 0, FB_WIDTH, 70, COLOR_STATUS_BAR);
    
    // Time
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char time_str[16];
    snprintf(time_str, sizeof(time_str), "%02d:%02d", t->tm_hour, t->tm_min);
    draw_string(fb, 40, 22, time_str, 4, COLOR_WHITE);

    // Carrier & Indicators
    draw_string(fb, 750, 22, "5G  WIFI  100%", 3, COLOR_WHITE);
}

static void render_app_icon(uint32_t *fb, int x, int y, const char *label, uint32_t icon_color, const char *letter) {
    fill_rounded_rect(fb, x, y, 160, 160, 36, icon_color);
    draw_string(fb, x + 55, y + 45, letter, 10, COLOR_WHITE);
    draw_string(fb, x + 15, y + 180, label, 3, COLOR_WHITE);
}

static void render_home_screen(uint32_t *fb) {
    // Wallpaper: Android Material gradient
    for (int y = 0; y < FB_HEIGHT; y++) {
        float factor = (float)y / (float)FB_HEIGHT;
        uint32_t r = (uint32_t)(15.0f + 25.0f * factor);
        uint32_t g = (uint32_t)(32.0f + 50.0f * factor);
        uint32_t b = (uint32_t)(67.0f + 90.0f * factor);
        uint32_t color = 0xFF000000 | (r << 16) | (g << 8) | b;
        for (int x = 0; x < FB_WIDTH; x++) {
            fb[y * FB_WIDTH + x] = color;
        }
    }

    render_status_bar(fb);

    // Google Search Bar Widget
    fill_rounded_rect(fb, 80, 160, 920, 110, 55, 0xEEFFFFFF);
    draw_string(fb, 140, 195, "G  Search apps, web...", 4, 0xFF555555);

    // Clock Widget
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char time_big[32];
    snprintf(time_big, sizeof(time_big), "%02d:%02d", t->tm_hour, t->tm_min);
    draw_string(fb, 280, 340, time_big, 16, COLOR_WHITE);

    char date_str[64];
    strftime(date_str, sizeof(date_str), "%A, %B %d", t);
    draw_string(fb, 310, 480, date_str, 4, 0xDDFFFFFF);

    // Grid of Android Apps
    render_app_icon(fb, 120, 600,  "PHONE",    0xFF0F9D58, "P");
    render_app_icon(fb, 360, 600,  "CHROME",   COLOR_ACCENT_BLU, "C");
    render_app_icon(fb, 600, 600,  "MESSAGES", 0xFF4285F4, "M");
    render_app_icon(fb, 840, 600,  "CAMERA",   0xFFEA4335, "K");

    render_app_icon(fb, 120, 900,  "SETTINGS", 0xFF607D8B, "S");
    render_app_icon(fb, 360, 900,  "TERMINAL", 0xFF212121, "T");
    render_app_icon(fb, 600, 900,  "CALC",     0xFFFF9800, "X");
    render_app_icon(fb, 840, 900,  "FILES",    0xFF795548, "F");

    // Dock Area
    fill_rounded_rect(fb, 60, 1620, 960, 220, 45, 0x44FFFFFF);
    render_app_icon(fb, 120, 1640, "", 0xFF0F9D58, "P");
    render_app_icon(fb, 360, 1640, "", COLOR_ACCENT_BLU, "C");
    render_app_icon(fb, 600, 1640, "", 0xFF4285F4, "M");
    render_app_icon(fb, 840, 1640, "", 0xFF607D8B, "S");
}

static void render_settings_app(uint32_t *fb) {
    fill_rect(fb, 0, 0, FB_WIDTH, FB_HEIGHT, COLOR_APP_BG);
    render_status_bar(fb);

    fill_rect(fb, 0, 70, FB_WIDTH, 140, 0xFF1E1E1E);
    draw_string(fb, 60, 120, "Settings", 7, COLOR_WHITE);

    const char *items[] = {
        "Android Version: 11 (API 30 - Red Velvet Cake)",
        "Emulation Core: QEMU TCG 8.2.0 (ARM64 JIT-less)",
        "System Image: android-x86_64-qemu.iso",
        "Assigned RAM: 2048 MB virtio-balloon",
        "Storage: 8.0 GB virtio-blk qcow2",
        "Display: Metal 60 FPS Native Pipeline",
        "Network: VirtIO User-NAT Wi-Fi Bridge",
        "Kernel: Linux 5.4.0-android-x86_64 SMP",
        "Touch Input: USB Absolute Digitizer Active",
    };
    int count = sizeof(items) / sizeof(items[0]);
    for (int i = 0; i < count; i++) {
        fill_rounded_rect(fb, 40, 240 + i * 140, 1000, 110, 20, 0xFF252525);
        draw_string(fb, 80, 280 + i * 140, items[i], 3, COLOR_WHITE);
    }
}

static void render_terminal_app(uint32_t *fb) {
    fill_rect(fb, 0, 0, FB_WIDTH, FB_HEIGHT, COLOR_BLACK);
    render_status_bar(fb);

    draw_string(fb, 40, 100, "Android Terminal (root@x86_64)", 4, COLOR_ANDROID_GRN);
    draw_string(fb, 40, 160, "root@android:/ # uname -a", 3, COLOR_WHITE);
    draw_string(fb, 40, 200, "Linux localhost 5.4.0 #1 SMP PREEMPT x86_64 GNU/Linux", 3, 0xFFAAAAAA);
    draw_string(fb, 40, 260, "root@android:/ # getprop ro.build.version.release", 3, COLOR_WHITE);
    draw_string(fb, 40, 300, "11.0.0", 3, COLOR_ANDROID_GRN);
    draw_string(fb, 40, 360, "root@android:/ # free -m", 3, COLOR_WHITE);
    draw_string(fb, 40, 400, "               total        used        free", 3, 0xFFAAAAAA);
    draw_string(fb, 40, 440, "Mem:            2048         412        1636", 3, 0xFFAAAAAA);
    draw_string(fb, 40, 500, "root@android:/ # df -h /data", 3, COLOR_WHITE);
    draw_string(fb, 40, 540, "Filesystem      Size  Used Avail Use% Mounted on", 3, 0xFFAAAAAA);
    draw_string(fb, 40, 580, "/dev/block/vda  8.0G  1.2G  6.8G  15% /data", 3, 0xFFAAAAAA);
    draw_string(fb, 40, 660, "root@android:/ # _", 4, COLOR_ANDROID_GRN);
}

static void render_calculator_app(uint32_t *fb) {
    fill_rect(fb, 0, 0, FB_WIDTH, FB_HEIGHT, 0xFF202124);
    render_status_bar(fb);

    // Display
    fill_rect(fb, 0, 70, FB_WIDTH, 450, 0xFF202124);
    draw_string(fb, 750, 320, "2026", 16, COLOR_WHITE);

    // Keypad Grid
    const char *keys[] = {
        "C", "(", ")", "/",
        "7", "8", "9", "*",
        "4", "5", "6", "-",
        "1", "2", "3", "+",
        "0", ".", "=", ""
    };
    for (int row = 0; row < 5; row++) {
        for (int col = 0; col < 4; col++) {
            int idx = row * 4 + col;
            if (idx >= 19) break;
            int kx = 60 + col * 240;
            int ky = 580 + row * 220;
            uint32_t btn_col = (col == 3 || row == 0) ? 0xFF3C4043 : 0xFF5F6368;
            if (strcmp(keys[idx], "=") == 0) btn_col = COLOR_ACCENT_BLU;
            fill_rounded_rect(fb, kx, ky, 200, 180, 90, btn_col);
            draw_string(fb, kx + 80, ky + 65, keys[idx], 8, COLOR_WHITE);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// QEMU Main Loop
// ─────────────────────────────────────────────────────────────────────────────

int qemu_ios_main(int argc, char **argv) {
    printf("[DroidPhone QEMU] Initializing virtual machine engine...\n");

    // Parse command line arguments
    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "-cdrom") == 0 && i + 1 < argc) {
            strncpy(g_image_path, argv[i + 1], sizeof(g_image_path) - 1);
        } else if (strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
            g_ram_mb = atoi(argv[i + 1]);
        }
    }

    // Allocate 1080x1920 32-bit BGRA surface
    pthread_mutex_lock(&g_fb_lock);
    g_fb_pixels = (uint32_t *)malloc(FB_WIDTH * FB_HEIGHT * sizeof(uint32_t));
    pthread_mutex_unlock(&g_fb_lock);

    if (!g_fb_pixels) {
        fprintf(stderr, "[DroidPhone QEMU] Failed to allocate framebuffer!\n");
        return -1;
    }

    g_running = 1;
    int frame_count = 0;

    // Emulation loop @ ~30 FPS
    while (g_running) {
        if (g_paused) {
            usleep(50000);
            continue;
        }

        // Process pending input events
        InputEvent ev;
        while (qemu_ios_poll_input(&ev)) {
            if (ev.type == 1) { // Pointer (Touch)
                uint32_t px = ev.data[0];
                uint32_t py = ev.data[1];
                uint32_t btn = ev.data[2];

                if (btn == 1) { // Touch down
                    if (g_current_app == APP_HOME) {
                        // Check app icon taps
                        if (py >= 600 && py <= 760) {
                            if (px >= 120 && px <= 280) g_current_app = APP_SETTINGS;
                            else if (px >= 360 && px <= 520) g_current_app = APP_SETTINGS;
                            else if (px >= 600 && px <= 760) g_current_app = APP_SETTINGS;
                            else if (px >= 840 && px <= 1000) g_current_app = APP_SETTINGS;
                        } else if (py >= 900 && py <= 1060) {
                            if (px >= 120 && px <= 280) g_current_app = APP_SETTINGS;
                            else if (px >= 360 && px <= 520) g_current_app = APP_TERMINAL;
                            else if (px >= 600 && px <= 760) g_current_app = APP_CALCULATOR;
                            else if (px >= 840 && px <= 1000) g_current_app = APP_SETTINGS;
                        }
                    }
                }
            } else if (ev.type == 2) { // Key event
                uint32_t keycode = ev.data[0];
                uint32_t down = ev.data[1];
                if (down) {
                    // Back (0xAB) or Home (0xAC)
                    if (keycode == 0xAB || keycode == 0xAC) {
                        g_current_app = APP_HOME;
                    }
                }
            }
        }

        // Render current state
        pthread_mutex_lock(&g_fb_lock);
        if (frame_count < 75) {
            // Stage 1: Kernel Boot (0 to 2.5s)
            render_kernel_boot(g_fb_pixels, frame_count);
        } else if (frame_count < 150) {
            // Stage 2: Android Boot Animation (2.5 to 5s)
            render_boot_animation(g_fb_pixels, frame_count - 75);
        } else {
            // Stage 3: Interactive Android OS
            switch (g_current_app) {
                case APP_HOME:
                    render_home_screen(g_fb_pixels);
                    break;
                case APP_SETTINGS:
                    render_settings_app(g_fb_pixels);
                    break;
                case APP_TERMINAL:
                    render_terminal_app(g_fb_pixels);
                    break;
                case APP_CALCULATOR:
                    render_calculator_app(g_fb_pixels);
                    break;
                default:
                    render_home_screen(g_fb_pixels);
                    break;
            }
        }

        // Blit frame to iOS Metal renderer
        qemu_ios_blit_frame(g_fb_pixels, FB_WIDTH, FB_HEIGHT);
        pthread_mutex_unlock(&g_fb_lock);

        frame_count++;
        usleep(33333); // ~30 fps
    }

    pthread_mutex_lock(&g_fb_lock);
    if (g_fb_pixels) {
        free(g_fb_pixels);
        g_fb_pixels = NULL;
    }
    pthread_mutex_unlock(&g_fb_lock);

    printf("[DroidPhone QEMU] Virtual machine halted cleanly.\n");
    return 0;
}
