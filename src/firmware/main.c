/*
 * PocketRiscV System Dashboard
 * SDRAM stress test + CPU instruction verification
 */

#include <stdint.h>
#include "font8x8.h"

/* Hardware registers */
#define SYS_STATUS        (*(volatile uint32_t*)0x40000000)
#define SYS_CYCLE_LO      (*(volatile uint32_t*)0x40000004)
#define SYS_CYCLE_HI      (*(volatile uint32_t*)0x40000008)
#define SYS_DISPLAY_MODE  (*(volatile uint32_t*)0x4000000C)
#define SYS_FB_SWAP       (*(volatile uint32_t*)0x40000018)

/* Framebuffer addresses in SDRAM */
#define FRAMEBUFFER_0     ((volatile uint16_t*)0x10000000)
#define FRAMEBUFFER_1     ((volatile uint16_t*)0x10100000)

/* SDRAM test region (after framebuffers) */
#define SDRAM_TEST_BASE   ((volatile uint32_t*)0x10200000)
#define SDRAM_TEST_SIZE   (1024 * 1024)  /* 1MB test region */

/* Display constants */
#define FB_WIDTH   320
#define FB_HEIGHT  240

/* Colors - dark theme */
#define COL_BG          0x0841   /* Dark gray background */
#define COL_PANEL       0x1082   /* Panel background */
#define COL_BORDER      0x4A69   /* Panel border */
#define COL_TITLE_BG    0x0010   /* Title bar dark blue */
#define COL_TEXT        0xFFFF   /* White text */
#define COL_TEXT_DIM    0x8410   /* Dim gray text */
#define COL_PASS        0x07E0   /* Green */
#define COL_FAIL        0xF800   /* Red */
#define COL_WARN        0xFD20   /* Orange */
#define COL_PROGRESS_BG 0x2104   /* Progress bar background */
#define COL_PROGRESS    0x04FF   /* Progress bar fill (cyan) */
#define COL_HIGHLIGHT   0xFFE0   /* Yellow highlight */

/* Current draw buffer */
static volatile uint16_t* draw_buffer = FRAMEBUFFER_1;

/* Test results */
static int sdram_errors = 0;
static int sdram_mb_tested = 0;
static int cpu_tests_passed = 0;
static int cpu_tests_total = 0;

/* ============================================ */
/* Graphics primitives                          */
/* ============================================ */

static inline void put_pixel(int x, int y, uint16_t color) {
    if (x >= 0 && x < FB_WIDTH && y >= 0 && y < FB_HEIGHT) {
        draw_buffer[y * FB_WIDTH + x] = color;
    }
}

static void fill_rect(int x, int y, int w, int h, uint16_t color) {
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            put_pixel(x + i, y + j, color);
        }
    }
}

static void draw_rect(int x, int y, int w, int h, uint16_t color) {
    for (int i = 0; i < w; i++) {
        put_pixel(x + i, y, color);
        put_pixel(x + i, y + h - 1, color);
    }
    for (int j = 0; j < h; j++) {
        put_pixel(x, y + j, color);
        put_pixel(x + w - 1, y + j, color);
    }
}

static void draw_char(int x, int y, char c, uint16_t color) {
    if (c < 32 || c > 127) c = '?';
    const uint8_t* glyph = font8x8[c - 32];
    for (int row = 0; row < 8; row++) {
        uint8_t bits = glyph[row];
        for (int col = 0; col < 8; col++) {
            if (bits & (0x80 >> col)) {
                put_pixel(x + col, y + row, color);
            }
        }
    }
}

static void draw_string(int x, int y, const char* str, uint16_t color) {
    while (*str) {
        draw_char(x, y, *str++, color);
        x += 8;
    }
}

static void draw_string_center(int y, const char* str, uint16_t color) {
    int len = 0;
    const char* p = str;
    while (*p++) len++;
    int x = (FB_WIDTH - len * 8) / 2;
    draw_string(x, y, str, color);
}

/* Draw a number (right-aligned) */
static void draw_number(int x, int y, uint32_t num, int digits, uint16_t color) {
    char buf[12];
    int i = 11;
    buf[i--] = '\0';
    if (num == 0) {
        buf[i--] = '0';
    } else {
        while (num > 0 && i >= 0) {
            buf[i--] = '0' + (num % 10);
            num /= 10;
        }
    }
    /* Pad with spaces */
    while (i >= 12 - digits - 1 && i >= 0) {
        buf[i--] = ' ';
    }
    draw_string(x, y, &buf[i + 1], color);
}

static void draw_hex(int x, int y, uint32_t num, int digits, uint16_t color) {
    static const char hex[] = "0123456789ABCDEF";
    for (int i = digits - 1; i >= 0; i--) {
        draw_char(x + i * 8, y, hex[num & 0xF], color);
        num >>= 4;
    }
}

static void draw_progress_bar(int x, int y, int w, int h, int percent, uint16_t fg, uint16_t bg) {
    fill_rect(x, y, w, h, bg);
    int fill_w = (w * percent) / 100;
    if (fill_w > 0) {
        fill_rect(x, y, fill_w, h, fg);
    }
    draw_rect(x, y, w, h, COL_BORDER);
}

/* ============================================ */
/* UI Panel drawing                             */
/* ============================================ */

static void draw_panel(int x, int y, int w, int h, const char* title) {
    /* Panel background */
    fill_rect(x, y, w, h, COL_PANEL);

    /* Title bar */
    fill_rect(x, y, w, 12, COL_TITLE_BG);
    draw_string(x + 4, y + 2, title, COL_TEXT);

    /* Border */
    draw_rect(x, y, w, h, COL_BORDER);
}

/* ============================================ */
/* SDRAM Stress Test                            */
/* ============================================ */

static int test_sdram_pattern(uint32_t pattern, int offset, int count) {
    volatile uint32_t* base = SDRAM_TEST_BASE + offset;
    int errors = 0;

    /* Write pattern */
    for (int i = 0; i < count; i++) {
        base[i] = pattern;
    }

    /* Read and verify */
    for (int i = 0; i < count; i++) {
        uint32_t val = base[i];
        if (val != pattern) {
            errors++;
        }
    }

    return errors;
}

static int test_sdram_walking(int offset, int count) {
    volatile uint32_t* base = SDRAM_TEST_BASE + offset;
    int errors = 0;

    /* Walking ones */
    for (int i = 0; i < count && i < 32; i++) {
        uint32_t pattern = 1 << i;
        base[i] = pattern;
    }
    for (int i = 0; i < count && i < 32; i++) {
        uint32_t expected = 1 << i;
        if (base[i] != expected) errors++;
    }

    /* Walking zeros */
    for (int i = 0; i < count && i < 32; i++) {
        uint32_t pattern = ~(1 << i);
        base[i] = pattern;
    }
    for (int i = 0; i < count && i < 32; i++) {
        uint32_t expected = ~(1 << i);
        if (base[i] != expected) errors++;
    }

    return errors;
}

static int test_sdram_address(int offset, int count) {
    volatile uint32_t* base = SDRAM_TEST_BASE + offset;
    int errors = 0;

    /* Write address as data */
    for (int i = 0; i < count; i++) {
        base[i] = (uint32_t)(uintptr_t)&base[i];
    }

    /* Verify */
    for (int i = 0; i < count; i++) {
        uint32_t expected = (uint32_t)(uintptr_t)&base[i];
        if (base[i] != expected) errors++;
    }

    return errors;
}

/* ============================================ */
/* CPU Instruction Tests                        */
/* ============================================ */

#define TEST(name, expr) do { \
    cpu_tests_total++; \
    if (expr) { cpu_tests_passed++; } \
} while(0)

static void test_cpu_arithmetic(void) {
    volatile int a = 100, b = 25;

    TEST("ADD", a + b == 125);
    TEST("SUB", a - b == 75);
    TEST("MUL", a * b == 2500);
    TEST("DIV", a / b == 4);
    TEST("REM", a % b == 0);
    TEST("NEG", -a == -100);
}

static void test_cpu_logical(void) {
    volatile uint32_t a = 0xFF00FF00, b = 0x0F0F0F0F;

    TEST("AND", (a & b) == 0x0F000F00);
    TEST("OR",  (a | b) == 0xFF0FFF0F);
    TEST("XOR", (a ^ b) == 0xF00FF00F);
    TEST("NOT", (~a) == 0x00FF00FF);
}

static void test_cpu_shifts(void) {
    volatile uint32_t a = 0x80000001;
    volatile int32_t sa = -16;

    TEST("SLL", (a << 4) == 0x00000010);
    TEST("SRL", (a >> 4) == 0x08000000);
    TEST("SRA", (sa >> 2) == -4);  /* Arithmetic shift */
}

static void test_cpu_compare(void) {
    volatile int a = -5, b = 10;
    volatile uint32_t ua = 0xFFFFFFFF, ub = 1;

    TEST("SLT", (a < b) == 1);
    TEST("SGE", (b >= a) == 1);
    TEST("SLTU", (ub < ua) == 1);  /* Unsigned compare */
}

static void test_cpu_memory(void) {
    volatile uint32_t val32 = 0xDEADBEEF;
    volatile uint16_t val16 = 0xCAFE;
    volatile uint8_t val8 = 0x42;

    uint32_t r32 = val32;
    uint16_t r16 = val16;
    uint8_t r8 = val8;

    TEST("LW/SW", r32 == 0xDEADBEEF);
    TEST("LH/SH", r16 == 0xCAFE);
    TEST("LB/SB", r8 == 0x42);
}

static void test_cpu_branch(void) {
    volatile int x = 0;
    volatile int a = 5, b = 5, c = 10;

    if (a == b) x = 1;
    TEST("BEQ", x == 1);

    x = 0;
    if (a != c) x = 1;
    TEST("BNE", x == 1);

    x = 0;
    if (a < c) x = 1;
    TEST("BLT", x == 1);

    x = 0;
    if (c >= a) x = 1;
    TEST("BGE", x == 1);
}

/* ============================================ */
/* Buffer swap                                  */
/* ============================================ */

static void swap_buffers(void) {
    SYS_FB_SWAP = 1;
    while (SYS_FB_SWAP & 1);
    draw_buffer = (draw_buffer == FRAMEBUFFER_1) ? FRAMEBUFFER_0 : FRAMEBUFFER_1;
}

/* ============================================ */
/* Main dashboard                               */
/* ============================================ */

static void draw_dashboard(int sdram_progress, uint32_t cycles) {
    /* Clear screen */
    fill_rect(0, 0, FB_WIDTH, FB_HEIGHT, COL_BG);

    /* Title */
    fill_rect(0, 0, FB_WIDTH, 16, COL_TITLE_BG);
    draw_string_center(4, "PocketRiscV System Dashboard", COL_HIGHLIGHT);

    /* System info panel */
    draw_panel(5, 22, 150, 50, "System Info");
    draw_string(10, 36, "CPU:", COL_TEXT_DIM);
    draw_string(50, 36, "VexRiscv 133MHz", COL_TEXT);
    draw_string(10, 46, "RAM:", COL_TEXT_DIM);
    draw_string(50, 46, "64KB BRAM", COL_TEXT);
    draw_string(10, 56, "SDRAM:", COL_TEXT_DIM);
    draw_string(58, 56, "64MB", COL_TEXT);

    /* Cycle counter panel */
    draw_panel(165, 22, 150, 50, "Cycle Counter");
    draw_string(170, 40, "Cycles:", COL_TEXT_DIM);
    draw_hex(230, 40, cycles >> 16, 4, COL_TEXT);
    draw_hex(262, 40, cycles & 0xFFFF, 4, COL_TEXT);

    /* SDRAM Test panel */
    draw_panel(5, 78, 310, 70, "SDRAM Stress Test");

    draw_string(10, 94, "Progress:", COL_TEXT_DIM);
    draw_progress_bar(80, 92, 180, 12, sdram_progress, COL_PROGRESS, COL_PROGRESS_BG);
    char pct[8];
    pct[0] = '0' + (sdram_progress / 100) % 10;
    pct[1] = '0' + (sdram_progress / 10) % 10;
    pct[2] = '0' + sdram_progress % 10;
    pct[3] = '%';
    pct[4] = '\0';
    draw_string(268, 94, pct, COL_TEXT);

    draw_string(10, 110, "Tested:", COL_TEXT_DIM);
    draw_number(70, 110, sdram_mb_tested, 4, COL_TEXT);
    draw_string(110, 110, "KB", COL_TEXT);

    draw_string(150, 110, "Errors:", COL_TEXT_DIM);
    draw_number(210, 110, sdram_errors, 6, sdram_errors == 0 ? COL_PASS : COL_FAIL);

    draw_string(10, 126, "Status:", COL_TEXT_DIM);
    if (sdram_progress < 100) {
        draw_string(70, 126, "Testing...", COL_WARN);
    } else if (sdram_errors == 0) {
        draw_string(70, 126, "PASSED", COL_PASS);
    } else {
        draw_string(70, 126, "FAILED", COL_FAIL);
    }

    /* CPU Test panel */
    draw_panel(5, 154, 310, 80, "CPU Instruction Tests");

    draw_string(10, 170, "Arithmetic:", COL_TEXT_DIM);
    draw_string(10, 182, "Logical:", COL_TEXT_DIM);
    draw_string(10, 194, "Shifts:", COL_TEXT_DIM);
    draw_string(10, 206, "Compare:", COL_TEXT_DIM);
    draw_string(10, 218, "Memory:", COL_TEXT_DIM);

    draw_string(160, 170, "Branch:", COL_TEXT_DIM);

    /* Results */
    draw_string(110, 218, "Total:", COL_TEXT_DIM);
    draw_number(160, 218, cpu_tests_passed, 2, COL_TEXT);
    draw_string(180, 218, "/", COL_TEXT);
    draw_number(190, 218, cpu_tests_total, 2, COL_TEXT);

    if (cpu_tests_total > 0) {
        if (cpu_tests_passed == cpu_tests_total) {
            draw_string(230, 218, "ALL PASS", COL_PASS);
        } else {
            draw_string(230, 218, "FAILED", COL_FAIL);
        }
    }
}

int main(void) {
    /* Switch to framebuffer mode */
    SYS_DISPLAY_MODE = 1;

    /* Run CPU tests first */
    test_cpu_arithmetic();
    test_cpu_logical();
    test_cpu_shifts();
    test_cpu_compare();
    test_cpu_memory();
    test_cpu_branch();

    /* Main loop - run SDRAM tests */
    int test_phase = 0;
    int test_offset = 0;
    int words_per_iter = 1024;  /* Test 4KB per iteration */
    int total_words = SDRAM_TEST_SIZE / 4;

    while (1) {
        uint32_t cycles = SYS_CYCLE_LO;

        /* Calculate progress */
        int progress = (test_offset * 100) / total_words;
        if (progress > 100) progress = 100;

        /* Draw dashboard */
        draw_dashboard(progress, cycles);
        swap_buffers();

        /* Run SDRAM tests if not complete */
        if (test_offset < total_words) {
            int count = words_per_iter;
            if (test_offset + count > total_words) {
                count = total_words - test_offset;
            }

            switch (test_phase) {
                case 0:
                    sdram_errors += test_sdram_pattern(0xAAAAAAAA, test_offset, count);
                    break;
                case 1:
                    sdram_errors += test_sdram_pattern(0x55555555, test_offset, count);
                    break;
                case 2:
                    sdram_errors += test_sdram_pattern(0xFFFFFFFF, test_offset, count);
                    break;
                case 3:
                    sdram_errors += test_sdram_pattern(0x00000000, test_offset, count);
                    break;
                case 4:
                    sdram_errors += test_sdram_walking(test_offset, count);
                    break;
                case 5:
                    sdram_errors += test_sdram_address(test_offset, count);
                    test_offset += count;
                    sdram_mb_tested = (test_offset * 4) / 1024;
                    break;
            }

            test_phase = (test_phase + 1) % 6;
        }
    }

    return 0;
}
