/*
 * VexRiscv Bouncing Ball Demo
 * Animates a bouncing ball on the RGB565 framebuffer
 */

#include <stdint.h>

/* Hardware registers */
#define SYS_DISPLAY_MODE  (*(volatile uint32_t*)0x4000000C)
#define SYS_FB_SWAP       (*(volatile uint32_t*)0x40000018)

/* Framebuffer addresses in SDRAM */
#define FRAMEBUFFER_0     ((volatile uint16_t*)0x10000000)
#define FRAMEBUFFER_1     ((volatile uint16_t*)0x10100000)

/* Display constants */
#define FB_WIDTH   320
#define FB_HEIGHT  240

/* Ball parameters */
#define BALL_RADIUS  25

/* Display modes */
#define DISPLAY_MODE_TERMINAL    0
#define DISPLAY_MODE_FRAMEBUFFER 1

/* RGB565 colors */
#define COLOR_RED     0xF800
#define COLOR_GREEN   0x07E0
#define COLOR_BLUE    0x001F
#define COLOR_WHITE   0xFFFF
#define COLOR_YELLOW  0xFFE0
#define COLOR_CYAN    0x07FF
#define COLOR_BLACK   0x0000
#define COLOR_DARKBLUE 0x0010

/* Current draw buffer */
static volatile uint16_t* draw_buffer = FRAMEBUFFER_1;

/*
 * Put a single pixel
 */
static inline void put_pixel(int x, int y, uint16_t color) {
    if (x >= 0 && x < FB_WIDTH && y >= 0 && y < FB_HEIGHT) {
        draw_buffer[y * FB_WIDTH + x] = color;
    }
}

/*
 * Clear framebuffer to a solid color
 */
static void clear_framebuffer(uint16_t color) {
    for (int i = 0; i < FB_WIDTH * FB_HEIGHT; i++) {
        draw_buffer[i] = color;
    }
}

/*
 * Draw horizontal line
 */
static void draw_hline(int x, int y, int width, uint16_t color) {
    for (int i = 0; i < width; i++) {
        put_pixel(x + i, y, color);
    }
}

/*
 * Draw circle outline using midpoint algorithm
 */
static void draw_circle(int cx, int cy, int radius, uint16_t color) {
    int x = 0;
    int y = radius;
    int d = 1 - radius;

    while (x <= y) {
        /* Draw 8 symmetric points */
        put_pixel(cx + x, cy + y, color);
        put_pixel(cx - x, cy + y, color);
        put_pixel(cx + x, cy - y, color);
        put_pixel(cx - x, cy - y, color);
        put_pixel(cx + y, cy + x, color);
        put_pixel(cx - y, cy + x, color);
        put_pixel(cx + y, cy - x, color);
        put_pixel(cx - y, cy - x, color);

        x++;
        if (d < 0) {
            d += 2 * x + 1;
        } else {
            y--;
            d += 2 * (x - y) + 1;
        }
    }
}

/*
 * Draw filled circle using midpoint algorithm
 */
static void draw_filled_circle(int cx, int cy, int radius, uint16_t color) {
    int x = 0;
    int y = radius;
    int d = 1 - radius;

    while (x <= y) {
        /* Draw horizontal lines for filled circle */
        draw_hline(cx - x, cy + y, 2 * x + 1, color);
        draw_hline(cx - x, cy - y, 2 * x + 1, color);
        draw_hline(cx - y, cy + x, 2 * y + 1, color);
        draw_hline(cx - y, cy - x, 2 * y + 1, color);

        x++;
        if (d < 0) {
            d += 2 * x + 1;
        } else {
            y--;
            d += 2 * (x - y) + 1;
        }
    }
}

/*
 * Swap front and back buffers (waits for vsync)
 */
static void swap_buffers(void) {
    SYS_FB_SWAP = 1;

    /* Wait for swap to actually complete (happens on vsync) */
    while (SYS_FB_SWAP & 1)
        ;

    /* Now swap our local draw buffer pointer */
    if (draw_buffer == FRAMEBUFFER_1) {
        draw_buffer = FRAMEBUFFER_0;
    } else {
        draw_buffer = FRAMEBUFFER_1;
    }
}

/*
 * Main entry point
 */
int main(void) {
    /* Ball position (fixed point: 8 bits fractional) */
    int ball_x = 160 << 8;
    int ball_y = 120 << 8;

    /* Ball velocity (pixels per frame, fixed point) */
    int vel_x = 3 << 8;  /* 3 pixels per frame */
    int vel_y = 2 << 8;  /* 2 pixels per frame */

    /* Switch to framebuffer-only mode */
    SYS_DISPLAY_MODE = DISPLAY_MODE_FRAMEBUFFER;

    /* Animation loop */
    while (1) {
        /* Clear back buffer */
        clear_framebuffer(COLOR_DARKBLUE);

        /* Convert fixed point to integer for drawing */
        int cx = ball_x >> 8;
        int cy = ball_y >> 8;

        /* Draw ball (filled circle with outline) */
        draw_filled_circle(cx, cy, BALL_RADIUS, COLOR_YELLOW);
        draw_circle(cx, cy, BALL_RADIUS, COLOR_RED);

        /* Swap buffers (waits for vsync) */
        swap_buffers();

        /* Update position */
        ball_x += vel_x;
        ball_y += vel_y;

        /* Bounce off edges */
        if ((ball_x >> 8) - BALL_RADIUS <= 0) {
            ball_x = BALL_RADIUS << 8;
            vel_x = -vel_x;
        }
        if ((ball_x >> 8) + BALL_RADIUS >= FB_WIDTH) {
            ball_x = (FB_WIDTH - BALL_RADIUS) << 8;
            vel_x = -vel_x;
        }
        if ((ball_y >> 8) - BALL_RADIUS <= 0) {
            ball_y = BALL_RADIUS << 8;
            vel_y = -vel_y;
        }
        if ((ball_y >> 8) + BALL_RADIUS >= FB_HEIGHT) {
            ball_y = (FB_HEIGHT - BALL_RADIUS) << 8;
            vel_y = -vel_y;
        }
    }

    return 0;
}
