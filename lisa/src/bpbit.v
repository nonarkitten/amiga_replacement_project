/* verilator lint_off LATCH */
/* verilator lint_off UNOPTFLAT */

module bpbit (
    input      D,  // Parallel Data Inputs
    input      SI, // Shift Input

    input      WD, // Write Data signal    I$77
    input      LD, // Write Data signal    I$17
    input      XF, // Transfer signal      I$37
    input      SC, // Shift Control        I$20
    
    output reg SO  // Shift Output buffer  I$82
);
    reg        LR; // Latch "register"     I$78/I$79
    reg        XR; // Tansfer "register"   I$74/I$76

    always @(*) begin
        // WD is triggered on each BPLDATx load
        if (WD) LR = D; 

        // XF (XFER in BPLCON.v) is triggered on BPLDAT1 load
        if (XF && ~LD) XR = LR;
        // SC is controlled by PF match; LD has to allow
        else if (SC && LD) XR = SI;
        // else latch
        
        // SO will output XR if LD and SC allow it
        if (~SC && LD) SO = XR;
    end

endmodule

/* verilator lint_on LATCH */
/* verilator lint_on UNOPTFLAT */
