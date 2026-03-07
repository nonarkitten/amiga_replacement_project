// Copyright 2011, 2012 Frederic Requin
// Copyright 2024, 2025 Renee Cousins, The Buffee project, Inc
//  
// See README.md for details

///////////////////////////////
// Joystick/Mouse Quadrature //
///////////////////////////////

//              A    B
//   CCK        Low  High
// 1 Left Joy   Up   Left   M0V
// 2 Left Joy   Down Right  M0H
// 3 Right Joy  Up   Left   M1V
// 4 Right Joy  Down Right  M1H
//              V/H  VQ/HQ
//
// For compatibility, the signals should be brought into Denise
// using a similar method.
//
// Counting up           Couting Down
// V/H VQ/HQ  D1  D0     V/H VQ/HQ  D1  D0
//  0    0     1   0      0    0     1   0
//  1    0     1   1      0    1     0   1
//  1    1     0   0      1    1     0   0
//  0    1     0   1      1    0     1   1
//

// set_io [-nowarn] [-pullup yes|no] [-pullup_resistor 3P3K|6P8K|10K|100K] port pin

module JoyMouse (
    input          clk,             // master clock
    input          cck,             // CCK clock
    input          cck_edge,        // CCK edge

    input          w_rregs_joy0_p1, // RGA enable
    input          w_rregs_joy1_p1, // RGA enable
    input          w_wregs_joyw_p1, // RGA enable

    input          m0h,
    input          m0v,
    input          m1h,
    input          m1v,

	input 	[15:0] db_in,		    // bus data in
	output	[15:0] db_out,	   	    // bus data out
);

reg [7:0] r_m0v_data;
reg [7:0] r_m0h_data;
reg [7:0] r_m1v_data;
reg [7:0] r_m1h_data;

Quad m0v_quad(clk, cck, cck_edge, w_wregs_joyw_p1, db_in[15:8], m0v, r_m0v_data);
Quad m0h_quad(clk, cck, cck_edge, w_wregs_joyw_p1, db_in[7:0],  m0h, r_m0h_data);
Quad m1v_quad(clk, cck, cck_edge, w_wregs_joyw_p1, db_in[15:8], m1v, r_m1v_data);
Quad m1h_quad(clk, cck, cck_edge, w_wregs_joyw_p1, db_in[7:0],  m1h, r_m1h_data);

assign db_out = 
    (w_rregs_joy0_p1) ? { r_m0v_data, r_m0h_data } :
    (w_rregs_joy1_p1) ? { r_m1v_data, r_m1h_data } : 16'd0;

endmodule

module Quad(
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