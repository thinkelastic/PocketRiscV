# PocketRiscV

A minimal RISC-V system for the Analogue Pocket FPGA. Features a VexRiscv CPU with SDRAM framebuffer and text terminal display.

## Features

- **VexRiscv CPU** - RV32IM processor at 133 MHz with instruction/data caches
- **64KB BRAM** - Program and data storage
- **64MB SDRAM** - External memory at 133 MHz
- **320x240 Framebuffer** - RGB565 display with double buffering in SDRAM
- **40x30 Text Terminal** - Character overlay with 8x8 font
- **System Dashboard** - SDRAM stress test and CPU instruction verification demo

## Architecture

```
+-----------------------------------------------------------------------+
|                       Analogue Pocket FPGA                            |
|                     (Cyclone V 5CEBA4F23C8)                           |
+-----------------------------------------------------------------------+
|                                                                       |
|  +------------------+         +----------------------------------+    |
|  |   VexRiscv CPU   |         |        Memory Subsystem          |    |
|  |  RV32IM 133MHz   |         |                                  |    |
|  |                  |         |  +----------+    +----------+    |    |
|  |  +----+  +----+  |         |  |   BRAM   |    |  SDRAM   |    |    |
|  |  | I$ |  | D$ |  |         |  |   64KB   |    |   64MB   |    |    |
|  |  +----+  +----+  |         |  | Firmware |    |Framebuf  |    |    |
|  +--------+---------+         |  +----------+    +----------+    |    |
|           |                   +----------------------------------+    |
|           | Bus                                                       |
|  +--------+------------------------------------------------------+    |
|  |                      Memory Bus                               |    |
|  +--------+------------------------+------------------------+----+    |
|           |                        |                        |         |
|  +--------+--------+    +----------+----------+    +--------+-----+   |
|  | Text Terminal   |    |   Video Scanout     |    | System Regs  |   |
|  |    40x30        |    |  SDRAM Framebuffer  |    |              |   |
|  |                 |    |  Double Buffered    |    | Cycle counter|   |
|  |  0x20000000     |    |    0x10000000       |    | 0x40000000   |   |
|  +-----------------+    +---------------------+    +--------------+   |
|                                                                       |
+-----------------------------------------------------------------------+
```

## Memory Map

| Address       | Size  | Description              |
|---------------|-------|--------------------------|
| `0x00000000`  | 64KB  | BRAM (firmware)          |
| `0x10000000`  | 1MB   | Framebuffer 0 (RGB565)   |
| `0x10100000`  | 1MB   | Framebuffer 1 (RGB565)   |
| `0x20000000`  | 1.2KB | VRAM (text terminal)     |
| `0x40000000`  | 256B  | System registers         |

### System Registers (0x40000000)

| Offset | Register         | Description                        |
|--------|------------------|------------------------------------|
| 0x00   | SYS_STATUS       | Status flags                       |
| 0x04   | SYS_CYCLE_LO     | Cycle counter (low 32 bits)        |
| 0x08   | SYS_CYCLE_HI     | Cycle counter (high 32 bits)       |
| 0x0C   | SYS_DISPLAY_MODE | 0=terminal overlay, 1=framebuffer  |
| 0x18   | SYS_FB_SWAP      | Write 1 to swap buffers on vsync   |

## Building

### Prerequisites

```bash
# RISC-V toolchain
sudo pacman -S riscv64-elf-gcc  # Arch Linux

# Intel Quartus Prime 25.1+
```

### Firmware

```bash
cd src/firmware
make clean && make
```

### FPGA

```bash
cd src/fpga
make          # Full synthesis
make program  # Program via JTAG
```

## Project Structure

```
.
├── src/
│   ├── firmware/              # RISC-V firmware (C)
│   │   ├── crt0.S             # C runtime startup
│   │   ├── main.c             # System dashboard demo
│   │   ├── font8x8.h          # 8x8 bitmap font
│   │   ├── linker.ld          # Linker script
│   │   └── Makefile
│   │
│   └── fpga/                  # FPGA design
│       ├── core/
│       │   ├── core_top.v     # Top-level module
│       │   ├── cpu_system.v   # VexRiscv + bus + peripherals
│       │   ├── video_scanout.v# SDRAM framebuffer scanout
│       │   ├── text_terminal.v# Text rendering
│       │   └── io_sdram.v     # SDRAM controller
│       ├── vexriscv/
│       │   └── VexRiscv_Full.v# RISC-V CPU core
│       └── apf/               # Analogue Pocket framework
│
└── tools/
    └── capture_ocr.sh         # Screen capture utility
```

## License

- **VexRiscv**: MIT License (SpinalHDL)
- **PocketRiscV**: MIT License

## Acknowledgments

- [SpinalHDL/VexRiscv](https://github.com/SpinalHDL/VexRiscv) - RISC-V CPU core
- [Analogue](https://www.analogue.co/developer) - Pocket development framework
