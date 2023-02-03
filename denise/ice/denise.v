// Copyright 2011, 2012 Frederic Requin
//
// This file is part of the MCC216 project
//
// Denise re-implementation is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Denise re-implementation is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// The Denise core:
// ----------------
//  - It can interface with a real Amiga OCS/ECS HW
//  - It uses the 7 MHz clock (C7M) to generate a 28/56/85 MHz master clock
//  - CDAC_n and CCK phases are based on CCK value at rising edge of C7M
//  - Data bus (DB) is latched one cycle after address bus (RGA)
//  - The design does not have a reset input
//  - The design uses strobe cycles for the vertical blanking and lines lengths
//  - The design size is only 1120 LEs on a Cyclone III

/*

clk, cck, cdac_r & cdac_f are generated using a PLL :

wire clk;            // 28 MHz master clock
wire w_c7m_rise;     // 7 MHz rising edge

pll_28m pll_inst
(
  .areset(1'b0),
  .inclk0(C7M),
  .c0(clk),
  .c1(),
  .c2(),
  .c3(w_c7m_rise),
  .locked()
);

wire w_cck_rise;     // CCK rising edge
wire w_cdac_rise;    // CDAC_n rising edge
wire w_cdac_fall;    // CDAC_n falling edge

reg       r_cck_gen; // Re-generated CCK
reg [7:0] r_cck_ph;  // CCK clock phases
reg [3:0] r_cdac_ph; // CDAC_n clock phases

always@(posedge clk) begin
  // CCK phases
  if ((w_c7m_rise) && (CCK))
    r_cck_ph <= 8'b00001000;
  else
    r_cck_ph <= { r_cck_ph[6:0], r_cck_ph[7] };
  // Re-generated CCK
  r_cck_gen <= r_cck_ph[0] | r_cck_ph[1] | r_cck_ph[2] | r_cck_ph[7];
  // CDAC phases
  if (w_c7m_rise)
    r_cdac_ph <= 4'b0100;
  else
    r_cdac_ph <= { r_cdac_ph[2:0], r_cdac_ph[3] };
end

assign w_cck_rise  = r_cck_ph[0];
assign w_cdac_rise = r_cdac_ph[0];
assign w_cdac_fall = r_cdac_ph[2];

*/

module Denise
(
  // Main clock
  input             clk,       // Master clock (28/56/85 MHz)
  // Generated clocks
  input             cck,       // CCK clock
  input             cdac_r,    // CDAC_n rising edge
  input             cdac_f,    // CDAC_n falling edge
  // Configuration
  input             cfg_ecs,   // OCS(0) or ECS(1) chipset
  input             cfg_a1k,   // Normal mode(0), A1000 mode(1)
  // Busses
  input       [8:1] rga,       // RGA bus
  input      [15:0] db_in,     // Data bus input
  output reg [15:0] db_out,    // Data bus output
  output reg        db_oen,    // Data bus output enable
  // Video output
  output      [3:0] red,       // Red component output
  output      [3:0] green,     // Green component output
  output      [3:0] blue,      // Blue component output
  output reg        vsync,     // Vertical synchro
  output            blank_n,   // Composite blanking
  output reg        sol,       // Start of line (HPOS = 32)
  output            pal_ntsc   // PAL (1), NSTC (0) flag
);

// Measured values:
// ----------------

// HSSTRT : $01A (PAL), $01A (NTSC)
// HSSTOP : $03B,$029 (PAL), $03B, $02B (NTSC)
// HBSTRT : $00E (PAL), $00D (NTSC)
// HBSTOP : $05C (PAL), $05C (NTSC)

// PAL interlaced:
// ---------------
//   8 x STREQU \
//  18 x STRVBL  | 312 lines
// 286 x STRHOR /
//   9 x STREQU \
//  17 x STRVBL  | 313 lines
// 287 x STRHOR /

// PAL non-interlaced:
// -------------------
//   9 x STREQU \
//  17 x STRVBL  | 313 lines
// 287 x STRHOR /

// NTSC interlaced:
// ----------------
//  10 x STREQU \
//  11 x STRVBL  | 262 lines with 131 x STRLONG
// 241 x STRHOR /
//  10 x STREQU \
//  11 x STRVBL  | 263 lines with 131/132 x STRLONG
// 242 x STRHOR /

// NTSC non-interlaced:
// --------------------
//  10 x STREQU \
//  11 x STRVBL  | 263 lines with with 131/132 x STRLONG
// 242 x STRHOR /

//////////////////////
// DMA slot counter //
//////////////////////

//reg [7:0] r_slot_p1;
//
//always@(posedge clk) begin
//  // Rising edge of CDAC_n with CCK = 1
//  if ((cdac_r) && (cck)) begin
//    if ((r_wregs_str_p1) && (r_rga_p1[2:1] != 2'b11))
//      r_slot_p1 <= 8'd0;
//    else
//      r_slot_p1 <= r_slot_p1 + 8'd1;
//  end
//end

///////////////////////////////
// Register address decoding //
///////////////////////////////

reg  [5:1] r_rga_p1;
reg        r_rregs_clx_p1;
reg        r_wregs_str_p1;
reg        r_rregs_id_p1;
reg        r_wregs_diwb_p1;
reg        r_wregs_diwe_p1;
reg        r_wregs_clx_p1;
reg        r_wregs_ctl_p1;
reg        r_wregs_bpl_p1;
reg        r_wregs_spr_p1;
reg        r_wregs_clut_p1;
reg        r_wregs_diwh_p1;

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if (cdac_r & cck) begin
    // CLXDAT : $00E
    if (rga[8:1] == 8'b0_0000_111)
      r_rregs_clx_p1 <= 1'b1;
    else
      r_rregs_clx_p1 <= 1'b0;
    // Strobes : $038 - $03E
    if (rga[8:3] == 6'b0_0011_1)
      r_wregs_str_p1  <= 1'b1;
    else
      r_wregs_str_p1  <= 1'b0;
    // DENISEID : $07C
    if (rga[8:1] == 8'b0_0111_110)
      r_rregs_id_p1 <= 1'b1;
    else
      r_rregs_id_p1 <= 1'b0;
    // DIWSTRT : $08E
    if (rga[8:1] == 8'b0_1000_111)
      r_wregs_diwb_p1 <= 1'b1;
    else
      r_wregs_diwb_p1 <= 1'b0;
    // DIWSTOP : $090
    if (rga[8:1] == 8'b0_1001_000)
      r_wregs_diwe_p1 <= 1'b1;
    else
      r_wregs_diwe_p1 <= 1'b0;
    // CLXCON : $098
    if (rga[8:1] == 8'b0_1001_100)
      r_wregs_clx_p1 <= 1'b1;
    else
      r_wregs_clx_p1 <= 1'b0;
    // BPLCONx : $100 - $106
    if (rga[8:3] == 6'b1_0000_0)
      r_wregs_ctl_p1  <= 1'b1;
    else
      r_wregs_ctl_p1  <= 1'b0;
    // BPLxDAT : $110 - $11E
    if (rga[8:4] == 5'b1_0001)
      r_wregs_bpl_p1  <= 1'b1;
    else
      r_wregs_bpl_p1  <= 1'b0;
    // Sprites : $140 - $17E
    if (rga[8:6] == 3'b1_01)
      r_wregs_spr_p1  <= 1'b1;
    else
      r_wregs_spr_p1  <= 1'b0;
    // Color table : $180 - $1BE
    if (rga[8:6] == 3'b1_10)
      r_wregs_clut_p1 <= 1'b1;
    else
      r_wregs_clut_p1 <= 1'b0;
    // DIWHIGH : $1E4
    if (rga[8:1] == 8'b1_1110_010)
      r_wregs_diwh_p1 <= 1'b1;
    else
      r_wregs_diwh_p1 <= 1'b0;
    // Latch RGA bits 5 - 1 for next cycle
    r_rga_p1 <= rga[5:1];
  end
end

///////////////////
// PAL/NTSC flag //
///////////////////

reg [1:0] r_str_ctr;

always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r & cck) begin
    if (r_wregs_str_p1) begin
      // STRLONG strobes reset the counter
      if (r_rga_p1[2:1] == 2'b11)
        r_str_ctr <= 2'b00;
      else if (r_str_ctr != 2'b11)
        r_str_ctr <= r_str_ctr + 2'd1;
    end
  end
end

assign pal_ntsc = &r_str_ctr;

//////////////////////
// Vertical synchro //
//////////////////////

reg [3:0] r_equ_ctr;

always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r & cck) begin
    if (r_wregs_str_p1) begin
      // Discard STRLONG strobes
      if (r_rga_p1[2:1] != 2'b11) begin
        // STREQU strobes increment counter
        if (r_rga_p1[2:1] == 2'b00)
          r_equ_ctr <= r_equ_ctr + 4'd1;
        // STRVBL and STRHOR strobes clear it
        else
          r_equ_ctr <= 4'd0;
      end
    end
  end
  if (cdac_r) begin
    if (sol) begin
      vsync <= |r_equ_ctr;
    end
  end
end

////////////////////////
// Horizontal counter //
////////////////////////

wire      w_hpos_clr;
wire      w_hpos_dis;
reg [8:0] r_hpos;
reg       r_lol_ena;

// HPOS clear conditions
assign w_hpos_clr = (((r_rga_p1[2:1] == 2'b00) && (cfg_ecs)) || 
                     (r_rga_p1[2:1] == 2'b01) ||
                     (r_rga_p1[2:1] == 2'b10)) ? (r_wregs_str_p1 & cck) : 1'b0;
// HPOS disable conditions
assign w_hpos_dis = (r_rga_p1[2:1] == 2'b11) ? (r_wregs_str_p1 & cck) : 1'b0;

always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r) begin
    if (w_hpos_clr) begin
      // STREQU (ECS only), STRVBL or STRHOR : HPOS starts at 2
      r_hpos    <= 9'd2;
      r_lol_ena <= 1'b0;
    end
    else begin
      // STRLONG : long line, disable HPOS counting during 1 clock cycle
      if (w_hpos_dis)
        r_lol_ena <= 1'b1;
      else
        r_hpos    <= r_hpos + 9'd1;
    end
  end
  // Start of line flag for external scandoubler
  if (r_hpos == 9'd32)
    if (cdac_f) sol <= 1'b1;
  else
    if (cdac_r) sol <= 1'b0;
end

///////////////////////////////
// Horizontal display window //
///////////////////////////////

reg [8:0] r_HDIWSTRT;
reg [8:0] r_HDIWSTOP;
reg       r_hwin_ena_p0;
reg       r_hwin_ena_p1;
reg       r_hwin_ena_p2;
reg       r_vwin_ena_p0;

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if (cdac_r & cck) begin
    // DIWSTRT
    if (r_wregs_diwb_p1)
      r_HDIWSTRT <= { 1'b0, db_in[7:0] };
    // DIWSTOP
    if (r_wregs_diwe_p1)
      r_HDIWSTOP <= { 1'b1, db_in[7:0] };
    // DIWHIGH
    if ((r_wregs_diwh_p1) && (cfg_ecs)) begin
      r_HDIWSTRT[8] <= db_in[5];
      r_HDIWSTOP[8] <= db_in[13];
    end
  end
end

always@(posedge clk) begin
  // Falling edge of CDAC_n
  if (cdac_f) begin
    // Display window horizontal start
    if (r_hpos == r_HDIWSTRT)
      r_hwin_ena_p0 <= 1'b1;
    // Display window horizontal stop
    else if (r_hpos == r_HDIWSTOP)
      r_hwin_ena_p0 <= 1'b0;
    // Vertical window
    if (r_hpos == 9'h013)
      r_vwin_ena_p0 <= 1'b0;
    else if (r_wregs_bpl_p1)
      r_vwin_ena_p0 <= 1'b1;
    // Delayed horizontal + vertical window
    r_hwin_ena_p1 <= r_hwin_ena_p0 & r_vwin_ena_p0;
    r_hwin_ena_p2 <= r_hwin_ena_p1;
  end
end

///////////////////////
// Vertical blanking //
///////////////////////

reg  r_vblank_p2;

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if (cdac_r & cck) begin
    // Vertical blanking only during STREQU and STRVBL
    if ((r_wregs_str_p1) && (r_rga_p1[2:1] != 2'b11))
      r_vblank_p2 <= ~r_rga_p1[2];
  end
end

/////////////////////////
// Horizontal blanking //
/////////////////////////

reg  r_hblank_p3;

always@(posedge clk) begin
  // Falling edge of CDAC_n
  //if (cdac_f) begin
  //  r_hblank_p3 <= ~r_hwin_ena_p2;
  //end
  // Rising edge of CDAC_n
  if (cdac_r) begin
    if (r_hpos == 9'h013)
      r_hblank_p3 <= 1'b1;
    else if (r_hpos == 9'h061)
      r_hblank_p3 <= 1'b0;
  end
end

////////////////////////
// Composite blanking //
////////////////////////

reg  r_cblank_p4;

// (BUG!! but implemented this way on real HW)
always@(posedge clk) begin
  // Falling edge of CDAC_n
  if (cdac_f) begin
    r_cblank_p4 <= r_hblank_p3 | r_vblank_p2;
  end
end

////////////////////
// Bitplanes data //
////////////////////

reg [15:0] r_BPLxDAT_p2 [0:7];
reg [15:0] r_BPLxDAT_p3 [0:5];
reg        r_bpl_load_p3;
reg  [3:0] r_ddf_dly_p3;

always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r) begin
    if ((r_wregs_bpl_p1) && (cck)) begin
      // Load BPLxDAT register (6 & 7 unused)
      r_BPLxDAT_p2[r_rga_p1[3:1]] <= db_in[15:0];
      // BPL1DAT is written : 
      if (r_rga_p1[3:1] == 3'b000) begin
        // Trigger loading of second stage registers
        r_bpl_load_p3 <= 1'b1;
        // Non-aligned DDFSTRT delay
        r_ddf_dly_p3[3] <= r_hpos[3] & ~r_HIRES;
        r_ddf_dly_p3[2] <= r_hpos[2] & ~r_SHRES;
        r_ddf_dly_p3[1] <= r_hpos[1];
        r_ddf_dly_p3[0] <= 1'b0;
      end
    end
    else
      r_bpl_load_p3 <= 1'b0;
  end
end
      
always@(posedge clk) begin
  // Falling edge of CDAC_n
  if (cdac_f) begin
    // Load second stage registers
    if (r_bpl_load_p3) begin
      r_BPLxDAT_p3[0] <= r_BPLxDAT_p2[0] & {16{r_bpl_ena[0]}};
      r_BPLxDAT_p3[1] <= r_BPLxDAT_p2[1] & {16{r_bpl_ena[1]}};
      r_BPLxDAT_p3[2] <= r_BPLxDAT_p2[2] & {16{r_bpl_ena[2]}};
      r_BPLxDAT_p3[3] <= r_BPLxDAT_p2[3] & {16{r_bpl_ena[3]}};
      r_BPLxDAT_p3[4] <= r_BPLxDAT_p2[4] & {16{r_bpl_ena[4]}};
      r_BPLxDAT_p3[5] <= r_BPLxDAT_p2[5] & {16{r_bpl_ena[5]}};
    end
  end
end

////////////////////////////////////
// Playfields scrolling + shifter //
////////////////////////////////////

reg       r_HIRES;
reg       r_SHRES;
reg [3:0] r_BPU;
reg       r_HOMOD;
reg       r_DBLPF;

// BPLCON0 register
always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if (cdac_r & cck) begin
    if ((r_wregs_ctl_p1) && (r_rga_p1[2:1] == 2'b00)) begin
      r_HIRES <= db_in[15];
      //r_BPU   <= { db_in[4], db_in[14:12] };
      r_BPU   <= { 1'b0, db_in[14:12] };
      r_HOMOD <= db_in[11];
      r_DBLPF <= db_in[10];
      r_SHRES <= db_in[6];
    end
  end
end

reg [3:0] r_PF1H;
reg [3:0] r_PF2H;

// BPLCON1 register
always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if (cdac_r & cck) begin
    if ((r_wregs_ctl_p1) && (r_rga_p1[2:1] == 2'b01)) begin
      r_PF1H <= db_in[3:0];
      r_PF2H <= db_in[7:4];
    end
  end
end

reg [4:0]  r_pf_dly_p3;

// Counter that keeps track of playfield delay
always@(posedge clk) begin
  // Falling edge of CDAC_n
  if (cdac_f) begin
    if (r_bpl_load_p3)
      // Cleared when BPL1DAT is written
      r_pf_dly_p3 <= 5'b10000;
    else if (r_pf_dly_p3[4])
      // Incremented otherwise
      r_pf_dly_p3 <= r_pf_dly_p3 + 5'd1;
  end
end

reg [15:0] r_pf1dat_p4 [0:2];
reg [15:0] r_pf2dat_p4 [0:2];

// Playfields delays and shifters
always@(posedge clk) begin
  // Rising/falling edge of CDAC_n
  if ((cdac_f) || (cdac_r & r_HIRES)) begin
    if (((r_pf_dly_p3[3:0] ^ r_ddf_dly_p3) == r_PF1H) && (cdac_f) && (r_pf_dly_p3[4])) begin
      // Playfield #1 delay
      r_pf1dat_p4[0] <= r_BPLxDAT_p3[0];
      r_pf1dat_p4[1] <= r_BPLxDAT_p3[2];
      r_pf1dat_p4[2] <= r_BPLxDAT_p3[4];
    end
    else begin
      // Playfield #1 shifter
      r_pf1dat_p4[0] <= { r_pf1dat_p4[0][14:0], 1'b0 };
      r_pf1dat_p4[1] <= { r_pf1dat_p4[1][14:0], 1'b0 };
      r_pf1dat_p4[2] <= { r_pf1dat_p4[2][14:0], 1'b0 };
    end
    if (((r_pf_dly_p3[3:0] ^ r_ddf_dly_p3) == r_PF2H) && (cdac_f) && (r_pf_dly_p3[4])) begin
      // Playfield #2 delay
      r_pf2dat_p4[0] <= r_BPLxDAT_p3[1];
      r_pf2dat_p4[1] <= r_BPLxDAT_p3[3];
      r_pf2dat_p4[2] <= r_BPLxDAT_p3[5];
    end
    else begin
      // Playfield #2 shifter
      r_pf2dat_p4[0] <= { r_pf2dat_p4[0][14:0], 1'b0 };
      r_pf2dat_p4[1] <= { r_pf2dat_p4[1][14:0], 1'b0 };
      r_pf2dat_p4[2] <= { r_pf2dat_p4[2][14:0], 1'b0 };
    end
  end
end

//////////////////////////////////////
// 140 ns delay for NTSC long lines //
//////////////////////////////////////

wire [5:0] w_pf_data_p4;
reg  [5:0] r_pf_lol0_p4;
reg  [5:0] r_pf_lol1_p4;
wire [5:0] w_pf_lol_p4;

assign w_pf_data_p4[0] = r_pf1dat_p4[0][15];
assign w_pf_data_p4[1] = r_pf2dat_p4[0][15];
assign w_pf_data_p4[2] = r_pf1dat_p4[1][15];
assign w_pf_data_p4[3] = r_pf2dat_p4[1][15];
assign w_pf_data_p4[4] = r_pf1dat_p4[2][15];
assign w_pf_data_p4[5] = r_pf2dat_p4[2][15];

always@(posedge clk) begin
  // Rising/falling edge of CDAC_n
  if (cdac_r | cdac_f) begin
    r_pf_lol0_p4 <= w_pf_data_p4;
    r_pf_lol1_p4 <= r_pf_lol0_p4;
  end
end

assign w_pf_lol_p4 = (r_lol_ena) ? r_pf_lol1_p4 : w_pf_data_p4;

///////////////////////////////
// Playfields priority logic //
///////////////////////////////

reg       r_PF2PRI;
reg [2:0] r_PF2P;
reg [2:0] r_PF1P;

// BPLCON2 register
always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if (cdac_r & cck) begin
    if ((r_wregs_ctl_p1) && (r_rga_p1[2:1] == 2'b10)) begin
      r_PF2PRI <= db_in[6];
      r_PF2P   <= db_in[5:3];
      r_PF1P   <= db_in[2:0];
    end
  end
end

reg [7:0] r_bpl_ena;

// Bitplanes enable
always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if (cdac_r & cck) begin
    // Bitplane enable flags updated during BPL1DAT write
    if ((r_wregs_bpl_p1) && (r_rga_p1[3:1] == 3'b000)) begin
      case (r_BPU)
        4'd0    : r_bpl_ena <= 8'b00000000;
        4'd1    : r_bpl_ena <= 8'b00000001;
        4'd2    : r_bpl_ena <= 8'b00000011;
        4'd3    : r_bpl_ena <= 8'b00000111;
        4'd4    : r_bpl_ena <= 8'b00001111;
        4'd5    : r_bpl_ena <= 8'b00011111;
        4'd6    : r_bpl_ena <= 8'b00111111;
        4'd7    : r_bpl_ena <= 8'b01111111;
        default : r_bpl_ena <= 8'b11111111;
      endcase
    end
  end
end

reg [5:0] r_pf_data_p4;
reg [1:0] r_pf_vld_p5;
reg [5:0] r_bpl_clx_p5;
reg [5:0] r_bpl_clut_p5;

always@(posedge clk) begin
  // Rising/falling edge of CDAC_n
  if (cdac_r | cdac_f) begin
    // Masked playfields data
    r_pf_data_p4[0] = w_pf_lol_p4[0] & r_bpl_ena[0] & r_hwin_ena_p2;
    r_pf_data_p4[1] = w_pf_lol_p4[1] & r_bpl_ena[1] & r_hwin_ena_p2;
    r_pf_data_p4[2] = w_pf_lol_p4[2] & r_bpl_ena[2] & r_hwin_ena_p2;
    r_pf_data_p4[3] = w_pf_lol_p4[3] & r_bpl_ena[3] & r_hwin_ena_p2;
    r_pf_data_p4[4] = w_pf_lol_p4[4] & r_bpl_ena[4] & r_hwin_ena_p2;
    r_pf_data_p4[5] = w_pf_lol_p4[5] & r_bpl_ena[5] & r_hwin_ena_p2;
    
    // Playfields valid signal
    if (r_DBLPF) begin
      // Dual playfield mode
      r_pf_vld_p5[0] = r_pf_data_p4[0] | r_pf_data_p4[2] | r_pf_data_p4[4];
      r_pf_vld_p5[1] = r_pf_data_p4[1] | r_pf_data_p4[3] | r_pf_data_p4[5];
    end
    else begin
      // Single playfield mode
      r_pf_vld_p5[0] = 1'b0;
      r_pf_vld_p5[1] = |r_pf_data_p4;
    end
 
    // Playfields 1 & 2 priority logic
    if (r_DBLPF) begin
      // Dual playfield mode
      if (r_PF2PRI) begin
        // PF2 has priority
        case (r_pf_vld_p5)
          2'b00   : r_bpl_clut_p5 <= 6'b000000;
          2'b01   : r_bpl_clut_p5 <= { 3'b000, r_pf_data_p4[4], r_pf_data_p4[2], r_pf_data_p4[0] };
          default : r_bpl_clut_p5 <= { 3'b001, r_pf_data_p4[5], r_pf_data_p4[3], r_pf_data_p4[1] };
        endcase
      end
      else begin
        // PF1 has priority
        case (r_pf_vld_p5)
          2'b00   : r_bpl_clut_p5 <= 6'b000000;
          2'b10   : r_bpl_clut_p5 <= { 3'b001, r_pf_data_p4[5], r_pf_data_p4[3], r_pf_data_p4[1] };
          default : r_bpl_clut_p5 <= { 3'b000, r_pf_data_p4[4], r_pf_data_p4[2], r_pf_data_p4[0] };
        endcase
      end
    end
    else begin
      // Single playfield mode
      if ((r_PF2P[2:1] == 2'b11) && (r_pf_data_p4[4]))
        // OCS/ECS undocumented behaviour
        r_bpl_clut_p5 <= 6'b010000;
      else
        // Normal behaviour
        r_bpl_clut_p5 <= r_pf_data_p4;
    end

    // Bitplanes collisions data
    r_bpl_clx_p5 <= (r_pf_data_p4 ^ ~r_MVBP) | (~r_ENBP);
  end
end

////////////////////////////////
// Sprites data and positions //
////////////////////////////////

integer i;

reg        r_armed   [0:7];
reg        r_SPRATT  [0:7];
reg [8:0]  r_SPRHPOS [0:7];
reg [15:0] r_SPRDATA [0:7];
reg [15:0] r_SPRDATB [0:7];

// SPRxPOS,  SPRxCTL, SPRxDATA and SPRxDATB registers
always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r) begin
    if ((r_wregs_spr_p1) && (cck)) begin
      case (r_rga_p1[2:1])
        2'b00 : // SPRxPOS register
        begin
          r_SPRHPOS[r_rga_p1[5:3]][8:1] <= db_in[7:0];
        end
        2'b01 : // SPRxCTL register
        begin
          r_SPRATT[r_rga_p1[5:3]]       <= db_in[7];
          r_SPRHPOS[r_rga_p1[5:3]][0]   <= db_in[0];
          r_armed[r_rga_p1[5:3]]        <= 1'b0; // Sprite disabled
        end
        2'b10 : // SPRxDATA register
        begin
          r_SPRDATA[r_rga_p1[5:3]]      <= db_in[15:0];
          r_armed[r_rga_p1[5:3]]        <= 1'b1; // Sprite enabled
        end
        2'b11 : // SPRxDATB register
        begin
          r_SPRDATB[r_rga_p1[5:3]]      <= db_in[15:0];
        end
      endcase
    end
    // Sprites shift registers
    for (i = 0; i < 8; i = i + 1) begin
      if (r_spr_act_p0[i]) begin
        r_SPRDATA[i] <= { r_SPRDATA[i][14:0], r_SPRDATA[i][15] };
        r_SPRDATB[i] <= { r_SPRDATB[i][14:0], r_SPRDATB[i][15] };
      end
    end
  end
end

reg [4:0] r_match_ctr  [0:7];
reg       r_spr_act_p0 [0:7];

// Horizontal match
always@(posedge clk) begin
  // Falling edge of CDAC_n
  if (cdac_f) begin
    for (i = 0; i < 8; i = i + 1) begin
      r_spr_act_p0[i] <= r_match_ctr[i][4];
      if (r_hpos == r_SPRHPOS[i])
        r_match_ctr[i] <= { r_armed[i], 4'b0000 };
      else if (r_match_ctr[i][4])
        r_match_ctr[i] <= r_match_ctr[i] + 5'd1;
    end
  end
end

////////////////////////
// Sprites priorities //
////////////////////////

reg [1:0] r_spr_pix_p1 [0:7];
reg [3:0] r_spr_grp_p0;
reg [2:0] r_spr_vis_p1;

// Sprites pixels and groups
always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r) begin
    // Sprites pixels values (shift registers outputs)
    for (i = 0; i < 8; i = i + 1) begin
      r_spr_pix_p1[i][0] <= r_SPRDATA[i][15] & r_spr_act_p0[i];
      r_spr_pix_p1[i][1] <= r_SPRDATB[i][15] & r_spr_act_p0[i];
    end
    // Sprites #0 and #1 => group #0
    r_spr_grp_p0[0] = ((r_SPRDATA[0][15] | r_SPRDATB[0][15]) & r_spr_act_p0[0])
                    | ((r_SPRDATA[1][15] | r_SPRDATB[1][15]) & r_spr_act_p0[1]);
    // Sprites #2 and #3 => group #1
    r_spr_grp_p0[1] = ((r_SPRDATA[2][15] | r_SPRDATB[2][15]) & r_spr_act_p0[2])
                    | ((r_SPRDATA[3][15] | r_SPRDATB[3][15]) & r_spr_act_p0[3]);
    // Sprites #4 and #5 => group #2
    r_spr_grp_p0[2] = ((r_SPRDATA[4][15] | r_SPRDATB[4][15]) & r_spr_act_p0[4])
                    | ((r_SPRDATA[5][15] | r_SPRDATB[5][15]) & r_spr_act_p0[5]);
    // Sprites #6 and #7 => group #3
    r_spr_grp_p0[3] = ((r_SPRDATA[6][15] | r_SPRDATB[6][15]) & r_spr_act_p0[6])
                    | ((r_SPRDATA[7][15] | r_SPRDATB[7][15]) & r_spr_act_p0[7]);
    // Visible group number
    case (r_spr_grp_p0)
      4'b0000 : r_spr_vis_p1 <= 3'd7; // No sprite visible
      4'b0001 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      4'b0010 : r_spr_vis_p1 <= 3'd1; // Sprite #2 or #3 visible
      4'b0011 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      4'b0100 : r_spr_vis_p1 <= 3'd2; // Sprite #4 or #5 visible
      4'b0101 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      4'b0110 : r_spr_vis_p1 <= 3'd1; // Sprite #2 or #3 visible
      4'b0111 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      4'b1000 : r_spr_vis_p1 <= 3'd3; // Sprite #6 or #7 visible
      4'b1001 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      4'b1010 : r_spr_vis_p1 <= 3'd1; // Sprite #2 or #3 visible
      4'b1011 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      4'b1100 : r_spr_vis_p1 <= 3'd2; // Sprite #4 or #5 visible
      4'b1101 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      4'b1110 : r_spr_vis_p1 <= 3'd1; // Sprite #2 or #3 visible
      4'b1111 : r_spr_vis_p1 <= 3'd0; // Sprite #0 or #1 visible
      default : ;
    endcase
  end
end

reg [2:0] v_idx_e_p1;
reg [2:0] v_idx_o_p1;
reg       r_spr_att_p3;
reg [1:0] r_spr_odd_p3;
reg [1:0] r_spr_even_p3;
reg [2:0] r_spr_vis_p3;
reg [3:0] r_spr_clut_p5;
reg [2:0] r_spr_vis_p5;

// Sprites-sprites priority logic
always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r) begin
    // Sprites indexes
    v_idx_e_p1    = { r_spr_vis_p1[1:0], 1'b0 }; // Even (0, 2, 4 ,6)
    v_idx_o_p1    = { r_spr_vis_p1[1:0], 1'b1 }; // Odd (1, 3, 5, 7)
    // Sprite attached flag
    r_spr_att_p3  <= r_SPRATT[v_idx_o_p1] | (r_SPRATT[v_idx_e_p1] & cfg_ecs);
    // Odd and even sprites
    r_spr_odd_p3  <= r_spr_pix_p1[v_idx_o_p1];
    r_spr_even_p3 <= r_spr_pix_p1[v_idx_e_p1];
    // Visible sprite index (masked by the horizontal window)
    r_spr_vis_p3  <= r_spr_vis_p1 | {3{~r_hwin_ena_p1}};
    
    if (r_spr_att_p3)
      // Attached mode : 15-color sprite
      r_spr_clut_p5 <= { r_spr_odd_p3, r_spr_even_p3 };
    else begin
      // Normal mode : choose between odd and even sprite
      if (r_spr_even_p3 != 2'b00) begin
        // Show even sprite with 3 colors
        r_spr_clut_p5 <= { r_spr_vis_p3[1:0], r_spr_even_p3 };
      end
      else begin
        // Show odd sprite with 3 colors
        r_spr_clut_p5 <= { r_spr_vis_p3[1:0], r_spr_odd_p3 };
      end
    end
    // Sprite visible flags
    // [0] : PF1 is in front of sprites
    // [1] : PF2 is in front of sprites
    // [2] : No sprite visible
    if (r_spr_vis_p3 >= r_PF1P)
      r_spr_vis_p5[0] <= 1'b1;
    else
      r_spr_vis_p5[0] <= 1'b0;
    if (r_spr_vis_p3 >= r_PF2P)
      r_spr_vis_p5[1] <= 1'b1;
    else
      r_spr_vis_p5[1] <= 1'b0;
    r_spr_vis_p5[2] <= r_spr_vis_p3[2];
  end
end

reg [3:0] r_ham_clut_p5;
reg [5:0] r_bpl_clut_p6;
reg [5:0] r_clut_idx_p6;
reg       r_spr_sel_p6;

// Sprites-playfields priority logic
always@(posedge clk) begin
  // Rising/falling edge of CDAC_n
  if (cdac_r | cdac_f) begin
    // Memorize the last HAM CLUT access
    if (r_bpl_clut_p5[5:4] == 2'b00)
      r_ham_clut_p5 <= r_bpl_clut_p5[3:0];
    
    // Bitplane CLUT index for HAM mode decoder
    r_bpl_clut_p6 <= r_bpl_clut_p5;
    
    // Sprites/playfields test
    if (((r_spr_vis_p5[0]) && (r_pf_vld_p5[0])) || // Playfield #1 test
        ((r_spr_vis_p5[1]) && (r_pf_vld_p5[1])))   // Playfield #2 test
    begin
      // Playfields in front of sprites
      if ((r_HOMOD) && (r_bpl_clut_p5[5:4] != 2'b00))
        // HAM mode
        r_clut_idx_p6 <= { 2'b00, r_ham_clut_p5 };
      else
        // Normal mode
        r_clut_idx_p6 <= r_bpl_clut_p5;
      // Select playfields
      r_spr_sel_p6 <= 1'b0;
    end
    else begin
      // Sprites in front of playfields
      if (r_spr_vis_p5[2]) begin
        // No sprite visible : show playfields
        if ((r_HOMOD) && (r_bpl_clut_p5[5:4] != 2'b00))
          // HAM mode
          r_clut_idx_p6 <= { 2'b00, r_ham_clut_p5 };
        else
          // Normal mode
          r_clut_idx_p6 <= r_bpl_clut_p5;
        // Select playfields
        r_spr_sel_p6 <= 1'b0;
      end
      else begin
        // Sprites visible
        r_clut_idx_p6 <= { 2'b01, r_spr_clut_p5 };
        // Select sprites
        r_spr_sel_p6 <= 1'b1;
      end
    end
  end
end

//////////////////////////////////
// Sprites/bitplanes collisions //
//////////////////////////////////

reg   [3:0] r_ENSP;
reg   [5:0] r_ENBP;
reg   [5:0] r_MVBP;

// CLXCON register
always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if ((cdac_r) && (cck)) begin
    if (r_wregs_clx_p1) begin
      r_ENSP <= db_in[15:12];
      r_ENBP <= db_in[11:6];
      r_MVBP <= db_in[5:0];
    end
  end
end

reg [3:0] r_spr_clx_p1;
reg [3:0] r_spr_clx_p3;
reg [3:0] r_spr_clx_p5;

// Sprites collisions groups
always@(posedge clk) begin
  // Rising edge of CDAC_n
  if (cdac_r) begin
    // Sprites #0 and #1 => collision group #0
    r_spr_clx_p1[0] <= ((r_SPRDATA[0][15] | r_SPRDATB[0][15]) & r_spr_act_p0[0])
                     | ((r_SPRDATA[1][15] | r_SPRDATB[1][15]) & r_spr_act_p0[1] & r_ENSP[0]);
    // Sprites #2 and #3 => collision group #1
    r_spr_clx_p1[1] <= ((r_SPRDATA[2][15] | r_SPRDATB[2][15]) & r_spr_act_p0[2])
                     | ((r_SPRDATA[3][15] | r_SPRDATB[3][15]) & r_spr_act_p0[3] & r_ENSP[1]);
    // Sprites #4 and #5 => collision group #2
    r_spr_clx_p1[2] <= ((r_SPRDATA[4][15] | r_SPRDATB[4][15]) & r_spr_act_p0[4])
                     | ((r_SPRDATA[5][15] | r_SPRDATB[5][15]) & r_spr_act_p0[5] & r_ENSP[2]);
    // Sprites #6 and #7 => collision group #3
    r_spr_clx_p1[3] <= ((r_SPRDATA[6][15] | r_SPRDATB[6][15]) & r_spr_act_p0[6])
                     | ((r_SPRDATA[7][15] | r_SPRDATB[7][15]) & r_spr_act_p0[7] & r_ENSP[3]);
    // Delay collision group by 2 CDAC_n clock cycles
    r_spr_clx_p3 <= r_spr_clx_p1 & {4{r_hwin_ena_p1}}; // No collision "behind" the border
    r_spr_clx_p5 <= r_spr_clx_p3;
  end
end

wire        w_odd_clx_p5;
wire        w_even_clx_p5;
wire [14:0] w_CLXDAT;

// Odd and even bitplanes match
assign w_odd_clx_p5  = r_bpl_clx_p5[0] | r_bpl_clx_p5[2] | r_bpl_clx_p5[4];
assign w_even_clx_p5 = r_bpl_clx_p5[1] | r_bpl_clx_p5[3] | r_bpl_clx_p5[5];

// Sprites-sprites collisions
assign w_CLXDAT[14] = r_spr_clx_p5[2] & r_spr_clx_p5[3]; // Sprites #4 and #6
assign w_CLXDAT[13] = r_spr_clx_p5[1] & r_spr_clx_p5[3]; // Sprites #2 and #6
assign w_CLXDAT[12] = r_spr_clx_p5[1] & r_spr_clx_p5[2]; // Sprites #2 and #4
assign w_CLXDAT[11] = r_spr_clx_p5[0] & r_spr_clx_p5[3]; // Sprites #0 and #6
assign w_CLXDAT[10] = r_spr_clx_p5[0] & r_spr_clx_p5[2]; // Sprites #0 and #4
assign w_CLXDAT[9]  = r_spr_clx_p5[0] & r_spr_clx_p5[1]; // Sprites #0 and #2
// Sprites-bitplanes collisions
assign w_CLXDAT[8]  = w_even_clx_p5   & r_spr_clx_p5[3]; // Even and Sprite #6
assign w_CLXDAT[7]  = w_even_clx_p5   & r_spr_clx_p5[2]; // Even and Sprite #4
assign w_CLXDAT[6]  = w_even_clx_p5   & r_spr_clx_p5[1]; // Even and Sprite #2
assign w_CLXDAT[5]  = w_even_clx_p5   & r_spr_clx_p5[0]; // Even and Sprite #0
assign w_CLXDAT[4]  = w_odd_clx_p5    & r_spr_clx_p5[3]; // Odd and Sprite #6
assign w_CLXDAT[3]  = w_odd_clx_p5    & r_spr_clx_p5[2]; // Odd and Sprite #4
assign w_CLXDAT[2]  = w_odd_clx_p5    & r_spr_clx_p5[1]; // Odd and Sprite #2
assign w_CLXDAT[1]  = w_odd_clx_p5    & r_spr_clx_p5[0]; // Odd and Sprite #0
// Bitplanes-bitplanes collisions
assign w_CLXDAT[0]  = w_odd_clx_p5    & w_even_clx_p5;

////////////////////
// Registers read //
////////////////////

reg [14:0] r_CLXDAT;

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 0
  if (cdac_r & ~cck) begin
    db_out <= ({ 1'b0, r_CLXDAT } & {16{r_rregs_clx_p1}})  // CLXDAT register
            | (16'hFFFC & {16{cfg_ecs & r_rregs_id_p1}}); // DENISEID register
    db_oen <= r_rregs_clx_p1 | (cfg_ecs & r_rregs_id_p1);
  end
  if (cdac_r | cdac_f) begin
    if (cdac_r & ~cck & r_rregs_clx_p1)
    // CLXDAT read : clear the register
    r_CLXDAT <= 15'b0000000_00000000;
  else
    // Otherwise, track collisions
    r_CLXDAT <= r_CLXDAT | w_CLXDAT;
end
end

///////////////////////////////////////
// Color look-up table instantiation //
///////////////////////////////////////

wire        w_cpu_wr;
wire        w_clut_rd;
wire [11:0] w_clut_rgb_p7;

// Color look-up table write strobe
//assign w_cpu_wr = r_wregs_clut_p1 & cdac_r & cck;
// Half a CDAC_n cycle earlier for the Copper to be in sync.
assign w_cpu_wr = r_wregs_clut_p1 & cdac_f & ~cck;

// Color look-up table read strobe
assign w_clut_rd = cdac_r | cdac_f;

color_table U_color_table
(
  .clk(clk),
  .cpu_wr(w_cpu_wr),
  .cpu_idx(r_rga_p1[5:1]),
  .cpu_rgb(db_in[11:0]),
  .clut_rd(w_clut_rd),
  .clut_idx(r_clut_idx_p6[4:0]),
  .clut_rgb(w_clut_rgb_p7)
);

//////////////////////////////////
// HAM and EHB modes management //
//////////////////////////////////

reg        r_spr_sel_p7;
reg        r_ehb_sel_p7;
reg  [2:0] r_ham_sel_p7;
reg [11:0] r_ham_rgb_p7;
reg [11:0] r_rgb_p8;

// HAM decoder
always@(posedge clk) begin
  if (cdac_r | cdac_f) begin
    if (r_HOMOD) begin
      // Hold and modify mode
      case (r_bpl_clut_p6[5:4])
        2'b00 : // Select color
          r_ham_sel_p7[2:0]  <= 3'b000;
        2'b01 : // Modify blue
        begin
          r_ham_rgb_p7[3:0]  <= r_bpl_clut_p6[3:0];
          r_ham_sel_p7[0]    <= 1'b1;
        end
        2'b10 : // Modify red
        begin
          r_ham_rgb_p7[11:8] <= r_bpl_clut_p6[3:0];
          r_ham_sel_p7[2]    <= 1'b1;
        end
        2'b11 : // Modify green
        begin
          r_ham_rgb_p7[7:4]  <= r_bpl_clut_p6[3:0];
          r_ham_sel_p7[1]    <= 1'b1;
        end
      endcase
    end
    else begin
      // Normal mode
      r_ham_sel_p7[2:0]  <= 3'b000;
    end
    // Extra-half-brite
    r_ehb_sel_p7 <= r_clut_idx_p6[5] & ~r_spr_sel_p6 & ~cfg_a1k;
    // Playfields/sprites select
    r_spr_sel_p7 <= r_spr_sel_p6;
  end
end

// Final RGB color mixing
always@(posedge clk) begin
  if (cdac_r | cdac_f) begin
    if (r_spr_sel_p7)
      // RGB color from sprites
      r_rgb_p8 <= w_clut_rgb_p7;
    else begin
      // RGB color from playfields

      // Blue component
      if (r_ham_sel_p7[0])
        r_rgb_p8[3:0] <= r_ham_rgb_p7[3:0]; // HAM
      else if (r_ehb_sel_p7)
        r_rgb_p8[3:0] <= { 1'b0, w_clut_rgb_p7[3:1] }; // EHB
      else
        r_rgb_p8[3:0] <= w_clut_rgb_p7[3:0]; // CLUT
      // Green component
      if (r_ham_sel_p7[1])
        r_rgb_p8[7:4] <= r_ham_rgb_p7[7:4]; // HAM
      else if (r_ehb_sel_p7)
        r_rgb_p8[7:4] <= { 1'b0, w_clut_rgb_p7[7:5] }; // EHB
      else
        r_rgb_p8[7:4] <= w_clut_rgb_p7[7:4]; // CLUT
      // Red component
      if (r_ham_sel_p7[2])
        r_rgb_p8[11:8] <= r_ham_rgb_p7[11:8]; // HAM
      else if (r_ehb_sel_p7)
        r_rgb_p8[11:8] <= { 1'b0, w_clut_rgb_p7[11:9] }; // EHB
      else
        r_rgb_p8[11:8] <= w_clut_rgb_p7[11:8]; // CLUT
    end
  end
end

////////////////////////////
// Mask RGB with blanking //
////////////////////////////

reg [11:0] r_rgb_p9;
reg [11:0] r_rgb_p10;
reg        r_blank_n_p9;
reg        r_blank_n_p10;

always@(posedge clk) begin
  // Rising/falling edge of CDAC_n
  if (cdac_r | cdac_f) begin
    if (r_cblank_p4)
      r_rgb_p9    <= 12'h000;
    else
      r_rgb_p9    <= r_rgb_p8;
    r_blank_n_p9  <= ~r_cblank_p4;
    // Final output register
    r_rgb_p10     <= r_rgb_p9;
    r_blank_n_p10 <= r_blank_n_p9;
  end
end

// RGB output
assign red     = r_rgb_p10[11:8];
assign green   = r_rgb_p10[7:4];
assign blue    = r_rgb_p10[3:0];
assign blank_n = r_blank_n_p10;

endmodule

////////////////////////
// Color lookup table //
////////////////////////

// CLUT Latency is :
// -----------------
// 28 MHz : 1 cycle
// CDAC_n : 0.5 cycles

module color_table
(
  input         clk,
  input         cpu_wr,
  input   [4:0] cpu_idx,
  input  [11:0] cpu_rgb,
  input         clut_rd,
  input   [4:0] clut_idx,
  output [11:0] clut_rgb
);

`ifdef SIMULATION

// Infered block RAM
reg  [11:0] r_mem_clut [0:31];

// Write port
always@(posedge clk) begin
  if (cpu_wr) begin
    r_mem_clut[cpu_idx] <= cpu_rgb;
  end
end

reg  [11:0] r_q_p0;
reg  [11:0] r_q_p1;

// Read port
always@(posedge clk) begin
  if (clut_rd)
    r_q_p0 <= r_mem_clut[clut_idx];
  r_q_p1 <= r_q_p0;
end

assign clut_rgb = r_q_p1;

`else

// Declared Altera block RAM
altsyncram U_altsyncram_32x12
(
  // Port A : write side (Copper or CPU)
  .clock0    (clk),
  .wren_a    (cpu_wr),
  .address_a (cpu_idx),
  .data_a    (cpu_rgb),
  // Port B : read side (Bitplanes or Sprites)
  .clock1    (clk),
  .rden_b    (clut_rd),
  .address_b (clut_idx),
  .q_b       (clut_rgb)
);
defparam 
  U_altsyncram_32x12.operation_mode = "DUAL_PORT",
  U_altsyncram_32x12.width_a        = 12,
  U_altsyncram_32x12.widthad_a      = 5,
  U_altsyncram_32x12.width_b        = 12,
  U_altsyncram_32x12.widthad_b      = 5,
  U_altsyncram_32x12.outdata_reg_b  = "CLOCK1";

`endif

endmodule
