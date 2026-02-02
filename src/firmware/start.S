/*
 * VexRiscv Circle Demo
 * Draws a circle on the RGB565 framebuffer
 */

.section .text.start
.global _start

/* Memory addresses */
.equ TERMINAL_BASE, 0x20000000
.equ FRAMEBUFFER_BASE, 0x28000000
.equ SYS_DISPLAY_MODE, 0x4000000C   /* Display mode register */
.equ FB_WIDTH, 320
.equ FB_HEIGHT, 240

/* Display modes */
.equ DISPLAY_MODE_TERMINAL, 0      /* Terminal overlay on framebuffer */
.equ DISPLAY_MODE_FRAMEBUFFER, 1   /* Framebuffer only */

/* Circle parameters */
.equ CIRCLE_CX, 160          /* Center X */
.equ CIRCLE_CY, 120          /* Center Y */
.equ CIRCLE_R, 80            /* Radius */

/* Colors (RGB565) */
.equ COLOR_RED,    0xF800    /* 11111_000000_00000 */
.equ COLOR_GREEN,  0x07E0    /* 00000_111111_00000 */
.equ COLOR_BLUE,   0x001F    /* 00000_000000_11111 */
.equ COLOR_WHITE,  0xFFFF
.equ COLOR_YELLOW, 0xFFE0
.equ COLOR_CYAN,   0x07FF
.equ COLOR_BLACK,  0x0000

_start:
    /* Set up stack pointer */
    lui sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)

    /* Switch to framebuffer-only mode (disable terminal overlay) */
    li t0, SYS_DISPLAY_MODE
    li t1, DISPLAY_MODE_FRAMEBUFFER
    sw t1, 0(t0)

    /* Clear framebuffer to dark blue */
    lui a0, %hi(FRAMEBUFFER_BASE)
    addi a0, a0, %lo(FRAMEBUFFER_BASE)
    li a1, FB_WIDTH * FB_HEIGHT     /* pixel count */
    li a2, 0x0010                   /* dark blue */
    jal clear_framebuffer

    /* Draw filled circle */
    li a0, CIRCLE_CX
    li a1, CIRCLE_CY
    li a2, CIRCLE_R
    li a3, COLOR_YELLOW
    jal draw_filled_circle

    /* Draw circle outline in red */
    li a0, CIRCLE_CX
    li a1, CIRCLE_CY
    li a2, CIRCLE_R
    li a3, COLOR_RED
    jal draw_circle

halt:
    j halt

/*
 * clear_framebuffer: Fill framebuffer with color
 * a0 = framebuffer address
 * a1 = pixel count
 * a2 = color (16-bit)
 */
clear_framebuffer:
    beqz a1, clear_done
clear_loop:
    sh a2, 0(a0)
    addi a0, a0, 2
    addi a1, a1, -1
    bnez a1, clear_loop
clear_done:
    ret

/*
 * put_pixel: Draw a single pixel
 * a0 = x
 * a1 = y
 * a2 = color (16-bit RGB565)
 * Clobbers: t0, t1
 */
put_pixel:
    /* Bounds check */
    bltz a0, put_pixel_skip
    li t0, FB_WIDTH
    bge a0, t0, put_pixel_skip
    bltz a1, put_pixel_skip
    li t0, FB_HEIGHT
    bge a1, t0, put_pixel_skip

    /* Calculate address: base + y * 640 + x * 2 */
    /* y * 640 = y * 512 + y * 128 = (y << 9) + (y << 7) */
    slli t0, a1, 9          /* t0 = y * 512 */
    slli t1, a1, 7          /* t1 = y * 128 */
    add t0, t0, t1          /* t0 = y * 640 */
    slli t1, a0, 1          /* t1 = x * 2 */
    add t0, t0, t1          /* t0 = y * 640 + x * 2 */
    lui t1, %hi(FRAMEBUFFER_BASE)
    addi t1, t1, %lo(FRAMEBUFFER_BASE)
    add t0, t0, t1          /* t0 = final address */
    sh a2, 0(t0)            /* Store pixel */
put_pixel_skip:
    ret

/*
 * draw_circle: Draw circle outline using midpoint algorithm
 * a0 = cx (center x)
 * a1 = cy (center y)
 * a2 = radius
 * a3 = color
 */
draw_circle:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)            /* cx */
    sw s1, 8(sp)            /* cy */
    sw s2, 12(sp)           /* color */
    sw s3, 16(sp)           /* x */
    sw s4, 20(sp)           /* y */
    sw s5, 24(sp)           /* d (decision) */

    mv s0, a0               /* s0 = cx */
    mv s1, a1               /* s1 = cy */
    mv s2, a3               /* s2 = color */

    /* Initialize: x = 0, y = r, d = 1 - r */
    li s3, 0                /* x = 0 */
    mv s4, a2               /* y = r */
    li s5, 1
    sub s5, s5, a2          /* d = 1 - r */

circle_loop:
    bgt s3, s4, circle_done /* while x <= y */

    /* Draw 8 symmetric points */
    /* (cx+x, cy+y) */
    add a0, s0, s3
    add a1, s1, s4
    mv a2, s2
    jal put_pixel

    /* (cx-x, cy+y) */
    sub a0, s0, s3
    add a1, s1, s4
    mv a2, s2
    jal put_pixel

    /* (cx+x, cy-y) */
    add a0, s0, s3
    sub a1, s1, s4
    mv a2, s2
    jal put_pixel

    /* (cx-x, cy-y) */
    sub a0, s0, s3
    sub a1, s1, s4
    mv a2, s2
    jal put_pixel

    /* (cx+y, cy+x) */
    add a0, s0, s4
    add a1, s1, s3
    mv a2, s2
    jal put_pixel

    /* (cx-y, cy+x) */
    sub a0, s0, s4
    add a1, s1, s3
    mv a2, s2
    jal put_pixel

    /* (cx+y, cy-x) */
    add a0, s0, s4
    sub a1, s1, s3
    mv a2, s2
    jal put_pixel

    /* (cx-y, cy-x) */
    sub a0, s0, s4
    sub a1, s1, s3
    mv a2, s2
    jal put_pixel

    /* Update x and decision */
    addi s3, s3, 1          /* x++ */

    bgez s5, circle_d_pos   /* if d >= 0 */
    /* d < 0: d = d + 2*x + 1 */
    slli t0, s3, 1          /* t0 = 2*x */
    add s5, s5, t0
    addi s5, s5, 1
    j circle_loop

circle_d_pos:
    /* d >= 0: y--, d = d + 2*(x-y) + 1 */
    addi s4, s4, -1         /* y-- */
    sub t0, s3, s4          /* t0 = x - y */
    slli t0, t0, 1          /* t0 = 2*(x-y) */
    add s5, s5, t0
    addi s5, s5, 1
    j circle_loop

circle_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    lw s5, 24(sp)
    addi sp, sp, 32
    ret

/*
 * draw_filled_circle: Draw filled circle
 * a0 = cx, a1 = cy, a2 = radius, a3 = color
 */
draw_filled_circle:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)            /* cx */
    sw s1, 8(sp)            /* cy */
    sw s2, 12(sp)           /* color */
    sw s3, 16(sp)           /* x */
    sw s4, 20(sp)           /* y */
    sw s5, 24(sp)           /* d */

    mv s0, a0
    mv s1, a1
    mv s2, a3

    li s3, 0                /* x = 0 */
    mv s4, a2               /* y = r */
    li s5, 1
    sub s5, s5, a2          /* d = 1 - r */

filled_loop:
    bgt s3, s4, filled_done

    /* Draw horizontal lines for filled circle */
    /* Line from (cx-x, cy+y) to (cx+x, cy+y) */
    sub a0, s0, s3          /* x_start = cx - x */
    add a1, s1, s4          /* y = cy + y */
    slli a2, s3, 1          /* width = 2*x + 1 */
    addi a2, a2, 1
    mv a3, s2
    jal draw_hline

    /* Line from (cx-x, cy-y) to (cx+x, cy-y) */
    sub a0, s0, s3
    sub a1, s1, s4
    slli a2, s3, 1
    addi a2, a2, 1
    mv a3, s2
    jal draw_hline

    /* Line from (cx-y, cy+x) to (cx+y, cy+x) */
    sub a0, s0, s4
    add a1, s1, s3
    slli a2, s4, 1
    addi a2, a2, 1
    mv a3, s2
    jal draw_hline

    /* Line from (cx-y, cy-x) to (cx+y, cy-x) */
    sub a0, s0, s4
    sub a1, s1, s3
    slli a2, s4, 1
    addi a2, a2, 1
    mv a3, s2
    jal draw_hline

    /* Update */
    addi s3, s3, 1
    bgez s5, filled_d_pos
    slli t0, s3, 1
    add s5, s5, t0
    addi s5, s5, 1
    j filled_loop

filled_d_pos:
    addi s4, s4, -1
    sub t0, s3, s4
    slli t0, t0, 1
    add s5, s5, t0
    addi s5, s5, 1
    j filled_loop

filled_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    lw s5, 24(sp)
    addi sp, sp, 32
    ret

/*
 * draw_hline: Draw horizontal line
 * a0 = x_start, a1 = y, a2 = width, a3 = color
 */
draw_hline:
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)

    mv s0, a0               /* x */
    mv s1, a2               /* remaining width */
    mv s2, a3               /* color */
    mv a1, a1               /* y stays in a1 */

hline_loop:
    blez s1, hline_done
    mv a0, s0
    mv a2, s2
    jal put_pixel
    addi s0, s0, 1
    addi s1, s1, -1
    j hline_loop

hline_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    addi sp, sp, 16
    ret
