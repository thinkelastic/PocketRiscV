/*
 * VexRiscv minimal Hello World firmware
 * Assembly-only program that displays "Hello World!" on terminal
 */

.section .text.start
.global _start

_start:
    /* Set up stack pointer at end of RAM */
    lui sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)

    /* Terminal VRAM base address: 0x20000000 */
    /* 40x30 character grid, each byte is ASCII */
    lui t0, 0x20000     /* t0 = 0x20000000 (terminal base) */

    /* Write "Hello World!" starting at position (0, 0) */
    /* Each character written to consecutive addresses */

    li t1, 'H'
    sb t1, 0(t0)

    li t1, 'e'
    sb t1, 1(t0)

    li t1, 'l'
    sb t1, 2(t0)

    li t1, 'l'
    sb t1, 3(t0)

    li t1, 'o'
    sb t1, 4(t0)

    li t1, ' '
    sb t1, 5(t0)

    li t1, 'W'
    sb t1, 6(t0)

    li t1, 'o'
    sb t1, 7(t0)

    li t1, 'r'
    sb t1, 8(t0)

    li t1, 'l'
    sb t1, 9(t0)

    li t1, 'd'
    sb t1, 10(t0)

    li t1, '!'
    sb t1, 11(t0)

    /* Loop forever */
halt:
    j halt
