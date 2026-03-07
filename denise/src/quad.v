module quad(
    input            clk,
    input            cck,
    input            cck_edge,
    input            load_test,
    input      [7:0] test,
    input            quad,
    output reg [7:0] data
);

reg        v;
reg        vq;
wire [1:0] d = { !vq, vq ^ v };

always @(posedge clk)
  if (cck_edge) begin
    if(load_test) begin
        data[7:0] <= test[7:0];

    end else begin
        if(cck) v <= quad; 
        else vq <= quad;

        if((data[1:0] == 2'b11) && (d == 2'b00)) 
            data[7:2] <= data[7:2] + 6'd1;
        if((data[1:0] == 2'b00) && (d == 2'b11)) 
            data[7:2] <= data[7:2] - 6'd1;
                
        data[1:0] <= d;
    end
  end
endmodule
