/*
 * CIA 8520 IRQ module
 * Handles interrupt flag accumulation and IRQ generation
 * 
 * Design notes:
 * - Interrupt flags are available on posedge phi2
 * - Interrupt flags are cleared on falling edge of clr_i
 * - IRQ output (irq_o) updates on posedge phi2 (parent module will handle IRQ delay to negedge)
 * - Parent module handles ICR register interface and mask management
 * 
 * Interrupt sources (bit positions):
 * - bit 0: Timer A underflow
 * - bit 1: Timer B underflow
 * - bit 2: TOD alarm
 * - bit 3: Serial port
 * - bit 4: FLAG pin
 */
module cia_irq(
    input clk_i,   // master clock
    input rst_i,   // reset input (active high)

    // interrupt source pulses (active on posedge)
    input ta_i,    // timer A underflow
    input tb_i,    // timer B underflow
    input alrm_i,  // TOD alarm
    input sp_i,    // serial port
    input flg_i,   // FLAG pin

    // control
    input [4:0] msk_i,  // interrupt mask from parent
    input       clr_i,  // clear strobe (on ICR read)

    // outputs
    output reg [4:0] icr_o, // interrupt flags
    output           irq_o  // IRQ active flag (active high)
  );

  // clr_i edge detection
  reg clr_r;
  wire clr_pls = clr_r & ~clr_i; // falling edge detector

  // masked interrupt flags
  wire [4:0] irq_w = icr_o & msk_i;

  // IRQ active if any masked interrupt is set
  assign irq_o = |irq_w;

  // clr_i synchronization and edge detection
  always @(posedge clk_i)
  begin
    if (rst_i)
      clr_r <= 1'b0;
    else
      clr_r <= clr_i;
  end

  // interrupt flag management (posedge)
  always @(posedge clk_i)
  begin
    if (rst_i)
    begin
      icr_o <= 5'b0;
    end
    else if (clr_pls)
    begin
      // clear flags but keep new interrupts occurring in same cycle
      icr_o <= { flg_i, sp_i, alrm_i, tb_i, ta_i };
    end
    else
    begin
      // accumulate interrupt flags
      icr_o <= icr_o | { flg_i, sp_i, alrm_i, tb_i, ta_i };
    end
  end
endmodule
