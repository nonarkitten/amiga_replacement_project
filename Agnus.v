`include "arg_defs.vh"

module Agnus
(
  // Main reset & clock
  input             rst,       // Global reset
  input             ram_rdy,   // SDRAM ready
  input             clk,       // Master clock (28/56/85 MHz)
  // Generated clocks
  output            cck,       // CCK clock
  output            cdac_r,    // CDAC_n rising edge
  output            cdac_f,    // CDAC_n falling edge
  output            c7m_r,     // CPU 7 MHz clock rise
  output            c7m_f,     // CPU 7 MHz clock fall
  output            ena_28m,   // 28 MHz clock enable
  output      [2:0] cyc_28m,   // 28 MHz cycle number
  output     [11:0] cyc_ram,   // RAM sequencer cycles
  // Configuration
  input             cfg_ecs,   // OCS(0) or ECS(1) chipset
  input             cfg_a1k,   // Normal mode(0), A1000 mode(1)
  // Interrupt
  output            int3_n,    // Level 3 interrupt (Blitter)
  // Video beam position
  output      [7:0] hpos,      // Horizontal position
  output            lol,       // Long line (228 cycles)
  output            eol,       // End of line
  output      [8:0] vpos,      // Vertical position
  output            lof,       // Long field (263 or 313 lines)
  output            eof,       // End of field
  // DMA / Chip RAM control
  input             dmal,      // DMA request from Paula
  input       [8:1] rga_in,    // Register address bus in
  output      [8:1] rga_out,   // Register address bus out
  input      [15:0] db_in,     // Data bus input
  output reg [15:0] db_out,    // Data bus output
  output     [15:0] db_out_er, // Data bus output (early read)
  output     [22:1] addr_out,  // Chip RAM address output
  output            bus_we,    // Chip RAM write enable
  output            bus_req,   // Chip RAM requested by Agnus
  output            ram_ref,   // Chip RAM refresh request
  // Cache control
  output      [4:0] chan_out,  // DMA channel number
  output            cache_hit,  // DMA cache hit
  output            flush_line  // Flush current write cache line
);
// Clock input frequency : 28/57/85 MHz
parameter MAIN_FREQ = 85;

// Internal wires
wire        w_cdac_r;
wire        w_cdac_f;
wire        w_cck;
wire        w_ena_28m;
wire  [2:0] w_cyc_28m;
wire  [7:0] w_hpos;
wire        w_lol;
wire        w_eol;
wire  [8:0] w_vpos;
wire        w_lof;
wire        w_eof;
wire        w_vblend;
wire  [1:0] w_strb;
wire        w_refr;

wire        w_ptr_rd_ena;
wire  [9:2] w_ptr_rd_rga;
wire [22:0] w_ptr_rd_val;
wire        w_mod_rd_ena;
wire  [8:1] w_mod_rd_rga;
wire [22:1] w_mod_rd_val;
wire        w_pos_rd_ena;
wire  [8:2] w_pos_rd_rga;
wire  [8:0] w_spr_vstart;
wire  [8:0] w_spr_vstop;
wire        w_ptr_wr_ena;
wire  [8:2] w_ptr_wr_rga;
wire        w_cpu_wr_ena;

wire        w_cop_dma;
wire [22:1] w_cop_pc;
wire        w_cop_hit;

wire        w_ptr_inc;
wire        w_ptr_dec;
wire        w_mod_add;
wire        w_mod_sub;

wire  [4:0] w_chan_out;
wire        w_bst_ena;
wire        w_blt_last;
wire        w_bus_we;

//////////////////////////////////
// Registers addresses decoding //
//////////////////////////////////

reg        r_regs_dmar_p1; // DMACONR decoding
reg        r_regs_vpr_p1;  // VPOSR decoding
reg        r_regs_vhpr_p1; // VHPOSR decoding
reg        r_regs_cctl_p1; // COPCON decoding
reg [10:0] r_regs_bltw_p1; // BLTxxxx decoding
reg        r_regs_cjp1_p1; // COPJMP1 decoding
reg        r_regs_cjp2_p1; // COPJMP2 decoding
reg        r_regs_cins_p1; // COPINS decoding
reg        r_regs_diwb_p1; // DIWSTRT decoding
reg        r_regs_diwe_p1; // DIWSTOP decoding
reg        r_regs_ddfb_p1; // DDFSTRT decoding
reg        r_regs_ddfe_p1; // DDFSTOP decoding
reg        r_regs_dmaw_p1; // DMACON decoding
reg        r_regs_bctl_p1; // BPLCON0 decoding
reg        r_regs_beam_p1; // BEAMCON decoding
reg        r_regs_diwh_p1; // DIWHIGH decoding
reg        r_regs_fmod_p1; // FMODE decoding
reg  [8:1] r_rga_p1;       // RGA value for next cycle

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_regs_dmar_p1 <= 1'b0;
    r_regs_vpr_p1  <= 1'b0;
    r_regs_vhpr_p1 <= 1'b0;
    r_regs_cctl_p1 <= 1'b0;
    r_regs_bltw_p1 <= 11'b000_0000_0000;
    r_regs_cjp1_p1 <= 1'b0;
    r_regs_cjp2_p1 <= 1'b0;
    r_regs_cins_p1 <= 1'b0;
    r_regs_diwb_p1 <= 1'b0;
    r_regs_diwe_p1 <= 1'b0;
    r_regs_ddfb_p1 <= 1'b0;
    r_regs_ddfe_p1 <= 1'b0;
    r_regs_dmaw_p1 <= 1'b0;
    r_regs_bctl_p1 <= 1'b0;
    r_regs_beam_p1 <= 1'b0;
    r_regs_diwh_p1 <= 1'b0;
    r_regs_fmod_p1 <= 1'b0;
    r_rga_p1       <= 8'hFF;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // DMACONR : $002
    if (rga_in[8:1] == 8'b0_0000_001)
      r_regs_dmar_p1 <= 1'b1;
    else
      r_regs_dmar_p1 <= 1'b0;
    // VPOSR   : $004
    if (rga_in[8:1] == 8'b0_0000_010)
      r_regs_vpr_p1 <= 1'b1;
    else
      r_regs_vpr_p1 <= 1'b0;
    // VHPOSR  : $006
    if (rga_in[8:1] == 8'b0_0000_011)
      r_regs_vhpr_p1 <= 1'b1;
    else
      r_regs_vhpr_p1 <= 1'b0;
    // COPCON  : $02E
    if (rga_in[8:1] == 8'b0_0010_111)
      r_regs_cctl_p1 <= 1'b1;
    else
      r_regs_cctl_p1 <= 1'b0;
    // Blitter : $040 - $074
    if (rga_in[8:6] == 3'b0_01) begin
      case (rga_in[5:1])
        5'b00_000 : // BLTCON0
          r_regs_bltw_p1 <= 11'b000_0000_0001;
        5'b00_001 : // BLTCON1
          r_regs_bltw_p1 <= 11'b000_0000_0010;
        5'b00_010 : // BLTAFWM
          r_regs_bltw_p1 <= 11'b000_0000_0100;
        5'b00_011 : // BLTALWM
          r_regs_bltw_p1 <= 11'b000_0000_1000;
        5'b01_100 : // BLTSIZE
          r_regs_bltw_p1 <= 11'b000_0001_0000;
        5'b01_101 : // BLTCON0L
          r_regs_bltw_p1 <= 11'b000_0010_0000;
        5'b01_110 : // BLTSIZV
          r_regs_bltw_p1 <= 11'b000_0100_0000;
        5'b01_111 : // BLTSIZH
          r_regs_bltw_p1 <= 11'b000_1000_0000;
        5'b11_000 : // BLTCDAT
          r_regs_bltw_p1 <= 11'b001_0000_0000;
        5'b11_001 : // BLTBDAT
          r_regs_bltw_p1 <= 11'b010_0000_0000;
        5'b11_010 : // BLTADAT
          r_regs_bltw_p1 <= 11'b100_0000_0000;
        default :
          r_regs_bltw_p1 <= 11'b000_0000_0000;
      endcase
    end else
      r_regs_bltw_p1 <= 11'b000_0000_0000;
    // COPJMP1 : $088
    if (rga_in[8:1] == 8'b0_1000_100)
      r_regs_cjp1_p1 <= 1'b1;
    else
      r_regs_cjp1_p1 <= 1'b0;
    // COPJMP2 : $08A
    if (rga_in[8:1] == 8'b0_1000_101)
      r_regs_cjp2_p1 <= 1'b1;
    else
      r_regs_cjp2_p1 <= 1'b0;
    // COPINS  : $08C
    if (rga_in[8:1] == 8'b0_1000_110)
      r_regs_cins_p1 <= 1'b1;
    else
      r_regs_cins_p1 <= 1'b0;
    // DIWSTRT : $08E
    if (rga_in[8:1] == 8'b0_1000_111)
      r_regs_diwb_p1 <= 1'b1;
    else
      r_regs_diwb_p1 <= 1'b0;
    // DIWSTOP : $090
    if (rga_in[8:1] == 8'b0_1001_000)
      r_regs_diwe_p1 <= 1'b1;
    else
      r_regs_diwe_p1 <= 1'b0;
    // DIWSTRT : $092
    if (rga_in[8:1] == 8'b0_1001_001)
      r_regs_ddfb_p1 <= 1'b1;
    else
      r_regs_ddfb_p1 <= 1'b0;
    // DIWSTOP : $094
    if (rga_in[8:1] == 8'b0_1001_010)
      r_regs_ddfe_p1 <= 1'b1;
    else
      r_regs_ddfe_p1 <= 1'b0;
    // DMACON  : $096
    if (rga_in[8:1] == 8'b0_1001_011)
      r_regs_dmaw_p1 <= 1'b1;
    else
      r_regs_dmaw_p1 <= 1'b0;
    // BPLCON0 : $100
    if (rga_in[8:1] == 8'b1_0000_000)
      r_regs_bctl_p1 <= 1'b1;
    else
      r_regs_bctl_p1 <= 1'b0;
    // BEAMCON : $1DC
    if (rga_in[8:1] == 8'b1_1101_110)
      r_regs_beam_p1 <= 1'b1;
    else
      r_regs_beam_p1 <= 1'b0;
    // DIWHIGH : $1E4
    if (rga_in[8:1] == 8'b1_1110_010)
      r_regs_diwh_p1 <= 1'b1;
    else
      r_regs_diwh_p1 <= 1'b0;
    // FMODE : $1FC
    if (rga_in[8:1] == 8'b1_1111_110)
      r_regs_fmod_p1 <= 1'b1;
    else
      r_regs_fmod_p1 <= 1'b0;
    // Latch RGA bits 8 - 1 for next cycle
    r_rga_p1 <= rga_in;
  end
end

//////////////////////////////////
// Register memory write access //
//////////////////////////////////

reg        r_regs_wr_p2;
reg  [8:1] r_rga_p2;
reg [15:0] r_db_in;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_regs_wr_p2 <= 1'b0;
    r_rga_p2     <= 8'hFF;
    r_db_in      <= 16'h0000;
  end else if (cdac_r) begin
    // Global write to register memory
    if ((r_rga_p1[8:1] != 8'hFF) && (r_rga_p1[8:5] != 4'h0))
      r_regs_wr_p2 <= 1'b1;
    else
      r_regs_wr_p2 <= 1'b0;
    r_rga_p2 <= r_rga_p1;
    if (cck) r_db_in <= db_in;
  end
end

assign w_cpu_wr_ena = r_regs_wr_p2 & cck;

/////////////////////
// Registers read //
////////////////////

wire        w_BBUSY;
wire        w_BZERO;

wire [15:0] w_DMACONR;
wire [15:0] w_VPOSR;
wire [15:0] w_VHPOSR;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    db_out <= 16'h0000;
  // Rising edge of CDAC_n with CCK = 0
  end else if (cdac_r & ~cck) begin
    db_out <= ( w_DMACONR & {16{r_regs_dmar_p1}} )
            | ( w_VPOSR   & {16{r_regs_vpr_p1 }} )
            | ( w_VHPOSR  & {16{r_regs_vhpr_p1}} );
  end
end

// DMACONR bits
assign w_DMACONR[15:12] = {    1'b0,  w_BBUSY, w_BZERO,    1'b0 };
assign w_DMACONR[11:8]  = {    1'b0, r_BLTPRI, r_DMAEN, r_BPLEN };
assign w_DMACONR[7:4]   = { r_COPEN,  r_BLTEN, r_SPREN,    1'b0 };
assign w_DMACONR[3:0]   = 4'b0000; // Bits 4-0 are in Paula

// VPOSR bits
`ifdef AGNUS_PAL
assign w_VPOSR[15:8]    = { w_lof, 7'h20 }; // 8372 rev 4 PAL
`else
assign w_VPOSR[15:8]    = { w_lof, 7'h30 }; // 8372 rev 4 NTSC
`endif
assign w_VPOSR[7:0]     = { w_lol, 6'b000000, w_vpos[8] };

// VHPOSR bits
assign w_VHPOSR[15:8]   = w_vpos[7:0];
assign w_VHPOSR[7:0]    = w_hpos[7:0];

//////////////////////////
// DMA control register //
//////////////////////////

reg       r_BLTPRI;
reg       r_DMAEN;
reg       r_BPLEN;
reg       r_COPEN;
reg       r_BLTEN;
reg       r_SPREN;

wire      w_BPLEN;
wire      w_COPEN;
wire      w_BLTEN;
wire      w_SPREN;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef SIMULATION
    r_BLTPRI <= 1'b0;
    r_DMAEN  <= 1'b1;
    r_BPLEN  <= 1'b1;
    r_COPEN  <= 1'b1;
    r_BLTEN  <= 1'b1;
    r_SPREN  <= 1'b0;
    `else
    r_BLTPRI <= 1'b0;
    r_DMAEN  <= 1'b0;
    r_BPLEN  <= 1'b0;
    r_COPEN  <= 1'b0;
    r_BLTEN  <= 1'b0;
    r_SPREN  <= 1'b0;
    `endif
  end
  // Rising edge of CDAC_n with CCK = 1
  else if ((cdac_r) && (cck)) begin
    if (r_regs_dmaw_p1) begin
      if (db_in[15]) begin
        // Set
        r_BLTPRI <= r_BLTPRI | db_in[10];
        r_DMAEN  <= r_DMAEN  | db_in[9];
        r_BPLEN  <= r_BPLEN  | db_in[8];
        r_COPEN  <= r_COPEN  | db_in[7];
        r_BLTEN  <= r_BLTEN  | db_in[6];
        r_SPREN  <= r_SPREN  | db_in[5];
      end
      else begin
        // Clear
        r_BLTPRI <= r_BLTPRI & ~db_in[10];
        r_DMAEN  <= r_DMAEN  & ~db_in[9];
        r_BPLEN  <= r_BPLEN  & ~db_in[8];
        r_COPEN  <= r_COPEN  & ~db_in[7];
        r_BLTEN  <= r_BLTEN  & ~db_in[6];
        r_SPREN  <= r_SPREN  & ~db_in[5];
      end
    end
  end
end

assign w_BPLEN = r_BPLEN & r_DMAEN;
assign w_COPEN = r_COPEN & r_DMAEN;
assign w_BLTEN = r_BLTEN & r_DMAEN;
assign w_SPREN = r_SPREN & r_DMAEN;

/////////////////////////
// Fetch mode register //
/////////////////////////

reg [5:0] r_BSTMODE;     // Enable cache burst

always@(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef SIMULATION
    r_BSTMODE <= 6'b111111;
    `else
    r_BSTMODE <= 6'b000000;
    `endif
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    if (r_regs_fmod_p1) begin
      r_BSTMODE <= db_in[9:4];
    end
  end
end

////////////////////////
// Video beam control //
////////////////////////

reg       r_PAL;     // PAL video mode

always@(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef AGNUS_PAL
    r_PAL <= 1'b1;
    `else
    r_PAL <= 1'b0;
    `endif
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    if (r_regs_beam_p1) begin
      r_PAL <= db_in[5];
    end
  end
end

///////////////////////
// Bitplanes control //
///////////////////////

reg         r_LACE;      // Interlaced mode
reg   [5:0] r_BPLCON0;   // Bitplane control (SHRES, HIRES and BPU bits)
reg   [1:0] r_bplres_p1; // Bitplane resolution
reg   [2:0] r_ddfinc_p2; // DDF counter increment
reg   [3:0] r_bpu_p1;
reg   [3:0] r_bpu_p2;    // Bitplanes used, delayed by 2 CCKs

always@(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef SIMULATION
    r_LACE      <= 1'b1;
    r_BPLCON0   <= 6'b01_0100;
    r_bplres_p1 <= 2'b01;
    r_ddfinc_p2 <= 3'd2;
    r_bpu_p1    <= 4'd4;
    r_bpu_p2    <= 4'd4;
    `else
    r_LACE      <= 1'b0;
    r_BPLCON0   <= 6'b00_0000;
    r_bplres_p1 <= 2'b00;
    r_ddfinc_p2 <= 3'd1;
    r_bpu_p1    <= 4'd6;
    r_bpu_p2    <= 4'd6;
    `endif
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    if (r_regs_bctl_p1) begin
      r_LACE    <= db_in[2];
      //r_BPLCON0 <= { db_in[6], db_in[15], db_in[4], db_in[14:12] };
      r_BPLCON0 <= { db_in[6], db_in[15], 1'b0, db_in[14:12] };
    end
    // First CCK delay
    r_bplres_p1 <= { r_BPLCON0[5] & cfg_ecs, r_BPLCON0[4] };
    r_bpu_p1    <= r_BPLCON0[3:0];
    // Second CCK delay
    case (r_bplres_p1)
      2'b00   : r_ddfinc_p2 <= 3'd1; // Lo-res
      2'b01   : r_ddfinc_p2 <= 3'd2; // Hi-res
      default : r_ddfinc_p2 <= 3'd4; // Super hi-res
    endcase
    if (r_bpu_p1[2:0] == 3'd7)
      r_bpu_p2 <= 4'd4;
    else
      r_bpu_p2 <= r_bpu_p1;
  end
end

/////////////////////////////
// Vertical display window //
/////////////////////////////

reg [10:0] r_VDIWSTRT;
reg [10:0] r_VDIWSTOP;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef SIMULATION
    r_VDIWSTRT <= 11'd26;
    r_VDIWSTOP <= 11'd244;
    `else
    r_VDIWSTRT <= 11'd0;
    r_VDIWSTOP <= 11'd0;
    `endif
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // DIWSTRT
    if (r_regs_diwb_p1)
      r_VDIWSTRT <= { 3'b000, db_in[15:8] };
    // DIWSTOP
    if (r_regs_diwe_p1)
      r_VDIWSTOP <= { 3'b001, db_in[15:8] };
    // DIWHIGH
    if ((r_regs_diwh_p1) && (cfg_ecs)) begin
      r_VDIWSTRT[10:8] <= db_in[2:0];
      r_VDIWSTOP[10:8] <= db_in[10:8];
    end
  end
end

////////////////////////////////////
// Vertical display window enable //
////////////////////////////////////

reg       r_vdiw_ena;
reg       r_vdiw_soft_ena;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_vdiw_soft_ena <= 1'b0;
    r_vdiw_ena      <= 1'b0;
  // Rising edge of CDAC_n with CCK = 0
  end else if (cdac_r & ~cck) begin
    if (vpos == r_VDIWSTOP[8:0])
      r_vdiw_soft_ena <= 1'b0;
    else if (vpos == r_VDIWSTRT[8:0])
      r_vdiw_soft_ena <= 1'b1;
    r_vdiw_ena <= r_vdiw_soft_ena & w_strb[1] & ~w_strb[0];
  end
end

////////////////////////
// Display data fetch //
////////////////////////

reg [7:1] r_DDFSTRT;
reg [7:1] r_DDFSTOP;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef SIMULATION
    r_DDFSTRT <= 7'h1C;
    r_DDFSTOP <= 7'h68;
    `else
    r_DDFSTRT <= 7'd0;
    r_DDFSTOP <= 7'd0;
    `endif
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // DDFSTRT
    if (r_regs_ddfb_p1)
      r_DDFSTRT <= db_in[7:1];
    // DDFSTOP
    if (r_regs_ddfe_p1)
      r_DDFSTOP <= db_in[7:1];
  end
end

///////////////////////////////
// Display data fetch enable //
///////////////////////////////

reg       r_ddf_soft_ena;
reg       r_ddf_hard_ena;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_ddf_soft_ena <= 1'b0;
    r_ddf_hard_ena <= 1'b0;
  // Rising edge of CDAC_n with CCK = 0
  end else if (cdac_r & ~cck) begin
    // Software limits
    if (w_hpos == { r_DDFSTRT[7:2], r_DDFSTRT[1] & cfg_ecs, 1'b0 })
      r_ddf_soft_ena <= w_BPLEN;
    else if (w_hpos == { r_DDFSTOP[7:2], r_DDFSTOP[1] & cfg_ecs, 1'b0 })
      r_ddf_soft_ena <= 1'b0;
    // Hardware limits
    if (w_hpos[4:3] == 2'b11) begin
      if (w_hpos[7:6] == 2'b00) // $18
        r_ddf_hard_ena <= r_vdiw_ena;
      else if (w_hpos[7:6] == 2'b11) // $D8
        r_ddf_hard_ena <= 1'b0;
    end
  end
end

/////////////////////////
// Address computation //
/////////////////////////

wire        w_next_line;
wire [22:1] w_ptr_inc_val;
wire [22:1] w_ptr_val;
reg  [22:0] r_ptr_wr_val;
reg  [22:1] r_addr_out;
reg         r_cache_hit;
reg         r_flush_line;
reg         r_bus_we;

assign w_next_line   = w_mod_add                            // Add modulo
                     | w_mod_sub                            // Subtract modulo
                     | ( (&w_ptr_rd_val[3:1]) & w_ptr_inc)  // Increment 7->0
                     | (~(|w_ptr_rd_val[3:1]) & w_ptr_dec); // Decrement 0->7
assign w_ptr_inc_val = { {21{w_ptr_dec}}, w_ptr_inc | w_ptr_dec };
assign w_ptr_val = w_ptr_rd_val[22:1] + w_ptr_inc_val;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_ptr_wr_val <= 23'd0;
    r_addr_out   <= 22'd0;
    r_cache_hit  <= 1'b0;
    r_flush_line <= 1'b0;
    r_bus_we     <= 1'b0;
  end else if (cdac_r & ~cck) begin
    // Muxer between DMA pointer and Copper's PC
    if (w_cop_dma) begin
      // Copper DMA
      r_addr_out  <= w_cop_pc;
      r_cache_hit <= w_cop_hit & r_BSTMODE[4];
    end else begin
      // Other DMA
      r_addr_out  <= w_ptr_rd_val[22:1];
      r_cache_hit <= (w_ptr_rd_val[0] | w_bus_we) & w_bst_ena;
    end
    
    // Write cache flush
    r_flush_line <= (w_blt_last | w_next_line | ~w_bst_ena) & w_bus_we;
    
    // Write enable (Disk or Blitter)
    r_bus_we <= w_bus_we;
    
    // Compute next address (with cache hit flag)
    if (w_mod_add) begin
      // Add modulo
      r_ptr_wr_val[22:1] <= w_ptr_val + w_mod_rd_val;
    end else if (w_mod_sub) begin
      // Subtract modulo
      r_ptr_wr_val[22:1] <= w_ptr_val - w_mod_rd_val;
    end else begin
      // Increment/decrement address
      r_ptr_wr_val[22:1] <= w_ptr_val;
  end
    r_ptr_wr_val[0] <= ~w_next_line;
end
end

assign addr_out  = r_addr_out;
assign chan_out  = w_chan_out;
assign cache_hit = r_cache_hit;
assign flush_line = r_flush_line;
assign bus_we     = r_bus_we;

/////////////////////
// Clock generator //
/////////////////////
clocks_gen U_clocks_gen
(
  .rst(rst),
  .clk(clk),
  .c7m_r(c7m_r),
  .c7m_f(c7m_f),
  .cdac_r(w_cdac_r),
  .cdac_f(w_cdac_f),
  .cck(w_cck),
  .ena_28m(w_ena_28m),
  .cyc_28m(w_cyc_28m),
  .cyc_ram(cyc_ram)
);
defparam
  U_clocks_gen.MAIN_FREQ = MAIN_FREQ;

/////////////////////////
// Video beam counters //
/////////////////////////
beam_ctr U_beam_ctr
(
  .rst(~ram_rdy),
  .clk(clk),
  .cdac_r(w_cdac_r),
  .cck(w_cck),
  .pal_ntsc_n(r_PAL),
  .laced(r_LACE),
  .hpos(w_hpos),
  .lol(w_lol),
  .eol(w_eol),
  .vpos(w_vpos),
  .lof(w_lof),
  .eof(w_eof),
  .vblend(w_vblend),
  .strb(w_strb),
  .refr(w_refr)
);

///////////////////
// DMA scheduler //
///////////////////
dma_sched U_dma_sched
(
  // Clocks and reset
  .rst(~ram_rdy),
  .clk(clk),
  .cdac_r(w_cdac_r),
  .cdac_f(w_cdac_f),
  .cck(w_cck),
  // Configuration
  .cfg_ecs(cfg_ecs),
  // Beam position
  .hpos(w_hpos),
  .lol(w_lol),
  .eol(w_eol),
  .vpos(w_vpos),
  .eof(w_eof),
  .vblend(w_vblend),
  .strb(w_strb),
  .refr(w_refr),
  // Registers access
  .ptr_rd_ena(w_ptr_rd_ena),
  .ptr_rd_rga(w_ptr_rd_rga),
  .mod_rd_ena(w_mod_rd_ena),
  .mod_rd_rga(w_mod_rd_rga),
  .pos_rd_ena(w_pos_rd_ena),
  .pos_rd_rga(w_pos_rd_rga),
  .spr_vstart(w_spr_vstart),
  .spr_vstop(w_spr_vstop),
  .ptr_wr_ena(w_ptr_wr_ena),
  .ptr_wr_rga(w_ptr_wr_rga),
  // Address ALU control
  .ptr_inc(w_ptr_inc),
  .ptr_dec(w_ptr_dec),
  .mod_add(w_mod_add),
  .mod_sub(w_mod_sub),
  // Disk, Audio and Sprites control
  .dmal(dmal),
  .spren(w_SPREN),
  // Bitplane control
  .sddfen(r_ddf_soft_ena),
  .hddfen(r_ddf_hard_ena),
  .ddfinc(r_ddfinc_p2),
  .bpu(r_bpu_p2),
  // Copper control
  .copen(w_COPEN),
  .cop_con_wr(r_regs_cctl_p1),
  .cop_jmp1_wr(r_regs_cjp1_p1),
  .cop_jmp2_wr(r_regs_cjp2_p1),
  .cop_ins_wr(r_regs_cins_p1),
  .cop_loc(w_ptr_rd_val[22:1]),
  .cop_dma(w_cop_dma),
  .cop_pc(w_cop_pc),
  .cop_hit(w_cop_hit),
  // Blitter control
  .blten(w_BLTEN),
  .bltpri(r_BLTPRI),
  .bltwr(r_regs_bltw_p1),
  .bltsign(r_ptr_wr_val[15]),
  .bltbusy(w_BBUSY),
  .bltlast(w_blt_last),
  .bltirq_n(int3_n),
  .bltzero(w_BZERO),
  // Busses
  .ram_ref(ram_ref),
  .bus_we(w_bus_we),
  .bus_req(bus_req),
  .db_in(db_in),
  .db_out_er(db_out_er),
  .rga_out(rga_out),
  // Cache control
  .bst_mode(r_BSTMODE),
  .bst_ena(w_bst_ena),
  .chan_out(w_chan_out)
);

//////////////////////
// Custom registers //
//////////////////////
cust_regs_mp U_cust_regs_mp
(
  .rst(rst),
  .clk(clk),
  .ena_28m(w_ena_28m),
  .cyc_28m(w_cyc_28m),
  .ptr_rd_ena(w_ptr_rd_ena),
  .ptr_rd_rga(w_ptr_rd_rga),
  .ptr_rd_val(w_ptr_rd_val),
  .mod_rd_ena(w_mod_rd_ena),
  .mod_rd_rga(w_mod_rd_rga),
  .mod_rd_val(w_mod_rd_val),
  .pos_rd_ena(w_pos_rd_ena),
  .pos_rd_rga(w_pos_rd_rga),
  .spr_vstart(w_spr_vstart),
  .spr_vstop(w_spr_vstop),
  .ar3_rd_ena(1'b0),
  .ar3_rd_rga(8'h00),
  .ar3_rd_val(),
  .ptr_wr_ena(w_ptr_wr_ena),
  .ptr_wr_rga(w_ptr_wr_rga),
  .ptr_wr_val(r_ptr_wr_val),
  .cpu_wr_ena(w_cpu_wr_ena),
  .cpu_wr_rga(r_rga_p2),
  .cpu_wr_val(r_db_in)
);
defparam
  U_cust_regs_mp.MAIN_FREQ = MAIN_FREQ;

assign cdac_r  = w_cdac_r;
assign cdac_f  = w_cdac_f;
assign cck     = w_cck;
assign ena_28m = w_ena_28m;
assign cyc_28m = w_cyc_28m;
assign hpos    = w_hpos;
assign vpos    = w_vpos;
assign lol     = w_lol;
assign eol     = w_eol;
assign lof     = w_lof;
assign eof     = w_eof;

endmodule

module clocks_gen
(
  // Main reset & clock
  input             rst,         // Global reset
  input             clk,         // Master clock (28/56/85 MHz)
  // CPU and chipset clocks
  output reg        c7m_r,       // CPU 7 MHz clock rise
  output reg        c7m_f,       // CPU 7 MHz clock fall
  output reg        cdac_r,      // CDAC_n clock rise
  output reg        cdac_f,      // CDAC_n clock fall
  output reg        cck,         // CCK clock
  output reg        ena_28m,     // 28 MHz clock enable
  output reg  [2:0] cyc_28m,     // 28 MHz cycle number
  output reg [11:0] cyc_ram      // SDRAM cycle
);

// Clock input frequency : 28/57/85 MHz
parameter MAIN_FREQ = 85;

///////////////////////////////
// Quarter period generation //
///////////////////////////////

reg [2:0] r_cyc_sh; // Cycle shift register

always@(posedge rst or posedge clk) begin
  if (rst)
    r_cyc_sh <= 3'b100;
  else begin
    if (MAIN_FREQ == 85) // 85.909090 MHz case
      r_cyc_sh <= { r_cyc_sh[0], r_cyc_sh[2], r_cyc_sh[1] };
    if (MAIN_FREQ == 57) // 57.272727 MHz case
      r_cyc_sh <= { r_cyc_sh[1], r_cyc_sh[2], r_cyc_sh[0] };
    if (MAIN_FREQ == 28) // 28.636363 MHz case
      r_cyc_sh <= { r_cyc_sh[2], r_cyc_sh[1], r_cyc_sh[0] };
  end
end

///////////////////////
// Clocks generation //
///////////////////////

//           . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
//             _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _
// 85MHz   : _/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_
//             _______________________                         _______________________                         
// CCK     : _/                       \_______________________/  
//             ___________             ___________             ___________
// C7M     : _/           \___________/           \___________/           \___________
//                   ___________             ___________             ___________
// CDAC#   : _______/           \___________/           \___________/           \_____
//             _                       _                       _ 
// c7m_r   : _/ \_____________________/ \_____________________/ \_____________________
//                         _                       _                       _ 
// c7m_f   : _____________/ \_____________________/ \_____________________/ \_________
//                   _                       _                       _ 
// cdac_r  : _______/ \_____________________/ \_____________________/ \_______________
//                               _                       _                       _ 
// cdac_f  : ___________________/ \_____________________/ \_____________________/ \___
//             _     _     _     _     _     _     _     _     _     _     _     _
// ena_28m : _/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___
//
// cyc_28m : 7  X  0  X  1  X  2  X  3  X  4  X  5  X  6  X  7  X  0  X  1  X  2  X  3

reg [2:0] r_ph_ctr; // Phase counter

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_ph_ctr <= 3'd7;
    c7m_r    <= 1'b0;
    c7m_f    <= 1'b0;
    cdac_r   <= 1'b0;
    cdac_f   <= 1'b0;
    cck      <= 1'b0;
    ena_28m  <= 1'b0;
    cyc_28m  <= 3'd7;
  end else begin
    if (r_cyc_sh[2]) begin
      r_ph_ctr <= r_ph_ctr + 3'd1;
      case (r_ph_ctr)
        // Phase #0 -> #1
        3'b000:
        begin
          c7m_r  <= 1'b0;
          c7m_f  <= 1'b0;
          cdac_r <= 1'b1;
          cdac_f <= 1'b0;
          cck    <= 1'b1;
        end
        // Phase #1 -> #2
        3'b001:
        begin
          c7m_r  <= 1'b1;
          c7m_f  <= 1'b0;
          cdac_r <= 1'b0;
          cdac_f <= 1'b0;
          cck    <= 1'b1;
        end
        // Phase #2 -> #3
        3'b010:
        begin
          c7m_r  <= 1'b0;
          c7m_f  <= 1'b0;
          cdac_r <= 1'b0;
          cdac_f <= 1'b1;
          cck    <= 1'b1;
        end
        // Phase #3 -> #4
        3'b011:
        begin
          c7m_r  <= 1'b0;
          c7m_f  <= 1'b1;
          cdac_r <= 1'b0;
          cdac_f <= 1'b0;
          cck    <= 1'b0;
        end
        // Phase #4 -> #5
        3'b100:
        begin
          c7m_r  <= 1'b0;
          c7m_f  <= 1'b0;
          cdac_r <= 1'b1;
          cdac_f <= 1'b0;
          cck    <= 1'b0;
        end
        // Phase #5 -> #6
        3'b101:
        begin
          c7m_r  <= 1'b1;
          c7m_f  <= 1'b0;
          cdac_r <= 1'b0;
          cdac_f <= 1'b0;
          cck    <= 1'b0;
        end
        // Phase #6 -> #7
        3'b110:
        begin
          c7m_r  <= 1'b0;
          c7m_f  <= 1'b0;
          cdac_r <= 1'b0;
          cdac_f <= 1'b1;
          cck    <= 1'b0;
        end
        // Phase #7 -> #0
        3'b111:
        begin
          c7m_r  <= 1'b0;
          c7m_f  <= 1'b1;
          cdac_r <= 1'b0;
          cdac_f <= 1'b0;
          cck    <= 1'b1;
        end
        // Should never happen
        default:
        begin
          c7m_r  <= 1'b0;
          c7m_f  <= 1'b0;
          cdac_r <= 1'b0;
          cdac_f <= 1'b0;
          cck    <= 1'b0;
        end
      endcase
      ena_28m <= 1'b1;
    end else begin
      c7m_r   <= 1'b0;
      c7m_f   <= 1'b0;
      cdac_r  <= 1'b0;
      cdac_f  <= 1'b0;
      ena_28m <= 1'b0;
    end
    if (ena_28m)
      cyc_28m <= r_ph_ctr;
  end
end

always@(posedge rst or posedge clk) begin
  if (rst) begin
    cyc_ram  <= 12'b000000000000;
  end else begin
    if (cdac_r)
      cyc_ram  <= 12'b000000000001;
    else
      cyc_ram <= { cyc_ram[10:0], cyc_ram[11] };
  end
end

endmodule

module beam_ctr
(
  // Main reset & clock
  input             rst,         // Global reset
  input             clk,         // Master clock (28/56/85 MHz)
  input             cdac_r,      // CDAC_n clock rise
  input             cck,         // CCK clock
  input             pal_ntsc_n,  // NTSC(0) or PAL(1) mode
  input             laced,       // Interlaced mode
  output      [7:0] hpos,        // Horizontal position
  output            lol,         // Long line (228 cycles)
  output            eol,         // End of line
  output      [8:0] vpos,        // Vertical position
  output            lof,         // Long frame (263 or 313 lines)
  output            eof,         // End of frame
  output            vblend,      // End of vertical blanking
  output      [1:0] strb,        // Strobe line value
  output            refr         // Scanline with an extra refresh cycle
);

/////////////////////////
// Horizontal position //
/////////////////////////

reg        r_hpos_lol; // Long / short line toggle
reg  [7:0] r_hpos_ctr; // HPOS counter (0 - 226 or 227)
wire       w_hpos_eol; // End of line flag

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_hpos_lol <= 1'b0;
    r_hpos_ctr <= 8'd0;
  // Rising edge of CDAC_n with CCK = 0
  end else if (cdac_r & ~cck) begin
    // HPOS counter management
    if (w_hpos_eol) begin
      if (pal_ntsc_n)
        // No long line toggle in PAL mode
        r_hpos_lol <= 1'b0;
      else
        // Long line toggle in NTSC mode
        r_hpos_lol <= ~r_hpos_lol;
      // Clear HPOS
      r_hpos_ctr <= 8'd0;
    end else begin
      // Increment HPOS
      r_hpos_ctr <= r_hpos_ctr + 8'd1;
    end
  end
end

// End of line at cycle #226 or #227
assign w_hpos_eol = (r_hpos_ctr == { 7'b1110_001, r_hpos_lol }) ? 1'b1 : 1'b0;

assign hpos = r_hpos_ctr;
assign lol  = r_hpos_lol;
assign eol  = w_hpos_eol;

///////////////////////
// Vertical position //
///////////////////////

reg  [1:0] r_eol_dly;  // End of line delayed by 2 CCK cycles
reg        r_eof_dly;  // End of frame delayed by one line
reg        r_vpos_lof; // Long / short frame toggle
reg  [8:0] r_vpos_ctr; // VPOS counter (0 - 262 or 312)
reg        r_vpos_eof; // End of frame flag
wire [8:0] w_vpos_max; // Maximum VPOS value
wire       w_vpos_eof; // End of fram with LOF toggle
reg  [3:0] r_refr_ctr; // Refresh counter
reg        r_refr;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_eol_dly  <= 2'b00;
    r_eof_dly  <= 1'b0;
    r_vpos_lof <= 1'b0;
    `ifdef SIMULATION
    r_vpos_ctr <= 9'd260;
    `else
    r_vpos_ctr <= 9'd0;
    `endif
    r_vpos_eof <= 1'b0;
    r_refr_ctr <= 4'd0;
    r_refr     <= 1'b0;
  // Rising edge of CDAC_n with CCK = 0
  end else if (cdac_r & ~cck) begin
    // End of line delayed by 2 CCK cycles
    r_eol_dly <= { r_eol_dly[0], w_hpos_eol };
    // End of frame flag (it lasts one full line)
    r_vpos_eof <= (r_vpos_ctr == w_vpos_max) ? 1'b1 : 1'b0;

    if (r_eol_dly[1]) begin
      r_eof_dly <= r_vpos_eof & r_vpos_lof;
      // VPOS counter management
      if (w_vpos_eof) begin
        if (laced)
          // Long frame toggle in interlaced mode
          r_vpos_lof <= ~r_vpos_lof;
        else
          // Always a long frame in progressive
          r_vpos_lof <= 1'b1;
        // Clear VPOS
        r_vpos_ctr <= 9'd0;
      end else begin
        // Increment VPOS
        r_vpos_ctr <= r_vpos_ctr + 9'd1;
      end
      // Refresh counter management
      if (r_refr_ctr == 4'd9) begin
        r_refr_ctr <= 4'd0;
        r_refr     <= 1'b1;
      end else begin
        r_refr_ctr <= r_refr_ctr + 4'd1;
        r_refr     <= 1'b0;
      end
    end
  end
end

// 312 lines in PAL, 262 lines in NTSC
assign w_vpos_max = (pal_ntsc_n) ? 9'd311 : 9'd261;
// End of frame condition
assign w_vpos_eof = (r_vpos_eof & ~r_vpos_lof)
                  | (r_eof_dly  &  r_vpos_lof);

assign vpos = r_vpos_ctr;
assign lof  = r_vpos_lof;
assign eof  = w_vpos_eof;
assign refr = r_refr;

///////////////////////
// Strobes generator //
///////////////////////

`define STROBE_EQU 2'b00
`define STROBE_VBL 2'b01
`define STROBE_HOR 2'b10

reg  [1:0] r_str_fsm;    // Strobe FSM
reg  [3:0] r_strequ_cnt; // STREQU count (1 - 10)
reg  [4:0] r_strvbl_cnt; // STRVBL count (1 - 26)
reg        r_vblend;     // End of vertical blanking (registered)

wire [3:0] w_strequ_max; // Maximum value : 8, 9 or 10
wire [4:0] w_strvbl_max; // Maximum value : 21 or 26
wire       w_vblend;     // End of vertical blanking

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_strequ_cnt <= 4'd1;
    r_strvbl_cnt <= 5'd1;
    `ifdef SIMULATION
    r_str_fsm    <= `STROBE_HOR;
    `else
    r_str_fsm    <= `STROBE_EQU;
    `endif
    r_vblend     <= 1'b0;
  // Rising edge of CDAC_n with CCK = 0
  end else if (cdac_r & ~cck) begin
    if (w_hpos_eol) begin
      // Strobe state machine
      case (r_str_fsm)
        `STROBE_EQU :
          if (r_strequ_cnt == w_strequ_max)
            r_str_fsm <= `STROBE_VBL;
        `STROBE_VBL :
          if (w_vblend)
            r_str_fsm <= `STROBE_HOR;
        `STROBE_HOR :
          if (w_vpos_eof)
            r_str_fsm <= `STROBE_EQU;
        default :
          r_str_fsm <= `STROBE_EQU;
      endcase
      // Strobe line counters
      if (r_str_fsm[1]) begin
        r_strequ_cnt <= 4'd1;
        r_strvbl_cnt <= 5'd1;
      end else begin
        r_strequ_cnt <= r_strequ_cnt + 4'd1;
        r_strvbl_cnt <= r_strvbl_cnt + 5'd1;
      end
    end
    r_vblend <= w_vblend;
  end
end

// Number of STREQU lines :
// ------------------------
// NTSC    : 10 lines
// PAL SOF :  8 lines
// PAL LOF :  9 lines
assign w_strequ_max = { 2'b10, ~pal_ntsc_n, pal_ntsc_n & r_vpos_lof };

// Number of STREQU + STRVBL lines :
// ---------------------------------
// NTSC    : 21 lines
// PAL     : 26 lines
assign w_strvbl_max = { 1'b1, pal_ntsc_n, ~pal_ntsc_n, pal_ntsc_n, ~pal_ntsc_n };

assign w_vblend = (r_strvbl_cnt == w_strvbl_max) ? 1'b1 : 1'b0;
assign vblend = r_vblend;

assign strb = r_str_fsm;

endmodule

module dma_sched
(
  // Main reset & clock
  input             rst,         // Global reset
  input             clk,         // Master clock (28/56/85 MHz)
  // Generated clocks
  input             cck,         // CCK clock
  input             cdac_r,      // CDAC_n clock rise
  input             cdac_f,      // CDAC_n clock fall
  // Configuration
  input             cfg_ecs,     // OCS(0) or ECS(1) chipset
  // Horizontal position
  input       [7:0] hpos,        // Horizontal position
  input             lol,         // Long line (228 cycles)
  input             eol,         // End of line
  // Vertical position
  input       [8:0] vpos,        // Vertical position
  input             eof,         // End of field
  input             vblend,      // End of vertical blanking
  input       [1:0] strb,        // Strobe line value
  input             refr,        // Line with an extra refresh cycle
  // Registers access
  output            ptr_rd_ena,  // DMA pointer read enable
  output      [9:2] ptr_rd_rga,  // DMA pointer's RGA address
  output            mod_rd_ena,  // Modulo read enable
  output      [8:1] mod_rd_rga,  // Modulo's RGA address
  output            pos_rd_ena,  // Sprite position read enable
  output      [8:2] pos_rd_rga,  // Sprite position's RGA address
  input       [8:0] spr_vstart,  // Sprite vertical start value
  input       [8:0] spr_vstop,   // Sprite vertical stop value
  output            ptr_wr_ena,  // DMA pointer write enable
  output      [8:2] ptr_wr_rga,  // DMA pointer's RGA address
  // Address ALU control
  output            ptr_inc,     // Increment pointer
  output            ptr_dec,     // Decrement pointer
  output            mod_add,     // Add modulo to pointer
  output            mod_sub,     // Subtract modulo to pointer
  // Disk, Audio and Sprites control
  input             dmal,        // DMA request from Paula
  input             spren,       // DMA Sprite enable
  // Bitplane control
  input             sddfen,      // Display data fetch enable (soft)
  input             hddfen,      // Display data fetch enable (hard)
  input       [2:0] ddfinc,      // DDF counter increment
  input       [3:0] bpu,         // Bitplanes used
  // Copper control
  input             copen,       // DMA Copper enable
  input             cop_con_wr,  // COPCON written
  input             cop_jmp1_wr, // COPJMP1 written
  input             cop_jmp2_wr, // COPJMP2 written
  input             cop_ins_wr,  // COPINS written
  input      [22:1] cop_loc,     // COPxLOC value
  output            cop_dma,     // Copper uses DMA
  output     [22:1] cop_pc,      // Copper PC
  output            cop_hit,     // DMA cache hit
  // Blitter control
  input             blten,       // DMA Blitter enable
  input             bltpri,      // DMA Blitter priority
  input      [10:0] bltwr,       // BLTxxxx registers write
  input             bltsign,     // Sign for bresenham algorithm
  output            bltbusy,     // Blitter is busy
  output            bltlast,     // Last D cycle
  output            bltirq_n,    // Blitter interrupt
  output            bltzero,     // D channel result is null
  // Busses
  output            ram_ref,     // Chip RAM refresh request
  output            bus_we,      // Chip RAM write enable
  output            bus_req,     // Bus taken by Agnus
  input      [15:0] db_in,       // Data bus for Copper and Blitter
  output     [15:0] db_out_er,   // Data bus out from Blitter (early read)
  output      [8:1] rga_out,     // Register address bus out
  // Cache control
  input       [5:0] bst_mode,    // DMA burst mode
  output            bst_ena,     // Burst enable
  output      [4:0] chan_out     // DMA channel number
);

//////////////////////////////
// DMA finite state machine //
//////////////////////////////

`define DMA_REFRESH    5'b00001
`define DMA_DISK       5'b00010
`define DMA_AUDIO      5'b00100
`define DMA_SPRITE     5'b01000
`define DMA_BITPLANE   5'b10000

reg  [1:0] r_dmal;       // DMAL latched
reg  [4:0] r_dma_fsm_p0; // DMA FSM state

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_dmal       <= 2'b00;
    r_dma_fsm_p0 <= `DMA_REFRESH;
  end else if (cdac_r & ~cck) begin
    // Latch two previous DMAL
    r_dmal <= { r_dmal[0], dmal };
    
    // DMA state
    case (r_dma_fsm_p0)
      // Fixed DMA : memory refresh (cycles #000 - #008)
      `DMA_REFRESH :
      begin
        // Cycle #008 : go to next state
        if (hpos[3])
          r_dma_fsm_p0 <= `DMA_DISK;
      end
      
      // Fixed DMA : floppy disk (cycles #009 - #00E)
      `DMA_DISK :
      begin
        // Cycle #00E : go to next state
        if (hpos[3] & hpos[2] & hpos[1])
          r_dma_fsm_p0 <= `DMA_AUDIO;
      end
      
      // Fixed DMA : audio (cycles #00F - #015)
      `DMA_AUDIO :
      begin
        // Cycle #015 : go to next state
        if (hpos[4] & hpos[2] & hpos[0])
          r_dma_fsm_p0 <= `DMA_SPRITE;
      end
      
      // Fixed DMA : sprites (Cycles #017 - #035)
      `DMA_SPRITE :
      begin
        // Cycle #035 (or before) : go to next state
        if ((hpos[5] & hpos[4] & hpos[2] & hpos[0]) ||
            (sddfen))
          r_dma_fsm_p0 <= `DMA_BITPLANE;
      end
      
      // Fixed DMA : bitplanes (Cycles #036 - #0E3)
      `DMA_BITPLANE :
      begin
        // End of line : go to next state
        if (eol)
          r_dma_fsm_p0 <= `DMA_REFRESH;
      end
    endcase
  end
end

/////////////////////////
// RGA bus multiplexer //
/////////////////////////

reg  [8:1] r_rga_p3;     // RGA value muxed
reg  [4:0] r_ch_p3;      // DMA channel muxed
reg  [8:1] r_rga_p4;     // RGA value on the bus
reg  [4:0] r_ch_p4;      // DMA channel for the cache controller
reg        r_dsk_we_p3;  // Disk write enable
reg        r_blt_we_p4;  // Blitter write enable
reg        r_blt_we_p4b; // Blitter write enable
reg        r_bus_req_p3; // Bus requested by Agnus
reg        r_bus_req_p4; // Bus requested by Agnus
reg        r_bst_ena_p3; // DMA cache burst enable

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_rga_p3     <= 8'hFF;
    r_ch_p3      <= 5'h1F;
    r_rga_p4     <= 8'hFF;
    r_ch_p4      <= 5'h1F;
    r_dsk_we_p3  <= 1'b0;
    r_blt_we_p4  <= 1'b0;
    r_blt_we_p4b <= 1'b0;
    r_bus_req_p3 <= 1'b0;
    r_bus_req_p4 <= 1'b0;
    r_bst_ena_p3 <= 1'b0;
  end else begin
    if (cdac_r & ~cck) begin
    // Mux RGA values
    r_rga_p3 <= r_rga_ref_p2[8:1]
              & r_rga_dsk_p2[8:1]
              & r_rga_aud_p2[8:1]
              & r_rga_spr_p2[8:1]
              & r_rga_bpl_p2[8:1];
      // Mux channel values
      r_ch_p3 <= r_ch_dsk_p2
               & r_ch_aud_p2
               & r_ch_spr_p2
               & r_ch_bpl_p2;
               
      // Mux RGA value from Copper
    if (r_dma_cop_p3) begin
      if (r_use_ins_p3)
        // COPINS (FETCH_1 state)
        r_rga_p4 <= 8'h46;
      else
        // MOVE instruction (FETCH_2 state)
        if (~r_COPINS[0] & ~w_bad_reg)
          r_rga_p4 <= r_COPINS[8:1];
        // WAIT or SKIP instructions (FETCH_2 state)
        else
          r_rga_p4 <= 8'h46;
        r_ch_p4 <= 5'h1E;
      end else begin
      // Free cycle for Blitter or CPU
      r_rga_p4 <= r_rga_p3 & w_rga_blt_p3;
        r_ch_p4  <= r_ch_p3 & w_ch_blt_p3;
      end
      
      // DMA cache burst enable
      r_bst_ena_p3 <= (r_dma_dsk_p2 & bst_mode[0])
                    | (r_dma_aud_p2 & bst_mode[1])
                    | (r_dma_spr_p2 & bst_mode[2])
                    | (r_dma_bpl_p2 & bst_mode[3]);
      // Bus requested
      r_bus_req_p3 <= w_dma_use_p2;
      r_bus_req_p4 <= w_dma_blt_p3 | r_bus_req_p3;
      // Disk write enable
      r_dsk_we_p3  <= ~r_rga_dsk_p2[5];
      // Blitter write enable
      r_blt_we_p4  <= ~w_rga_blt_p3[4];
    end
    // Early read timing : half a CCK cycle sooner
    if (cdac_r & cck) begin
      r_blt_we_p4b <= r_blt_we_p4;
    end
  end
end

assign bus_we    = ~w_rga_blt_p3[4] | r_dsk_we_p3;
assign bus_req   = r_bus_req_p4;
assign db_out_er = (r_blt_we_p4b) ? w_db_out_p4 : 16'h0000;
assign rga_out = r_rga_p4;
assign chan_out  = r_ch_p4;
assign bst_ena   = r_bst_ena_p3 | (w_dma_blt_p3 & bst_mode[5]);

///////////////////////////////
// Internal registers access //
///////////////////////////////

reg        r_ptr_rd_p3;
reg  [9:2] r_ptr_rga_p3;
reg        r_mod_rd_p3;
reg  [8:1] r_mod_rga_p3;
reg        r_ptr_wr_p4;
reg  [8:2] r_ptr_rga_p4;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_ptr_rd_p3  <= 1'b0;
    r_ptr_rga_p3 <= 8'hFF;
    r_mod_rd_p3  <= 1'b0;
    r_mod_rga_p3 <= 8'hFF;
    r_ptr_wr_p4  <= 1'b0;
    r_ptr_rga_p4 <= 7'h7F;
  end else if (cdac_r & ~cck) begin
    r_ptr_rd_p3  <= r_dma_dsk_p2
                  | r_dma_aud_p2
                  | r_dma_spr_p2
                  | r_dma_bpl_p2;
    r_ptr_rga_p3 <= r_rga_dskp_p2[9:2]
                  & r_rga_audp_p2[9:2]
                  & r_rga_sprp_p2[9:2]
                  & r_rga_bplp_p2[9:2];
    r_mod_rd_p3  <= r_mod_bpl_p2;
    r_mod_rga_p3 <= r_rga_bplm_p2[8:1];
    r_ptr_wr_p4  <= r_ptr_rd_p3
                  | w_pinc_blt_p3 | w_pdec_blt_p3
                  | w_madd_blt_p3 | w_msub_blt_p3;
    r_ptr_rga_p4 <= r_ptr_rga_p3[8:2] & w_rga_bltp_p3;
  end
end

assign ptr_rd_ena = (r_ptr_rd_p3   | r_loc_cop_p3  |
                     w_pinc_blt_p3 | w_pdec_blt_p3 |
                     w_madd_blt_p3 | w_msub_blt_p3) & cck;
assign ptr_rd_rga = r_ptr_rga_p3 & r_rga_copp_p3[9:2] & w_rga_bltp_p3;
assign mod_rd_ena = (r_mod_rd_p3 | w_madd_blt_p3 | w_msub_blt_p3) & cck;
assign mod_rd_rga = r_mod_rga_p3 & w_rga_bltm_p3;
assign ptr_wr_ena = r_ptr_wr_p4 & cck;
assign ptr_wr_rga = r_ptr_rga_p4;

assign ptr_inc = r_ptr_rd_p3 | w_pinc_blt_p3;
assign ptr_dec = w_pdec_blt_p3;
assign mod_add = r_mod_rd_p3 | w_madd_blt_p3;
assign mod_sub = w_msub_blt_p3;

//////////////////////////
// DMA refresh evaluate //
//////////////////////////

reg        r_dma_ref_p2;    // DMA refresh active
reg  [8:0] r_rga_ref_p2;    // RGA value for DMA refresh
reg        r_dma_ref_p3;    // DMA refresh active

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_dma_ref_p2 <= 1'b0;
    r_rga_ref_p2 <= 9'h1FE;
    r_dma_ref_p3 <= 1'b0;
  end else if (cdac_r & ~cck) begin
    // Refresh state
    if (r_dma_fsm_p0[0]) begin
      // DMA allocation
      r_dma_ref_p2 <= hpos[0];
      // RGA computation
      case (hpos[2:0])
        // STREQU, STRVBL or STRHOR "DMA"
        3'b001  :
          r_rga_ref_p2 <= { 6'b0_0011_1, strb, 1'b0 };
        // STRLONG "DMA"
        3'b011 :
          if (lol)
            r_rga_ref_p2 <= 9'h03E;
          else
            r_rga_ref_p2 <= 9'h1FE;
        // No "DMA"
        default :
          r_rga_ref_p2 <= 9'h1FE;
      endcase
    // Others states
    end else begin
      r_dma_ref_p2 <= 1'b0;
      r_rga_ref_p2 <= 9'h1FE;
    end
    r_dma_ref_p3 <= r_dma_ref_p2;
  end
end

///////////////////
// SDRAM refresh //
///////////////////

reg        r_ram_ref_p4;    // SDRAM refresh active

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_ram_ref_p4 <= 1'b0;
  end else if (cdac_r) begin
    if (cck) begin
      r_ram_ref_p4 <= (hpos[2:1] == 2'b10) ? (refr & r_ram_ref_p4) : 1'b0;
    end else begin
      r_ram_ref_p4 <= r_dma_ref_p3;
    end
  end
end

assign ram_ref = r_ram_ref_p4;

///////////////////////
// DMA disk evaluate //
///////////////////////

reg        r_dma_dsk_p2;    // DMA disk active
reg  [8:0] r_rga_dsk_p2;    // RGA value for DMA disk
reg  [9:0] r_rga_dskp_p2;   // Internal RGA value for DMA disk pointer
reg  [4:0] r_ch_dsk_p2;     // DMA disk channel number (28 - 29)

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_dma_dsk_p2  <= 1'b0;
    r_rga_dsk_p2  <= 9'h1FE;
    r_rga_dskp_p2 <= 10'h3FE;
    r_ch_dsk_p2   <= 5'h1F;
  end else if (cdac_r & ~cck) begin
    // Disk state
    if (r_dma_fsm_p0[1]) begin
      // DMA allocation
      r_dma_dsk_p2 <= r_dmal[0] & hpos[0];
      // RGA computation
      if (r_dmal[0] & hpos[0]) begin
        if (r_dmal[1]) begin
          // Disk write : Memory -> Register
          r_rga_dsk_p2 <= 9'h026;
          r_ch_dsk_p2  <= 5'h1C;
        end else begin
          // Disk read : Register -> Memory
          r_rga_dsk_p2 <= 9'h008;
          r_ch_dsk_p2  <= 5'h1D;
        end
        r_rga_dskp_p2 <= 10'h220;
      end else begin
        // No DMA
        r_rga_dsk_p2  <= 9'h1FE;
        r_rga_dskp_p2 <= 10'h3FE;
        r_ch_dsk_p2   <= 5'h1F;
      end
    // Others states
    end else begin
      r_dma_dsk_p2  <= 1'b0;
      r_rga_dsk_p2  <= 9'h1FE;
      r_rga_dskp_p2 <= 10'h3FE;
      r_ch_dsk_p2   <= 5'h1F;
    end
  end
end

////////////////////////
// DMA audio evaluate //
////////////////////////

reg  [1:0] r_aud_ch_p1;     // Audio channel (0 - 3)
reg        r_dma_aud_p2;    // DMA audio active
reg  [8:0] r_rga_aud_p2;    // RGA value for DMA audio
reg  [9:0] r_rga_audp_p2;   // Internal RGA value for DMA audio pointer
reg  [4:0] r_ch_aud_p2;     // DMA audio channel number (16 - 19)

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_aud_ch_p1   <= 2'd0;
    r_dma_aud_p2  <= 1'b0;
    r_rga_aud_p2  <= 9'h1FE;
    r_rga_audp_p2 <= 10'h3FE;
    r_ch_aud_p2   <= 5'h1F;
  end else if (cdac_r & ~cck) begin
    // Audio channel counting
    if (!hpos[0]) begin
      if (r_dma_fsm_p0[2])
        r_aud_ch_p1 <= r_aud_ch_p1 + 2'd1;
      else
        r_aud_ch_p1 <= 2'd0;
    end
    // Audio state
    if (r_dma_fsm_p0[2]) begin
      // DMA allocation
      r_dma_aud_p2 <= r_dmal[0] & hpos[0];
      // RGA computation
      if (r_dmal[0] & hpos[0])
        // Audio DMA
        case (r_aud_ch_p1)
          2'b00 : begin // Channel #0
            r_rga_aud_p2  <= 9'h0AA;
            r_rga_audp_p2 <= {~r_dmal[1], 9'h0A0};
            r_ch_aud_p2   <= 5'h10;
          end
          2'b01 : begin // Channel #1
            r_rga_aud_p2  <= 9'h0BA;
            r_rga_audp_p2 <= {~r_dmal[1], 9'h0B0};
            r_ch_aud_p2   <= 5'h11;
          end
          2'b10 : begin // Channel #2
            r_rga_aud_p2  <= 9'h0CA;
            r_rga_audp_p2 <= {~r_dmal[1], 9'h0C0};
            r_ch_aud_p2   <= 5'h12;
          end
          2'b11 : begin // Channel #3
            r_rga_aud_p2  <= 9'h0DA;
            r_rga_audp_p2 <= {~r_dmal[1], 9'h0D0};
            r_ch_aud_p2   <= 5'h13;
          end
        endcase
      else begin
        // No DMA
        r_rga_aud_p2  <= 9'h1FE;
        r_rga_audp_p2 <= 10'h3FE;
        r_ch_aud_p2   <= 5'h1F;
      end
    // Others states
    end else begin
      r_dma_aud_p2  <= 1'b0;
      r_rga_aud_p2  <= 9'h1FE;
      r_rga_audp_p2 <= 10'h3FE;
      r_ch_aud_p2   <= 5'h1F;
    end
  end
end

/////////////////////////
// DMA sprite evaluate //
/////////////////////////

reg  [2:0] r_spr_nr_p0;     // Sprite number (0 - 7)
reg        r_vstart_equ_p1; // Vertical start comparator
reg        r_vstop_equ_p1;  // Vertical stop comparator
reg  [7:0] r_spr_st_mem;    // Sprites DMA states
reg        r_spr_st_rd_p1;  // Read sprite DMA state
reg        r_spr_st_wr_p1;  // Written sprite DMA state
reg        r_dma_spr_p2;    // DMA sprite active
reg  [8:0] r_rga_spr_p2;    // RGA value for DMA sprite
reg  [9:0] r_rga_sprp_p2;   // Internal RGA value for DMA sprite pointer
reg  [4:0] r_ch_spr_p2;     // DMA sprite channel number (0 - 7)

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_spr_nr_p0     <= 3'd0;
    r_vstart_equ_p1 <= 1'b0;
    r_vstop_equ_p1  <= 1'b0;
    r_spr_st_mem    <= 8'b00000000;
    r_spr_st_rd_p1  <= 1'b0;
    r_spr_st_wr_p1  <= 1'b0;
    r_dma_spr_p2    <= 1'b0;
    r_rga_spr_p2    <= 9'h1FE;
    r_rga_sprp_p2   <= 10'h3FE;
    r_ch_spr_p2     <= 5'h1F;
  end else if (cdac_r & ~cck) begin
    // Sprite number counting
    if (hpos[1:0] == 2'b01) begin
      if (r_dma_fsm_p0[3])
        r_spr_nr_p0 <= r_spr_nr_p0 + 3'd1;
      else
        r_spr_nr_p0 <= 3'd0;
    end
    // Vertical comparators
    r_vstart_equ_p1 <= (spr_vstart == vpos) ? 1'b1 : 1'b0;
    r_vstop_equ_p1  <= (spr_vstop  == vpos) ? 1'b1 : 1'b0;
    // Read current sprite DMA state
    r_spr_st_rd_p1  <= r_spr_st_mem[r_spr_nr_p0];
    // HPOS = 017, 019, 01B, ... 02F, 031, 033, 035
    if (r_dma_fsm_p0[3] & hpos[0] & spren) begin
      // Evaluate sprite DMA state
      if ((strb != 2'b10) || (r_vstop_equ_p1))
        r_spr_st_wr_p1 = 1'b0;
      else if (r_vstart_equ_p1)
        r_spr_st_wr_p1 = 1'b1;
      else
        r_spr_st_wr_p1 = r_spr_st_rd_p1;
      // Write back sprite DMA state
      r_spr_st_mem[r_spr_nr_p0] <= r_spr_st_wr_p1;
      // DMA sprite active flag and RGA value
      if ((vblend) || ((r_vstop_equ_p1) && (strb == 2'b10))) begin
        // Read SPRxPOS and SPRxCTL
        r_dma_spr_p2  <= 1'b1;
        r_rga_spr_p2  <= { 3'b101, r_spr_nr_p0, 1'b0, ~hpos[1], 1'b0 };
        r_rga_sprp_p2 <= { 5'b11001, r_spr_nr_p0, 2'b00 };
        r_ch_spr_p2   <= { 2'b00, r_spr_nr_p0 };
      end else if (r_spr_st_wr_p1) begin
        // Read SPRxDATA and SPRxDATB
        r_dma_spr_p2  <= 1'b1;
        r_rga_spr_p2  <= { 3'b101, r_spr_nr_p0, 1'b1, ~hpos[1], 1'b0 };
        r_rga_sprp_p2 <= { 5'b11001, r_spr_nr_p0, 2'b00 };
        r_ch_spr_p2   <= { 2'b00, r_spr_nr_p0 };
      end else begin
        r_dma_spr_p2  <= 1'b0;
        r_rga_spr_p2  <= 9'h1FE;
        r_rga_sprp_p2 <= 10'h3FE;
        r_ch_spr_p2   <= 5'h1F;
      end
    end
    // Others states
    else begin
      r_dma_spr_p2  <= 1'b0;
      r_rga_spr_p2  <= 9'h1FE;
      r_rga_sprp_p2 <= 10'h3FE;
      r_ch_spr_p2   <= 5'h1F;
    end
  end
end

// Sprite position access
assign pos_rd_ena = r_dma_fsm_p0[3];
assign pos_rd_rga = { 3'b101, r_spr_nr_p0, 1'b0 };

///////////////////////////
// DMA bitplane evaluate //
///////////////////////////

reg        r_ddf_ena_p1;    // Fetch enable
reg        r_ddf_end_p1;    // End of fetch
reg  [2:0] r_ddf_ctr_p1;    // Fetch counter (0 - 7)
wire       w_bpl_ena_p1;    // Bitplane enable
wire [2:0] w_bpl_nr_p1;     // Bitplane number (0 - 7)
reg        r_dma_bpl_p2;    // DMA bitplane active
reg        r_mod_bpl_p2;    // Add modulo to DMA pointer
reg  [8:0] r_rga_bpl_p2;    // RGA value for DMA bitplane
reg  [9:0] r_rga_bplp_p2;   // Internal RGA value for DMA bitplane pointers
reg  [8:0] r_rga_bplm_p2;   // Internal RGA value for modulos
reg  [4:0] r_ch_bpl_p2;     // DMA bitplane channel number (8 - 15)

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_ddf_ena_p1  <= 1'b0;
    r_ddf_end_p1  <= 1'b0;
    r_ddf_ctr_p1  <= 3'd0;
    r_dma_bpl_p2  <= 1'b0;
    r_mod_bpl_p2  <= 1'b0;
    r_rga_bpl_p2  <= 9'h1FE;
    r_rga_bplp_p2 <= 10'h3FE;
    r_rga_bplm_p2 <= 9'h1FE;
    r_ch_bpl_p2   <= 5'h1F;
  end else if (cdac_r & ~cck) begin
    // DMA bitplane enable
    r_ddf_ena_p1 <= sddfen & hddfen;
    // Data fetch counter
    if (r_dma_fsm_p0[4] & (r_ddf_ena_p1 | r_ddf_end_p1)) begin
      // Last data fetch
      if (r_ddf_ctr_p1 == 3'd7) begin
        if (sddfen & hddfen)
          r_ddf_end_p1 <= 1'b0;
        else
          r_ddf_end_p1 <= r_ddf_ena_p1;
      end
      // Lo-res       : counts 0, 1, 2, 3, 4, 5, 6, 7
      // Hi-res       : counts 1, 3, 5, 7
      // Super hi-res : counts 3, 7
      r_ddf_ctr_p1 <= r_ddf_ctr_p1 + ddfinc;
    end else begin
      r_ddf_end_p1 <= 1'b0;
      // Reset value : 0 (Lo-res), 1 (Hi-res), 3 (Super hi-res)
      r_ddf_ctr_p1 <= 3'd7 + ddfinc;
    end
    
    // DMA bitplane active flag and RGA value
    if ((w_bpl_nr_p1 < bpu) && (w_bpl_ena_p1)) begin
      r_dma_bpl_p2  <= 1'b1;
      r_mod_bpl_p2  <= r_ddf_end_p1;
      r_rga_bpl_p2  <= { 5'b10001, w_bpl_nr_p1, 1'b0 };
      r_rga_bplp_p2 <= { 5'b10111, w_bpl_nr_p1, 2'b00 };
      r_ch_bpl_p2   <= { 2'b01, w_bpl_nr_p1 };
    end else begin
      r_dma_bpl_p2  <= 1'b0;
      r_rga_bpl_p2  <= 9'h1FE;
      r_rga_bplp_p2 <= 10'h3FE;
      r_ch_bpl_p2   <= 5'h1F;
    end
    
    // Modulo add cycle
    if (r_ddf_end_p1) begin
      r_mod_bpl_p2  <= 1'b1;
      r_rga_bplm_p2 <= { 7'b1000010, w_bpl_nr_p1[0], 1'b0 };
    end else begin
      r_mod_bpl_p2  <= 1'b0;
      r_rga_bplm_p2 <= 9'h1FE;
    end
  end
end

// Lo-res       : counts 7, 3, 5, 1, 6, 2, 4, 0
// Hi-res       : counts 3, 1, 2, 0
// Super hi-res : counts 1, 0
assign w_bpl_nr_p1  = { ~r_ddf_ctr_p1[0], ~r_ddf_ctr_p1[1], ~r_ddf_ctr_p1[2] };
// Bitplane enable
assign w_bpl_ena_p1 = r_dma_fsm_p0[4] & (r_ddf_ena_p1 | r_ddf_end_p1);

/////////////////////////
// DMA Copper evaluate //
/////////////////////////

`define COP_IDLE         6'b000001
`define COP_JUMP         6'b000010
`define COP_FETCH_1      6'b000100
`define COP_FETCH_2      6'b001000
`define COP_WAIT_SKIP_1  6'b010000
`define COP_WAIT_SKIP_2  6'b100000

reg  [5:0] r_cop_fsm;       // Copper state
reg [22:1] r_cop_pc;        // Copper program counter
reg        r_cop_hit;       // Cache hit for Copper
reg        r_skip_ins;      // Skip next MOVE

reg  [2:0] r_cop_ena_p0_p2; // Copper enabled on even cycles
reg        r_dma_cop_p3;    // DMA Copper active
reg        r_upd_fsm_p3;    // Update Copper FSM
reg        r_loc_cop_p3;    // Read COPxLOC register
reg        r_use_ins_p3;    // Use COPINS as RGA value
reg  [9:0] r_rga_copp_p3;   // Internal RGA value for COPxLOC register

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_skip_ins      <= 1'b0;
    r_cop_pc        <= 22'd0;
    r_cop_hit       <= 1'b0;
    r_cop_fsm       <= `COP_IDLE;
    r_cop_ena_p0_p2 <= 3'b000;
    r_dma_cop_p3    <= 1'b0;
    r_upd_fsm_p3    <= 1'b0;
    r_loc_cop_p3    <= 1'b0;
    r_use_ins_p3    <= 1'b0;
    r_rga_copp_p3   <= 10'h3FE;
  end else if (cdac_r & ~cck) begin
    // Copper enabled
    r_cop_ena_p0_p2 <= { r_cop_ena_p0_p2[1:0], ~hpos[0] & copen & ~eol};
    // Copper finite state machine
    // (active if no DMA bitplane on even cycles)
    if (r_cop_ena_p0_p2[2] & ~r_dma_bpl_p2)
    begin
      r_upd_fsm_p3  <= 1'b1;
      case (r_cop_fsm)
        // Copper is idling
        default :
        begin
          r_dma_cop_p3  <= 1'b0;
          r_loc_cop_p3  <= 1'b0;
          r_use_ins_p3  <= 1'b0;
          r_rga_copp_p3 <= 10'h3FE;
        end
        // After start of frame or COPJMPx write
        `COP_JUMP :
        begin
          r_dma_cop_p3  <= 1'b1;
          r_loc_cop_p3  <= 1'b1;
          r_use_ins_p3  <= 1'b1;
          r_rga_copp_p3 <= { 7'b0010000, r_cop_loc, 2'b00 };
        end
        // Fetch first instruction word
        `COP_FETCH_1 :
        begin
          r_dma_cop_p3  <= 1'b1;
          r_loc_cop_p3  <= 1'b0;
          r_use_ins_p3  <= 1'b1;
          r_rga_copp_p3 <= 10'h3FE;
        end
        // Fetch second instruction word
        `COP_FETCH_2 :
        begin
          r_dma_cop_p3  <= 1'b1;
          r_loc_cop_p3  <= 1'b0;
          r_use_ins_p3  <= r_skip_ins;
          r_rga_copp_p3 <= 10'h3FE;
        end
      endcase
    end else begin
      // DMA is free for Blitter or CPU
      r_upd_fsm_p3  <= 1'b0;
      r_dma_cop_p3  <= 1'b0;
      r_loc_cop_p3  <= 1'b0;
      r_rga_copp_p3 <= 10'h3FE;
    end
    
    if (r_upd_fsm_p3) begin
      case (r_cop_fsm)
        default :
        begin
          r_cop_fsm <= `COP_IDLE;
        end
        `COP_JUMP :
        begin
          // Update PC from COPxLOC
          r_cop_pc  <= cop_loc;
          r_cop_hit <= 1'b0;
          // Fetch first instruction word
          r_cop_fsm <= `COP_FETCH_1;
        end
        `COP_FETCH_1 :
        begin
          // Increment PC
          r_cop_pc  <= r_cop_pc + 22'd1;
          r_cop_hit <= ~(&r_cop_pc[3:1]);
          // Fetch second instruction word
          r_cop_fsm <= `COP_FETCH_2;
        end
        `COP_FETCH_2 :
        begin
          // Increment PC
          r_cop_pc   <= r_cop_pc + 22'd1;
          r_cop_hit <= ~(&r_cop_pc[3:1]);
          // Clear skip flag
          r_skip_ins <= 1'b0;
          if (r_COPINS[0])
            // WAIT or SKIP
            r_cop_fsm <= `COP_WAIT_SKIP_1;
          else if (w_bad_reg)
            // MOVE to protected register : halt Copper
            r_cop_fsm <= `COP_IDLE;
          else
            // Allowed MOVE
            r_cop_fsm <= `COP_FETCH_1;
        end
        `COP_WAIT_SKIP_1 :
        begin
          // Dummy cycle
          r_cop_fsm <= `COP_WAIT_SKIP_2;
        end
        `COP_WAIT_SKIP_2 :
        begin
          if (r_beam_equ[r_COPINS[0]]) begin
            // SKIP instruction : set flag
            r_skip_ins <= r_COPINS[0];
            // Fetch first instruction word
            r_cop_fsm <= `COP_FETCH_1;
          end else begin
            // SKIP instruction does not wait
            if (r_COPINS[0])
              r_cop_fsm <= `COP_FETCH_1;
          end
        end
      endcase
      // COPxJMP written or start of frame
      if (r_cop_jmp) r_cop_fsm <= `COP_JUMP;
    end
  end
end

assign cop_dma = r_dma_cop_p3;
assign cop_pc  = r_cop_pc;
assign cop_hit = r_cop_hit;

///////////////////////////
// Video beam comparator //
///////////////////////////

wire [7:1] w_hpos_cmp;
wire [7:0] w_vpos_cmp;
reg  [1:0] r_beam_equ;

assign w_hpos_cmp = (r_COPINS[7:1] & r_COPINS[23:17])
                  | (~r_COPINS[7:1] & hpos[7:1]);
assign w_vpos_cmp = ({1'b1, r_COPINS[14:8]} & r_COPINS[31:24])
                  | (~r_COPINS[14:8] & vpos[6:0]);

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_beam_equ <= 2'b00;
  end else if (cdac_r & ~cck) begin
    if ({vpos[7:0], hpos[7:1]} >= {w_vpos_cmp, w_hpos_cmp})
      r_beam_equ[1] <= r_COPINS[15] | ~w_blt_busy;
    else
      r_beam_equ[1] <= 1'b0;
    r_beam_equ[0] <= r_beam_equ[1];
  end
end

//////////////////////
// Copper registers //
//////////////////////

reg         r_CDANG;
reg         r_cop_jmp;
reg         r_cop_loc;
reg  [31:0] r_COPINS;
wire        w_bad_reg;

always @(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef SIMULATION
    r_CDANG   <= 1'b1;
    `else
    r_CDANG   <= 1'b0;
    `endif
    r_cop_jmp <= 1'b0;
    r_cop_loc <= 1'b0;
    r_COPINS  <= 32'h01FE01FE; // Dummy MOVE
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // COPCON register
    if (cop_con_wr)
      r_CDANG <= db_in[1];
    // COPJMP1 register
    if ((cop_jmp1_wr) || ((hpos[2:0] == 3'b001) && (eof) && (r_dma_fsm_p0[0])))
    begin
      r_cop_jmp <= 1'b1;
      r_cop_loc <= 1'b0; // Get PC from COPLC1
    end
    else if (r_cop_fsm[1]) // JUMP state
      r_cop_jmp <= 1'b0;
    // COPJMP2 register
    if (cop_jmp2_wr)
    begin
      r_cop_jmp <= 1'b1;
      r_cop_loc <= 1'b1; // Get PC from COPLC2
    end
    else if (r_cop_fsm[1]) // JUMP state
      r_cop_jmp <= 1'b0;
    // COPINS register
    if (cop_ins_wr)
      r_COPINS <= { r_COPINS[15:0], db_in };
  end
end

assign w_bad_reg = ((r_COPINS[8:6] == 3'b000) && (!cfg_ecs))
                || ((r_COPINS[8:7] == 2'b00) && (!r_CDANG)) ? 1'b1 : 1'b0;

//////////////////////////
// DMA Blitter evaluate //
//////////////////////////

wire        w_blt_busy;
wire        w_blt_last;
wire        w_blt_zero;
wire        w_dma_use_p2;
wire        w_dma_blt_p3;
wire        w_pinc_blt_p3;
wire        w_pdec_blt_p3;
wire        w_madd_blt_p3;
wire        w_msub_blt_p3;
wire  [8:1] w_rga_blt_p3;
wire  [9:2] w_rga_bltp_p3;
wire  [8:1] w_rga_bltm_p3;
wire  [4:0] w_ch_blt_p3;
wire [15:0] w_db_out_p4;

// 2-LUT levels, 3 LUTs total
assign w_dma_use_p2 = r_dma_ref_p2                              // Refresh
                    | r_dma_dsk_p2                              // Disk
                    | r_dma_aud_p2                              // Audio
                    | r_dma_spr_p2                              // Sprites
                    | r_dma_bpl_p2                              // Bitplanes
                    | (r_cop_ena_p0_p2[2] & (|r_cop_fsm[3:1])); // Copper         

blitter U_blitter
(
  .rst(rst),
  .clk(clk),
  .cck(cck),
  .cdac_r(cdac_r),
  .cdac_f(cdac_f),
  .cfg_ecs(cfg_ecs),
  .blten(blten),
  .bltpri(bltpri),
  .dmafree(~w_dma_use_p2),
  .bltbusy(w_blt_busy),
  .bltirq_n(bltirq_n),
  .bltlast(bltlast),
  .bltzero(w_blt_zero),
  .bltdma(w_dma_blt_p3),
  .bltpinc(w_pinc_blt_p3),
  .bltpdec(w_pdec_blt_p3),
  .bltmadd(w_madd_blt_p3),
  .bltmsub(w_msub_blt_p3),
  .bltwr(bltwr),
  .bltsign(bltsign),
  .db_in(db_in),
  .db_out(w_db_out_p4),
  .rga_out(w_rga_blt_p3),
  .rga_ptr(w_rga_bltp_p3),
  .rga_mod(w_rga_bltm_p3),
  .chan_out(w_ch_blt_p3)
);

assign bltbusy = w_blt_busy;
assign bltzero = w_blt_zero;

endmodule

module blitter
(
  // Main reset & clock
  input             rst,       // Global reset
  input             clk,       // Master clock (28/56/85 MHz)
  // Generated clocks
  input             cck,       // CCK clock
  input             cdac_r,    // CDAC_n rising edge
  input             cdac_f,    // CDAC_n falling edge
  // Configuration
  input             cfg_ecs,   // OCS(0) or ECS(1) chipset
  // DMA control
  input             blten,     // DMA Blitter enable
  input             bltpri,    // DMA Blitter priority
  input             dmafree,   // DMA slot free
  input             bltsign,   // Sign for bresenham algorithm
  output            bltbusy,   // Blitter busy
  output            bltirq_n,  // Blitter interrupt
  output            bltlast,   // Last D cycle
  output            bltzero,   // Blitter zero flag
  output            bltdma,    // Blitter uses this cycle
  output            bltpinc,   // Blitter increments pointer
  output            bltpdec,   // Blitter decrements pointer
  output            bltmadd,   // Blitter adds modulo
  output            bltmsub,   // Blitter subtracts modulo
  // Address decoding
  input      [10:0] bltwr,     // BLTxxxx registers write
  // Busses
  input      [15:0] db_in,     // Data bus input
  output     [15:0] db_out,    // Data bus output
  output      [8:1] rga_out,   // Register address bus out
  output      [9:2] rga_ptr,   // Internal RGA for pointers
  output      [8:1] rga_mod,   // Internal RGA for modulos
  output      [4:0] chan_out   // DMA channel number
);

/////////////////////////
// BLTCON0(L) register //
/////////////////////////

reg   [3:0] r_ASH;     // Shift value of A source
reg  [15:0] r_ash_msk; // Bit mask for multipliers
reg   [3:0] r_USEx;    // Use A, B, C or/and D
reg   [7:0] r_LF;      // Logic function minterm select

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_ASH     <= 4'd0;
    r_ash_msk <= 16'h0001;
    r_USEx    <= 4'b0000;
    r_LF      <= 8'h00;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // A source shift value
    if (bltwr[0]) r_ASH <= db_in[15:12];
    if (r_blt_fsm[0]) begin
      case (r_ASH)
        4'h0 : r_ash_msk <= 16'h0001;
        4'h1 : r_ash_msk <= 16'h0002;
        4'h2 : r_ash_msk <= 16'h0004;
        4'h3 : r_ash_msk <= 16'h0008;
        4'h4 : r_ash_msk <= 16'h0010;
        4'h5 : r_ash_msk <= 16'h0020;
        4'h6 : r_ash_msk <= 16'h0040;
        4'h7 : r_ash_msk <= 16'h0080;
        4'h8 : r_ash_msk <= 16'h0100;
        4'h9 : r_ash_msk <= 16'h0200;
        4'hA : r_ash_msk <= 16'h0400;
        4'hB : r_ash_msk <= 16'h0800;
        4'hC : r_ash_msk <= 16'h1000;
        4'hD : r_ash_msk <= 16'h2000;
        4'hE : r_ash_msk <= 16'h4000;
        4'hF : r_ash_msk <= 16'h8000;
      endcase
    end else if (r_ash_inc) begin
      r_ash_msk <= { r_ash_msk[14:0], r_ash_msk[15] };
    end else if (r_ash_dec) begin
      r_ash_msk <= { r_ash_msk[0], r_ash_msk[15:1] };
    end
    
    // Channels used
    if (bltwr[0]) begin
      r_USEx <= db_in[11:8];
    end else if (w_blk_end & w_seq_end & dmafree) begin
      // End of block : keep only D channel
      r_USEx[3:1] <= 3'b000;
    end
    
    // Logical function select
    if (bltwr[0] | (bltwr[5] & cfg_ecs)) begin
      r_LF <= db_in[7:0];
    end
  end
end

//////////////////////
// BLTCON1 register //
//////////////////////

reg   [3:0] r_BSH;     // Shift value of B source
reg  [15:0] r_bsh_msk; // Bit mask for multipliers
reg   [7:0] r_BLTCON1; // Rest of BLTCON1
wire  [2:0] w_OCTANT;  // Octant number
wire        w_LINE;    // Line mode
wire        w_DESC;    // Descending mode
wire        w_FCI;     // Fill carry in
wire        w_EFE;     // Exclusive fill mode
wire        w_IFE;     // Inclusive fill mode

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_BSH     <= 4'd0;
    r_bsh_msk <= 16'h0001;
    r_BLTCON1 <= 8'h00;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // B source shift value
    if (bltwr[1]) r_BSH <= db_in[15:12];
    if (r_blt_fsm[0]) begin
      case (r_BSH)
        4'h0 : r_bsh_msk <= 16'h0001;
        4'h1 : r_bsh_msk <= 16'h0002;
        4'h2 : r_bsh_msk <= 16'h0004;
        4'h3 : r_bsh_msk <= 16'h0008;
        4'h4 : r_bsh_msk <= 16'h0010;
        4'h5 : r_bsh_msk <= 16'h0020;
        4'h6 : r_bsh_msk <= 16'h0040;
        4'h7 : r_bsh_msk <= 16'h0080;
        4'h8 : r_bsh_msk <= 16'h0100;
        4'h9 : r_bsh_msk <= 16'h0200;
        4'hA : r_bsh_msk <= 16'h0400;
        4'hB : r_bsh_msk <= 16'h0800;
        4'hC : r_bsh_msk <= 16'h1000;
        4'hD : r_bsh_msk <= 16'h2000;
        4'hE : r_bsh_msk <= 16'h4000;
        4'hF : r_bsh_msk <= 16'h8000;
      endcase
    end else if (r_bsh_dec) begin
      r_bsh_msk <= { r_bsh_msk[0], r_bsh_msk[15:1] };
    end

    // Misc. flags
    if (bltwr[1]) begin
      r_BLTCON1 <= db_in[7:0];
    end
  end
end

// Line mode
assign w_LINE = r_BLTCON1[0];
// Octant number
assign w_OCTANT = r_BLTCON1[4:2];
// Descending mode
assign w_DESC = ~r_BLTCON1[0] & r_BLTCON1[1];
// Fill carry in
assign w_FCI  = ~r_BLTCON1[0] & r_BLTCON1[2];
// Inclusive fill mode
assign w_IFE  = ~r_BLTCON1[0] & r_BLTCON1[3];
// Exclusive fill mode
assign w_EFE  = ~r_BLTCON1[0] & r_BLTCON1[4];

///////////////////////
// BLTAxWM registers //
///////////////////////

reg  [15:0] r_BLTAFWM; // Blitter first word mask for source A
reg  [15:0] r_BLTALWM; // Blitter last word mask for source A
reg  [15:0] r_bltamsk; // Blitter mask for source A

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_BLTAFWM <= 16'h0000;
    r_BLTALWM <= 16'h0000;
    r_bltamsk <= 16'hFFFF;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    if (bltwr[2]) r_BLTAFWM <= db_in;
    if (bltwr[3]) r_BLTALWM <= db_in;
    r_bltamsk <= (r_BLTAFWM | {16{~r_fwt_dly[2]}})
               & (r_BLTALWM | {16{~r_lwt_dly[2]}});
  end
end

///////////////////////
// BLTSIZx registers //
///////////////////////

reg  [14:0] r_BLTSIZV; // Blitter size : height
reg  [10:0] r_BLTSIZH; // Blitter size : width
reg         r_ocsblit; // OCS size blit
reg         r_stblit;  // Start blitter
reg         r_bltbusy; // Blitter busy

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_BLTSIZV <= 15'd0;
    r_BLTSIZH <= 11'd0;
    r_ocsblit <= 1'b0;
    r_stblit  <= 1'b0;
    r_bltbusy <= 1'b0;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // OCS register
    if (bltwr[4]) begin
      r_BLTSIZV <= { 5'b00000, db_in[15:6] };
      r_BLTSIZH <= { 5'b00000, db_in[5:0] };
      r_ocsblit <= 1'b1;
      r_stblit  <= blten;
      r_bltbusy <= blten;
    end
    // ECS registers
    if (bltwr[6] & cfg_ecs) begin
      r_BLTSIZV <= db_in[14:0];
    end
    if (bltwr[7] & cfg_ecs) begin
      r_BLTSIZH <= db_in[10:0];
      r_ocsblit <= 1'b0;
      r_stblit  <= blten;
      r_bltbusy <= blten;
    end
    // Clear start bit during INIT cycle
    if (r_blt_fsm[0]) r_stblit <= 1'b0;
    // Clear blitter busy
    if (r_blt_done & w_seq_end & dmafree) r_bltbusy <= 1'b0;
  end
end

assign bltbusy = r_bltbusy;
assign bltirq_n = ~r_blt_done;

///////////////////
// Size counters //
///////////////////

reg  [14:0] r_bltvcnt;    // Vertical counter
reg  [10:0] r_blthcnt;    // Horizontal counter
reg   [2:0] r_fwt_dly;    // First word time delayed by 3 cycles
reg   [2:0] r_lwt_dly;    // Last word time delayed by 3 cycles
reg   [4:0] r_seq_dly;    // End of sequence delayed by 4 or 5 cycles

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_bltvcnt <= 15'd0;
    r_blthcnt <= 11'd0;
    r_fwt_dly <= 3'b000;
    r_lwt_dly <= 3'b000;
    r_seq_dly <= 5'b00000;
  end else if (cdac_r & ~cck) begin
    if (dmafree) begin
      if (r_blt_fsm[0]) begin
        // Init : load counters
        r_bltvcnt <= r_BLTSIZV;
        r_blthcnt <= r_BLTSIZH;
      end else if (w_seq_end) begin
        // Channel C or D : decrement counters
        if (r_last_word | w_LINE) begin
          // One line processed
          r_bltvcnt <= r_bltvcnt - 15'd1;
          r_blthcnt <= r_BLTSIZH;
        end else begin
          // One word processed
          r_blthcnt <= r_blthcnt - 11'd1;
        end
      end
      // First word time
      r_fwt_dly <= { r_fwt_dly[1:0], r_first_word };
      // Last word time
      r_lwt_dly <= { r_lwt_dly[1:0], r_last_word };
      // End of sequence
      if (r_USEx[1:0] == 2'b10)
        // Delayed by 5 cycles when USEC = 1 and USED = 0
        r_seq_dly <= { r_seq_dly[3:0], w_seq_end };
      else
        // Delayed by 4 cycles otherwise
        r_seq_dly <= { r_seq_dly[3], r_seq_dly[1], r_seq_dly[1:0], w_seq_end };
    end
  end
end

reg         r_first_word; // First word of line
reg         r_last_word;  // last word of line
reg         r_last_line;  // Last line of block
wire        w_blk_end;    // End of block

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_first_word <= 1'b0;
    r_last_word  <= 1'b0;
    r_last_line  <= 1'b0;
  end else if (cdac_r & cck) begin
    // First word comparator
    if (r_blthcnt == r_BLTSIZH)
      r_first_word <= 1'b1;
    else
      r_first_word <= 1'b0;
    // Last word comparator
    if (((r_blthcnt[10:6] == 5'd0) || (r_ocsblit)) && (r_blthcnt[5:0] == 6'd1))
      r_last_word <= 1'b1;
    else
      r_last_word <= 1'b0;
    // Last line comparator
    if (((r_bltvcnt[14:10] == 5'd0) || (r_ocsblit)) && (r_bltvcnt[9:0] == 10'd1))
      r_last_line <= 1'b1;
    else
      r_last_line <= 1'b0;
  end
end

// End of block transfer
assign w_blk_end = r_last_word & r_last_line;

///////////////////////
// BLTxDAT registers //
///////////////////////

reg  [15:0] r_BLTADAT;
wire [15:0] w_bltadat;
reg  [15:0] r_bltaold;

reg  [15:0] r_BLTBDAT;
reg  [15:0] r_bltbold;

reg  [15:0] r_BLTCDAT;

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_BLTCDAT <= 16'h0000;
    r_BLTBDAT <= 16'h0000;
    r_bltbold <= 16'h0000;
    r_BLTADAT <= 16'h0000;
    r_bltaold <= 16'h0000;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    if (bltwr[8])
      r_BLTCDAT <= db_in;     // C hold

    if (r_blt_fsm[0])
      // Clear B old during INIT
      r_bltbold <= 16'h0000;
    else if (r_seq_dly[3])
      // Store B old when sequence ends
      r_bltbold <= r_BLTBDAT;

    if (bltwr[9])
      r_BLTBDAT <= db_in;     // B new

    if (r_blt_fsm[0])
      // Clear A old during INIT
      r_bltaold <= 16'h0000;
    else if (r_seq_dly[3])
      // Store A old when sequence ends
      r_bltaold <= w_bltadat;

    if (bltwr[10])
      r_BLTADAT <= db_in;     // A new
  end
end

// Combine first and last word masks with A
assign w_bltadat = r_BLTADAT & r_bltamsk;

//////////////////////
// Blitter shifters //
//////////////////////

wire [15:0] w_bltash;   // Shifted A source
wire [15:0] w_bltbsh;   // Shifted B source

blt_shifter a_shifter
(
  .desc(w_DESC),
  .bit_mask(r_ash_msk),
  .data_old(r_bltaold),
  .data_new(r_BLTADAT),
  .data_out(w_bltash)
);

blt_shifter b_shifter
(
  .desc(w_DESC),
  .bit_mask(r_bsh_msk),
  .data_old(r_bltbold),
  .data_new(r_BLTBDAT),
  .data_out(w_bltbsh)
);

reg  [15:0] r_bltahold; // A hold
reg  [15:0] r_bltbhold; // B hold

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_bltahold <= 16'h0000;
    r_bltbhold <= 16'h0000;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    if (r_seq_dly[3]) begin
      r_bltahold <= w_bltash; // A hold
      r_bltbhold <= w_bltbsh; // B hold
    end
  end
end

/////////////////////
// Blitter minterm //
/////////////////////

integer     i;
reg  [15:0] r_mt_out;   // Minterm output

always @(r_bltahold or r_bltbhold or r_BLTCDAT or r_LF) begin
  for (i = 0; i <= 15; i = i + 1)
  begin
    r_mt_out[i] = ~r_bltahold[i] & ~r_bltbhold[i] & ~r_BLTCDAT[i] & r_LF[0]
                | ~r_bltahold[i] & ~r_bltbhold[i] &  r_BLTCDAT[i] & r_LF[1]
                | ~r_bltahold[i] &  r_bltbhold[i] & ~r_BLTCDAT[i] & r_LF[2]
                | ~r_bltahold[i] &  r_bltbhold[i] &  r_BLTCDAT[i] & r_LF[3]
                |  r_bltahold[i] & ~r_bltbhold[i] & ~r_BLTCDAT[i] & r_LF[4]
                |  r_bltahold[i] & ~r_bltbhold[i] &  r_BLTCDAT[i] & r_LF[5]
                |  r_bltahold[i] &  r_bltbhold[i] & ~r_BLTCDAT[i] & r_LF[6]
                |  r_bltahold[i] &  r_bltbhold[i] &  r_BLTCDAT[i] & r_LF[7];
  end
end

////////////////
// Fill logic //
////////////////

wire  [3:0] w_fill_cry; // Intermediate fill carry
wire [15:0] w_fill_out; // Fill logic output
reg         r_fill_cin; // Fill carry in
reg  [15:0] r_bltdhold; // D hold
reg         r_bltzero;  // Blitter zero flag

// First nibble
blt_fill U_blt_fill_0
(
  .ife(w_IFE),
  .efe(w_EFE),
  .fci(r_fill_cin),
  .din(r_mt_out[3:0]),
  .fco(w_fill_cry[0]),
  .dout(w_fill_out[3:0])
);

// Second nibble
blt_fill U_blt_fill_1
(
  .ife(w_IFE),
  .efe(w_EFE),
  .fci(w_fill_cry[0]),
  .din(r_mt_out[7:4]),
  .fco(w_fill_cry[1]),
  .dout(w_fill_out[7:4])
);

// Third nibble
blt_fill U_blt_fill_2
(
  .ife(w_IFE),
  .efe(w_EFE),
  .fci(w_fill_cry[1]),
  .din(r_mt_out[11:8]),
  .fco(w_fill_cry[2]),
  .dout(w_fill_out[11:8])
);

// Fourth nibble
blt_fill U_blt_fill_3
(
  .ife(w_IFE),
  .efe(w_EFE),
  .fci(w_fill_cry[2]),
  .din(r_mt_out[15:12]),
  .fco(w_fill_cry[3]),
  .dout(w_fill_out[15:12])
);

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_fill_cin <= 1'b0;
    r_bltdhold <= 16'h0000;
    r_bltzero  <= 1'b0;
  // Rising edge of CDAC_n with CCK = 1
  end else if (cdac_r & cck) begin
    // Load flag when line starts
    if (r_seq_dly[3] & r_fwt_dly[2])
      r_fill_cin <= w_FCI;
    else if (r_seq_dly[4])
      r_fill_cin <= w_fill_cry[3];

    // Register that holds the result      
    if (r_seq_dly[4])
      r_bltdhold <= w_fill_out;
      
    // Blitter "zero" flag
    if (r_blt_fsm[0])
      r_bltzero <= 1'b1;
    else if ((r_seq_dly[4]) && (w_fill_out != 16'h0000))
      r_bltzero <= 1'b0;
  end
end

assign bltzero = r_bltzero;
assign db_out  = r_bltdhold;

//////////////////////////////////
// Blitter finite state machine //
//////////////////////////////////

`define BLT_IDLE     6'b000000
`define BLT_INIT     6'b000001
`define BLT_SRC_A    6'b000010
`define BLT_SRC_B    6'b000100
`define BLT_SRC_C    6'b001000
`define BLT_DST_D    6'b010000
`define BLT_LINE_1   6'b100010
`define BLT_LINE_2   6'b100100
`define BLT_LINE_3   6'b101000
`define BLT_LINE_4   6'b110000

wire       w_seq_end;       // End of DMA sequence
reg        r_d_avail;       // D data available
reg        r_blt_done;      // Blitter done
reg        r_ash_inc;       // Increment BLTCON0's ASH value
reg        r_ash_dec;       // Decrement BLTCON0's ASH value
reg        r_bsh_dec;       // Decrement BLTCON1's BSH value
reg        r_dma_blt_p3;    // DMA blitter active
reg        r_madd_blt_p3;   // Blitter adds modulo to pointer
reg        r_msub_blt_p3;   // Blitter subtracts modulo to pointer
reg        r_pinc_blt_p3;   // Pointers are incremented
reg        r_pdec_blt_p3;   // Pointers are decremented
reg  [8:0] r_rga_blt_p3;    // RGA value for DMA blitter
reg  [9:0] r_rga_bltp_p3;   // Internal RGA value for DMA blitter pointer
reg  [8:0] r_rga_bltm_p3;   // Internal RGA value for DMA blitter modulo
reg  [4:0] r_ch_blt_p3;     // DMA blitter channel number (24 - 27)
reg        r_last_cyc_p3;   // Last blitter cycle (flush D's cache line)
reg  [5:0] r_blt_fsm;       // Blitter state

always @(posedge rst or posedge clk) begin
  if (rst) begin
    r_d_avail     <= 1'b0;
    r_blt_done    <= 1'b0;
    r_ash_inc     <= 1'b0;
    r_ash_dec     <= 1'b0;
    r_bsh_dec     <= 1'b0;
    r_dma_blt_p3  <= 1'b0;
    r_pinc_blt_p3 <= 1'b0;
    r_pdec_blt_p3 <= 1'b0;
    r_madd_blt_p3 <= 1'b0;
    r_msub_blt_p3 <= 1'b0;
    r_rga_blt_p3  <= 9'h1FE;
    r_rga_bltp_p3 <= 10'h3FE;
    r_rga_bltm_p3 <= 9'h1FE;
    r_ch_blt_p3   <= 5'h1F;
    r_last_cyc_p3 <= 1'b0;
    r_blt_fsm     <= `BLT_IDLE;
  end else if (cdac_r & ~cck) begin
    if (dmafree) begin
      case (r_blt_fsm)
        // Idle state
        `BLT_IDLE :
        begin
          r_d_avail     <= 1'b0;
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_blt_done    <= 1'b0;
          r_dma_blt_p3  <= 1'b0;
          r_pinc_blt_p3 <= 1'b0;
          r_pdec_blt_p3 <= 1'b0;
          r_madd_blt_p3 <= 1'b0;
          r_msub_blt_p3 <= 1'b0;
          r_rga_blt_p3  <= 9'h1FE;
          r_rga_bltp_p3 <= 10'h3FE;
          r_rga_bltm_p3 <= 9'h1FE;
          r_ch_blt_p3   <= 5'h1F;
          if (r_stblit) r_blt_fsm <= `BLT_INIT;
        end
        
        // Initialize transfer
        `BLT_INIT :
        begin
          r_d_avail     <= 1'b0;
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_blt_done    <= 1'b0;
          r_dma_blt_p3  <= 1'b0;
          r_pinc_blt_p3 <= 1'b0;
          r_pdec_blt_p3 <= 1'b0;
          r_madd_blt_p3 <= 1'b0;
          r_msub_blt_p3 <= 1'b0;
          r_rga_blt_p3  <= 9'h1FE;
          r_rga_bltp_p3 <= 10'h3FE;
          r_rga_bltm_p3 <= 9'h1FE;
          r_ch_blt_p3   <= 5'h1F;
          if (w_LINE)
            r_blt_fsm   <= `BLT_LINE_1;
          else
          r_blt_fsm     <= `BLT_SRC_A;
        end
        
        // Fetch A source
        `BLT_SRC_A :
        begin
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_dma_blt_p3  <= r_USEx[3];
          r_pinc_blt_p3 <= r_USEx[3] & ~w_DESC;
          r_pdec_blt_p3 <= r_USEx[3] &  w_DESC;
          r_madd_blt_p3 <= r_USEx[3] & r_last_word & ~w_DESC;
          r_msub_blt_p3 <= r_USEx[3] & r_last_word &  w_DESC;
          r_rga_bltp_p3 <= 10'h250; // BLTAPTR
          r_rga_bltm_p3 <= 9'h064;  // BLTAMOD
          if (r_USEx[3]) begin
            r_rga_blt_p3 <= 9'h074; // BLTADAT
            r_ch_blt_p3  <= 5'h1A;
          end else begin
            r_rga_blt_p3 <= 9'h1FE; // Idling
            r_ch_blt_p3  <= 5'h1F;
          end
            
          if (r_USEx[2])
            r_blt_fsm <= `BLT_SRC_B;
          else if (r_USEx[1] | ~r_USEx[0])
            r_blt_fsm <= `BLT_SRC_C;
          else
            r_blt_fsm <= `BLT_DST_D;
        end
        
        // Fetch B source
        `BLT_SRC_B :
        begin
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_dma_blt_p3  <= r_USEx[2];
          r_pinc_blt_p3 <= r_USEx[2] & ~w_DESC;
          r_pdec_blt_p3 <= r_USEx[2] &  w_DESC;
          r_madd_blt_p3 <= r_USEx[2] & r_last_word & ~w_DESC;
          r_msub_blt_p3 <= r_USEx[2] & r_last_word &  w_DESC;
          r_rga_bltp_p3 <= 10'h24C; // BLTBPTR
          r_rga_bltm_p3 <= 9'h062;  // BLTBMOD
          if (r_USEx[2]) begin
            r_rga_blt_p3 <= 9'h072; // BLTBDAT
            r_ch_blt_p3  <= 5'h19;
          end else begin
            r_rga_blt_p3 <= 9'h1FE; // Idling
            r_ch_blt_p3  <= 5'h1F;
          end

          if (r_USEx[1] | ~r_USEx[0])
            r_blt_fsm <= `BLT_SRC_C;
          else
            r_blt_fsm <= `BLT_DST_D;
        end
        
        // Fetch C source
        `BLT_SRC_C :
        begin
          if (!r_USEx[0]) r_blt_done <= w_blk_end;
          
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_dma_blt_p3  <= r_USEx[1];
          r_pinc_blt_p3 <= r_USEx[1] & ~w_DESC;
          r_pdec_blt_p3 <= r_USEx[1] &  w_DESC;
          r_madd_blt_p3 <= r_USEx[1] & r_last_word & ~w_DESC;
          r_msub_blt_p3 <= r_USEx[1] & r_last_word &  w_DESC;
          r_rga_bltp_p3 <= 10'h248; // BLTCPTR
          r_rga_bltm_p3 <= 9'h060;  // BLTCMOD
          if (r_USEx[1]) begin
            r_rga_blt_p3 <= 9'h070; // BLTCDAT
            r_ch_blt_p3  <= 5'h18;
          end else begin
            r_rga_blt_p3 <= 9'h1FE; // Idling
            r_ch_blt_p3  <= 5'h1F;
          end
          
          if (r_USEx[0])
            r_blt_fsm <= `BLT_DST_D;
          else if (r_blt_done)
            r_blt_fsm <= `BLT_IDLE;
          else
            r_blt_fsm <= `BLT_SRC_A;
        end
        
        // Write D destination
        `BLT_DST_D :
        begin
          r_d_avail  <= 1'b1;
          
          if (r_USEx[0]) r_blt_done <= w_blk_end;
          
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_dma_blt_p3  <= r_USEx[0] & r_d_avail;
          r_pinc_blt_p3 <= r_USEx[0] & r_d_avail & ~w_DESC;
          r_pdec_blt_p3 <= r_USEx[0] & r_d_avail &  w_DESC;
          r_madd_blt_p3 <= r_USEx[0] & r_d_avail & r_first_word & ~w_DESC;
          r_msub_blt_p3 <= r_USEx[0] & r_d_avail & r_first_word &  w_DESC;
          r_rga_bltp_p3 <= 10'h254; // BLTDPTR
          r_rga_bltm_p3 <= 9'h066;  // BLTDMOD
          if (r_USEx[0] & r_d_avail) begin
            r_rga_blt_p3 <= 9'h000; // BLTDDAT
            r_ch_blt_p3  <= 5'h1B;
          end else begin
            r_rga_blt_p3 <= 9'h1FE; // Idling
            r_ch_blt_p3  <= 5'h1F;
          end

          if (r_blt_done)
            r_blt_fsm <= `BLT_IDLE;
          else
            r_blt_fsm <= `BLT_SRC_A;
        end
        
        // Update error accumulator
        `BLT_LINE_1 :
        begin
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_dma_blt_p3  <= 1'b0;
          r_pinc_blt_p3 <= 1'b0;
          r_pdec_blt_p3 <= 1'b0;
          r_madd_blt_p3 <= 1'b1;
          r_msub_blt_p3 <= 1'b0;
          r_rga_bltp_p3 <= 10'h250;  // BLTAPTR
          if (bltsign)
            r_rga_bltm_p3 <= 9'h062; // BLTBMOD
          else
            r_rga_bltm_p3 <= 9'h064; // BLTAMOD
          r_rga_blt_p3  <= 9'h1FE;
          r_ch_blt_p3   <= 5'h1F;
          r_blt_fsm     <= `BLT_LINE_2;
        end
        
        // Fetch data with channel C
        `BLT_LINE_2 :
        begin
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_dma_blt_p3  <= r_USEx[1];
          r_pinc_blt_p3 <= 1'b0;
          r_pdec_blt_p3 <= 1'b0;
          r_madd_blt_p3 <= 1'b0;
          r_msub_blt_p3 <= 1'b0;
          r_rga_bltp_p3 <= 10'h248; // BLTCPTR
          r_rga_bltm_p3 <= 9'h1FE;
          r_rga_blt_p3  <= 9'h070;  // BLTCDAT
          r_ch_blt_p3   <= 5'h1A;
          r_blt_fsm     <= `BLT_LINE_3;
        end
        
        // Free cycle
        `BLT_LINE_3 :
        begin
          r_ash_inc     <= 1'b0;
          r_ash_dec     <= 1'b0;
          r_bsh_dec     <= 1'b0;
          r_dma_blt_p3  <= 1'b0;
          r_pinc_blt_p3 <= 1'b0;
          r_pdec_blt_p3 <= 1'b0;
          r_madd_blt_p3 <= 1'b0;
          r_msub_blt_p3 <= 1'b0;
          r_rga_bltp_p3 <= 10'h3FE;
          r_rga_bltm_p3 <= 9'h1FE;
          r_rga_blt_p3  <= 9'h1FE;
          r_ch_blt_p3   <= 5'h1F;
          r_blt_fsm     <= `BLT_LINE_4;
        end
        
        // Store pixel with channel D or C
        `BLT_LINE_4 :
        begin
          r_d_avail  <= 1'b1;
          
          //          |     
          //      \   |   /    
          //       \ 3|1 /
          //        \ | /     
          //      7  \|/  6
          //  --------*--------
          //      5  /|\  4
          //        / | \     
          //       / 2|0 \
          //      /   |   \      
          //          |
          //
          // X displacement :
          // ----------------
          // if [0,1,4,6]
          //   if (ash == 15)
          //     if [4,6] || sign = 0
          //       ptr++
          //     endif
          //   endif
          //   ash++
          // else
          //   if (ash == 0)
          //     if [5,7] || sign = 0
          //       ptr--
          //     endif
          //   endif
          //   ash--
          // endif
          //
          // Y displacement :
          // ----------------
          // if [0,2,4,5]
          //   if [0,2] || sign = 0
          //     ptr += modulo
          //   endif
          // else
          //   if [1,3] || sign = 0
          //     ptr -= modulo
          //   endif
          // endif
          //
          case (w_OCTANT)
            3'd0 :
            begin
              r_ash_inc     <= 1'b1;
              r_ash_dec     <= 1'b0;
              r_pinc_blt_p3 <= r_ash_msk[15] & ~bltsign;
              r_pdec_blt_p3 <= 1'b0;
              r_madd_blt_p3 <= 1'b1;
              r_msub_blt_p3 <= 1'b0;
            end
            3'd1 :
            begin
              r_ash_inc     <= 1'b1;
              r_ash_dec     <= 1'b0;
              r_pinc_blt_p3 <= r_ash_msk[15] & ~bltsign;
              r_pdec_blt_p3 <= 1'b0;
              r_madd_blt_p3 <= 1'b0;
              r_msub_blt_p3 <= 1'b1;
            end
            3'd2 :
            begin
              r_ash_inc     <= 1'b0;
              r_ash_dec     <= 1'b1;
              r_pinc_blt_p3 <= 1'b0;
              r_pdec_blt_p3 <= r_ash_msk[0] & ~bltsign;
              r_madd_blt_p3 <= 1'b1;
              r_msub_blt_p3 <= 1'b0;
            end
            3'd3 :
            begin
              r_ash_inc     <= 1'b0;
              r_ash_dec     <= 1'b1;
              r_pinc_blt_p3 <= 1'b0;
              r_pdec_blt_p3 <= r_ash_msk[0] & ~bltsign;
              r_madd_blt_p3 <= 1'b0;
              r_msub_blt_p3 <= 1'b1;
            end
            3'd4 :
            begin
              r_ash_inc     <= 1'b1;
              r_ash_dec     <= 1'b0;
              r_pinc_blt_p3 <= r_ash_msk[15];
              r_pdec_blt_p3 <= 1'b0;
              r_madd_blt_p3 <= ~bltsign;
              r_msub_blt_p3 <= 1'b0;
            end
            3'd5 :
            begin
              r_ash_inc     <= 1'b0;
              r_ash_dec     <= 1'b1;
              r_pinc_blt_p3 <= 1'b0;
              r_pdec_blt_p3 <= r_ash_msk[0];
              r_madd_blt_p3 <= ~bltsign;
              r_msub_blt_p3 <= 1'b0;
            end
            3'd6 :
            begin
              r_ash_inc     <= 1'b1;
              r_ash_dec     <= 1'b0;
              r_pinc_blt_p3 <= r_ash_msk[15];
              r_pdec_blt_p3 <= 1'b0;
              r_madd_blt_p3 <= 1'b0;
              r_msub_blt_p3 <= ~bltsign;
            end
            3'd7 :
            begin
              r_ash_inc     <= 1'b0;
              r_ash_dec     <= 1'b1;
              r_pinc_blt_p3 <= 1'b0;
              r_pdec_blt_p3 <= r_ash_msk[0];
              r_madd_blt_p3 <= 1'b0;
              r_msub_blt_p3 <= ~bltsign;
            end
          endcase
          r_bsh_dec     <= 1'b1;
          
          //if (r_d_avail)
            r_rga_bltp_p3 <= 10'h248; // BLTCPTR
          //else
          //  r_rga_bltp_p3 <= 10'h254; // BLTDPTR
          r_rga_bltm_p3 <= 9'h060;  // BLTCMOD
          if (r_USEx[1]) begin
            r_rga_blt_p3 <= 9'h000; // BLTDDAT
            r_ch_blt_p3  <= 5'h1B;
          end else begin
            r_rga_blt_p3 <= 9'h1FE; // Idling
            r_ch_blt_p3  <= 5'h1F;
          end
          
        end
      endcase
      r_last_cyc_p3 <= r_blt_fsm[4] & r_blt_done;
    end else begin
      // Cycle is used by another DMA source
      r_ash_inc     <= 1'b0;
      r_ash_dec     <= 1'b0;
      r_bsh_dec     <= 1'b0;
      r_dma_blt_p3  <= 1'b0;
      r_pinc_blt_p3 <= 1'b0;
      r_pdec_blt_p3 <= 1'b0;
      r_madd_blt_p3 <= 1'b0;
      r_msub_blt_p3 <= 1'b0;
      r_rga_blt_p3  <= 9'h1FE;
      r_rga_bltp_p3 <= 10'h3FE;
      r_rga_bltm_p3 <= 9'h1FE;
      r_ch_blt_p3   <= 5'h1F;
      r_last_cyc_p3 <= 1'b0;
    end
  end
end

// Last transfer in the DMA sequence
assign w_seq_end = r_USEx[0] ? r_blt_fsm[4] : r_blt_fsm[3];

assign bltdma  = r_dma_blt_p3;
assign bltlast  = r_last_cyc_p3;
assign bltpinc  = r_pinc_blt_p3;
assign bltpdec  = r_pdec_blt_p3;
assign bltmadd  = r_madd_blt_p3;
assign bltmsub  = r_msub_blt_p3;
assign rga_out = r_rga_blt_p3[8:1];
assign rga_ptr = r_rga_bltp_p3[9:2];
assign rga_mod = r_rga_bltm_p3[8:1];
assign chan_out = r_ch_blt_p3;

endmodule

// Barrel shifter done with two 17-bit x 17-bit multipliers
// Descending mode changes the shift direction
// "bit_mask" is the number of steps as one hot value
module blt_shifter
(
  input         desc,
  input  [15:0] bit_mask,
  input  [15:0] data_old,
  input  [15:0] data_new,
  output [15:0] data_out
);

wire [16:0] w_mult_val;
wire [33:0] w_mult_old;
wire [33:0] w_mult_new;

assign w_mult_val[0]  = desc ? bit_mask[0]  : 1'b0;
assign w_mult_val[1]  = desc ? bit_mask[1]  : bit_mask[15];
assign w_mult_val[2]  = desc ? bit_mask[2]  : bit_mask[14];
assign w_mult_val[3]  = desc ? bit_mask[3]  : bit_mask[13];
assign w_mult_val[4]  = desc ? bit_mask[4]  : bit_mask[12];
assign w_mult_val[5]  = desc ? bit_mask[5]  : bit_mask[11];
assign w_mult_val[6]  = desc ? bit_mask[6]  : bit_mask[10];
assign w_mult_val[7]  = desc ? bit_mask[7]  : bit_mask[9];
assign w_mult_val[8]  = desc ? bit_mask[8]  : bit_mask[8];
assign w_mult_val[9]  = desc ? bit_mask[9]  : bit_mask[7];
assign w_mult_val[10] = desc ? bit_mask[10] : bit_mask[6];
assign w_mult_val[11] = desc ? bit_mask[11] : bit_mask[5];
assign w_mult_val[12] = desc ? bit_mask[12] : bit_mask[4];
assign w_mult_val[13] = desc ? bit_mask[13] : bit_mask[3];
assign w_mult_val[14] = desc ? bit_mask[14] : bit_mask[2];
assign w_mult_val[15] = desc ? bit_mask[15] : bit_mask[1];
assign w_mult_val[16] = desc ? 1'b0         : bit_mask[0];

assign w_mult_old = w_mult_val * { 1'b0, data_old };
assign w_mult_new = w_mult_val * { 1'b0, data_new };

assign data_out = desc
                ? (w_mult_old[31:16] | w_mult_new[15:0])
                : (w_mult_new[31:16] | w_mult_old[15:0]);

endmodule

// Blitter fill logic for 4 bits of data
// 4 blocks have to be chained together
// for a complete fill logic
module blt_fill
(
  input            ife,  // Inclusive fill enable
  input            efe,  // Exclusive fill enable
  input            fci,  // Fill carry in
  input      [3:0] din,  // Data in
  output reg       fco,  // Fill carry out
  output reg [3:0] dout  // Data out
);

reg [3:0] r_fill;

always @(ife or efe or fci or din) begin
  // Fill logic
  case (din)
    4'b0000 : r_fill = 4'b0000 ^ {4{fci}};
    4'b0001 : r_fill = 4'b1111 ^ {4{fci}};
    4'b0010 : r_fill = 4'b1110 ^ {4{fci}};
    4'b0011 : r_fill = 4'b0001 ^ {4{fci}};
    4'b0100 : r_fill = 4'b1100 ^ {4{fci}};
    4'b0101 : r_fill = 4'b0011 ^ {4{fci}};
    4'b0110 : r_fill = 4'b0010 ^ {4{fci}};
    4'b0111 : r_fill = 4'b1101 ^ {4{fci}};
    4'b1000 : r_fill = 4'b1000 ^ {4{fci}};
    4'b1001 : r_fill = 4'b0111 ^ {4{fci}};
    4'b1010 : r_fill = 4'b0110 ^ {4{fci}};
    4'b1011 : r_fill = 4'b1001 ^ {4{fci}};
    4'b1100 : r_fill = 4'b0100 ^ {4{fci}};
    4'b1101 : r_fill = 4'b1011 ^ {4{fci}};
    4'b1110 : r_fill = 4'b1010 ^ {4{fci}};
    4'b1111 : r_fill = 4'b0101 ^ {4{fci}};
  endcase
  
  // Fill muxer
  if (efe)
    // Exclusive fill
    dout <= r_fill;
  else if (ife)
    // Inclusive fill
    dout <= din | r_fill;
  else
    // No fill
    dout <= din;

  // Fill carry out
  fco <= r_fill[3];
end

endmodule

// Custom registers mapped to a multi-ported RAM
// Multi-port is achieved using time multiplexing @ 28 MHz
// DMA slots can run @ 3.5 MHz or 7 MHz
module cust_regs_mp
(
  // Main reset & clock
  input             rst,         // Global reset
  input             clk,         // Master clock (28/56/85 MHz)
  // 28 MHz simulated clock
  input             ena_28m,     // 28 MHz clock enable
  input       [2:0] cyc_28m,     // 28 MHz cycle number
  // Read port #1 : PTR or LOC
  input             ptr_rd_ena,  // DMA pointer read enable
  input       [9:2] ptr_rd_rga,  // DMA pointer's RGA address
  output reg [22:0] ptr_rd_val,  // 23-bit pointer value
  // Read port #2 : Modulo
  input             mod_rd_ena,  // Modulo read enable
  input       [8:1] mod_rd_rga,  // Modulo's RGA address
  output reg [22:1] mod_rd_val,  // 22-bit modulo read value
  // Read port #3 : SPRxPOS/SPRxCTL
  input             pos_rd_ena,  // Sprite position read enable
  input       [8:2] pos_rd_rga,  // Sprite position's RGA address
  output      [8:0] spr_vstart,  // Sprite vertical start value
  output      [8:0] spr_vstop,   // Sprite vertical stop value
  // Read port #4 : Action replay mk3
  input             ar3_rd_ena,  // Register read enable
  input       [8:1] ar3_rd_rga,  // Register's RGA address
  output reg [15:0] ar3_rd_val,  // 16-bit register value
  // Write port #1 : PTR
  input             ptr_wr_ena,  // DMA pointer write enable
  input       [8:2] ptr_wr_rga,  // DMA pointer's RGA address
  input      [22:0] ptr_wr_val,  // 23-bit pointer value
  // Write port #2 : CPU / copper access
  input             cpu_wr_ena,  // Register write enable
  input       [8:1] cpu_wr_rga,  // Register's RGA address
  input      [15:0] cpu_wr_val   // 16-bit register value
);
// Clock input frequency : 28/57/85 MHz
parameter MAIN_FREQ = 85;

/////////////////////////
// Multiplexer control //
/////////////////////////

// [0] : PTR write
// [1] : CPU/Copper write
reg   [1:0] r_amux_a;

always@(posedge rst or posedge clk) begin
  if (rst)
    r_amux_a <= 2'b00;
  else if (ena_28m) begin
    casez (cyc_28m[1:0])
      2'b00   : // CPU/Copper write (shadow) -> cycles #1 or #5
        r_amux_a <= 2'b10;
      2'b01   : // CPU/Copper write (normal) -> cycles #2 or #6
        if ((cpu_wr_rga[8:5] == 4'b0101) || // AUD0xxx, AUD1xxx
            (cpu_wr_rga[8:5] == 4'b0110))   // AUD2xxx, AUD3xxx
          r_amux_a <= 2'b00; // Disable write for Audio
        else
          r_amux_a <= 2'b10; // Enable write for others registers
      2'b10   : // PTR write -> cycles #3 or #7
        r_amux_a <= 2'b01;
      default : // No access -> cycles #4 or #0
        r_amux_a <= 2'b00;
    endcase
  end
end

// [0] : PTR/LOC read
// [1] : Modulo read
// [2] : SPRxCTL/SPRxPOS read
// [3] : Action replay read
reg   [3:0] r_amux_b;

always@(posedge rst or posedge clk) begin
  if (rst)
    r_amux_b <= 4'b0000;
  else if (ena_28m) begin
    case (cyc_28m)                   // CDAC# C7M CCK
      3'b000  : r_amux_b <= 4'b0001; //   r    -   1  No access
      3'b001  : r_amux_b <= 4'b0010; //   -    r   1  PTR/LOC read
      3'b010  : r_amux_b <= 4'b0100; //   f    -   1  Modulo read
      3'b011  : r_amux_b <= 4'b0000; //   -    f   0  SPRxCTL/SPRxPOS read
      3'b100  : r_amux_b <= 4'b0001; //   r    -   0  No access
      3'b101  : r_amux_b <= 4'b0010; //   -    r   0  PTR/LOC read
      3'b110  : r_amux_b <= 4'b1000; //   f    -   0  Modulo read
      3'b111  : r_amux_b <= 4'b0000; //   -    f   1  Action replay read
      default : r_amux_b <= 4'b0000; //   -    -   -  No access
    endcase
  end
end

////////////////////////////
// Multiplexer for port A //
////////////////////////////

wire        w_wren_a;
wire  [3:0] w_bena_a;
wire  [7:0] w_addr_a;
wire [31:0] w_wdat_a;

// 1-LUT level, 1 LUT total
assign w_wren_a = (ptr_wr_ena & r_amux_a[0])                           // PTR write
                | (cpu_wr_ena & r_amux_a[1]);                          // CPU/Copper write

// 1-LUT level, 2 LUTs total
assign w_bena_a[3] =  r_amux_a[0]                                      // PTR write
                   | (r_amux_a[1] & ~cpu_wr_rga[1]);                   // CPU/Copper write
assign w_bena_a[2] =  r_amux_a[0]                                      // PTR write
                   | (r_amux_a[1] & ~cpu_wr_rga[1]);                   // CPU/Copper write
assign w_bena_a[1] =  r_amux_a[0]                                      // PTR write
                   | (r_amux_a[1] & cpu_wr_rga[1]);                    // CPU/Copper write
assign w_bena_a[0] =  r_amux_a[0]                                      // PTR write
                   | (r_amux_a[1] & cpu_wr_rga[1]);                    // CPU/Copper write
                   
// 1-LUT level, 8 LUTs total
assign w_addr_a = ({1'b1, ptr_wr_rga[8:2]} & {8{r_amux_a[0]}})         // PTR write
                | ({~cyc_28m[0], cpu_wr_rga[8:2]} & {8{r_amux_a[1]}}); // CPU/Copper write

// 1-LUT level, 32 LUTs total
assign w_wdat_a = ({9'b0, ptr_wr_val} & {32{r_amux_a[0]}})             // PTR write
                | ({cpu_wr_val, cpu_wr_val} & {32{r_amux_a[1]}});      // CPU/Copper write
 
////////////////////////////
// Multiplexer for port B //
////////////////////////////

reg         r_rden_b;
wire        w_rden_b;
wire  [7:0] w_addr_b;
wire [31:0] w_rdat_b;

// 2-LUT level, 3 LUTs total
assign w_rden_b = ((ptr_rd_ena & r_amux_b[0])                     // PTR/LOC read
                |  (mod_rd_ena & r_amux_b[1])                     // Modulo read
                |  (pos_rd_ena & r_amux_b[2])                     // SPRxPOS/SPRxCTL read
                |  (ar3_rd_ena & r_amux_b[3])) & ena_28m;         // Action replay read

// 2-LUT level, 24 LUTs total
assign w_addr_b = (ptr_rd_rga[9:2]         & {8{r_amux_b[0]}})    // PTR/LOC read
                | ({1'b1, mod_rd_rga[8:2]} & {8{r_amux_b[1]}})    // Modulo read
                | ({1'b1, pos_rd_rga[8:2]} & {8{r_amux_b[2]}})    // SPRxPOS/SPRxCTL read
                | ({1'b0, ar3_rd_rga[8:2]} & {8{r_amux_b[3]}});   // Action replay read

// Data demultiplexer, registered
always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_rden_b   <= 1'b0;
    ar3_rd_val <= 16'd0;
    ptr_rd_val <= 23'd0;
    mod_rd_val <= 22'd0;
  end else if (ena_28m) begin
    r_rden_b <= w_rden_b;
    casez (cyc_28m)
      3'b000 : // Action replay read
        if (r_rden_b) begin
          if (ar3_rd_rga[1])
            ar3_rd_val <= w_rdat_b[15:0];
          else
            ar3_rd_val <= w_rdat_b[31:16];
        end else
          ar3_rd_val <= 16'h0000;
      3'b?10 : // PTR/LOC read
        if (r_rden_b)
          ptr_rd_val <= w_rdat_b[22:0];
        else
          ptr_rd_val <= 23'd0;
      3'b?11 : // Modulo read
        if (r_rden_b) begin
          if (mod_rd_rga[1])
            mod_rd_val <= {{7{w_rdat_b[15]}}, w_rdat_b[15:1]};
          else
            mod_rd_val <= {{7{w_rdat_b[31]}}, w_rdat_b[31:17]};
        end else
          mod_rd_val <= 22'd0;
      default : // No access
        ;
    endcase
  end
end

// Sprite vertical start and stop
assign spr_vstart = {w_rdat_b[2], w_rdat_b[31:24]};
assign spr_vstop  = {w_rdat_b[1], w_rdat_b[15:8]};

///////////////////////////////////////////////
// 2 x 128 x 32-bit dual-ported RAM instance //
///////////////////////////////////////////////

cust_regs_dp U_cust_regs_dp
(
  // Port A
  .clock_a(clk),
  .clken_a(ena_28m),
  .wren_a(w_wren_a),
  .byteena_a(w_bena_a),
  .address_a(w_addr_a),
  .data_a(w_wdat_a),
  // Port B
  .clock_b(clk),
  .rden_b(w_rden_b),
  .address_b(w_addr_b),
  .q_b(w_rdat_b)
);
defparam
  U_cust_regs_dp.MAIN_FREQ = MAIN_FREQ;

endmodule

// Custom registers mapped to a dual-ported RAM
// Size : 2 x 128 x 32-bit words
module cust_regs_dp
(
  // Port A : write access
  input         clock_a,
  input         clken_a,
  input         wren_a,
  input   [3:0] byteena_a,
  input   [7:0] address_a,
  input  [31:0] data_a,
  // Port B : read access
  input         clock_b,
  input         rden_b,
  input   [7:0] address_b,
  output [31:0] q_b
);
// Clock input frequency : 28/57/85 MHz
parameter MAIN_FREQ = 85;

`ifdef SIMULATION

// Infered block RAM
reg  [31:0] r_mem_blk [0:255];

initial begin
  $readmemh("cust_regs_32.mem", r_mem_blk);
end

// Write port
always@(posedge clock_a) begin
  if (clken_a & wren_a) begin
    if (byteena_a[0])
      r_mem_blk[address_a][7:0]   <= data_a[7:0];
    if (byteena_a[1])
      r_mem_blk[address_a][15:8]  <= data_a[15:8];
    if (byteena_a[2])
      r_mem_blk[address_a][23:16] <= data_a[23:16];
    if (byteena_a[3])
      r_mem_blk[address_a][31:24] <= data_a[31:24];
  end
end

reg  [31:0] r_q_p0;
reg  [31:0] r_q_p1;

// Read port
always@(posedge clock_b) begin
  if (rden_b)
    r_q_p0 <= r_mem_blk[address_b];
  r_q_p1 <= r_q_p0;
end

assign q_b = (MAIN_FREQ == 28) ? r_q_p0 : r_q_p1;

`else

// Declared Altera block RAM
altsyncram  altsyncram_component
(
  // Port A : write side
  .aclr0          (1'b0),
  .clocken0       (clken_a),
  .clock0         (clock_a),    
  .rden_a         (1'b0),
  .wren_a         (wren_a),
  .byteena_a      (byteena_a),
  .addressstall_a (1'b0),
  .address_a      (address_a),
  .data_a         (data_a),
  .q_a            (),
  // Port B : read side
  .aclr1          (1'b0),
  .clocken1       (1'b1),
  .clock1         (clock_b),
  .rden_b         (rden_b),
  .wren_b         (1'b0),
  .byteena_b      (1'b1),
  .addressstall_b (1'b0),
  .address_b      (address_b),
  .data_b         (32'b0),
  .q_b            (q_b),
  // Misc.
  .clocken2       (1'b1),
  .clocken3       (1'b1),
  .eccstatus      ()
);
defparam
  altsyncram_component.address_reg_b = "CLOCK1",
  altsyncram_component.clock_enable_input_a = "NORMAL",
  altsyncram_component.clock_enable_input_b = "NORMAL",
  altsyncram_component.clock_enable_output_a = "NORMAL",
  altsyncram_component.clock_enable_output_b = "NORMAL",
  altsyncram_component.indata_reg_b = "CLOCK1",
  altsyncram_component.init_file = "cust_regs_32.mif",
  altsyncram_component.intended_device_family = "Cyclone III",
  altsyncram_component.lpm_type = "altsyncram",
  altsyncram_component.numwords_a = 256,
  altsyncram_component.numwords_b = 256,
  altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
  altsyncram_component.outdata_aclr_a = "NONE",
  altsyncram_component.outdata_aclr_b = "NONE",
  altsyncram_component.outdata_reg_a = (MAIN_FREQ == 28)? "NONE" : "CLOCK0",
  altsyncram_component.outdata_reg_b = (MAIN_FREQ == 28)? "NONE" : "CLOCK1",
  altsyncram_component.power_up_uninitialized = "FALSE",
  altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_WITH_NBE_READ",
  altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_WITH_NBE_READ",
  altsyncram_component.widthad_a = 8,
  altsyncram_component.widthad_b = 8,
  altsyncram_component.width_a = 32,
  altsyncram_component.width_b = 32,
  altsyncram_component.width_byteena_a = 4,
  altsyncram_component.width_byteena_b = 1,
  altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK1";

`endif

endmodule
