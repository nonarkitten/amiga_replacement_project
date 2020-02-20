`include "arg_defs.vh"

module dma_cache
(
  // Main reset & clock
  input             rst,         // Global reset
  input             clk,         // Master clock (28/56/85 MHz)
  // Generated clocks
  input             cck,         // CCK clock
  input             cdac_r,      // CDAC_n rising edge
  input             cdac_f,      // CDAC_n falling edge
  output            ena_28m,     // 28 MHz clock enable
  output      [2:0] cyc_28m,     // 28 MHz cycle number
  // Cache control
  input       [4:0] dma_chan,    // DMA channel number
  input             cache_hit,   // DMA cache hit
  input             flush_line,  // Flush current cache write line
  // Bus from ECS chipset
  input             bus_req,     // Bus access request
  input             bus_we,      // Write access to Chip RAM
  input      [22:1] bus_addr,    // Address from Agnus
  input      [15:0] bus_dout_er, // Bus data out (early read)
  output     [15:0] bus_din,     // Bus data in
  // Bus to SDRAM controller
  output            ram_sel,     // SDRAM select
  output     [23:1] ram_addr,    // SDRAM address
  output      [1:0] ram_bena,    // SDRAM byte enable
  input      [15:0] ram_rddata,  // SDRAM read data
  output     [15:0] ram_wrdata,  // SDRAM write data
  input             ram_rd_bst,  // SDRAM read burst
  input             ram_wr_bst   // SDRAM write burst
);

// Tags for Blitter's A channel
reg  [22:4] r_blt_src_a_tag; // Multicycle : 12
reg         r_blt_src_a_vld; // Multicycle : 12
reg         r_blt_src_a_hit; // Multicycle : 9
// Tags for Blitter's B channel
reg  [22:4] r_blt_src_b_tag; // Multicycle : 12
reg         r_blt_src_b_vld; // Multicycle : 12
reg         r_blt_src_b_hit; // Multicycle : 6
// Tags for Blitter's C channel
reg  [22:4] r_blt_src_c_tag; // Multicycle : 12
reg         r_blt_src_c_vld; // Multicycle : 12
reg         r_blt_src_c_hit; // Multicycle : 3

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_blt_src_a_tag <= 19'd0;
    r_blt_src_a_vld <= 1'b0;
    r_blt_src_a_hit <= 1'b0;
    r_blt_src_b_tag <= 19'd0;
    r_blt_src_b_vld <= 1'b0;
    r_blt_src_b_hit <= 1'b0;
    r_blt_src_c_tag <= 19'd0;
    r_blt_src_c_vld <= 1'b0;
    r_blt_src_c_hit <= 1'b0;
  end else begin
    if (cdac_r & cck) begin
      // Replace data in Blitter's read cache
      if (bus_we) begin
        r_blt_src_a_hit <=
          (bus_addr[22:4] == r_blt_src_a_tag)
            ? r_blt_src_a_vld
            : 1'b0;
        r_blt_src_b_hit <=
          (bus_addr[22:4] == r_blt_src_b_tag)
            ? r_blt_src_b_vld
            : 1'b0;
        r_blt_src_c_hit <=
          (bus_addr[22:4] == r_blt_src_c_tag)
            ? r_blt_src_c_vld
            : 1'b0;
      end else begin
        r_blt_src_a_hit <= 1'b0;
        r_blt_src_b_hit <= 1'b0;
        r_blt_src_c_hit <= 1'b0;
      end
    end
      
    if (cdac_r & ~cck) begin
      // Keep track of blitter accesses
      case (dma_chan)
        5'h18 : // Channel C
        begin
          r_blt_src_c_vld <= 1'b1;
          r_blt_src_c_tag <= bus_addr[22:4];
        end
        5'h19 : // Channel B
        begin
          r_blt_src_b_vld <= 1'b1;
          r_blt_src_b_tag <= bus_addr[22:4];
        end
        5'h1A : // Channel A
        begin
          r_blt_src_a_vld <= 1'b1;
          r_blt_src_a_tag <= bus_addr[22:4];
        end
        default :
          ;
      endcase
    end
  end
end

reg   [8:0] r_dpram_addr_a; // Multicycle : 3
reg         r_dpram_wren_a; // Multicycle : 3

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_dpram_addr_a <= 8'd0;
    r_dpram_wren_a <= 1'b0;
  end else if (ena_28m) begin
    case (cyc_28m)
      3'd0 :
      begin
        // Update current channel's cache line
        r_dpram_addr_a <= { 1'b0, dma_chan, bus_addr[3:1] };
        r_dpram_wren_a <= bus_we;
      end
      3'd1 :
      begin
        // Update Blitter C channel's cache line
        if (bus_we) r_dpram_addr_a[8:3] <= 6'h18;
        r_dpram_wren_a <= bus_we & r_blt_src_c_hit;
      end
      3'd2 :
      begin
        // Update Blitter B channel's cache line
        if (bus_we) r_dpram_addr_a[8:3] <= 6'h19;
        r_dpram_wren_a <= bus_we & r_blt_src_b_hit;
      end
      3'd3 :
      begin
        // Update Blitter A channel's cache line
        if (bus_we) r_dpram_addr_a[8:3] <= 6'h1A;
        r_dpram_wren_a <= bus_we & r_blt_src_a_hit;
      end
      default :
      begin
        r_dpram_addr_a <= { 1'b0, dma_chan, bus_addr[3:1] };
        r_dpram_wren_a <= 1'b0;
      end
    endcase
  end
end

reg   [8:0] r_dpram_addr_b;
reg         r_sdram_sel;    // Multicycle : 6
reg  [23:1] r_sdram_addr;   // Multicycle : 6

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_dpram_addr_b <= 8'd0;
    r_sdram_addr   <= 23'd0;
    r_sdram_sel    <= 1'b0;
  end else begin
    if (cdac_f & ~cck) begin
      if (flush_line) begin
        // Write current word last into SDRAM
        r_dpram_addr_b <= { 1'b0, dma_chan, ~bus_addr[3], bus_addr[2:1] };
        r_sdram_addr   <= { 1'b0, bus_addr[22:4], ~bus_addr[3], bus_addr[2:1] };
      end else begin
        // Read requested word first from SDRAM
        r_dpram_addr_b <= { 1'b0, dma_chan, bus_addr[3:1] };
        r_sdram_addr   <= { 1'b0, bus_addr[22:4], bus_addr[3:1] };
      end
      r_sdram_sel <= bus_req & (flush_line | ~cache_hit);      
    end
    if (ram_rd_bst | ram_wr_bst) begin
      r_dpram_addr_b[2:0] <= r_dpram_addr_b[2:0] + 3'd1;
    end
  end
end

assign ram_sel  = r_sdram_sel;
assign ram_addr = r_sdram_addr;

wire        w_rden_a;
wire        w_wren_a;
wire [17:0] w_data_a;
wire [17:0] w_q_a;

wire        w_rden_b;
wire        w_wren_b;
wire [17:0] w_data_b;
wire [17:0] w_q_b;

cache_ram U_cache_ram
(
  .clk(clk),
  .rden_a(w_rden_a),
  .wren_a(w_wren_a),
  .address_a(r_dpram_addr_a),
  .data_a(w_data_a),
  .q_a(w_q_a),
  .rden_b(w_rden_b),
  .wren_b(w_wren_b),
  .address_b(r_dpram_addr_b),
  .data_b(w_data_b),
  .q_b(w_q_b)
);

assign w_rden_a    = cdac_r & ~cck & ~bus_we & bus_req;
assign w_wren_a    = r_dpram_wren_a & ena_28m;
assign w_data_a    = { 1'b1, bus_dout_er[15:8], 1'b1, bus_dout_er[7:0] };
assign bus_din     = { w_q_a[16:9], w_q_a[7:0] };

assign w_rden_b    = ram_wr_bst;
assign w_wren_b    = ram_rd_bst | ram_wr_bst;
assign w_data_b    = (ram_rd_bst)
                   ? { 1'b1, ram_rddata[15:8], 1'b1, ram_rddata[7:0] }
                   : 18'h00000;
assign ram_wrdata  = { w_q_b[16:9], w_q_b[7:0] };

assign ram_bena[0] = w_q_b[8];
assign ram_bena[1] = w_q_b[17];


endmodule

module cache_ram
(
  input         clk,
  // Port A
  input         rden_a,
  input         wren_a,
  input   [8:0] address_a,
  input  [17:0] data_a,
  output [17:0] q_a,
  // Port B
  input         rden_b,
  input         wren_b,
  input   [8:0] address_b,
  input  [17:0] data_b,
  output [17:0] q_b
);

`ifdef SIMULATION

// Infered block RAM
reg  [17:0] r_mem_blk [0:511];

initial begin
  $readmemh("dpram_clear.mem", r_mem_blk);
end

// Port A side
reg  [17:0] r_q_a_p0;
reg  [17:0] r_q_a_p1;

always@(posedge clk) begin
  if (rden_a) begin
    r_q_a_p0 <= r_mem_blk[address_a];
  end
  r_q_a_p1 <= r_q_a_p0;
  if (wren_a) begin
    r_mem_blk[address_a] <= data_a;
  end
end

assign q_a = r_q_a_p1;

// Port B side
reg  [17:0] r_q_b;

always@(posedge clk) begin
  if (rden_b) begin
    r_q_b <= r_mem_blk[address_b];
  end
  if (wren_b) begin
    r_mem_blk[address_b] <= data_b;
  end
end

assign q_b = r_q_b;

`else

  altsyncram U_altsyncram_512x18
  (
    .clock0 (clk),
    .rden_a (rden_a),
    .wren_a (wren_a),
    .byteena_a (2'b11),
    .address_a (address_a),
    .data_a (data_a),
    .q_a (q_a),
    .rden_b (rden_b),
    .wren_b (wren_b),
    .byteena_b (2'b11),
    .address_b (address_b),
    .data_b (data_b),
    .q_b (q_b),
    .aclr0 (1'b0),
    .aclr1 (1'b0),
    .addressstall_a (1'b0),
    .addressstall_b (1'b0),
    .clock1 (1'b1),
    .clocken0 (1'b1),
    .clocken1 (1'b1),
    .clocken2 (1'b1),
    .clocken3 (1'b1),
    .eccstatus ()
  );
  defparam
    U_altsyncram_512x18.address_reg_b = "CLOCK0",
    U_altsyncram_512x18.byteena_reg_b = "CLOCK0",
    U_altsyncram_512x18.byte_size = 9,
    U_altsyncram_512x18.clock_enable_input_a = "BYPASS",
    U_altsyncram_512x18.clock_enable_input_b = "BYPASS",
    U_altsyncram_512x18.clock_enable_output_a = "BYPASS",
    U_altsyncram_512x18.clock_enable_output_b = "BYPASS",
    U_altsyncram_512x18.indata_reg_b = "CLOCK0",
    U_altsyncram_512x18.init_file = init_file,
    U_altsyncram_512x18.init_file_layout = "PORT_A",
    U_altsyncram_512x18.intended_device_family = "Cyclone III",
    U_altsyncram_512x18.lpm_type = "altsyncram",
    U_altsyncram_512x18.numwords_a = 512,
    U_altsyncram_512x18.numwords_b = 512,
    U_altsyncram_512x18.operation_mode = "BIDIR_DUAL_PORT",
    U_altsyncram_512x18.outdata_aclr_a = "NONE",
    U_altsyncram_512x18.outdata_aclr_b = "NONE",
    U_altsyncram_512x18.outdata_reg_a = "CLOCK0",
    U_altsyncram_512x18.outdata_reg_b = "UNREGISTERED",
    U_altsyncram_512x18.power_up_uninitialized = "FALSE",
    U_altsyncram_512x18.read_during_write_mode_mixed_ports = "DONT_CARE",
    U_altsyncram_512x18.read_during_write_mode_port_a = "DONT_CARE",
    U_altsyncram_512x18.read_during_write_mode_port_b = "OLD_DATA",
    U_altsyncram_512x18.widthad_a = 9,
    U_altsyncram_512x18.widthad_b = 9,
    U_altsyncram_512x18.width_a = 18,
    U_altsyncram_512x18.width_b = 18,
    U_altsyncram_512x18.width_byteena_a = 2,
    U_altsyncram_512x18.width_byteena_b = 2,
    U_altsyncram_512x18.wrcontrol_wraddress_reg_b = "CLOCK0";

`endif

endmodule

