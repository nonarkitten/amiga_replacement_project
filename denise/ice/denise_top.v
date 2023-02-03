module denise_top
(
  // Clocks and reset
  input             RESET_n,    // Global reset from FT2232 chip
  input             FPGA_CLK,   // 27 MHz clock from crystal
  input             VID_CLK,    // PAL or NTSC clock from MK2712
  // 8 MB 16-bit Cypress SSRAM
  output            RAM_CLK,
  output            RAM_CE,
  output            RAM_WE_n,
  output            RAM_BWB_n,
  output            RAM_BWA_n,
  output     [21:0] RAM_A,
  inout      [15:0] RAM_D,
  // FT2232 interface
  inout      [7:0]  USB_D,
  input             USB_TXE_n,
  input             USB_RXF_n,
  output            USB_RD_n,
  output            USB_WR,
  // 30-bit VGA output
  output            VGA_CLK,
  output reg        VGA_VSYNC,
  output reg        VGA_HSYNC,
  output reg        VGA_CSYNC,
  output reg        VGA_BLANK,
  output reg [9:0]  VGA_R,
  output reg [9:0]  VGA_G,
  output reg [9:0]  VGA_B,
  // CSG 8362R8 Denise chip
  input      [8:1]  RGA,
  input      [15:0] DB,
  input             C7M,
  input             CCK,
  input             CDAC_n,
  //input       [3:0] RED,
  //input       [3:0] GRN,
  //input       [3:0] BLU,
  //input             BURST_n,
  input             CSYNC_n,
  input             ZD_n,
  // CSG 8364R7 Paula chip
  input             DSK_RD_n,
  input             DSK_WD_n,
  input             DSK_WE_n,
  input             RXD_n,
  input             TXD_n,
  input             DMAL,
  input             INT2_n,
  input             INT3_n,
  input             INT6_n,
  input      [2:0]  IPL_n,
  output            AUDIO_L,
  output            AUDIO_R
);

wire [3:0] RED = 4'b0000;
wire [3:0] GRN = 4'b0000;
wire [3:0] BLU = 4'b0000;

/*
//////////////////////////////////////////////////////
// PLL that generates 28/56/85 MHz clock from 7 MHz //
//////////////////////////////////////////////////////

wire w_arst_n;
wire clk_28m;
wire clk_56m;
wire clk_85m;
wire w_c7m_rise;

pll_cbm pll_inst
(
  .areset(1'b0),
  .inclk0(C7M),
  .c0(clk_28m),
  .c1(clk_56m),
  .c2(clk_85m),
  .c3(w_c7m_rise),
  .locked(w_arst_n)
);

/////////////////////////////////////////////////
// Re-generated CCK and CDAC_n clocks @ 28 MHz //
/////////////////////////////////////////////////

reg       r_cck_28m;
reg [7:0] r_cck_ph_28m;
reg [3:0] r_cdac_ph_28m;

always@(posedge clk_28m) begin
  // CCK phases
  if ((w_c7m_rise) && (CCK))
    r_cck_ph_28m <= 8'b00000100;
  else
    r_cck_ph_28m <= { r_cck_ph_28m[6:0], r_cck_ph_28m[7] };
  // Re-generated CCK
  r_cck_28m <= (|r_cck_ph_28m[2:0]) | r_cck_ph_28m[7];
  // CDAC phases
  if (w_c7m_rise)
    r_cdac_ph_28m <= 4'b0100;
  else
    r_cdac_ph_28m <= { r_cdac_ph_28m[2:0], r_cdac_ph_28m[3] };
end

/////////////////////////////////////////////////
// Re-generated CCK and CDAC_n clocks @ 56 MHz //
/////////////////////////////////////////////////

reg        r_cck_56m;
reg [15:0] r_cck_ph_56m;
reg  [7:0] r_cdac_ph_56m;

always@(posedge clk_56m) begin
  // CCK phases
  if ((w_c7m_rise) && (CCK))
    r_cck_ph_56m <= 16'b0000000000010000;
  else
    r_cck_ph_56m <= { r_cck_ph_56m[14:0], r_cck_ph_56m[15] };
  // Re-generated CCK
  r_cck_56m <= (|r_cck_ph_56m[6:0]) | r_cck_ph_56m[15];
  // CDAC phases
  if (w_c7m_rise)
    r_cdac_ph_56m <= 8'b00010000;
  else
    r_cdac_ph_56m <= { r_cdac_ph_56m[6:0], r_cdac_ph_56m[7] };
end

/////////////////////////////////////////////////
// Re-generated CCK and CDAC_n clocks @ 85 MHz //
/////////////////////////////////////////////////

reg  [1:0] r_cck_cc_85m;
reg        r_cck_85m;
reg [23:0] r_cck_ph_85m;
reg [11:0] r_cdac_ph_85m;

always@(posedge clk_85m) begin
  r_cck_cc_85m <= { r_cck_cc_85m[0], CCK };
  // CCK phases
  if ((w_c7m_rise) && (r_cck_cc_85m[1]))
    r_cck_ph_85m <= 24'b000000000000000001000000;
  else
    r_cck_ph_85m <= { r_cck_ph_85m[22:0], r_cck_ph_85m[23] };
  // Re-generated CCK
  r_cck_85m <= (|r_cck_ph_85m[10:0]) | r_cck_ph_85m[23];
  // CDAC phases
  if (w_c7m_rise)
    r_cdac_ph_85m <= 12'b000001000000;
  else
    r_cdac_ph_85m <= { r_cdac_ph_85m[10:0], r_cdac_ph_85m[11] };
end

wire        w_clk;
wire        w_cck;
wire        w_28m_edge;
wire        w_cdac_rise;
wire        w_cdac_fall;
wire [15:0] w_rga;
wire [15:0] w_dbi;
wire  [3:0] w_ami_red;
wire  [3:0] w_ami_grn;
wire  [3:0] w_ami_blu;

//assign w_clk       = clk_28m;
//assign w_cck       = r_cck_28m;
//assign w_cdac_rise = r_cdac_ph_28m[0];
//assign w_cdac_fall = r_cdac_ph_28m[2];

//assign w_clk       = clk_56m;
//assign w_cck       = r_cck_56m;
//assign w_cdac_rise = r_cdac_ph_56m[1];
//assign w_cdac_fall = r_cdac_ph_56m[5];

assign w_clk       = clk_85m;
assign w_cck       = r_cck_85m;
assign w_28m_edge  = r_cdac_ph_85m[2] | r_cdac_ph_85m[5] 
                   | r_cdac_ph_85m[8] | r_cdac_ph_85m[11];
assign w_cdac_rise = r_cdac_ph_85m[2];
assign w_cdac_fall = r_cdac_ph_85m[8];

assign w_rga       = RGA;
assign w_dbi       = DB;
assign w_ami_red   = RED;
assign w_ami_grn   = GRN;
assign w_ami_blu   = BLU;
*/

///////////////////////////////////////////////////////
// PLL that generates 28/56/85 MHz clock from 17 MHz //
///////////////////////////////////////////////////////

wire w_arst_n;
wire clk_28m;
wire clk_56m;
wire clk_85m;
wire w_c7m_rise;

pll_ctp pll_inst
(
  .areset(1'b0),
  .inclk0(VID_CLK),
  .c0(clk_28m),
  .c1(clk_56m),
  .c2(clk_85m),
  .c3(w_c7m_rise),
  .locked(w_arst_n)
);

/////////////////////////////////////////////////////////
// Synchronous reset for the 28/56/85 MHz clock domain //
/////////////////////////////////////////////////////////

reg [1:0] r_arst_cc;
reg       r_srst;

always@(negedge w_arst_n or posedge w_clk) begin
  if (!w_arst_n) begin
    r_arst_cc <= 2'b11;
    r_srst    <= 1'b1;
  end
  else begin
    r_arst_cc <= { r_arst_cc[0], 1'b0 };
    r_srst    <= r_arst_cc[1];
  end
end

///////////////////////////////////////////////////////
// Clock domain crossing : 7 MHz Amiga -> 85 MHz CTP //
///////////////////////////////////////////////////////

reg  [2:0] r_cck_cc_85m;
reg  [7:0] r_cck_85m;
reg  [4:0] r_c7m_cc_85m;
reg  [4:0] r_cdac_cc_85m;
reg        r_cdac_r_85m;
reg        r_cdac_f_85m;
reg  [1:0] r_28m_ctr_85m;
reg        r_28m_edge_85m;
reg        r_28m_ami_85m;
reg  [8:1] r_rga_cc_85m [0:2];
reg [15:0] r_dbi_cc_85m [0:2];
reg  [3:0] r_red_cc_85m [0:2];
reg  [3:0] r_grn_cc_85m [0:2];
reg  [3:0] r_blu_cc_85m [0:2];

always @(posedge clk_85m) begin
  r_cck_cc_85m    <= { r_cck_cc_85m[1:0], CCK };
  r_c7m_cc_85m    <= { r_c7m_cc_85m[3:0], C7M };
  r_cdac_cc_85m   <= { r_cdac_cc_85m[3:0], CDAC_n };
  r_cdac_r_85m    <= (r_cdac_cc_85m[4:1] == 4'b0011) ? 1'b1 : 1'b0;
  r_cdac_f_85m    <= (r_cdac_cc_85m[4:1] == 4'b1100) ? 1'b1 : 1'b0;
  r_28m_ami_85m   <= (r_cdac_cc_85m[4:1] == 4'b0011) // CDAC_n rises
                  || (r_cdac_cc_85m[4:1] == 4'b1100) // CDAC_n falls
                  || (r_c7m_cc_85m[4:1] == 4'b0011)  // C7M rises
                  || (r_c7m_cc_85m[4:1] == 4'b1100)  // C7M falls
                  ? 1'b1 : 1'b0;
  if (r_28m_ami_85m) begin
    if (r_cdac_f_85m & r_cck_cc_85m[2])
      r_cck_85m <= 8'b00001111;
    else
      r_cck_85m <= { r_cck_85m[6:0], r_cck_85m[7] };
  end
  if (r_28m_ctr_85m == 2'b10) begin
    r_28m_ctr_85m  <= 2'b00;
    r_28m_edge_85m <= 1'b1;
  end
  else begin
    r_28m_ctr_85m  <= r_28m_ctr_85m + 2'd1;
    r_28m_edge_85m <= 1'b0;
  end
  r_rga_cc_85m[0] <= RGA;
  r_rga_cc_85m[1] <= r_rga_cc_85m[0];
  r_rga_cc_85m[2] <= r_rga_cc_85m[1];
  r_dbi_cc_85m[0] <= DB;
  r_dbi_cc_85m[1] <= r_dbi_cc_85m[0];
  r_dbi_cc_85m[2] <= r_dbi_cc_85m[1];
  r_red_cc_85m[0] <= RED;
  r_red_cc_85m[1] <= r_red_cc_85m[0];
  r_red_cc_85m[2] <= r_red_cc_85m[1];
  r_grn_cc_85m[0] <= GRN;
  r_grn_cc_85m[1] <= r_grn_cc_85m[0];
  r_grn_cc_85m[2] <= r_grn_cc_85m[1];
  r_blu_cc_85m[0] <= BLU;
  r_blu_cc_85m[1] <= r_blu_cc_85m[0];
  r_blu_cc_85m[2] <= r_blu_cc_85m[1];
end

wire        w_clk;
wire        w_clk_28m;
wire        w_cck;
wire        w_cckq;
wire        w_28m_edge;
wire        w_cdac_rise;
wire        w_cdac_fall;
wire [15:0] w_rga;
wire [15:0] w_dbi;
wire  [3:0] w_ami_red;
wire  [3:0] w_ami_grn;
wire  [3:0] w_ami_blu;

assign w_clk       = clk_85m;
assign w_clk_28m   = r_28m_ami_85m;
assign w_cck       = r_cck_85m[0];
assign w_cckq      = r_cck_85m[2];
assign w_28m_edge  = r_28m_edge_85m;
assign w_cdac_rise = r_cdac_r_85m;
assign w_cdac_fall = r_cdac_f_85m;
assign w_rga       = r_rga_cc_85m[2];
assign w_dbi       = r_dbi_cc_85m[2];
assign w_ami_red   = r_red_cc_85m[2];
assign w_ami_grn   = r_grn_cc_85m[2];
assign w_ami_blu   = r_blu_cc_85m[2];


/////////////////////////////
// Instantiate Denise chip //
/////////////////////////////

wire [15:0] w_dbo_d;
wire        w_dbo_d_en;
wire  [3:0] w_red;
wire  [3:0] w_green;
wire  [3:0] w_blue;
wire        w_sol;
wire        w_blank_n;
wire        w_vsync;

Denise Denise_inst
(
  .clk(w_clk),
  .cck(w_cck),
  .cdac_r(w_cdac_rise),
  .cdac_f(w_cdac_fall),
  .cfg_ecs(1'b1),
  .cfg_a1k(1'b0),
  .rga(w_rga),
  .dbi(w_dbi),
  .dbo(w_dbo_d),
  .dbo_en(w_dbo_d_en),
  .red(w_red),
  .green(w_green),
  .blue(w_blue),
  .vsync(w_vsync),
  .blank_n(w_blank_n),
  .sol(w_sol),
  .pal_ntsc()
);
  
denise_quad m0h(
  .clk(cckq), 
  .quadMux(m0h_in),
  .count(r_JOY0DAT[7:0])
);
denise_quad m0v(
  .clk(cckq), 
  .quadMux(m0v_in),
  .count(r_JOY0DAT[15:8])
);
denise_quad m1h(
  .clk(cckq),
  .quadMux(m1h_in),
  .count(r_JOY1DAT[7:0])
);
denise_quad m1v(
  .clk(cckq),
  .quadMux(m1v_in),
  .count(r_JOY1DAT[15:8])
);


/////////////////
// Scandoubler //
/////////////////

reg   [1:0] r_csync_cc;

always@(posedge w_clk)
  r_csync_cc <= { r_csync_cc[0], CSYNC_n };

wire [13:0] w_data_wr;

assign w_data_wr[13]   = w_sol;              // Start of line
assign w_data_wr[12]   = w_blank_n;          // Composite blanking
assign w_data_wr[11:8] = w_red;              // Red component
assign w_data_wr[7:4]  = w_green;            // Green component
assign w_data_wr[3:0]  = w_blue;             // Blue component

reg  [11:0] r_addr_wr;

// Write side : 14 MHz pixel clock
always@(posedge w_clk) begin
  if (w_cdac_rise | w_cdac_fall) begin
    if (w_sol) begin
      r_addr_wr[9:0]   <= 10'd0;
      r_addr_wr[11:10] <= r_addr_wr[11:10] + 2'd1;
    end
    else begin
      r_addr_wr[9:0]   <= r_addr_wr[9:0] + 10'd1;
    end
  end
end

// Dual line buffer : 2 x 1024 x 15-bits
altsyncram line_buf_inst
(
  // Write side : 15 KHz
  .clock0    (w_clk),
  .wren_a    (w_cdac_rise | w_cdac_fall),
  .address_a (r_addr_wr),
  .data_a    (w_data_wr),
  // Read side : 31 KHz
  .clock1    (w_clk),
  .rden_b    (w_28m_edge),
  .address_b (r_addr_rd),
  .q_b       (w_data_rd)
);
defparam 
    line_buf_inst.operation_mode = "DUAL_PORT",
    line_buf_inst.width_a        = 14,
    line_buf_inst.widthad_a      = 12,
    line_buf_inst.width_b        = 14,
    line_buf_inst.widthad_b      = 12;
    
wire [13:0] w_data_rd;
reg  [11:0] r_addr_rd;
reg         r_line_tgl;
reg         r_hsync;
reg         r_vsync;
reg         r_csync;

// Read side : 28 MHz pixel clock
always@(posedge w_clk) begin
  if (w_28m_edge) begin
    if (w_sol & w_vsync) begin
      r_addr_rd[11:10] <= r_addr_wr[11:10] - 2'd2;
      r_line_tgl <= 1'b0;
    end
    else if (w_data_rd[13]) begin
      r_line_tgl <= ~r_line_tgl;
      if (r_line_tgl) r_addr_rd[11:10] <= r_addr_rd[11:10] + 2'd1;
    end
    if (w_data_rd[13] | (w_sol & w_vsync))
      r_addr_rd[9:0] <= 10'd1;
    else
      r_addr_rd[9:0] <= r_addr_rd[9:0] + 10'd1;
    // Horizontal and vertical synchro
    if (r_addr_rd[9:0] == 10'd511)
      r_csync <= r_csync_cc[1];
    if (r_addr_rd[9:0] == 10'd1) begin
      r_hsync <= 1'b1;
    end
    else if (r_addr_rd[9:0] == 10'd68) begin
      r_hsync <= 1'b0;
      r_vsync <= ~r_csync;
    end
  end
end

reg [3:0] r_real_r;
reg [3:0] r_real_g;
reg [3:0] r_real_b;

reg [3:0] r_fpga_r;
reg [3:0] r_fpga_g;
reg [3:0] r_fpga_b;

reg       r_mismatch;
reg [3:0] r_mis_filt;

// Screen comparator
always@(posedge w_clk) begin
  if (w_cdac_rise | w_cdac_fall) begin
    // The real stuff
    r_real_r <= w_ami_red;
    r_real_g <= w_ami_grn;
    r_real_b <= w_ami_blu;
    // The FPGA stuff
    r_fpga_r <= w_red;
    r_fpga_g <= w_green;
    r_fpga_b <= w_blue;
    if (((r_real_r != r_fpga_r) ||
         (r_real_g != r_fpga_g) ||
         (r_real_b != r_fpga_b)) &&
         (w_blank_n == 1'b1))
      r_mis_filt <= { r_mis_filt[2:0], 1'b1 };
    else
      r_mis_filt <= { r_mis_filt[2:0], 1'b0 };
    r_mismatch <= &r_mis_filt;
  end
end

assign VGA_CLK = ~w_clk;
// VGA output
always@(posedge w_clk) begin
  //VGA_CLK   <= ~w_28m_edge;
  VGA_VSYNC <= r_vsync;
  VGA_HSYNC <= r_hsync;
  VGA_CSYNC <= 1'b0;
  VGA_BLANK <= w_data_rd[12];
  VGA_R     <= { w_data_rd[11:8], w_data_rd[11:8], 2'b00 };
  VGA_G     <= {  w_data_rd[7:4],  w_data_rd[7:4], 2'b00 };
  VGA_B     <= {  w_data_rd[3:0],  w_data_rd[3:0], 2'b00 };
end

// SSRAM disabled
assign RAM_CLK   = 1'b0;
assign RAM_CE    = 1'b0;
assign RAM_WE_n  = 1'b1;
assign RAM_BWA_n = 1'b1;
assign RAM_BWB_n = 1'b1;

// DEBUG, to be removed
assign RAM_A[15:0] = { w_dmal, r_mismatch, w_dbo_d_en | w_dbo_p_en, r_vsync, w_red, w_green, w_blue };
assign RAM_D[15:0] = w_dbo_d | w_dbo_p;

endmodule
