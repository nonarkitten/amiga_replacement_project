module channelmixer(
    input        clk,            // bus clock (3.58MHz)
    input [7:0]  sample0,        // sample 0 input
    input [7:0]  sample1,        // sample 1 input
    input [6:0]  vol0,           // volume 0 input
    input [6:0]  vol1,           // volume 1 input
    input        lfsr,           // pseudo-random bitstream or 0
    output reg   bitstream       // bitstream output
);
//--------------------------------------------------------------------------------------

    //local signals
    reg [8:0]    acc0;           // PDM channel 0 accumulator
    reg [8:0]    acc1;           // PDM channel 1 accumulator

    reg [5:0]    count;          // PWM counter
    reg          pwm0;           // PWM state
    reg          pwm1;           // PWM state

    reg [1:0]    out0;           // Channel output, -1 (00), Z (01) or +1 (10)
    reg [1:0]    out1;           // Channel output, -1 (00), Z (01) or +1 (10)

    always @(posedge clk) begin
        // PWM counter 0 to 63
        count <= count + 1;
        
             if(vol0[6])            pwm0 <= 1'b1; // PWM is always at maximum
        else if(vol0[5:0] == count) pwm0 <= 1'b0; // Reset when match occurs
        else if(count == 0)         pwm0 <= 1'b1; // Set when counter resets

        // add into our accumulator the absolute of the 7-bit part
        acc0 <= acc0[7:0] + ({ sample0[6:0], lfsr } ^ 8{ sample0[7] }) + acc0[8];
        
        // volume off, always high-z
        if (pwm0 == 1'b0) out0 <= 2'b01;
        // negative, toggle between high-Z and 0
        else if (sample0[7]) out0 <= acc0[8] ? 2'b00, 2'b01;
        // positive, toggle between high-Z and 1  
        else out0 <= acc0[8] ? 2'b10, 2'b01;
        
             if(vol1[6])            pwm1 <= 1'b1; // PWM is always at maximum
        else if(vol1[5:0] == count) pwm1 <= 1'b0; // Reset when match occurs
        else if(count == 0)         pwm1 <= 1'b1; // Set when counter resets

        // add into our accumulator the absolute of the 7-bit part
        acc1 <= acc1[7:0] + ({ sample1[6:0], lfsr } ^ 8{ sample1[7] }) + acc1[8];

        // volume off, always high-z
        if (pwm1 == 1'b0) out1 <= 2'b01;
        // negative, toggle between high-Z and 0
        else if (sample1[7]) out1 <= acc0[8] ? 2'b00, 2'b01;
        // positive, toggle between high-Z and 1  
        else out1 <= acc0[8] ? 2'b10, 2'b01;
                    
        // Mix the two channels into one tristate output
        // We sum two 0..2 and get 0..4 as an output
        // The levels 0, 2 and 4 will correspond to -1, Z and +1 respectively
        // The levels 1 and 3 prevent zero-crossing as a "weak" level change
        case (out0 + out1) begin
        // both are -1
        3'b000 : bitstream <= 1'b0; 
        // one is -1 and one is Z (weakly negative)
        3'b001 : bitstream <= (bitstream == 1'b1) ? 1'bZ : 1'b0;
        // both Z, or one is +1 and one is -1
        3'b010 : bitstream <= 1'bZ; 
        // one is +1 and one is Z (weakly positive)
        3'b011 : bitstream <= (bitstream == 1'b0) ? 1'bZ : 1'b1;
        // both are +1
        3'b100 : bitstream <= 1'b1; 
        endcase

    end
endmodule