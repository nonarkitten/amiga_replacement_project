/*
 * CIA 8520 TOD helper module
 * 
 * The real TOD workd with clk_i / 4. This is not applied
 *
 *
 * Protocol with parent:
 * - Module asserts cnt_o on posedge to request increment
 * - Parent increments count_i on negedge (if no bus write)
 * - Parent asserts cnt_i on negedge when incrementing tod
 * - Module compares alarm on next posedge when cnt_i is asserted
 * 
 * Write sequence (from CIA spec):
 * - ANY write to TOD stops counting
 * - Clock restarts only after write to LSB (TOD_LO)
 * 
 * Read sequence (from CIA spec):
 * - Read MSB (TOD_HI) latches all registers
 * - Latch stays frozen until read of LSB (TOD_LO)
 * - TOD continues counting while latched
 */
module cia_tod(
    input clk_i, // master clock
    input rst_i, // reset input (active high)

    input tod_i, // tod count input (from external CIA pin)

    // bus strobes relayed from parent
    input sel_i, // chip select
    input we_i,  // write enable

    // input from parent address decoder.
    input sel_alrm_i,  // select alrm for writes
    input sel_todlo_i, // selected tod lsb
    input sel_todmi_i,
    input sel_todhi_i, // selected tod msb

    // tod counters
    input      [23:0] alrm_i,  // parent alrm register
    input      [23:0] count_i, // parent tod count (from register)
    output reg [23:0] latch_o, // output tod latch

    // tod counter control
    output cnt_o, // indicate to parent that tod should be incremented on next negedge
    input  cnt_i, // parent did increment tod count on last negedge, check alrm
    output pls_o  // tod alrm pulse for IRQs
  );

  // tod synchronization
  reg [2:0] tod_s;

  wire tod_pls = ~tod_s[2] & tod_s[1];

  always @(posedge clk_i)
  begin
    // start tod signal sync (on posedge)
    tod_s[0] <= tod_i;

    // since we need to generate a tod pulse on posedge, there is no need
    // for dual edge sync like in timer A / B

    // end tod signal sync and trigger pulse for 1 clock cycle
    { tod_s[2:1] } <= { tod_s[1:0] };
  end

  reg tod_latch_e; // tod latch enable (active high)
  reg tod_count_e; // tod count enable (active high)

  // handle enable/disable of latch and count
  always @(negedge clk_i)
  begin
    if (rst_i)
    begin
      tod_latch_e <= 1'b0;
      tod_count_e <= 1'b0; // tod is not running after reset
    end
    else if (sel_i)
    begin
      if (~we_i)
      begin
        // latch register when reading tod_hi
        // unlatch register when reading tod low
        tod_latch_e <= (tod_latch_e | sel_todhi_i) & ~sel_todlo_i;
      end
      else if (~sel_alrm_i)
      begin
        // Write to TOD: any write stops, LSB write restarts
        tod_count_e <= sel_todlo_i;  // 1 if writing lo, 0 otherwise
      end
    end
  end

  // latch_o is used by the parent for bus output (free run)
  // updates when latch is disabled
  always @(posedge clk_i)
  begin
    if (~tod_latch_e)
      latch_o <= count_i;
  end

  // signals the parent that it can increment the tod counter
  // NOTE: even if cnt_o can count, the parent may not increment the tod
  // (in case a bus write is writing to the tod)
  assign cnt_o = tod_pls & tod_count_e;

  // combinatorial alarm check - allows interrupt one cycle earlier
  assign pls_o = cnt_i & (alrm_i == count_i);
endmodule
