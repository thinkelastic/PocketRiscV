//
// RGB565 Framebuffer for 320x240 resolution
// Memory-mapped at 0x28000000, 153,600 bytes (320*240*2)
// Each pixel is 16 bits: RRRRR_GGGGGG_BBBBB
//

`default_nettype none

module framebuffer (
    input wire clk,           // Video clock (12.288 MHz)
    input wire clk_cpu,       // CPU clock (133 MHz)
    input wire reset_n,

    // Video interface
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    output reg [23:0] pixel_color,

    // CPU memory interface
    input wire        mem_valid,
    input wire [31:0] mem_addr,
    input wire [31:0] mem_wdata,
    input wire [3:0]  mem_wstrb,
    output reg [31:0] mem_rdata,
    output reg        mem_ready
);

// Framebuffer dimensions
localparam FB_WIDTH = 320;
localparam FB_HEIGHT = 240;
localparam FB_SIZE = FB_WIDTH * FB_HEIGHT;  // 76,800 pixels

// Calculate pixel address for video output
// Linear address = y * 320 + x
wire [16:0] video_addr = pixel_y * FB_WIDTH + pixel_x;

// CPU address decoding
// Address format: 0x28000000 + (y * 640) + (x * 2)
// Word address = byte_addr[17:2], gives us 32-bit word containing 2 pixels
wire [16:0] cpu_pixel_addr = mem_addr[17:1];  // Pixel address (each pixel is 2 bytes)
wire [15:0] cpu_word_addr = mem_addr[17:2];   // Word address (2 pixels per word)
wire        cpu_pixel_sel = mem_addr[1];       // Which pixel in the word (0=low, 1=high)

// Video read - need to read 16-bit pixels, output 24-bit RGB
// Use 16-bit wide memory, one pixel per address
wire [15:0] video_pixel_data;

// Dual-port BRAM for framebuffer
// Port A: Video read (16-bit, pixel clock)
// Port B: CPU read/write (32-bit, CPU clock) - 2 pixels at a time
wire [31:0] cpu_read_data;

altsyncram #(
    .operation_mode("BIDIR_DUAL_PORT"),
    .width_a(16),
    .widthad_a(17),
    .numwords_a(76800),         // 320 * 240 pixels
    .width_b(32),
    .widthad_b(16),
    .numwords_b(38400),         // 76800 / 2 words
    .width_byteena_b(4),
    .lpm_type("altsyncram"),
    .outdata_reg_a("UNREGISTERED"),
    .outdata_reg_b("UNREGISTERED"),
    .intended_device_family("Cyclone V"),
    .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
    .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
    .power_up_uninitialized("TRUE")
) vram (
    // Port A - Video read (16-bit pixels)
    .clock0(clk),
    .address_a(video_addr),
    .data_a(16'b0),
    .wren_a(1'b0),
    .q_a(video_pixel_data),

    // Port B - CPU read/write (32-bit words = 2 pixels)
    .clock1(clk_cpu),
    .address_b(cpu_word_addr),
    .data_b(mem_wdata),
    .wren_b(mem_valid && !mem_ready && |mem_wstrb),
    .byteena_b(mem_wstrb),
    .q_b(cpu_read_data),

    // Unused ports
    .aclr0(1'b0),
    .aclr1(1'b0),
    .addressstall_a(1'b0),
    .addressstall_b(1'b0),
    .byteena_a(1'b1),
    .clocken0(1'b1),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .eccstatus(),
    .rden_a(1'b1),
    .rden_b(1'b1)
);

// Pipeline for video output (1 cycle BRAM latency)
reg [9:0] pixel_x_d1, pixel_y_d1;

always @(posedge clk) begin
    pixel_x_d1 <= pixel_x;
    pixel_y_d1 <= pixel_y;
end

// Convert RGB565 to RGB888
// RGB565: RRRRR_GGGGGG_BBBBB
// RGB888: RRRRRRRR_GGGGGGGG_BBBBBBBB
wire [4:0] r5 = video_pixel_data[15:11];
wire [5:0] g6 = video_pixel_data[10:5];
wire [4:0] b5 = video_pixel_data[4:0];

// Expand by replicating top bits into bottom bits for better color mapping
wire [7:0] r8 = {r5, r5[4:2]};
wire [7:0] g8 = {g6, g6[5:4]};
wire [7:0] b8 = {b5, b5[4:2]};

// Visible area check
wire in_visible_area = (pixel_x_d1 < FB_WIDTH) && (pixel_y_d1 < FB_HEIGHT);

// Generate pixel color
always @(*) begin
    if (in_visible_area)
        pixel_color = {r8, g8, b8};
    else
        pixel_color = 24'h000000;  // Black outside visible area
end

// CPU memory interface - handle ready signal
reg mem_pending;

always @(posedge clk_cpu) begin
    mem_ready <= 0;

    if (!reset_n) begin
        mem_pending <= 0;
    end else if (mem_valid && !mem_ready && !mem_pending) begin
        mem_pending <= 1;
    end else if (mem_pending) begin
        mem_ready <= 1;
        mem_pending <= 0;
        mem_rdata <= cpu_read_data;
    end
end

endmodule
