//
// VexRiscv CPU System (Minimal)
// - VexRiscv RISC-V CPU with Wishbone interface
// - 64KB RAM for program/data (using block RAM)
// - Memory-mapped terminal at 0x20000000
// - Framebuffer at 0x28000000 (320x240 RGB565)
// - SDRAM access at 0x10000000 (64MB)
// - System registers at 0x40000000
//

`default_nettype none

module cpu_system (
    input wire clk,           // CPU clock (133 MHz - same as SDRAM controller)
    input wire clk_74a,       // Bridge clock (74.25 MHz) - for APF interface
    input wire reset_n,
    input wire dataslot_allcomplete,  // All data slots loaded by APF

    // Terminal memory interface
    output wire        term_mem_valid,
    output wire [31:0] term_mem_addr,
    output wire [31:0] term_mem_wdata,
    output wire [3:0]  term_mem_wstrb,
    input wire  [31:0] term_mem_rdata,
    input wire         term_mem_ready,

    // Framebuffer memory interface
    output wire        fb_mem_valid,
    output wire [31:0] fb_mem_addr,
    output wire [31:0] fb_mem_wdata,
    output wire [3:0]  fb_mem_wstrb,
    input wire  [31:0] fb_mem_rdata,
    input wire         fb_mem_ready,

    // SDRAM word interface (directly to io_sdram via core_top)
    // CPU and SDRAM controller run at same clock (133 MHz)
    output reg         sdram_rd,
    output reg         sdram_wr,
    output reg  [23:0] sdram_addr,
    output reg  [31:0] sdram_wdata,
    input wire  [31:0] sdram_rdata,
    input wire         sdram_busy,
    input wire         sdram_rdata_valid,  // Pulses when read data is valid

    // Display mode output
    output wire        display_mode  // 0=terminal overlay, 1=framebuffer only
);

// ============================================
// VexRiscv Wishbone signals
// ============================================

// Instruction bus (Wishbone)
wire        ibus_cyc;
wire        ibus_stb;
reg         ibus_ack;
wire        ibus_we;
wire [29:0] ibus_adr;
reg  [31:0] ibus_dat_miso;
wire [31:0] ibus_dat_mosi;
wire [3:0]  ibus_sel;
wire [1:0]  ibus_bte;
wire [2:0]  ibus_cti;

// Data bus (Wishbone)
wire        dbus_cyc;
wire        dbus_stb;
reg         dbus_ack;
wire        dbus_we;
wire [29:0] dbus_adr;
reg  [31:0] dbus_dat_miso;
wire [31:0] dbus_dat_mosi;
wire [3:0]  dbus_sel;
wire [1:0]  dbus_bte;
wire [2:0]  dbus_cti;

// Active-high reset for VexRiscv
wire reset = ~reset_n;

// Instantiate VexRiscv CPU
VexRiscv cpu (
    .clk(clk),
    .reset(reset),

    // Reset vector - boot at 0x00000000
    .externalResetVector(32'h00000000),

    // Interrupts (tie off for now)
    .timerInterrupt(1'b0),
    .softwareInterrupt(1'b0),
    .externalInterruptArray(32'b0),

    // Instruction Wishbone bus
    .iBusWishbone_CYC(ibus_cyc),
    .iBusWishbone_STB(ibus_stb),
    .iBusWishbone_ACK(ibus_ack),
    .iBusWishbone_WE(ibus_we),
    .iBusWishbone_ADR(ibus_adr),
    .iBusWishbone_DAT_MISO(ibus_dat_miso),
    .iBusWishbone_DAT_MOSI(ibus_dat_mosi),
    .iBusWishbone_SEL(ibus_sel),
    .iBusWishbone_ERR(1'b0),
    .iBusWishbone_BTE(ibus_bte),
    .iBusWishbone_CTI(ibus_cti),

    // Data Wishbone bus
    .dBusWishbone_CYC(dbus_cyc),
    .dBusWishbone_STB(dbus_stb),
    .dBusWishbone_ACK(dbus_ack),
    .dBusWishbone_WE(dbus_we),
    .dBusWishbone_ADR(dbus_adr),
    .dBusWishbone_DAT_MISO(dbus_dat_miso),
    .dBusWishbone_DAT_MOSI(dbus_dat_mosi),
    .dBusWishbone_SEL(dbus_sel),
    .dBusWishbone_ERR(1'b0),
    .dBusWishbone_BTE(dbus_bte),
    .dBusWishbone_CTI(dbus_cti)
);

// ============================================
// Arbitrated memory interface
// ============================================
// Data bus has priority over instruction bus
// Convert Wishbone to simple valid/ready protocol

wire ibus_req = ibus_cyc & ibus_stb & ~ibus_ack;
wire dbus_req = dbus_cyc & dbus_stb & ~dbus_ack;

// Grant: data has priority
wire dbus_grant = dbus_req;
wire ibus_grant = ibus_req & ~dbus_req;

// Muxed memory interface signals
wire        mem_valid = dbus_grant | ibus_grant;
wire [31:0] mem_addr  = dbus_grant ? {dbus_adr, 2'b00} : {ibus_adr, 2'b00};
wire [31:0] mem_wdata = dbus_dat_mosi;
wire [3:0]  mem_wstrb = dbus_grant ? (dbus_we ? dbus_sel : 4'b0) : 4'b0;
wire        mem_write = dbus_grant & dbus_we;

// Memory map:
// 0x00000000 - 0x0000FFFF : RAM (64KB)
// 0x10000000 - 0x13FFFFFF : SDRAM (64MB)
// 0x20000000 - 0x20001FFF : Terminal VRAM
// 0x28000000 - 0x2804AFFF : Framebuffer (320x240 RGB565)
// 0x40000000 - 0x400000FF : System registers

// Decode memory regions
wire ram_select    = (mem_addr[31:16] == 16'b0);                    // 0x00000000-0x0000FFFF (64KB)
wire sdram_select  = (mem_addr[31:26] == 6'b000100);                // 0x10000000-0x13FFFFFF (64MB)
wire term_select   = (mem_addr[31:13] == 19'h10000);                // 0x20000000-0x20001FFF
wire fb_select     = (mem_addr[31:19] == 13'h0500);                 // 0x28000000-0x2807FFFF
wire sysreg_select = (mem_addr[31:8] == 24'h400000);                // 0x40000000-0x400000FF

// ============================================
// RAM using block RAM (64KB = 16384 x 32-bit words)
// ============================================
wire [31:0] ram_rdata;
wire [13:0] ram_addr_mux = mem_addr[15:2];
wire ram_wren = mem_valid && ram_select && |mem_wstrb;

altsyncram #(
    .operation_mode("SINGLE_PORT"),
    .width_a(32),
    .widthad_a(14),              // 14 bits = 16384 words = 64KB
    .numwords_a(16384),
    .width_byteena_a(4),
    .lpm_type("altsyncram"),
    .outdata_reg_a("UNREGISTERED"),
    .init_file("core/firmware.mif"),
    .intended_device_family("Cyclone V"),
    .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ")
) ram (
    .clock0(clk),
    .address_a(ram_addr_mux),
    .data_a(mem_wdata),
    .wren_a(ram_wren),
    .byteena_a(mem_wstrb),
    .q_a(ram_rdata),
    // Unused ports
    .aclr0(1'b0),
    .aclr1(1'b0),
    .address_b(1'b0),
    .addressstall_a(1'b0),
    .addressstall_b(1'b0),
    .byteena_b(1'b1),
    .clock1(1'b1),
    .clocken0(1'b1),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .data_b({32{1'b0}}),
    .eccstatus(),
    .q_b(),
    .rden_a(1'b1),
    .rden_b(1'b0),
    .wren_b(1'b0)
);

// Forward terminal requests to terminal module
assign term_mem_valid = mem_valid && term_select;
assign term_mem_addr = mem_addr;
assign term_mem_wdata = mem_wdata;
assign term_mem_wstrb = mem_wstrb;

// Forward framebuffer requests to framebuffer module
assign fb_mem_valid = mem_valid && fb_select;
assign fb_mem_addr = mem_addr;
assign fb_mem_wdata = mem_wdata;
assign fb_mem_wstrb = mem_wstrb;

// ============================================
// System registers
// ============================================
// 0x00: SYS_STATUS      - Bit 0: always 1 (SDRAM ready), Bit 1: dataslot_allcomplete
// 0x04: SYS_CYCLE_LO    - Cycle counter low
// 0x08: SYS_CYCLE_HI    - Cycle counter high
// 0x0C: SYS_DISPLAY_MODE - 0=terminal overlay, 1=framebuffer only

reg [31:0] sysreg_rdata;
reg [63:0] cycle_counter;
reg display_mode_reg;  // 0=terminal overlay, 1=framebuffer only

assign display_mode = display_mode_reg;

// Synchronize dataslot_allcomplete from bridge clock domain (clk_74a) to CPU clock domain
reg [2:0] dataslot_allcomplete_sync;
always @(posedge clk) begin
    dataslot_allcomplete_sync <= {dataslot_allcomplete_sync[1:0], dataslot_allcomplete};
end
wire dataslot_allcomplete_s = dataslot_allcomplete_sync[2];

always @(posedge clk) begin
    if (reset) begin
        cycle_counter <= 0;
        display_mode_reg <= 0;  // Start in terminal overlay mode
    end else begin
        cycle_counter <= cycle_counter + 1;

        // Write to display mode register (0x4000000C)
        if (mem_valid && sysreg_select && |mem_wstrb && mem_addr[7:2] == 6'b000011) begin
            display_mode_reg <= mem_wdata[0];
        end
    end
end

always @(*) begin
    case (mem_addr[7:2])
        6'b000000: sysreg_rdata = {30'b0, dataslot_allcomplete_s, 1'b1};  // SYS_STATUS
        6'b000001: sysreg_rdata = cycle_counter[31:0];   // SYS_CYCLE_LO
        6'b000010: sysreg_rdata = cycle_counter[63:32];  // SYS_CYCLE_HI
        6'b000011: sysreg_rdata = {31'b0, display_mode_reg};  // SYS_DISPLAY_MODE
        default: sysreg_rdata = 32'h0;
    endcase
end

// ============================================
// Memory access state machine
// ============================================
// Handle RAM, SDRAM, terminal, and sysreg accesses
// Generate Wishbone ACK when complete

reg mem_pending;
reg [1:0] pending_bus;  // 0=none, 1=ibus, 2=dbus
reg ram_pending;
reg term_pending;
reg fb_pending;
reg sdram_read_pending;
reg sdram_write_pending;
reg sdram_write_started;
reg sysreg_pending;
reg [31:0] pending_rdata;

localparam BUS_NONE = 2'd0;
localparam BUS_IBUS = 2'd1;
localparam BUS_DBUS = 2'd2;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        ibus_ack <= 0;
        dbus_ack <= 0;
        ibus_dat_miso <= 0;
        dbus_dat_miso <= 0;
        mem_pending <= 0;
        pending_bus <= BUS_NONE;
        ram_pending <= 0;
        term_pending <= 0;
        fb_pending <= 0;
        sdram_read_pending <= 0;
        sdram_write_pending <= 0;
        sdram_write_started <= 0;
        sysreg_pending <= 0;
        sdram_rd <= 0;
        sdram_wr <= 0;
        sdram_addr <= 0;
        sdram_wdata <= 0;
        pending_rdata <= 0;
    end else begin
        // Default: deassert ACKs and single-cycle signals
        ibus_ack <= 0;
        dbus_ack <= 0;
        sdram_rd <= 0;
        sdram_wr <= 0;

        if (!mem_pending && mem_valid) begin
            // Start new memory access
            pending_bus <= dbus_grant ? BUS_DBUS : BUS_IBUS;

            if (ram_select) begin
                mem_pending <= 1;
                ram_pending <= 1;
            end else if (sdram_select) begin
                sdram_addr <= mem_addr[25:2];
                if (mem_write) begin
                    sdram_wr <= 1;
                    sdram_wdata <= mem_wdata;
                    mem_pending <= 1;
                    sdram_write_pending <= 1;
                    sdram_write_started <= 0;
                end else begin
                    sdram_rd <= 1;
                    mem_pending <= 1;
                    sdram_read_pending <= 1;
                end
            end else if (term_select) begin
                mem_pending <= 1;
                term_pending <= 1;
            end else if (fb_select) begin
                mem_pending <= 1;
                fb_pending <= 1;
            end else if (sysreg_select) begin
                mem_pending <= 1;
                sysreg_pending <= 1;
            end else begin
                // Unknown region - return 0 immediately
                if (dbus_grant) begin
                    dbus_ack <= 1;
                    dbus_dat_miso <= 32'h0;
                end else begin
                    ibus_ack <= 1;
                    ibus_dat_miso <= 32'h0;
                end
            end
        end else if (mem_pending) begin
            // Complete pending access
            if (ram_pending) begin
                pending_rdata <= ram_rdata;
                if (pending_bus == BUS_DBUS) begin
                    dbus_ack <= 1;
                    dbus_dat_miso <= ram_rdata;
                end else begin
                    ibus_ack <= 1;
                    ibus_dat_miso <= ram_rdata;
                end
                mem_pending <= 0;
                ram_pending <= 0;
                pending_bus <= BUS_NONE;
            end else if (sdram_read_pending && sdram_rdata_valid) begin
                pending_rdata <= sdram_rdata;
                if (pending_bus == BUS_DBUS) begin
                    dbus_ack <= 1;
                    dbus_dat_miso <= sdram_rdata;
                end else begin
                    ibus_ack <= 1;
                    ibus_dat_miso <= sdram_rdata;
                end
                mem_pending <= 0;
                sdram_read_pending <= 0;
                pending_bus <= BUS_NONE;
            end else if (sdram_write_pending) begin
                // Write: wait for busy HIGH then LOW
                if (!sdram_write_started && sdram_busy) begin
                    sdram_write_started <= 1;
                end else if (sdram_write_started && !sdram_busy) begin
                    if (pending_bus == BUS_DBUS) begin
                        dbus_ack <= 1;
                        dbus_dat_miso <= 32'h0;
                    end else begin
                        ibus_ack <= 1;
                        ibus_dat_miso <= 32'h0;
                    end
                    mem_pending <= 0;
                    sdram_write_pending <= 0;
                    sdram_write_started <= 0;
                    pending_bus <= BUS_NONE;
                end
            end else if (term_pending && term_mem_ready) begin
                if (pending_bus == BUS_DBUS) begin
                    dbus_ack <= 1;
                    dbus_dat_miso <= term_mem_rdata;
                end else begin
                    ibus_ack <= 1;
                    ibus_dat_miso <= term_mem_rdata;
                end
                mem_pending <= 0;
                term_pending <= 0;
                pending_bus <= BUS_NONE;
            end else if (fb_pending && fb_mem_ready) begin
                if (pending_bus == BUS_DBUS) begin
                    dbus_ack <= 1;
                    dbus_dat_miso <= fb_mem_rdata;
                end else begin
                    ibus_ack <= 1;
                    ibus_dat_miso <= fb_mem_rdata;
                end
                mem_pending <= 0;
                fb_pending <= 0;
                pending_bus <= BUS_NONE;
            end else if (sysreg_pending) begin
                if (pending_bus == BUS_DBUS) begin
                    dbus_ack <= 1;
                    dbus_dat_miso <= sysreg_rdata;
                end else begin
                    ibus_ack <= 1;
                    ibus_dat_miso <= sysreg_rdata;
                end
                mem_pending <= 0;
                sysreg_pending <= 0;
                pending_bus <= BUS_NONE;
            end
        end
    end
end

endmodule
