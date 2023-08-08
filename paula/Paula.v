`timescale 1 ns / 1 ps

// Copyright 2022, Renee Cousins
//
// This file is part of the Amiga Replacement Project
// Any features below which were not part of the original Amiga chipset have
// been removed and replaced with what is understood as the correct implementation
// within the real chips.
//
// Changes:
// --------
//  - Removed 248-tap moving average filter because an RC filter is cheaper than FPGA space
//  - Audio DAC is the correct PWM + PDM implementation on a real Paula; no multipliers needed
//  - Code is proven on MiniMig, but needs verification on real hardware
//
// Copyright 2011, 2012 Frederic Requin
//
// This file is part of the MCC216 project
//
// Paula re-implementation is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Paula re-implementation is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// The Paula core:
// ---------------
//  - It can interface with a real Amiga OCS/ECS HW
//  - It uses the 7 MHz clock (C7M) to generate a 28/56/85 MHz master clock
//  - Data bus (DB) is latched one cycle after address bus (RGA)
//  - Full audio state machine with attached period and volume
//  - Audio state machines HW are time-multiplexed to save resource
//  - Include a 248-tap moving average filter to mimic a low pass at 7 KHz
//  - Audio DAC is a 3rd order delta-sigma with 90dB SNR
//  - The disk digital phase locked loop is based on patent #4,780,844
//  - 3-word disk FIFO implementation
//

module Paula
(
  input             rst,       // Global reset
  input             clk,       // Master clock (28/56/85 MHz)
  input             clk_28m,   // Clock enable @ 28 MHz
  input             cck,       // Re-generated CCK
  input             cdac_r,    // CDAC_n rising edge
  input             cdac_f,    // CDAC_n falling edge
  input             cfg_ecs,   // 0=OCS mode, 1=ECS mode
  input             cfg_a1k,   // 0=Normal mode, 1=A1000 mode
  input       [8:1] rga_in,    // RGA bus
  input      [15:0] db_in,     // Data bus input
  output reg [15:0] db_out,    // Data bus output
  output     [15:0] db_out_er, // Data bus output (early read)
  output reg        db_oe,     // Data bus output enable
  input             int2_n,    // Level 2 interrupt
  input             int3_n,    // Level 3 interrupt
  input             int6_n,    // Level 6 interrupt
  output reg  [2:0] ipl_n,     // Interrupt priority level to 68000
  input             rxd,       // Serial receive
  output            txd,       // Serial transmit
  output            dmal,      // DMA request to Agnus
  input             dkrd_n,    // Disk read
  output            dkwr_n,    // Disk write
  output            dkwe,      // Disk write enable
  output            aud_l,     // Audio left
  output            aud_r      // Audio right
);

///////////////////////////////
// Register address decoding //
///////////////////////////////

reg [8:1] r_rga_p1;
reg       r_regs_datr_p1; // DSKDATR
reg       r_regs_adkr_p1; // ADKCONR
reg       r_regs_bytr_p1; // DSKBYTR
reg       r_regs_ienr_p1; // INTENAR
reg       r_regs_irqr_p1; // INTREQR
reg       r_regs_len_p1;  // DSKLEN
reg       r_regs_datw_p1; // DSKDAT
reg       r_regs_str_p1;  // STREQU, STRVBL, STRHOR, STRLONG
reg       r_regs_sync_p1; // DSKSYNC
reg       r_regs_dmaw_p1; // DMACON
reg       r_regs_ienw_p1; // INTENA
reg       r_regs_irqw_p1; // INTREQ
reg       r_regs_adkw_p1; // ADKCON
reg       r_regs_aud_p1;  // AUDxLEN, AUDxPER, AUDxVOL, AUDxDAT

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if ((cdac_r) && (cck)) begin
    // DSKDATR : $008
    if (rga_in[8:1] == 8'b0_0000_100)
      r_regs_datr_p1 <= 1'b1;
    else
      r_regs_datr_p1 <= 1'b0;
    // ADKCONR : $010
    if (rga_in[8:1] == 8'b0_0001_000)
      r_regs_adkr_p1 <= 1'b1;
    else
      r_regs_adkr_p1 <= 1'b0;
    // DSKBYTR : $01A
    if (rga_in[8:1] == 8'b0_0001_101)
      r_regs_bytr_p1 <= 1'b1;
    else
      r_regs_bytr_p1 <= 1'b0;
    // INTENAR : $01C
    if (rga_in[8:1] == 8'b0_0001_110)
      r_regs_ienr_p1 <= 1'b1;
    else
      r_regs_ienr_p1 <= 1'b0;
    // INTREQR : $01E
    if (rga_in[8:1] == 8'b0_0001_111)
      r_regs_irqr_p1 <= 1'b1;
    else
      r_regs_irqr_p1 <= 1'b0;
    // DSKLEN : $024
    if (rga_in[8:1] == 8'b0_0010_010)
      r_regs_len_p1 <= 1'b1;
    else
      r_regs_len_p1 <= 1'b0;
    // DSKDAT : $026
    if (rga_in[8:1] == 8'b0_0010_011)
      r_regs_datw_p1 <= 1'b1;
    else
      r_regs_datw_p1 <= 1'b0;
    // Strobes : $038 - $03E
    if (rga_in[8:3] == 6'b0_0011_1)
      r_regs_str_p1  <= 1'b1;
    else
      r_regs_str_p1  <= 1'b0;
    // DSKSYNC : $07E
    if (rga_in[8:1] == 8'b0_0111_111)
      r_regs_sync_p1 <= 1'b1;
    else
      r_regs_sync_p1 <= 1'b0;
    // DMACON : $096
    if (rga_in[8:1] == 8'b0_1001_011)
      r_regs_dmaw_p1 <= 1'b1;
    else
      r_regs_dmaw_p1 <= 1'b0;
    // INTENA : $09A
    if (rga_in[8:1] == 8'b0_1001_101)
      r_regs_ienw_p1 <= 1'b1;
    else
      r_regs_ienw_p1 <= 1'b0;
    // INTREQ : $09C
    if (rga_in[8:1] == 8'b0_1001_110)
      r_regs_irqw_p1 <= 1'b1;
    else
      r_regs_irqw_p1 <= 1'b0;
    // ADKCON : $09E
    if (rga_in[8:1] == 8'b0_1001_111)
      r_regs_adkw_p1 <= 1'b1;
    else
      r_regs_adkw_p1 <= 1'b0;
    // AUDxLEN, AUDxPER, AUDxVOL, AUDxDAT : $0Ax - $0Dx
    if ((rga_in[8:7] == 2'b01) && (rga_in[6] ^ rga_in[5]))
      r_regs_aud_p1 <= 1'b1;
    else
      r_regs_aud_p1 <= 1'b0;
    // Latch RGA for next cycle
    r_rga_p1 <= rga_in;
  end
end

//////////////////////////
// DMA control register //
//////////////////////////

reg       r_DMAEN;
reg       r_DSKEN;
reg [3:0] r_AUDEN;

wire      w_AUDxON;
wire      w_DSKON;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_DMAEN <= 1'b0;
    r_DSKEN <= 1'b0;
    r_AUDEN <= 4'b0000;
  end
  // Rising edge of CDAC_n with CCK = 1
  else if ((cdac_r) && (cck)) begin
    if (r_regs_dmaw_p1) begin
      if (db_in[15]) begin
        // Set
        r_DMAEN <= r_DMAEN | db_in[9];
        r_DSKEN <= r_DSKEN | db_in[4];
        r_AUDEN <= r_AUDEN | db_in[3:0];
      end
      else begin
        // Clear
        r_DMAEN <= r_DMAEN & ~db_in[9];
        r_DSKEN <= r_DSKEN & ~db_in[4];
        r_AUDEN <= r_AUDEN & ~db_in[3:0];
      end
    end
  end
end

assign w_AUDxON = (r_AUDEN[0] & r_DMAEN & r_ch_sel[0])
                | (r_AUDEN[1] & r_DMAEN & r_ch_sel[1])
                | (r_AUDEN[2] & r_DMAEN & r_ch_sel[2])
                | (r_AUDEN[3] & r_DMAEN & r_ch_sel[3]);

assign w_DSKON  = r_DSKEN & r_DMAEN & r_DSKENA[1];

///////////////////////////////
// Interrupt enable register //
///////////////////////////////

reg  [14:0] r_INTENA;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_INTENA <= 15'b0;
  end
  // Rising edge of CDAC_n with CCK = 1
  else if ((cdac_r) && (cck)) begin
    if (r_regs_ienw_p1) begin
      if (db_in[15]) begin
        // Set
        r_INTENA <= r_INTENA | db_in[14:0];
      end
      else begin
        // Clear
        r_INTENA <= r_INTENA & ~db_in[14:0];
      end
    end
  end
end

////////////////////////////////
// Interrupt request register //
////////////////////////////////

reg  [13:0] r_INTREQ;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_INTREQ <= 14'b0;
  end
  // Rising edge of CDAC_n with CCK = 1
  else if ((cdac_r) && (cck)) begin
    if (r_regs_ienw_p1) begin
      if (db_in[15]) begin
        // Set (software requests)
        r_INTREQ <= r_INTREQ | w_int_req | db_in[13:0];
      end
      else begin
        // Clear
        r_INTREQ <= r_INTREQ | w_int_req & ~db_in[13:0];
      end
    end
    else
      // Keep track of requests
      r_INTREQ <= r_INTREQ | w_int_req;
  end
end

/////////////////////////////////
// Vertical blanking interrupt //
/////////////////////////////////

reg         r_vsync;
reg         r_int_VERTB;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_vsync     <= 1'b0;
    r_int_VERTB <= 1'b0;
  end
  // Rising edge of CDAC_n with CCK = 1
  else if ((cdac_r) && (cck)) begin
    r_int_VERTB <= 1'b0;
    if (r_regs_str_p1) begin
      // Discard STRLONG strobes
      if (r_rga_p1[2:1] != 2'b11) begin
        // STREQU strobes set VS
        if (r_rga_p1[2:1] == 2'b00) begin
          r_vsync     <= 1'b1;
          r_int_VERTB <= ~r_vsync;
        end
        // STRVBL and STRHOR strobes clear VS
        else begin
          r_vsync <= 1'b0;
        end
      end
    end
  end
end

//////////////////////////
// Interrupt controller //
//////////////////////////

wire [13:0] w_int_req;

// Requests from hardware
assign w_int_req[0]  = 1'b0; //r_int_TBE;
assign w_int_req[1]  = r_int_DSKBLK;
assign w_int_req[2]  = 1'b0; // SOFT
assign w_int_req[3]  = r_int_PORTS[1];
assign w_int_req[4]  = 1'b0; // COPPER
assign w_int_req[5]  = r_int_VERTB;
assign w_int_req[6]  = r_int_BLIT[1];
assign w_int_req[7]  = r_AUDxIR[0];
assign w_int_req[8]  = r_AUDxIR[1];
assign w_int_req[9]  = r_AUDxIR[2];
assign w_int_req[10] = r_AUDxIR[3];
assign w_int_req[11] = 1'b0; //r_int_RBF;
assign w_int_req[12] = w_sync_det;
assign w_int_req[13] = r_int_EXTER[1];

reg   [1:0] r_int_PORTS;
reg   [1:0] r_int_BLIT;
reg   [1:0] r_int_EXTER;

// Latch interrupts #2, #3 and #6
always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_int_PORTS <= 2'b00; // #2
    r_int_BLIT  <= 2'b00; // #3
    r_int_EXTER <= 2'b00; // #6
  end
  // Rising edge of CDAC_n
  else if (cdac_r) begin
    r_int_PORTS <= { r_int_PORTS[0], ~int2_n };
    r_int_BLIT  <= { r_int_BLIT[0],  ~int3_n };
    r_int_EXTER <= { r_int_EXTER[0], ~int6_n };
  end
end

// Generate IPL_n[2:0] signal
always@(posedge rst or posedge clk) begin
  if (rst) begin
    ipl_n <= ~(3'b000);
  end
  // Rising edge of CDAC_n
  else if (cdac_r) begin
    if (r_INTENA[14]) begin
      // Master interrupt enable
      casez (r_INTENA[13:0] & r_INTREQ)
        14'b1????????????? : ipl_n <= ~(3'bZZ0); // EXTER  : level 6
        14'b01???????????? : ipl_n <= ~(3'bZ0Z); // DSKSYN : level 5
        14'b001??????????? : ipl_n <= ~(3'bZ0Z); // RBF    : level 5
        14'b0001?????????? : ipl_n <= ~(3'bZ00); // AUD3   : level 4
        14'b00001????????? : ipl_n <= ~(3'bZ00); // AUD2   : level 4
        14'b000001???????? : ipl_n <= ~(3'bZ00); // AUD1   : level 4
        14'b0000001??????? : ipl_n <= ~(3'bZ00); // AUD0   : level 4
        14'b00000001?????? : ipl_n <= ~(3'b0ZZ); // BLIT   : level 3
        14'b000000001????? : ipl_n <= ~(3'b0ZZ); // VERTB  : level 3
        14'b0000000001???? : ipl_n <= ~(3'b0ZZ); // COPPER : level 3
        14'b00000000001??? : ipl_n <= ~(3'b0Z0); // PORTS  : level 2
        14'b000000000001?? : ipl_n <= ~(3'b00Z); // SOFT   : level 1
        14'b0000000000001? : ipl_n <= ~(3'b00Z); // DSKBLK : level 1
        14'b00000000000001 : ipl_n <= ~(3'b00Z); // TBE    : level 1
        default            : ipl_n <= ~(3'b000); // No interrupt
      endcase
    end
    else
      // Master interrupt disable
      ipl_n <= ~(3'b000);
  end
end

/////////////////////////////////
// DMA request to Agnus (DMAL) //
/////////////////////////////////

reg [14:0] r_dmal;
reg  [3:0] r_dmal_ctr;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_dmal     <= 15'b000000_000000000;
    r_dmal_ctr <= 4'd15;
  end
  else begin
    // Rising edge of CDAC_n with CCK = 1
    if (cck & cdac_r) begin
      // Horizontal strobe received
      if ((r_regs_str_p1) && (r_rga_p1[2:1] != 2'b11)) begin
        // Clear DMAL counter
        r_dmal_ctr <= 4'd0;
        // Disk DMA slot #1
        r_dmal[13] <= r_DSKDIR;
        r_dmal[12] <= r_dskdatr[0][16];
        // Disk DMA slot #2
        r_dmal[11] <= r_DSKDIR;
        r_dmal[10] <= r_dskdatr[1][16];
        // Disk DMA slot #3
        r_dmal[9]  <= r_DSKDIR;
        r_dmal[8]  <= r_dskdatr[2][16];
        // Audio channel #0
        r_dmal[7]  <= r_AUDxDR[0] & (r_dmasen[0] | r_lenfin[0]);
        r_dmal[6]  <= r_AUDxDR[0];
        // Audio channel #1
        r_dmal[5]  <= r_AUDxDR[1] & (r_dmasen[1] | r_lenfin[1]);
        r_dmal[4]  <= r_AUDxDR[1];
        // Audio channel #2
        r_dmal[3]  <= r_AUDxDR[2] & (r_dmasen[2] | r_lenfin[2]);
        r_dmal[2]  <= r_AUDxDR[2];
        // Audio channel #3
        r_dmal[1]  <= r_AUDxDR[3] & (r_dmasen[3] | r_lenfin[3]);
        r_dmal[0]  <= r_AUDxDR[3];
      end
      else begin
        // Increment DMAL counter
        if (r_dmal_ctr != 4'd15)
          r_dmal_ctr <= r_dmal_ctr + 4'd1;
        // Start shifting when DMAL counter > 0
        if (r_dmal_ctr != 4'd0)
          r_dmal <= { r_dmal[13:0], 1'b0 };
      end
    end
  end
end
assign dmal = r_dmal[14];

/////////////////////////////////
// Audio/disk control register //
/////////////////////////////////

reg   [1:0] r_PRECOMP;  // 
reg         r_MFMPREC;  // 
reg         r_WORDSYNC; // MFM word synchro enable
reg         r_HDDISK;   // High density disk support
reg         r_MSBSYNC;  // 
reg         r_FAST;     // GCR(0) / MFM(1) rate
reg   [3:0] r_ATPER;    // Attached period
reg   [3:0] r_ATVOL;    // Attached volume
wire [15:0] w_adkconr;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_PRECOMP  <= 2'b00;
    r_MFMPREC  <= 1'b0;
    r_HDDISK   <= 1'b0;
    r_WORDSYNC <= 1'b0;
    r_MSBSYNC  <= 1'b0;
    r_FAST     <= 1'b0;
    r_ATPER    <= 4'b0000;
    r_ATVOL    <= 4'b0000;
  end
  // Rising edge of CDAC_n with CCK = 1
  else if ((cdac_r) && (cck)) begin
    if (r_regs_adkw_p1) begin
      if (db_in[15]) begin
        // Set
        r_PRECOMP  <= r_PRECOMP  | db_in[14:13];
        r_MFMPREC  <= r_MFMPREC  | db_in[12];
        r_HDDISK   <= r_HDDISK   | db_in[11];
        r_WORDSYNC <= r_WORDSYNC | db_in[10];
        r_MSBSYNC  <= r_MSBSYNC  | db_in[9];
        r_FAST     <= r_FAST     | db_in[8];
        r_ATPER    <= r_ATPER    | db_in[7:4];
        r_ATVOL    <= r_ATVOL    | db_in[3:0];
      end
      else begin
        // Clear
        r_PRECOMP  <= r_PRECOMP  & ~db_in[14:13];
        r_MFMPREC  <= r_MFMPREC  & ~db_in[12];
        r_HDDISK   <= r_HDDISK   & ~db_in[11];
        r_WORDSYNC <= r_WORDSYNC & ~db_in[10];
        r_MSBSYNC  <= r_MSBSYNC  & ~db_in[9];
        r_FAST     <= r_FAST     & ~db_in[8];
        r_ATPER    <= r_ATPER    & ~db_in[7:4];
        r_ATVOL    <= r_ATVOL    & ~db_in[3:0];
      end
    end
  end
end
// Disk precomp
assign w_adkconr[15:12] = { 1'b0, r_PRECOMP, r_MFMPREC };
// Disk synchro and bitrate
assign w_adkconr[11:8]  = { r_HDDISK, r_WORDSYNC, r_MSBSYNC, r_FAST };
// Audio control
assign w_adkconr[7:0]   = { r_ATPER, r_ATVOL };

////////////////////
// Disk registers //
////////////////////

reg  [1:0] r_DSKENA;
reg        r_DSKDIR;
reg [13:0] r_DSKLEN;
reg [15:0] r_DSKSYNC;
reg        r_sync_arm;
reg        r_int_DSKBLK;
wire       w_dsk_dma;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_DSKENA     <= 2'b00;
    `ifdef SIMULATION
    r_DSKDIR     <= 1'b0;
    `else
    r_DSKDIR     <= 1'b0;
    `endif
    r_DSKLEN     <= 14'd0;
    r_DSKSYNC    <= 16'h4489;
    r_sync_arm   <= 1'b0;
    r_int_DSKBLK <= 1'b0;
  end
  // Rising edge of CDAC_n with CCK = 1
  else if (cck & cdac_r) begin
    // Default : no disk block interrupt
    r_int_DSKBLK <= 1'b0;
    // DSKLEN register
    if (r_regs_len_p1) begin
      // Double write to activate DMA
      r_DSKENA[0] <= db_in[15];
      r_DSKENA[1] <= r_DSKENA[0] & db_in[15];
      // DMA direction (disk read : 0, disk write : 1)
      r_DSKDIR <= db_in[14];
      // DMA length (in words)
      r_DSKLEN <= db_in[13:0];
    end
    // New data available from the DPLL
    else if ((r_buf_rdy != w_buf_rdy) && (w_dsk_dma)) begin
      // Decrement DSKLEN
      r_DSKLEN <= r_DSKLEN - 14'd1;
      // End of disk block reached :
      if (r_DSKLEN[13:1] == 13'd0) begin
        // Deactivate DMA
        r_DSKENA <= 2'b00;
        // Set interrupt
        r_int_DSKBLK <= 1'b1;
      end
    end
    // DSKSYNC register
    if (r_regs_sync_p1) begin
      r_DSKSYNC <= db_in[15:0];
    end
    // MFM synchronization
    if (r_regs_len_p1)
      // Set the armed flag
      r_sync_arm <= r_WORDSYNC & r_DSKENA[0] & db_in[15];
    else if (w_sync_det)
      // Clear the armed flag
      r_sync_arm <= 1'b0;
  end
end
// Disk DMA enable
assign w_dsk_dma = w_DSKON & ~r_sync_arm;

/////////////////////////////
// MFM/GCR data separation //
/////////////////////////////

wire [15:0] w_dskdatr;   // MFM/GCR read data
wire        w_buf_rdy;   // MFM read buffer is ready
wire        w_sync_det;  // MFM synchro detected
wire        w_dsk_start; // Start disk DMA

// Disk DMA start signal for DPLL
assign w_dsk_start = r_regs_len_p1 & r_DSKENA[0] & db_in[15];

// Digital phase locked loop
mfm_dpll U_mfm_dpll
(
  .rst(rst),
  .clk(clk),
  .clk_ena(cdac_r | (cdac_f & r_FAST)),
  .dsk_rd_n(dkrd_n),
  .buf_rd(w_dskdatr),
  .buf_rdy(w_buf_rdy),
  .start(w_dsk_start),
  .wr_mode(r_DSKDIR),
  .sync_arm(r_sync_arm),
  .sync_ena(r_WORDSYNC),
  .sync_word(r_DSKSYNC),
  .sync_det(w_sync_det)
);

///////////////////////////
// 3-word data read FIFO //
///////////////////////////

reg [16:0] r_dskdatr [0:2];
reg  [2:0] r_seldatr;
reg        r_buf_rdy;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    `ifdef SIMULATION
    r_dskdatr[0] <= 17'h14489;
    r_dskdatr[1] <= 17'h1AAAA;
    r_dskdatr[2] <= 17'h15555;
    `else
    r_dskdatr[0] <= 17'h00000;
    r_dskdatr[1] <= 17'h00000;
    r_dskdatr[2] <= 17'h00000;
    `endif
    r_seldatr    <= 3'b001;
    r_buf_rdy    <= 1'b0;
  end
  // Rising edge of CDAC_n with CCK = 1
  else if (cck & cdac_r) begin
    // Horizontal strobe received
    if ((r_regs_str_p1) && (r_rga_p1[2:1] != 2'b11)) begin
      // Clear the filled buffer flags
      r_dskdatr[0][16] <= 1'b0;
      r_dskdatr[1][16] <= 1'b0;
      r_dskdatr[2][16] <= 1'b0;
    end
    else begin
      // New data available from the DPLL
      if ((r_buf_rdy != w_buf_rdy) && (w_dsk_dma) && (!r_DSKDIR)) begin
        // Fill one of the empty buffers
        if (r_seldatr[0]) r_dskdatr[0] <= {w_dsk_dma, w_dskdatr };
        if (r_seldatr[1]) r_dskdatr[1] <= {w_dsk_dma, w_dskdatr };
        if (r_seldatr[2]) r_dskdatr[2] <= {w_dsk_dma, w_dskdatr };
        // Go to the next one
        r_seldatr <= { r_seldatr[1:0], r_seldatr[2] };
      end
      r_buf_rdy <= w_buf_rdy;
    end
  end
end

////////////////////
// Registers read //
////////////////////

reg  [2:0] r_dsk_slot;

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 0
  if (cdac_r & ~cck) begin
    // Disk slots are based on DMAL counter values
    r_dsk_slot[0] <= (r_dmal_ctr[3:1] == 3'd3) ? 1'b1 : 1'b0;
    r_dsk_slot[1] <= (r_dmal_ctr[3:1] == 3'd4) ? 1'b1 : 1'b0;
    r_dsk_slot[2] <= (r_dmal_ctr[3:1] == 3'd5) ? 1'b1 : 1'b0;
    // Data bus output
    db_out <= ( w_adkconr           & {16{r_regs_adkr_p1}} )
            | ( { 1'b0,  r_INTENA } & {16{r_regs_ienr_p1}} )
            | ( { 2'b00, r_INTREQ } & {16{r_regs_irqr_p1}} );
    // Data bus output enable
    db_oe  <= r_regs_adkr_p1
            | r_regs_bytr_p1
            | r_regs_ienr_p1
            | r_regs_irqr_p1;
  end
end

assign db_out_er = ( r_dskdatr[0][15:0] & {16{r_dsk_slot[0] & r_regs_datr_p1}} )
                 | ( r_dskdatr[1][15:0] & {16{r_dsk_slot[1] & r_regs_datr_p1}} )
                 | ( r_dskdatr[2][15:0] & {16{r_dsk_slot[2] & r_regs_datr_p1}} );


/////////////////////
// Audio registers //
/////////////////////

integer i;

reg [15:0] r_AUDxLEN [0:3];
reg [15:0] r_AUDxPER [0:3];
reg  [6:0] r_AUDxVOL [0:3];
reg [15:0] r_AUDxDAT [0:3];
reg  [3:0] r_auddat;
reg  [1:0] v_chan_nr;
reg  [6:0] r_volbuf  [0:3];

always@(posedge rst or posedge clk) begin
  if (rst) begin
    for (i = 0; i < 4; i = i + 1) begin
      r_AUDxLEN[i] <= 16'h0000;
      r_AUDxPER[i] <= 16'h0000;
      r_AUDxVOL[i] <= 7'd0;
      r_AUDxDAT[i] <= 16'h0000;
      r_auddat[i]  <= 1'b0;
      r_volbuf[i]  <= 7'd0;
    end
  end
  // Rising edge of CDAC_n with CCK = 1
  else if ((cdac_r) && (cck)) begin
    v_chan_nr[1] = ~r_rga_p1[5];
    v_chan_nr[0] =  r_rga_p1[4];
    r_auddat <= 4'b0000;
    if (r_regs_aud_p1) begin
      case (r_rga_p1[3:1])
        3'b010 : // AUDxLEN
          r_AUDxLEN[v_chan_nr] <= db_in[15:0];
        3'b011 : // AUDxPER
          r_AUDxPER[v_chan_nr] <= db_in[15:0];
        3'b100 : // AUDxVOL
          r_AUDxVOL[v_chan_nr] <= db_in[6:0];
        3'b101 : // AUDxDAT
        begin
          r_AUDxDAT[v_chan_nr] <= db_in[15:0];
          r_auddat[v_chan_nr]  <= 1'b1;
        end
        default : ;
      endcase
    end
    // No volume modulation on channel #0
    r_volbuf[0] <= r_AUDxVOL[0];
    // Channel #0 modulates volume of channel #1
    if (r_ATVOL[0]) begin
      if (r_pbufld1[0]) r_volbuf[1] <= r_AUDxDAT[0][6:0];
    end else
      r_volbuf[1] <= r_AUDxVOL[1];
    // Channel #0 modulates period of channel #1
    if (r_pbufld2[0]) r_AUDxPER[1] <= r_AUDxDAT[0];
    // Channel #1 modulates volume of channel #2
    if (r_ATVOL[1]) begin
      if (r_pbufld1[1]) r_volbuf[2] <= r_AUDxDAT[1][6:0];
    end else
      r_volbuf[2] <= r_AUDxVOL[2];
    // Channel #1 modulates period of channel #2
    if (r_pbufld2[1]) r_AUDxPER[2] <= r_AUDxDAT[1];
    // Channel #2 modulates volume of channel #3
    if (r_ATVOL[2]) begin
      if (r_pbufld1[2]) r_volbuf[3] <= r_AUDxDAT[2][6:0];
    end else
      r_volbuf[3] <= r_AUDxVOL[3];
    // Channel #2 modulates period of channel #3
    if (r_pbufld2[2]) r_AUDxPER[3] <= r_AUDxDAT[2];
  end
end

///////////////////////////
// Audio period counters //
///////////////////////////

reg [15:0] r_perctr [0:3];
reg        r_perfin [0:3];

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if ((cdac_r) && (cck)) begin
    for (i = 0; i < 4; i = i + 1) begin
      if (r_perctrld[i])
        r_perctr[i] <= r_AUDxPER[i];
      else if (r_perctren[i])
        r_perctr[i] <= r_perctr[i] - 16'd1; 
    end
  end
  // Falling edge of CDAC_n with CCK = 1
  if ((cdac_f) && (cck)) begin
    for (i = 0; i < 4; i = i + 1) begin
      // Period finished comparators
      r_perfin[i] <= (r_perctr[i] == 16'd1) ? 1'b1 : 1'b0;
    end
  end
end

///////////////////////////
// Audio length counters //
///////////////////////////

reg [15:0] r_lenctr [0:3];
reg        r_lenfin [0:3];

always@(posedge clk) begin
  // Rising edge of CDAC_n with CCK = 1
  if ((cdac_r) && (cck)) begin
    for (i = 0; i < 4; i = i + 1) begin
      if (r_lenctrld[i])
        r_lenctr[i] <= r_AUDxLEN[i];
      else if (r_lenctren[i])
        r_lenctr[i] <= r_lenctr[i] - 16'd1; 
    end
  end
  // Falling edge of CDAC_n with CCK = 1
  if ((cdac_f) && (cck)) begin
    for (i = 0; i < 4; i = i + 1) begin
      // Length finished comparators
      r_lenfin[i] <= (r_lenctr[i] == 16'd1) ? 1'b1 : 1'b0;
    end
  end
end

//////////////////////////////
// Audio and sample buffers //
//////////////////////////////

reg [15:0] r_audbuf [0:3];
reg [7:0]  r_smpbuf [0:3];

always@(posedge rst or posedge clk) begin
  if (rst) begin
    for (i = 0; i < 4; i = i + 1) begin
      r_audbuf[i] <= 16'h0000;
      r_smpbuf[i] <= 8'h00;
    end
  end
  else if ((cdac_r) && (cck)) begin
    for (i = 0; i < 4; i = i + 1) begin
      if (r_pbufld1[i]) r_audbuf[i] <= r_AUDxDAT[i];
      if ((!r_ATVOL[i]) && (!r_ATPER[i]))
        if (r_penhi[i])
          r_smpbuf[i][7:0] <= r_audbuf[i][15:8];
        else
          r_smpbuf[i][7:0] <= r_audbuf[i][7:0];
      else
        r_smpbuf[i][7:0] <= 8'h00;
    end
  end
end

////////////////////////////
// Audio FSM multiplexing //
////////////////////////////

reg [3:0]  r_ch_sel;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_ch_sel <= 4'b0000;
  end
  else if (clk_28m) begin
    if (cck)
      r_ch_sel <= 4'b0001;
    else
      r_ch_sel <= { r_ch_sel[2:0], 1'b0 };
  end
end

///////////////////////////////////
// Multiplexed audio channel FSM //
///////////////////////////////////

// States definitions according to the HRM
`define AUDIO_STATE_0 3'b000
`define AUDIO_STATE_1 3'b001
`define AUDIO_STATE_2 3'b101
`define AUDIO_STATE_3 3'b010
`define AUDIO_STATE_4 3'b011

// Multiplexed signals
wire       w_AUDxDAT;
wire       w_AUDxIP;
wire       w_ATPER;
wire       w_napnav;
wire       w_perfin;
wire       w_lenfin;

// Audio data available
assign w_AUDxDAT = (r_auddat[0] & r_ch_sel[0]) | (r_auddat[1] & r_ch_sel[1])
                 | (r_auddat[2] & r_ch_sel[2]) | (r_auddat[3] & r_ch_sel[3]);
// Audio interrupt pending
assign w_AUDxIP  = (r_INTREQ[7] & r_ch_sel[0]) | (r_INTREQ[8] & r_ch_sel[1])
                 | (r_INTREQ[9] & r_ch_sel[2]) | (r_INTREQ[10] & r_ch_sel[3]);
// Attached period mode
assign w_ATPER   = (r_ATPER[0] & r_ch_sel[0]) | (r_ATPER[1] & r_ch_sel[1])
                 | (r_ATPER[2] & r_ch_sel[2]) | (r_ATPER[3] & r_ch_sel[3]);
// Conditions for normal DMA and interrupts requests
assign w_napnav  = (((~r_ATVOL[0] & ~r_ATPER[0]) | r_ATVOL[0]) & r_ch_sel[0])
                 | (((~r_ATVOL[1] & ~r_ATPER[1]) | r_ATVOL[1]) & r_ch_sel[1])
                 | (((~r_ATVOL[2] & ~r_ATPER[2]) | r_ATVOL[2]) & r_ch_sel[2])
                 | (((~r_ATVOL[3] & ~r_ATPER[3]) | r_ATVOL[3]) & r_ch_sel[3]);
// Period counter finished
assign w_perfin  = (r_perfin[0] & r_ch_sel[0]) | (r_perfin[1] & r_ch_sel[1])
                 | (r_perfin[2] & r_ch_sel[2]) | (r_perfin[3] & r_ch_sel[3]);
// Length counter finished
assign w_lenfin  = (r_lenfin[0] & r_ch_sel[0]) | (r_lenfin[1] & r_ch_sel[1])
                 | (r_lenfin[2] & r_ch_sel[2]) | (r_lenfin[3] & r_ch_sel[3]);

// Temporary signals
reg       v_AUDxDR;
reg       v_AUDxIR;
reg       v_irq2_clr;
reg       v_irq2_set;
reg       v_dmasen;
reg       v_perctrld;
reg       v_perctren;
reg       v_lenctrld;
reg       v_lenctren;
reg       v_pbufld1;
reg       v_pbufld2;
reg       v_penhi;
reg [2:0] v_audstate;

// Control signals according to the HRM
reg [3:0] r_AUDxDR;         // Audio DMA request
reg [3:0] r_AUDxIR;         // Audio interrupt request
reg [3:0] r_intreq2;        // Prepare for interrupt request
reg [3:0] r_dmasen;         // Restart request enable
reg [3:0] r_perctrld;       // Period counter load
reg [3:0] r_perctren;       // Period counter enable
reg [3:0] r_lenctrld;       // Length counter load
reg [3:0] r_lenctren;       // Length counter enable
reg [3:0] r_pbufld1;        // Data buffer #1 load (sample or AV mode)
reg [3:0] r_pbufld2;        // Data buffer #2 load (AP mode)
reg [3:0] r_penhi;          // Use MSB as sample
reg [2:0] r_audstate [0:3]; // Audio channel state

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_AUDxDR      <= 4'b0000;
    r_AUDxIR      <= 4'b0000;
    r_dmasen      <= 4'b0000;
    r_intreq2     <= 4'b0000;
    r_lenctrld    <= 4'b0000;
    r_lenctren    <= 4'b0000;
    r_perctrld    <= 4'b0000;
    r_perctren    <= 4'b0000;
    r_pbufld1     <= 4'b0000;
    r_pbufld2     <= 4'b0000;
    r_penhi       <= 4'b0000;
    r_audstate[0] <= `AUDIO_STATE_0;
    r_audstate[1] <= `AUDIO_STATE_0;
    r_audstate[2] <= `AUDIO_STATE_0;
    r_audstate[3] <= `AUDIO_STATE_0;
  end
  else if (clk_28m) begin
    if (!cck) begin
      case (r_audstate[0])
      
        `AUDIO_STATE_0 : // Idle (000)
        begin
          // No IRQ preparation
          v_irq2_set = 1'b0;
          v_irq2_clr = 1'b1;
          // DMA audio ON
          if (w_AUDxON) begin
            // Idle -> Start of audio DMA
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = 1'b1; // Data request
            v_dmasen   = 1'b1; // Restart enable
            v_lenctrld = 1'b1; // Load length counter
            v_lenctren = 1'b0; // No length counting
            v_perctrld = 1'b1; // Load period counter
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b0; // No audio buffer loading
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_1;
          end
          // Data available and no pending interrupt
          else if ((w_AUDxDAT) && (!w_AUDxIP)) begin
            // Idle -> CPU driven audio
            v_AUDxIR   = 1'b1; // Interrupt request
            v_AUDxDR   = 1'b0; // No data request
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter load
            v_lenctren = 1'b0; // No length counting
            v_perctrld = 1'b1; // Load period counter
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b1; // Load audio buffer #1
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_3;
          end
          else begin
            // Stay in idle state
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = 1'b0; // No data request
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter loading
            v_lenctren = 1'b0; // No length counting
            v_perctrld = 1'b1; // Load period counter
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b0; // No audio buffer loading
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_0;
          end
        end
        
        `AUDIO_STATE_1 : // Audio DMA started (001)
        begin
          // No IRQ preparation
          v_irq2_set = 1'b0;
          v_irq2_clr = 1'b1;
          // DMA audio off
          if (!w_AUDxON) begin
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = 1'b0; // No data request
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter loading
            v_lenctren = 1'b0; // No length counting
            v_perctrld = 1'b0; // No period counter loading
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b0; // No audio buffer loading
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_0;
          end
          // Audio data available
          else if (w_AUDxDAT) begin
            // Audio DMA started -> Audio DMA enabled
            v_AUDxIR   = 1'b1; // Interrupt request
            v_AUDxDR   = 1'b1; // Data request
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter loading
            v_lenctren = ~w_lenfin; // Count if length > 1
            v_perctrld = 1'b0; // No period counter loading
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b0; // Discard first word
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_2;
          end
          else begin
            // Stay in "audio DMA started" state
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = 1'b0; // No data request
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter loading
            v_lenctren = 1'b0; // No length counting
            v_perctrld = 1'b0; // No period counter loading
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b0; // No audio buffer loading
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_1;
          end
        end
        
        `AUDIO_STATE_2 : // Audio DMA enabled (101)
        begin
          // No IRQ preparation
          v_irq2_set = 1'b0;
          v_irq2_clr = 1'b1;
          // DMA audio off
          if (!w_AUDxON) begin
            // Audio DMA enabled -> Idle
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = 1'b0; // No data request
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter loading
            v_lenctren = 1'b0; // No length counting
            v_perctrld = 1'b0; // No period counter loading
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b0; // No audio buffer loading
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_0;
          end
          // Audio data available
          else if (w_AUDxDAT) begin
            // Audio DMA enabled -> Output first sample
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = w_napnav; // Data request if no attach mode
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter loading
            v_lenctren = ~w_lenfin; // Count if length > 1
            v_perctrld = 1'b1; // Load period counter
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b1; // Load audio buffer #1
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_3;
          end
          else begin
            // Stay in "Audio DMA enabled" state
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = 1'b0; // No data request
            v_dmasen   = 1'b0; // Restart disable
            v_lenctrld = 1'b0; // No length counter loading
            v_lenctren = 1'b0; // No length counting
            v_perctrld = 1'b0; // No period counter loading
            v_perctren = 1'b0; // No period counting
            v_pbufld1  = 1'b0; // No audio buffer loading
            v_pbufld2  = 1'b0;
            v_penhi    = 1'b0; // Select LSB as sample
            v_audstate = `AUDIO_STATE_2;
          end
        end
        
        `AUDIO_STATE_3 : // Output first sample (010)
        begin
          v_dmasen   = 1'b0; // Restart disable
          v_penhi    = 1'b1; // Select MSB as sample
          
          // DMA still ON and new data available
          if ((w_AUDxON) && (w_AUDxDAT)) begin
            // Check length counter
            if (w_lenfin) begin
              // End of waveform : reload length counter
              v_lenctren = 1'b0;
              v_lenctrld = 1'b1;
              // Prepare for interrupt
              v_irq2_set = 1'b1;
              v_irq2_clr = 1'b0;
            end
            else begin
              // Otherwise, decrement length counter
              v_lenctren = 1'b1;
              v_lenctrld = 1'b0;
              // Do not change interrupt preparation
              v_irq2_set = 1'b0;
              v_irq2_clr = 1'b0;
            end
          end
          else begin
            // No new data : do not touch length counter
            v_lenctren = 1'b0;
            v_lenctrld = 1'b0;
            // Do not change interrupt preparation
            v_irq2_set = 1'b0;
            v_irq2_clr = 1'b0;
          end
          
          // Period counter expired
          if (w_perfin) begin
            // Clear interrupt preparation
            v_irq2_clr = r_intreq2[0] & w_ATPER;
            // Interrupt request :
            // - Waveform finished with DMA still ON and AP mode
            // - Or DMA turned OFF and AP mode
            v_AUDxIR   = ((r_intreq2[0] & w_AUDxON) | ~w_AUDxON) & w_ATPER;
            // Data request : DMA still ON and AP mode
            v_AUDxDR   = w_AUDxON & w_ATPER;
            // Load audio buffer #2 (AP mode only)
            v_pbufld1  = 1'b0;
            v_pbufld2  = w_ATPER;
            // Reload period counter
            v_perctren = 1'b0;
            v_perctrld = 1'b1;
            // Output first sample -> Output second sample
            v_audstate = `AUDIO_STATE_4;
          end
          else begin
            v_irq2_clr = 1'b0;
            // No interrupt request
            v_AUDxIR   = 1'b0;
            // No data request
            v_AUDxDR   = 1'b0;
            // No audio buffer loading
            v_pbufld1  = 1'b0;
            v_pbufld2  = 1'b0;
            // Otherwise, decrement period counter
            v_perctren = 1'b1;
            v_perctrld = 1'b0;
            // Stay in "Output first sample" state
            v_audstate = `AUDIO_STATE_3;
          end
          
          v_pbufld1  = 1'b0; // No audio buffer loading
        end
        
        `AUDIO_STATE_4 : // Output second sample (011)
        begin
          v_dmasen   = 1'b0; // Restart disable
          v_penhi    = 1'b0; // Select LSB as sample

          // DMA still ON and new data available
          if ((w_AUDxON) && (w_AUDxDAT)) begin
            // Check length counter
            if (w_lenfin) begin
              // End of waveform : reload length counter
              v_lenctren = 1'b0;
              v_lenctrld = 1'b1;
              // Prepare for interrupt
              v_irq2_set = 1'b1;
              v_irq2_clr = 1'b0;
            end
            else begin
              // Otherwise, decrement length counter
              v_lenctren = 1'b1;
              v_lenctrld = 1'b0;
              // Do not change interrupt preparation
              v_irq2_set = 1'b0;
              v_irq2_clr = 1'b0;
            end
          end
          else begin
            // No new data : do not touch length counter
            v_lenctren = 1'b0;
            v_lenctrld = 1'b0;
            // Do not change interrupt preparation
            v_irq2_set = 1'b0;
            v_irq2_clr = 1'b0;
          end

          // Period counter expired
          if (w_perfin) begin
            // Audio DMA ON (DMA driven) or no interrupt pending (CPU driven)
            if ((w_AUDxON) || (!w_AUDxIP)) begin
              // Clear interrupt preparation
              v_irq2_clr = r_intreq2[0] & w_napnav;
              // Interrupt request :
              // - Waveform finished with DMA still ON and no AP mode
              // - Or DMA turned OFF and no AP mode
              v_AUDxIR   = ((r_intreq2[0] & w_AUDxON) | ~w_AUDxON) & w_napnav;
              // Data request : DMA still ON and no AP mode
              v_AUDxDR   = w_AUDxON & w_napnav;
              // Load audio buffer #1 (AV or normal mode)
              v_pbufld1  = 1'b1;
              v_pbufld2  = 1'b0;
              // Reload period counter
              v_perctren = 1'b0;
              v_perctrld = 1'b1;
              // Output second sample -> Output first sample
              v_audstate = `AUDIO_STATE_3;
            end
            // Audio DMA inactive
            else begin
              v_irq2_clr = 1'b0;
              v_AUDxIR   = 1'b0; // No interrupt request
              v_AUDxDR   = 1'b0; // No data request
              v_pbufld1  = 1'b0; // No audio buffer loading
              v_pbufld2  = 1'b0;
              v_perctrld = 1'b0; // No period counter loading
              v_perctren = 1'b0; // No period counting
              // Go back to idle
              v_audstate = `AUDIO_STATE_0;
            end
          end
          else begin
            v_irq2_clr = 1'b0;
            v_AUDxIR   = 1'b0; // No interrupt request
            v_AUDxDR   = 1'b0; // No data request
            v_pbufld1  = 1'b0; // No audio buffer loading
            v_pbufld2  = 1'b0;
            // Decrement period counter
            v_perctren = 1'b1;
            v_perctrld = 1'b0;
            // Stay in "Output second sample" state
            v_audstate = `AUDIO_STATE_4;
          end
        end
        
        default : // Not used (100, 110, 111)
        begin
          // Go back to Idle
          v_irq2_set = 1'b0; // No IRQ preparation
          v_irq2_clr = 1'b1;
          v_AUDxIR   = 1'b0; // No interrupt request
          v_AUDxDR   = 1'b0; // No data request
          v_dmasen   = 1'b0; // Restart disable
          v_lenctrld = 1'b0; // No length counter loading
          v_lenctren = 1'b0; // No length counting
          v_perctrld = 1'b0; // No period counter loading
          v_perctren = 1'b0; // No period counting
          v_pbufld1  = 1'b0; // No audio buffer loading
          v_pbufld2  = 1'b0;
          v_penhi    = 1'b0; // Select LSB as sample
          v_audstate = `AUDIO_STATE_0;
        end
      endcase
      
      // Interrupt request preparation
      r_intreq2[3]   <= (r_intreq2[0] & ~v_irq2_clr) | v_irq2_set;
      r_intreq2[2:0] <= r_intreq2[3:1];
      // DMA restart enable
      r_dmasen       <= { v_dmasen, r_dmasen[3:1] };
      // Audio interrupt request
      r_AUDxIR       <= { v_AUDxIR, r_AUDxIR[3:1] };
      // Audio DMA request
      r_AUDxDR       <= { v_AUDxDR, r_AUDxDR[3:1] };
      // Period counter value load
      r_lenctrld     <= { v_lenctrld, r_lenctrld[3:1] };
      // Period counter enable
      r_lenctren     <= { v_lenctren, r_lenctren[3:1] };
      // Length counter value load
      r_perctrld     <= { v_perctrld, r_perctrld[3:1] };
      // Length counter enable
      r_perctren     <= { v_perctren, r_perctren[3:1] };
      // Data buffer #1 load (sample or attach volume mode)
      r_pbufld1      <= { v_pbufld1, r_pbufld1[3:1] };
      // Data buffer #2 load (attach period mode)
      r_pbufld2      <= { v_pbufld2, r_pbufld2[3:1] };
      // LSB / MSB sample select
      r_penhi        <= { v_penhi, r_penhi[3:1] };
      // Audio channel state
      r_audstate[0]  <= r_audstate[1];
      r_audstate[1]  <= r_audstate[2];
      r_audstate[2]  <= r_audstate[3];
      r_audstate[3]  <= v_audstate;
    end
  end
end

//////////////////////
// Channels mixing //
/////////////////////

  // inputs
  //   reg  [6:0] r_volbuf  [0:3];
  //   reg  [7:0]  r_smpbuf [0:3];
  // outputs
  //   aud_l (wire)
  //   aud_r (wire)
  // locals
  reg          [5:0] r_pwmcnt;
  reg          [8:0] r_acc    [0:3];
  reg          [2:0] r_mix_r;
  reg          [2:0] r_mix_l;
  reg          [3:0] r_pwm;

  //integer i;

  // Output is simply bit 2 of each
  assign aud_l = r_mix_l[2];
  assign aud_r = r_mix_r[2];

  always @(posedge clk) begin
    // This portion needs to run at 3.58MHz!
    if (!cck) begin
      // PWM counter counts from 0 to 63 constantly
      r_pwmcnt <= r_pwmcnt + 1;

      // For each channel
      for (i = 0; i < 4; i = i + 1) begin
        // Check our PWM counter against our thresholds
        if(r_volbuf[i][6])                         r_pwm[i] <= 1; // if 64 then volume is always on
        else if(r_volbuf[i][5:0] == r_pwmcnt[5:0]) r_pwm[i] <= 0; // volume >= counter, set PWM
        else if(r_pwmcnt[5:0] == 0)                r_pwm[i] <= 1; // counter 0, reset PWM

        // accumulate the channel pulse-density output
        // high bit is captured the final carry out which we feed back for rounding
        r_acc[i] <= r_acc[i][7:0] + { ~r_smpbuf[i][7], r_smpbuf[i][6:0] } + r_acc[i][8];
      end

      // Left is channels 1 and 2
      r_mix_l <= {2{(r_acc[1][8] & r_pwm[1])}}
               + {2{(r_acc[2][8] & r_pwm[2])}}
               + r_mix_l[0];

      // Right is channels 0 and 3
      r_mix_r <= {2{(r_acc[0][8] & r_pwm[0])}}
               + {2{(r_acc[3][8] & r_pwm[3])}}
               + r_mix_r[0];    
    end // if (!cck)
  end // always
endmodule

// This module is based on :                                                    //
// Patent #4,780,844 from Commodore-Amiga Inc.
// DATA INPUT CIRCUIT WITH DIGITAL PHASE LOCKED LOOP

module mfm_dpll
(
  input         rst,       //          Global reset
  input         clk,       // Ref. 21, 85 MHz clock
  input         clk_ena,   // Ref. 21, 100 for HD, 100000 for DD, 100000000000 for SD
  input         dsk_rd_n,  // Ref. 11, disk read port
  output [15:0] buf_rd,    // Ref. 15, read shift register
  output        buf_rdy,   //          Data buffer ready
  input         start,     //          DMA start strobe
  input         wr_mode,   // Ref. 23, read (0), write (1)
  input         sync_arm,  //          MFM synchronization armed
  input         sync_ena,  //          MFM synchronization enabled
  input  [15:0] sync_word, //          MFM synchronization word value
  output        sync_det   //          MFM synchronization detected
);

// ================================
// == Falling edge detector (71) ==
// ================================

reg  [2:0] r_dsk_rd_cc;   // Ref. 71
wire       w_dsk_rd_edge; // Ref. 93

always@(posedge rst or posedge clk) begin
  if (rst)
    r_dsk_rd_cc <= 3'b111;
  else if (clk_ena) begin
    if (sync_arm | ~wr_mode)
      r_dsk_rd_cc <= { r_dsk_rd_cc[1:0], dsk_rd_n };
  end
end
assign w_dsk_rd_edge = r_dsk_rd_cc[2] & ~r_dsk_rd_cc[1];

// ================================
// == MFM/GCR bit flip-flop (81) ==
// == 16-bit shift register (15) ==
// ================================

reg        r_bit_ff;      // Ref. 81
reg [15:0] r_buf_rd;      // Ref. 15

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_bit_ff <= 1'b0;
    r_buf_rd <= 16'h0000;
  end else if (clk_ena) begin
    if (w_dsk_rd_edge)
      r_bit_ff <= 1'b1;
    else if (w_roll_over)
      r_bit_ff <= 1'b0;
    if (w_roll_over)
      r_buf_rd <= { r_buf_rd[14:0], r_bit_ff };
  end
end
assign buf_rd = r_buf_rd;

// ==============================
// == MFM synchronization word ==
// ==    MFM word alignment    ==
// ==============================

reg        r_sync_equ;
reg        r_sync_det;
reg  [3:0] r_bit_ctr;
reg        r_buf_rdy;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_sync_equ <= 1'b0;
    r_sync_det <= 1'b0;
    r_bit_ctr  <= 4'd0;
    r_buf_rdy  <= 1'b0;
  end else if (clk_ena) begin
    // MFM synchronization
    r_sync_equ <= ({ r_buf_rd[14:0], r_bit_ff } == sync_word) ? 1'b1 : 1'b0;
    if (w_roll_over) r_sync_det <= r_sync_equ;
    // MFM word alignment
    if ((w_roll_over & r_sync_equ & sync_ena) | start)
      r_bit_ctr <= 4'd0;
    else if (w_roll_over)
      r_bit_ctr <= r_bit_ctr + 4'd1;
    if ((r_bit_ctr == 4'd15) && (w_roll_over))
      r_buf_rdy <= ~r_buf_rdy;
  end
end
assign sync_det = r_sync_det;
assign buf_rdy  = r_buf_rdy;

// ==================================
// == Window history register (91) ==
// ==================================

reg  [1:0] r_msb_hist;    // Ref. 91

always@(posedge rst or posedge clk) begin
  if (rst)
    r_msb_hist <= 2'b00;
  else if (w_dsk_rd_edge & clk_ena)
    r_msb_hist <= { r_msb_hist[0], r_ph_adder[11] };
end

// ================================
// == 8-bit up/down counter (25) ==
// ================================

`define CTR_MAX_VAL 8'd159
`define CTR_AVG_VAL 8'd146
`define CTR_MIN_VAL 8'd133

reg  [7:0] r_up_dn_ctr;   // Ref. 25

always@(posedge rst or posedge clk) begin
  if (rst)
    r_up_dn_ctr <= `CTR_AVG_VAL;
  else if (clk_ena) begin
    if (start)
      r_up_dn_ctr <= `CTR_AVG_VAL;
    else if ((r_cnt_up) && (r_up_dn_ctr != `CTR_MAX_VAL))
      r_up_dn_ctr <= r_up_dn_ctr + 8'd1;
    else if ((r_cnt_dn) && (r_up_dn_ctr != `CTR_MIN_VAL))
      r_up_dn_ctr <= r_up_dn_ctr - 8'd1;
  end
end

// ==================================
// == Added value multiplexer (41) ==
// ==================================

`define ADD_LO_VAL 9'd34
`define ADD_HI_VAL 9'd258

wire [8:0] w_ctr_val;
wire [8:0] w_add_val;     // Ref. 41

assign w_ctr_val = (r_add_four)
                 ? ({1'b0, r_up_dn_ctr} + 9'd4)     // Write mode add four
                 : {1'b0, r_up_dn_ctr};             // Normal mode

assign w_add_val = ({9{r_sel_low}}  & `ADD_LO_VAL)  // Negative phase correction
                 | ({9{r_sel_ctr}}  & w_ctr_val)    // No phase correction
                 | ({9{r_sel_high}} & `ADD_HI_VAL); // Positive phase correction

// =============================
// == 12-bit phase adder (43) ==
// =============================

reg [11:0] r_ph_adder;    // Ref. 43

always@(posedge rst or posedge clk) begin
  if (rst)
    r_ph_adder <= 12'd0;
  else if (clk_ena) begin
    if (start)
      r_ph_adder <= 12'd0;
    else
      r_ph_adder <= r_ph_adder + w_add_val;
  end
end

// ==========================
// == Adder roll-over (79) ==
// ==========================

reg        r_msb_dly;     // Ref. 79
wire       w_roll_over;   // Ref. 83

always@(posedge rst or posedge clk) begin
  if (rst)
    r_msb_dly <= 1'b0;
  else if (clk_ena)
    // Set when 111, cleared otherwise
    r_msb_dly <= &r_ph_adder[11:9];
end
// 111 -> 000 : roll-over detection
assign w_roll_over = r_msb_dly & ~(&r_ph_adder[11:9]);

// ===============================
// == Add four instruction (89) ==
// ===============================

reg        r_add_four;    // Ref. 89

always@(posedge rst or posedge clk) begin
  if (rst)
    r_add_four <= 1'b0;
  else if (clk_ena)
    // Add 4 every 14 cycles during write mode
    r_add_four <= (&r_ph_adder[10:8]) & wr_mode & ~sync_arm;
end

// ==============================
// == Freq. error decoder (73) ==
// ==============================

reg  [3:0] r_freq_err;    // Ref. 99
reg        r_cnt_up;      // Ref. 27
reg        r_cnt_dn;      // Ref. 29

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_freq_err <= 4'd0;
    r_cnt_up   <= 1'b0;
    r_cnt_dn   <= 1'b0;
  end else if (clk_ena) begin
    if (w_dsk_rd_edge) begin
      // Compute frequency correction based on:
      // - phase history
      // - current phase
      case ({r_msb_hist, r_ph_adder[11:9]})
        5'b00000 : r_freq_err <= 4'b0100; // +4
        5'b00001 : r_freq_err <= 4'b0011; // +3
        5'b00010 : r_freq_err <= 4'b0010; // +2
        5'b00011 : r_freq_err <= 4'b0001; // +1
        5'b00100 : r_freq_err <= 4'b1000; // +0
        5'b00101 : r_freq_err <= 4'b1001; // -1
        5'b00110 : r_freq_err <= 4'b1010; // -2
        5'b00111 : r_freq_err <= 4'b1011; // -3
        5'b01000 : r_freq_err <= 4'b0000; // +0
        5'b01001 : r_freq_err <= 4'b0000; // +0
        5'b01010 : r_freq_err <= 4'b0000; // +0
        5'b01011 : r_freq_err <= 4'b0000; // +0
        5'b01100 : r_freq_err <= 4'b1000; // +0
        5'b01101 : r_freq_err <= 4'b1001; // -1
        5'b01110 : r_freq_err <= 4'b1010; // -2
        5'b01111 : r_freq_err <= 4'b1011; // -3
        5'b10000 : r_freq_err <= 4'b0011; // +3
        5'b10001 : r_freq_err <= 4'b0010; // +2
        5'b10010 : r_freq_err <= 4'b0001; // +1
        5'b10011 : r_freq_err <= 4'b0000; // +0
        5'b10100 : r_freq_err <= 4'b1000; // +0
        5'b10101 : r_freq_err <= 4'b1000; // +0
        5'b10110 : r_freq_err <= 4'b1000; // +0
        5'b10111 : r_freq_err <= 4'b1000; // +0
        5'b11000 : r_freq_err <= 4'b0011; // +3
        5'b11001 : r_freq_err <= 4'b0010; // +2
        5'b11010 : r_freq_err <= 4'b0001; // +1
        5'b11011 : r_freq_err <= 4'b0000; // +0
        5'b11100 : r_freq_err <= 4'b1001; // -1
        5'b11101 : r_freq_err <= 4'b1010; // -2
        5'b11110 : r_freq_err <= 4'b1011; // -3
        5'b11111 : r_freq_err <= 4'b1100; // -4
        default : ;
      endcase
      // No frequency correction
      r_cnt_up   <= 1'b0;
      r_cnt_dn   <= 1'b0;
    end else begin
      if (r_freq_err[2:0]) begin
        // Apply frequency correction
        r_freq_err[2:0] <= r_freq_err[2:0] - 3'd1;
        if (r_freq_err[3]) begin
          // Decrement frequency
          r_cnt_up   <= 1'b0;
          r_cnt_dn   <= 1'b1;
        end else begin
          // Increment frequency
          r_cnt_up   <= 1'b1;
          r_cnt_dn   <= 1'b0;
        end
      end else begin
        // No frequency correction
        r_cnt_up   <= 1'b0;
        r_cnt_dn   <= 1'b0;
      end
    end
  end
end

// ==============================
// == Phase error decoder (75) ==
// ==============================

reg  [3:0] r_ph_err;      // Ref. 101
reg        r_sel_low;     // Ref. 45
reg        r_sel_ctr;     // Ref. 47
reg        r_sel_high;    // Ref. 49

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_ph_err   <= 4'd0;
    r_sel_low  <= 1'b0;
    r_sel_ctr  <= 1'b1;
    r_sel_high <= 1'b0;
  end else if (clk_ena) begin
    if (w_dsk_rd_edge) begin
      // Measure phase error
      r_ph_err[3] <= r_ph_adder[11];
      if (r_ph_adder[11]) begin
        // Negative error
        r_sel_low     <= 1'b1;
        r_sel_ctr     <= 1'b0;
        r_sel_high    <= 1'b0;
        r_ph_err[2:0] <= r_ph_adder[10:8];
      end else begin
        // Positive error
        r_sel_low     <= 1'b0;
        r_sel_ctr     <= 1'b0;
        r_sel_high    <= 1'b1;
        r_ph_err[2:0] <= ~r_ph_adder[10:8];
      end
    end else begin
      if (r_ph_err[2:0]) begin
        // Apply phase correction
        r_ph_err[2:0] <= r_ph_err[2:0] - 3'd1;
        if (r_ph_err[3]) begin
          // Negative phase correction
          r_sel_low  <= 1'b1;
          r_sel_ctr  <= 1'b0;
          r_sel_high <= 1'b0;
        end else begin
          // Positive phase correction
          r_sel_low  <= 1'b0;
          r_sel_ctr  <= 1'b0;
          r_sel_high <= 1'b1;
        end
      end else begin
        // No phase correction
        r_sel_low  <= 1'b0;
        r_sel_ctr  <= 1'b1;
        r_sel_high <= 1'b0;
      end
    end
  end
end
  
endmodule
