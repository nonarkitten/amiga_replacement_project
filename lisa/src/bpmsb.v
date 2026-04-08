/* verilator lint_off LATCH */
/* verilator lint_off UNOPTFLAT */

module bpmsb (
    input      D,  // Parallel Data Inputs
    input      SI, // Shift Input

    input      WD, // Write Data signal    I$4
    input      LD, // Write Data signal    I$13
    input      XF, // Transfer signal      I$7
    input      SC, // Shift Control        I$17
    input      BP, // Bitplane Clock
    
    output reg SO  // Shift Output buffer  I$21
);
    reg        LR; // Latch "register"     I$5/I$6
    reg        XR; // Transfer "register"  I$10/I$11

    always @(*) begin
        // WD is triggered on each BPLDATx load
        if (WD) LR = D; 

        // XF (XFER in BPLCON.v) is triggered on BPLDAT1 load
        if (XF && ~LD) XR = LR;
        // SC is controlled by PF match; LD has to allow
        else if (SC && LD) XR = SI;
        // else latch
        
        // SO will output XR if LD and SC allow it
        if (BP) SO = XR;
    end

endmodule

/* verilator lint_on LATCH */
/* verilator lint_on UNOPTFLAT */
