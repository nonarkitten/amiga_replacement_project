`timescale 1ps/1ps

module quad(
    input            clk,
    input            cck,
    input            cck_edge,
    input            load_test,
    input      [7:0] test,
    input            data,
    output reg [7:0] counter
);

reg        v;
reg        vq;
wire [1:0] d = { !vq, vq ^ v };

always @(posedge clk)
  if (cck_edge) begin
    if(load_test) begin
        counter[7:0] <= test[7:0];

    end else begin
        if(!cck) v <= data; 
        else vq <= data;

        if((counter[1:0] == 2'b11) && (d == 2'b00)) 
            counter[7:2] <= counter[7:2] + 6'd1;
        if((counter[1:0] == 2'b00) && (d == 2'b11)) 
            counter[7:2] <= counter[7:2] - 6'd1;
                
        counter[1:0] <= d;
    end
  end
endmodule
