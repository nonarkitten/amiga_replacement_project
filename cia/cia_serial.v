/*
 * CIA 8520 Serial Port Module
 * This module implements the bidirectional synchronous serial shift register
 * found in the MOS 8520. It handles both internal (Timer A) and external 
 * (CNT pin) clocking.
 *
 * Design Architecture:
 * - Shift Register: A 9-bit register is used. 
 * - In both Input and Output a stop bit is used to detect transmission has ended
 * - one clock cycle is required to setup the port in input or output mode.
 *
 * Sampling Coherency:
 *   The Serial Port input (sp_i) is sampled by the parent beside cnt_i.
 *
 * Clocking Phase:
 * - Internal state and shifting occur on the POSITIVE edge of clk_i.
 * - External output pins (cnt_o and sp_o) update on the NEGATIVE edge 
 * to ensure stable setup time for external hardware.
 *
 * Extension Features:
 * - Lookahead restart: In input mode, the module anticipates the 8th bit 
 * to remove "dead cycles" between transmissions.
 *
 * Timing:
 * - Output Baud Rate: (up to) Half the frequency of Timer A underflows (with fast extensions enabled in parent).
 * - Input Baud Rate: Determined by the external CNT clock frequency.
 */
module cia_serial(
    input clk_i, // master clock
    input rst_i, // reset input (active high)

    input  [7:0] dat_i, // data input (when in output mode)
    output [7:0] dat_o, // data output (when in input mode, always set to shift register contents)

    // cnt clock, parent handle synchronization (shared with timers A/B)
    input       unfl_i, // timer A underflow input (available at posedge)
    input       cnt_i,  // synchronized cnt input (sampled and available at posedge)
    output reg  cnt_o,  // cnt output, updated at negedge

    input      sp_i, // serial input (sampled with cnt)
    output reg sp_o, // serial output, updated at negedge

    input      spmd_i, // serial mode (0= input, 1=output)
    input      spoe_i, // output enable
    output reg spoe_o, // output acknowledge

    output     spo_o, // output data sent pulse
    output reg spi_o  // input data ready pulse
  );

  reg [8:0] shft;

  // serial input stuff
  reg spi_rdy; // strobe to signal that serial port is ready to receive data

  wire [8:0] spi_nxt = { shft[7:0], sp_i };
  wire       spi_done = spi_nxt[8];

  assign dat_o = shft[7:0];

  // serial output stuff
  reg cnt_d; // delayed cnt pin (computed at posedge for negedge)
  reg sp_d; // delayed sp pin (computed at posedge for negedge)

  reg  spo_rdy; // strobe to signal that serial port is ready to send data
  wire spo_pnd = spoe_i ^ spoe_o; // pending output data

  wire [8:0] spo_new = { dat_i, 1'b1 };
  wire [8:0] spo_nxt = { shft[7:0], 1'b0 };

  // spo_done indicates that the *next shift event* will transmit the final bit.
  // The next shift may occur several phi2 cycles later (Timer A driven).
  wire spo_done = ~(|spo_nxt[7:0]); // output data has been sent

  assign spo_o = spo_s[0] & ~spo_s[1];
  reg [1:0] spo_s;

  // always update output interrupt pulses
  always @(posedge clk_i)
  begin
    if (rst_i)
    begin
      spo_s <= 2'b11;
      spi_o <= 1'b0;
    end
    else
    begin
      spi_o <= spi_done & ~spmd_i & cnt_i;
      spo_s <= {spo_s[0], spo_rdy ? spo_done : 1'b1};
    end
  end

  // initialize shift register for input or output
  always @(posedge clk_i)
  begin
    if (rst_i)
    begin
      shft <= 9'b0;
      spi_rdy <= 1'b0;
      spo_rdy <= 1'b0;

      cnt_d <= 1'b1; // cnt_d is always reset to '1'
      sp_d <= 1'b0;

      spoe_o <= 1'b0;
    end
    else
    begin
      if (spmd_i)
      begin
        spi_rdy <= 1'b0;

        if (spo_rdy)
        begin
          if (unfl_i)
          begin
            if (cnt_d)
            begin
              if (spo_done)
              begin
                if (spo_pnd)
                begin
                  // data is pending, begin a new transmission
                  shft <= spo_new;
                  spoe_o <= spoe_i;

                  cnt_d <= ~cnt_d;
                  sp_d <= spo_new[8];
                end
                else
                begin
                  // no pending data, set the port to idle (all zero)
                  shft <= spo_nxt;
                end
              end
              else
              begin
                // last case, port is not idle nor done.
                // shift next bit and make it available to serial output pin
                shft <= spo_nxt;

                cnt_d <= ~cnt_d;
                sp_d <= spo_nxt[8];
              end
            end
            else
            begin
              cnt_d <= 1'b1;
            end
          end
        end
        else
        begin
          // initialize shift register to zero
          shft <= 9'b000000000;
          spo_rdy <= 1'b1;
        end
      end
      else
      begin
        // ensure that output is disabled and cnt is high
        spo_rdy <= 1'b0;
        cnt_d <= 1'b1;

        if (spi_rdy)
        begin
          if (cnt_i)
          begin
            // when receiving a cnt pulse, shift the buffer
            // and restart if last bit
            shft <= spi_nxt;

            // lookahead restart: if stop bit detected in next state,
            // restart transmission immediately (no dead cycle). The
            // parent MUST transfer dat_o to sdr BEFORE next bit comes in.
            spi_rdy <= ~spi_done;
          end
        end
        else
        begin
          if (cnt_i)
          begin
            // handle the special case where a cnt pulse comes during serial reset
            // This should not occur since cnt_i is a pulse and not a strobe.
            shft <= { 8'b00000001, sp_i };
          end
          else
          begin
            // setup serial port for receiving (add the stop bit)
            shft <= 9'b000000001;
          end

          spi_rdy <= 1'b1;
        end
      end
    end
  end

  always @(negedge clk_i)
  begin
    cnt_o <= cnt_d;
    sp_o <= sp_d;
  end
endmodule
