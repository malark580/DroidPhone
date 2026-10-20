// qemu_ios_backend.c
// DroidPhone — iOS display + input backend for QEMU
// This file is compiled as part of libqemu-ios (built on macOS CI)

#include "qemu_ios_backend.h"
#include <string.h>
#include <stdlib.h>
#include <pthread.h>

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

static qemu_framebuffer_cb g_framebuffer_cb = NULL;
static uint32_t g_fb_width  = 1080;
static uint32_t g_fb_height = 1920;
static void    *g_fb_pixels = NULL;
static pthread_mutex_t g_fb_lock = PTHREAD_MUTEX_INITIALIZER;

// Input ring-buffer (simple; real impl uses QEMU's event queue)
#define INPUT_RING_SIZE 64
typedef struct { uint32_t type; uint32_t data[4]; } InputEvent;
static InputEvent g_input_ring[INPUT_RING_SIZE];
static int g_input_head = 0, g_input_tail = 0;
static pthread_mutex_t g_input_lock = PTHREAD_MUTEX_INITIALIZER;

// ─────────────────────────────────────────────────────────────────────────────
// Framebuffer registration
// ─────────────────────────────────────────────────────────────────────────────

void qemu_ios_set_framebuffer_callback(qemu_framebuffer_cb cb) {
    g_framebuffer_cb = cb;
}

// Called by QEMU's display layer (ios-fb display backend) to blit a frame.
void qemu_ios_blit_frame(const void *pixels, uint32_t width, uint32_t height) {
    pthread_mutex_lock(&g_fb_lock);

    if (g_fb_width != width || g_fb_height != height || !g_fb_pixels) {
        free(g_fb_pixels);
        g_fb_pixels = malloc(width * height * 4);
        g_fb_width  = width;
        g_fb_height = height;
    }

    if (g_fb_pixels && pixels) {
        memcpy(g_fb_pixels, pixels, width * height * 4);
    }

    pthread_mutex_unlock(&g_fb_lock);

    if (g_framebuffer_cb && g_fb_pixels) {
        g_framebuffer_cb(g_fb_pixels, width, height);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input
// ─────────────────────────────────────────────────────────────────────────────

void qemu_ios_send_pointer(uint32_t x, uint32_t y, uint32_t buttons) {
    pthread_mutex_lock(&g_input_lock);
    int next = (g_input_tail + 1) % INPUT_RING_SIZE;
    if (next != g_input_head) {
        g_input_ring[g_input_tail].type     = 1;  // pointer
        g_input_ring[g_input_tail].data[0]  = x;
        g_input_ring[g_input_tail].data[1]  = y;
        g_input_ring[g_input_tail].data[2]  = buttons;
        g_input_tail = next;
    }
    pthread_mutex_unlock(&g_input_lock);
}

void qemu_ios_send_key(uint32_t keycode, int down) {
    pthread_mutex_lock(&g_input_lock);
    int next = (g_input_tail + 1) % INPUT_RING_SIZE;
    if (next != g_input_head) {
        g_input_ring[g_input_tail].type     = 2;  // keyboard
        g_input_ring[g_input_tail].data[0]  = keycode;
        g_input_ring[g_input_tail].data[1]  = (uint32_t)down;
        g_input_tail = next;
    }
    pthread_mutex_unlock(&g_input_lock);
}

// Called by QEMU's main loop to drain pending input events
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

// ─────────────────────────────────────────────────────────────────────────────
// VM lifecycle
// ─────────────────────────────────────────────────────────────────────────────

static volatile int g_running = 0;

void qemu_ios_stop(void)   { g_running = 0; }
void qemu_ios_pause(void)  { /* signal QEMU pause */ }
void qemu_ios_resume(void) { /* signal QEMU resume */ }
