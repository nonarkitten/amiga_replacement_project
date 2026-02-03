/*
 * CIA 8520 Handshake module
 * Handles FLAG input synchronization and PC output generation
 * 
 * Design notes:
 * - FLAG input is synchronized through 3-stage pipeline
 * - Flag pulse (pls_o) is generated on negedge for interrupt logic
 * - PC will go low on 1 cycle after a  port B  access
 */
module cia_handshake(
    input clk_i, // master clock (phi2)

    input prb_i, // strobe for PRB write
    input flg_ni, // inverted external flag pin

    // outputs
    output     pls_o, // flag pulse for interrupts
    output reg pc_no   // pc output
  );

  // registers
  reg [2:0] flg_s; // flag sync register
  reg       pc_s;  // pc sync register

  // flag pulse generator
  assign pls_o = ~flg_s[2] & flg_s[1];

  always @(posedge clk_i)
  begin
    // start flag signal sync
    flg_s[0] <= ~flg_ni;
  end

  always @(negedge clk_i)
  begin
    // end flag signal sync and trigger pulse for 1 clock cycle
    { flg_s[2], flg_s[1] } <= { flg_s[1], flg_s[0] };
  end

  always @(negedge clk_i)
  begin
    // trigger PC low for 1 clock cycle following a read or write to PRB
    { pc_no, pc_s } <= { ~pc_s, prb_i};
  end
endmodule
