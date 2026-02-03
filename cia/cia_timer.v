/*
 * CIA 8520 Timer module
 * Single timer (phi2) implementation
 * 
 * Design notes:
 * - fast reload (if frle_i asserted)
 * - when reloading the counter does not tick nor underflow
 * - early underflow detection allow interrupt delivery at the same cycle the underflow occurs
 * - underflow detection is the output of combinatorial used by counter logic
 * 
 * timing behavior:
 * - counter (cnt_o) updates on posedge phi2
 * - prb_o update on negedge phi2
 * - pls_o, run_o updates on posedge phi2
 * - unfl_o is meant to be used on phi2 posedge (early underflow detection)
 * 
 * PRB fast pulse (improvement over original CIA 8520 if fste_i asserted):
 *   When latch value is zero, consecutive underflows are detected, PRB
 *   pulse width is shortened to half phi2 period. fast pulse have a visible
 *   only if reload delay is suppressed
 * 
 */
module cia_timer(
    input clk_i, // master clock (phi2)
    input rst_i, // reset input (active high)

    // control inputs
    input cnt_i,  // counter tick strobe (1 = tick this phi2 cycle)
    input omd_i,  // output mode (0=pulse, 1=toggle)
    input str_i,  // start control from CRA/CRB (1=running, 0=stopped)
    input fld_i,  // force load strobe (1=reload from latch)

    // extended features
    input fste_i, // enable half pulses on port B
    input frle_i, // enable fast timer reload (no dead cycle)

    // register interface
    input      [15:0] lch_i, // timer latch (must be stable at rising phi2)
    output reg [15:0] cnt_o, // timer counter output (updated at rising phi2)

    // outputs
    output     run_o, // timer running flag
    output reg pls_o, // pulse output (1 phi2 period on underflow, set on posedge)
    output     prb_o, // port output (for PB6/PB7, set on negedge)
    output     unfl_o // signal that timer is underflowing (only valid at rising phi2)
  );

  // internal registers
  reg [1:0] run_s;  // running status sync (for toggle reset detection)
  reg [1:0] pls_s;  // pulse generator for PRB
  reg       tgl_r;  // toggle output state
  reg       fst_r;  // current prb pulse is short
  reg       frle_d; // delay after reload (or underflow)

  // tick_n waits for toggle output to be high
  wire   tick_n = (str_i & cnt_i) & ~frle_d & ~fld_i & run_s[1]; // counter should tick this cycle

  // unfl_o is asserted on the same posedge where the counter reloads,
  // allowing same-cycle IRQ and timer chaining
  assign unfl_o = tick_n & cnt_z; // counter will underflow on next posedge

  // return timer status
  assign run_o = |run_s; // report running until complete stop

  // counter arithmetic (inverted: increment instead of decrement)
  reg [16:0] cnt_n; // next counter value
  reg        cnt_z; // underflow

  always @(*)
  begin
    if (fld_i)
      // force load resets the counter
      cnt_n = {1'b0, lch_i};
    else
      cnt_n = cnt_o - tick_n;

    cnt_z = cnt_n[16]; // borrow out
  end

  // compute next value for toggle output
  reg tgl_n;

  always @(*)
  begin
    if (run_s[0] & ~run_s[1])
      // timer is starting, set toggle high
      tgl_n = 1'b1;
    else if (run_s[1])
      // Toggle on underflow if timer still running
      tgl_n = tgl_r ^ pls_o;
    else
      tgl_n = tgl_r;
  end

  // outputs
  wire   pls_w = pls_s[0] ^ pls_s[1];   // port pulse (can be half phi2 period if timer too fast)
  assign prb_o = omd_i ? tgl_r : pls_w; // port output

  // free run assignements without reset

  always @(posedge clk_i)
  begin
    // start run signal sync
    run_s[0] <= str_i;

    // save underflow flag for next negedge
    pls_o <= unfl_o;

    // save fast pulse mode
    // so stopping the timer when in fast mode won't produce full pulse.
    fst_r <= pls_o & unfl_o;

    // disable next clock after a reload
    // this only matters when clocked with phi2 (cnt_i always high)
    frle_d <= ~frle_i & (cnt_z | fld_i);
  end

  always @(negedge clk_i)
  begin
    run_s[1] <= run_s[0]; // end run signal sync
  end

  // end of free run blocks

  // main counter logic (on phi2 posedge)
  always @(posedge clk_i)
  begin
    if (rst_i)
    begin
      pls_s[0] <= 1'b0;
      cnt_o <= 16'hffff;
    end
    else
    begin
      // update output with next counter computed value
      cnt_o <= cnt_z ? lch_i : cnt_n[15:0];

      // fast mode detection: if we underflowed in both previous and current phi2 cycle,
      // shorten the pulse by syncing pls_s[0] (happens after counter reload above)
      // in case of 'force load 0' prb pulse remains short.
      if (fste_i & (fst_r | (pls_o & unfl_o)))
      begin
        pls_s[0] <= pls_s[1];
      end
    end
  end

  // underflow pulse (negedge)
  always @(negedge clk_i)
  begin
    if (rst_i)
    begin
      pls_s[1] <= 1'b0;
    end
    else
    begin
      pls_s[1] <= pls_o ^ pls_s[0]; // generate pulse for PRB
    end
  end

  // toggle output (negedge)
  always @(negedge clk_i)
  begin
    if (rst_i)
    begin
      tgl_r <= 1'b1;
    end
    else
    begin
      tgl_r <= tgl_n;
    end
  end
endmodule
