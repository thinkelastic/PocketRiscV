# VexRiscv Minimal Firmware Makefile
# Assembly-only Hello World

# Toolchain
CROSS = riscv64-elf-
AS = $(CROSS)gcc
LD = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump
SIZE = $(CROSS)size

# Target
TARGET = firmware

# Directories
FPGA_CORE_DIR = ../fpga/core

# Assembly sources
SRCS_S = start.S
OBJS = $(SRCS_S:.S=.o)

# Architecture flags for RV32IM
ARCH = rv32im
ABI = ilp32

# Assembler flags
ASFLAGS = -march=$(ARCH) -mabi=$(ABI)

# Linker flags
LDFLAGS = -march=$(ARCH) -mabi=$(ABI)
LDFLAGS += -T linker.ld -nostdlib -nostartfiles
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -Wl,-Map=$(TARGET).map

# RAM size for MIF generation (64KB = 16384 words)
RAM_WORDS = 16384

# Default target
all: $(TARGET).bin $(TARGET).mif
	$(SIZE) $(TARGET).elf

# Link
$(TARGET).elf: $(OBJS) linker.ld
	$(LD) $(LDFLAGS) -o $@ $(OBJS)

# Binary output
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Quartus MIF output (Memory Initialization File)
$(TARGET).mif: $(TARGET).bin
	@echo "-- Firmware RAM initialization - $(RAM_WORDS) x 32-bit words (64KB)" > $@
	@echo "-- Auto-generated from $(TARGET).bin" >> $@
	@echo "" >> $@
	@echo "WIDTH=32;" >> $@
	@echo "DEPTH=$(RAM_WORDS);" >> $@
	@echo "" >> $@
	@echo "ADDRESS_RADIX=DEC;" >> $@
	@echo "DATA_RADIX=HEX;" >> $@
	@echo "" >> $@
	@echo "CONTENT BEGIN" >> $@
	@hexdump -v -e '1/4 "%08X\n"' $< | awk '{printf "%d : %s;\n", NR-1, $$1}' >> $@
	@LAST=$$(hexdump -v -e '1/4 "%08X\n"' $< | wc -l); \
	if [ $$LAST -lt $(RAM_WORDS) ]; then \
		echo "[$$LAST..$$(($(RAM_WORDS)-1))] : 00000013;" >> $@; \
	fi
	@echo "END;" >> $@
	@echo "Generated $@ with $$(hexdump -v -e '1/4 "%08X\n"' $< | wc -l) words of firmware"

# Assemble assembly sources
%.o: %.S
	$(AS) $(ASFLAGS) -c -o $@ $<

# Install MIF to FPGA core directory
install: $(TARGET).bin $(TARGET).mif
	cp $(TARGET).mif $(FPGA_CORE_DIR)/firmware.mif
	@echo "MIF installed to $(FPGA_CORE_DIR)/firmware.mif"

# Clean build artifacts
clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).mif $(TARGET).map

# Rebuild everything
rebuild: clean all

.PHONY: all clean rebuild install
