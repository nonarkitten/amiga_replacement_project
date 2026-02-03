/*
 * CIA 8520 Address Decoder and Read Multiplexer
 * 
 * Combinatorial module that decodes the 4-bit register address (RS3-RS0)
 * and routes data between the CIA's internal registers and the data bus.
 * 
 * Design notes:
 * - Pure combinatorial logic (no clock, no state)
 * - One-hot decoding for address selection (adr_sel)
 * - Generates individual strobe signals for each register
 * - Multiplexes 16 input registers onto single 8-bit output bus
 * 
 * Register Map (MOS 8520 compatible):
 *   $0 (0x0) - PRA     : Port A data register
 *   $1 (0x1) - PRB     : Port B data register
 *   $2 (0x2) - DDRA    : Port A data direction (0=input, 1=output)
 *   $3 (0x3) - DDRB    : Port B data direction
 *   $4 (0x4) - TA_LO   : Timer A low byte
 *   $5 (0x5) - TA_HI   : Timer A high byte
 *   $6 (0x6) - TB_LO   : Timer B low byte
 *   $7 (0x7) - TB_HI   : Timer B high byte
 *   $8 (0x8) - TOD_LO  : Time of day counter LSB
 *   $9 (0x9) - TOD_MID : Time of day counter
 *   $A (0xA) - TOD_HI  : Time of day counter MSB
 *   $B (0xB) - EXT     : Extension register
 *   $C (0xC) - SDR     : Serial data register
 *   $D (0xD) - ICR     : Interrupt control register
 *   $E (0xE) - CRA     : Control register A
 *   $F (0xF) - CRB     : Control register B
 * 
 * Usage:
 * - Address strobe outputs (pra_o, prb_o, etc.) are used by parent module
 *   to detect register access and trigger side effects (e.g., PC pulse on PRB access,
 *   TOD latch on TOD_HI read, timer reload on TA_HI/TB_HI write)
 * - Data output (dat_o) provides the read value for the selected register
 * - All outputs are valid within the same combinatorial path as adr_i
 * 
 * Implementation:
 * - One-hot decode using shift: 16'b1 << adr_i (synthesizes to simple logic)
 * - Read mux using OR of masked inputs (synthesizes to efficient mux tree)
 * - No critical paths: fully combinatorial, no feedback
 */
module cia_decoder(
    input  [3:0] adr_i, // address selector input

    // input from other modules to be set in dat_o
    input  [7:0] pra_i,
    input  [7:0] prb_i,
    input  [7:0] ddra_i,
    input  [7:0] ddrb_i,
    input  [7:0] talo_i,
    input  [7:0] tahi_i,
    input  [7:0] tblo_i,
    input  [7:0] tbhi_i,
    input  [7:0] todlo_i,
    input  [7:0] todmid_i,
    input  [7:0] todhi_i,
    input  [7:0] ext_i,
    input  [7:0] sdr_i,
    input  [7:0] icr_i,
    input  [7:0] cra_i,
    input  [7:0] crb_i,

    // selected output
    output [7:0] dat_o,

    // output selected address as strobe
    output pra_o,
    output prb_o,
    output ddra_o,
    output ddrb_o,
    output talo_o,
    output tahi_o,
    output tblo_o,
    output tbhi_o,
    output todlo_o,
    output todmid_o,
    output todhi_o,
    output ext_o,
    output sdr_o,
    output icr_o,
    output cra_o,
    output crb_o
  );

  // register addresses (constants)
  localparam [3:0] REG_PRA     = 4'h0;
  localparam [3:0] REG_PRB     = 4'h1;
  localparam [3:0] REG_DDRA    = 4'h2;
  localparam [3:0] REG_DDRB    = 4'h3;
  localparam [3:0] REG_TA_LO   = 4'h4;
  localparam [3:0] REG_TA_HI   = 4'h5;
  localparam [3:0] REG_TB_LO   = 4'h6;
  localparam [3:0] REG_TB_HI   = 4'h7;
  localparam [3:0] REG_TOD_LOW = 4'h8;
  localparam [3:0] REG_TOD_MID = 4'h9;
  localparam [3:0] REG_TOD_HI  = 4'ha;
  localparam [3:0] REG_EXT     = 4'hb;
  localparam [3:0] REG_SDR     = 4'hc;
  localparam [3:0] REG_ICR     = 4'hd;
  localparam [3:0] REG_CRA     = 4'he;
  localparam [3:0] REG_CRB     = 4'hf;

  // barrel shifter
  wire [15:0] adr_sel = 16'b1 << adr_i;

  // address comparators
  assign pra_o    = adr_sel[REG_PRA];
  assign prb_o    = adr_sel[REG_PRB];
  assign ddra_o   = adr_sel[REG_DDRA];
  assign ddrb_o   = adr_sel[REG_DDRB];
  assign talo_o   = adr_sel[REG_TA_LO];
  assign tahi_o   = adr_sel[REG_TA_HI];
  assign tblo_o   = adr_sel[REG_TB_LO];
  assign tbhi_o   = adr_sel[REG_TB_HI];
  assign todlo_o  = adr_sel[REG_TOD_LOW];
  assign todmid_o = adr_sel[REG_TOD_MID];
  assign todhi_o  = adr_sel[REG_TOD_HI];
  assign ext_o    = adr_sel[REG_EXT];
  assign sdr_o    = adr_sel[REG_SDR];
  assign icr_o    = adr_sel[REG_ICR];
  assign cra_o    = adr_sel[REG_CRA];
  assign crb_o    = adr_sel[REG_CRB];

  // module output
  assign dat_o =
         ({8{pra_o}}   & pra_i)   |
         ({8{prb_o}}   & prb_i)   |
         ({8{ddra_o}}  & ddra_i)  |
         ({8{ddrb_o}}  & ddrb_i)  |
         ({8{talo_o}}  & talo_i)  |
         ({8{tahi_o}}  & tahi_i)  |
         ({8{tblo_o}}  & tblo_i)  |
         ({8{tbhi_o}}  & tbhi_i)  |
         ({8{todlo_o}} & todlo_i) |
         ({8{todmid_o}}& todmid_i)|
         ({8{todhi_o}} & todhi_i) |
         ({8{ext_o}}   & ext_i)   |
         ({8{sdr_o}}   & sdr_i)   |
         ({8{icr_o}}   & icr_i)   |
         ({8{cra_o}}   & cra_i)   |
         ({8{crb_o}}   & crb_i);
endmodule
