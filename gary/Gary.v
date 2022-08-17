`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////// 
// 
// Company:        The Buffee Project Inc.
// Engineers:      c. 2022 Renee Cousins
//                 c. 2015 Matthias 'Matze' Heinrichs
// 
// Create Date:    20:24:47 10/29/2015
// Design Name:    Gary
// Project Name:   Amiga Replacement Project
// Target Devices: XC9572XL
// Tool versions:  Xilinx ISE 13
// Description:    Implements the original logic of the Commodore Amiga
//                 CSG 5719 "Gary" chip. The original specification as far
//                 as it is known should be included in this archive. 
// Dependencies:   None
// 
// Revision:       0.01 - File Created
//                 0.20 - First working version (>90% boots pass)
//                 0.21 - Added waitstates for RTC and BGACK
// 
////////////////////////////////////////////////////////////////////////////////// 
module Gary(           //                     ACTV HANDLED
                       // PIN NAME    TYPE    PLTY BY      DESCRIPTION
                       // --- ------- ------- ---- ------- --------------------------
                       //  1  VSS     PWR          n/a     Common ground supply
    output nVPA,       //  2  NVPA    OUT     LO   PALEN   Valid peripheral address 
    output nCDR,       //  3  NCDR    OUT     LO   PALCAS  Enable video bus read buffers
    output nCDW,       //  4  NCDW    OUT     LO   PALCAS  Enable video bus output buffers
    input nKRES,       //  5  NKRES   IN      LO   n/a     Power-up/Keybd Reset 
                       //  6  VDD     PWR          n/a     Common 5v supply
    input nMTR,        //  7  NMTR    IN      LO   n/a     Disk motor enable 
    input nDKWD,       //  8  NDKWD   IN      LO   n/a     Disk write data
    input nDKWE,       //  9  NDKWE   IN      HI   n/a     Disk write enable
    input nLDS,        // 10  NLDS    IN      LO   n/a     68000 lower byte data strobe
    input nUDS,        // 11  NUDS    IN      LO   n/a     68000 upper byte data strobe
    input PRnW,        // 12  PPRnW   IN      LO   n/a     68000 write enable
    input nAS,         // 13  NAS     IN      LO   n/a     68000 Adress strobe
    input nBGACK,      // 14  NBGACK  IN      LO   n/a     Bus grant acknowledge; add 1WS
    input nDBR,        // 15  NDBR    IN      LO   n/a     DMA bus request 
    input nSEL0,       // 16  NSEL0   IN      LO   n/a     (??)
                       // 17  VDD     PWR          n/a     Common 5v supply
    output nRGAE,      // 18  NRGAE   OUT     LO   PALEN   Amiga chip register address decode
    output nBLS,       // 19  NBLS    OUT     LO   PALEN   Blitter slowdown
    output nRAME,      // 20  NRAME   OUT     LO   PALEN   Video RAM address decode
    output nROME,      // 21  NROME   OUT     LO   PALEN   On-board ROM address decode
    output nRTCR,      // 22  NRTCR   OUT     LO   PALCAS  Real time clock read enable; add 3WS
    output nRTCW,      // 23  NRTCW   OUT     LO   PALCAS  Real time clock write enable; add 3WS
                       // 24  VSS     PWR          n/a     Common ground supply
    output reg nLATCH, // 25  C4      OUT     LO   CLOCKS  Enable video bus read latch (LS373 EN)
    input nCDAC,       // 26  NCDAC   IN      CLK  n/a     7.14Mhz clk (high while C3 changes)
    input C3,          // 27  C3      IN      CLK  n/a     3.57Mhz clk (90 deg lag of C1)
    input C1,          // 28  C1      IN      CLK  n/a     3.57Mhz clk 
    input nOVR,        // 29  NOVR    IN      LO   n/a     Override (internal decoding and DTACK)
    input OVL,         // 30  OVL     IN      HI   n/a     Overlay (ROM to address 0)
    input XRDY,        // 31  XRDY    IN      HI   n/a     External ready
    input nEXP,        // 32  NEXP    IN      LO   n/a     Expansion Ram (present)
    input [23:17] A,   // 33  A17     IN      HI   n/a     68000 CPU Address
                       // 34  A18     IN      HI   n/a     68000 CPU Address
                       // 35  A19     IN      HI   n/a     68000 CPU Address
                       // 36  A20     IN      HI   n/a     68000 CPU Address
                       // 37  A21     IN      HI   n/a     68000 CPU Address
                       // 38  A22     IN      HI   n/a     68000 CPU Address
                       // 39  A23     IN      HI   n/a     68000 CPU Address
                       // 40  N/C                  n/a     No connect
    inout nRESET,      // 41  NRESET  OUT OD  LO   FILTER  68000 reset; OD feed back from bus
    output nHALT,      // 42  NHALT   OUT OD  LO   FILTER  68000 halt
    output nDTACK,     // 43  NDTACK  OUT TS  LO   PALEN   Data transfer acknowledge
    output DKWEB,      // 44  DKWEB   OUT     HI           Disk write enable buffered
    output DKWDB,      // 45  DKWDB   OUT     HI           Disk write data buffered
    output MTR0D,      // 46  MTR0D   OUT     HI           Latched disk 0 motor on (?)
    output MTRXD       // 47  MTRXD   OUT     HI           Buffered NMTR 
                       // 48  VDD     PWR          n/a     Common 5v supply
);

    // internal registers
    reg nDBR_D0, nDTACK_S, nCDR_S, nCDW_S,nBLS_S, MTR0_S;
    reg [2:0] COUNT;    // Cycle counter for CPU-state alignment
    reg [2:0] nWAIT;    // Wait-states for clock and Zorro access

    // RESET is open-drain, input/output (IOBUFE)
    assign nRESET = nKRES ? 1'bz : 1'b0;
    // HALT is open-drain, output only
    assign nHALT = nRESET ? 1'bz : 1'b0;
    // Global ENABLE signal
    wire ENABLE = nRESET & nOVR & ~nAS;
    // DTACK is tri-state, output only
    assign nDTACK = ENABLE ? nDTACK_S : 1'bz;

    // generate processor clock
    wire C7M = C3 ~^ C1;                    // 7MHz (c1 xnor c2)
    wire C14M = C7M ~^ nCDAC;               // 14MHz (7MHz xnor CDAC)
    wire DS = ~nUDS | ~nLDS;                // Either data select
    
    // ADDRESS DECODE
    wire CHIPRAM    = (~OVL & A[23:21]==3'b000);  //    000000-1FFFFF
    
    wire ROM        = ((OVL & A[23:21]==3'b000)   // ROM overlay during start
                    | (A[23:19]==5'b1111_1)       // or F80000-FFFFFF
                    | (A[23:19]==5'b1110_0));     // or E00000-E7FFFF
                    
    wire CIA        = A[23:20]==4'b1011;          //    B00000-BFFFFF CIA
    
    wire CLOCK      = A[23:17]==7'b1101_110;      //    DC0000-DDFFFF clock
    
    wire CHIPSET    = nEXP &                      // expansion absent
                     ((A[23:20]==4'b1100)         // or C00000-CFFFFF
                    | (A[23:19]==5'b1101_0))      // or D00000-D7FFFF
                    | (A[23:17]==7'b1101_111);    // or DE0000-DFFFFF chipset
                    
    wire RANGER     = ~nEXP &                     // expansion present
                     ((A[23:20]==4'b1100)         // or C00000-CFFFFF ranger (low)
                    | (A[23:19]==5'b1101_0));     // or D00000-D7FFFF ranger (high)
        
    // assign simple signals
    assign DKWDB = ~nDKWD;
    assign DKWEB = nDKWE & nRESET;
    assign MTRXD = ~nMTR & nRESET;
    assign MTR0D = MTR0_S;
    
    wire nBLIT = nDBR_D0 & nDBR;
    wire AGNUS = CHIPRAM | RANGER | CHIPSET;
    
    // select floppy motor
    always @(negedge nSEL0, negedge nRESET)
        MTR0_S <= (nRESET==0) ? 0 : ~nMTR;
    
    // decode address and generate the internal signals
    always @(posedge C14M) begin
        // this replaces the nasty latch!
        nLATCH  <= C3;
        nDBR_D0 <= nDBR;
        
        if(nAS | (nRESET==0)) begin
            nDTACK_S    <= 1;
            nCDR_S      <= 1;
            nCDW_S      <= 1;
            nBLS_S      <= 1;
            
            COUNT       <= 0;
            
            if(CLOCK)       nWAIT <= 3'b111; // 3 waits
            else if(nBGACK) nWAIT <= 3'b100; // 1 wait
            else            nWAIT <= 3'b000; // no waits
            
        end else begin
            // Track out wait states
            nWAIT <= { nWAIT[1:0], 1'b0 };
        
            // count 7Mhz-flanks: odd falling even rising
            // the cycle starts at S3: this time the first cycle is seen!
            // ergo, this should be 0 (read) at S3 when C7M should be low
            COUNT[0] <= C3; // C7M;
            COUNT[2:1] <= COUNT[2:1] + COUNT[0];
            
            // assert DTACK when ready
            if ((~nBLIT & AGNUS ) | CIA & nDTACK_S)
                nDTACK_S <= 1;
            else 
                nDTACK_S <= nWAIT[2] | ~XRDY;
            
            // slow down blitter
            nBLS_S <= ~(AGNUS & (COUNT[1:0]>=2'b00 & COUNT[1:0]<=2'b01));

            // read from RAM / register  
            if((COUNT >= 8'h01) & PRnW & nBLIT & AGNUS & nCDR_S)
                nCDR_S  <= 0;
            
            // write to RAM / register
            if(~PRnW & nBLIT & AGNUS & nCDW_S)
                nCDW_S  <= 0;

        end
    end
        
    // output signal generation
    assign nVPA =   ENABLE ? ~CIA : 1;
    assign nROME =  ENABLE ? ~(ROM & PRnW) : 1; // only on read!
    assign nRTCR =  ENABLE ? ~(CLOCK &  PRnW & DS) : 1;
    assign nRTCW =  ENABLE ? ~(CLOCK & ~PRnW & DS) : 1;
    assign nRAME =  ENABLE ? ~(CHIPRAM | RANGER ) : 1;
    assign nCDR  =  ENABLE ? nCDR_S : 1;
    assign nCDW  =  ENABLE ? nCDW_S : 1;
    assign nRGAE =  ENABLE ? ~CHIPSET : 1;
    assign nBLS  =  ENABLE ? nBLS_S : 1;

endmodule
