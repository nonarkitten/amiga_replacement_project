/*
 * Implementation of 8520 Complex Interface Adapter (CIA) in Verilog.
 * Written by Niklas Ekström in June 2021.
 *
 * Features:
 * - 2x 8-bit I/O ports (PORTA, PORTB)
 * - Handshaking for I/O port communication (PC, FLAG)
 * - 2x interval timers (TA, TB)
 * - Time of Day clock (TOD)
 * - Serial port (SDR)
 * - Interrupt control (ICR)
 * - Control Registers (CRA, CRB)
 */

module cia(
    // Chip access control.
    input nRES,
    input ECLK,
    input nCS,
    input RW,
    input [3:0] RS,
    inout [7:0] DB,

    // Port A/B.
    inout [7:0] PA,
    inout [7:0] PB,

    // Handshake.
    output nPC,
    input nFLAG,

    // Serial port.
    inout CNT,
    inout SP,

    // TOD TOD.
    input TOD,

    // Interrupt.
    output nIRQ
  );

  wire dat_oe = ~nCS & RW;
  wire [7:0] dat_o;

  assign DB = dat_oe ? dat_o : 8'bz;

  wire [7:0] ddra;
  wire [7:0] ddrb;

  wire [7:0] pra;
  wire [7:0] prb;

  assign PA[0] = ddra[0] ? pra[0] : 1'bz;
  assign PA[1] = ddra[1] ? pra[1] : 1'bz;
  assign PA[2] = ddra[2] ? pra[2] : 1'bz;
  assign PA[3] = ddra[3] ? pra[3] : 1'bz;
  assign PA[4] = ddra[4] ? pra[4] : 1'bz;
  assign PA[5] = ddra[5] ? pra[5] : 1'bz;
  assign PA[6] = ddra[6] ? pra[6] : 1'bz;
  assign PA[7] = ddra[7] ? pra[7] : 1'bz;

  assign PB[0] = ddrb[0] ? prb[0] : 1'bz;
  assign PB[1] = ddrb[1] ? prb[1] : 1'bz;
  assign PB[2] = ddrb[2] ? prb[2] : 1'bz;
  assign PB[3] = ddrb[3] ? prb[3] : 1'bz;
  assign PB[4] = ddrb[4] ? prb[4] : 1'bz;
  assign PB[5] = ddrb[5] ? prb[5] : 1'bz;
  assign PB[6] = ddrb[6] ? prb[6] : 1'bz;
  assign PB[7] = ddrb[7] ? prb[7] : 1'bz;

  wire sp_o;
  wire sp_oe;
  wire cnt_o;

  assign SP = sp_oe ? sp_o : 1'bz;
  assign CNT = sp_oe ? cnt_o : 1'bz;

  cia8520 ciai(
            .nRES(nRES),
            .ECLK(ECLK),
            .nCS(nCS),
            .RW(RW),
            .RS(RS),
            .DBi(DB),
            .DBo(dat_o),
            .PRAi(PA),
            .PRAo(pra),
            .PRAd(ddra),
            .PRBi(PB),
            .PRBo(prb),
            .PRBd(ddrb),
            .nFLAG(nFLAG),
            .nPC(nPC),
            .SPi(SP),
            .SPo(sp_o),
            .SPd(sp_oe),
            .CNTi(CNT),
            .CNTo(cnt_o),
            .TOD(TOD),
            .nIRQ(nIRQ)
          );
endmodule
