// Copyright 2011, 2012 Frederic Requin
// Copyright 2024, 2025 Renee Cousins, The Buffee project, Inc
//  
// See README.md for details

///////////////////////////////
// Collision Detection       //
///////////////////////////////

module Collision (
    input          clk,            // master clock
    input          cck_pos_edge,   // bus clock / lores pixel clock

    input          w_wregs_clx_p1,
    input          w_rregs_clx_p1,

	input 	[15:0] db_in,		   // bus data in
	output	[15:0] db_out,	   	   // bus data out
	input	 [5:0] bpl_data,	   // bitplane serial video data in
	input	[15:0] spr_data_flat   // sprite data
);

reg   [3:0] r_ENSP;
reg   [5:0] r_ENBP;
reg   [5:0] r_MVBP;

wire [14:0] w_CLXDAT;
reg  [14:0] r_CLXDAT;


always@(posedge clk) begin
  if (cck_pos_edge) begin
    if (w_wregs_clx_p1) begin
      r_ENSP <= db_in[15:12];
      r_ENBP <= db_in[11:6];
      r_MVBP <= db_in[5:0];
    end
    if (w_rregs_clx_p1) begin
        r_CLXDAT <= 0;
    end else begin
        r_CLXDAT <= r_CLXDAT | w_CLXDAT;
    end
  end
end

assign db_out = w_rregs_clx_p1 ? r_CLXDAT : 16'd0;

// Unpack sprite data
wire [1:0] spr_data [0:7];
assign {spr_data[7],spr_data[6],spr_data[5],spr_data[4],
        spr_data[3],spr_data[2],spr_data[1],spr_data[0]} = spr_data_flat;

// Sprite groups        
wire [3:0] w_spr_clx;
assign w_spr_clx[0] = ((|spr_data[0]) | (|spr_data[1])) & r_ENSP[0];
assign w_spr_clx[1] = ((|spr_data[2]) | (|spr_data[3])) & r_ENSP[1];
assign w_spr_clx[2] = ((|spr_data[4]) | (|spr_data[5])) & r_ENSP[2];
assign w_spr_clx[3] = ((|spr_data[6]) | (|spr_data[7])) & r_ENSP[3];

// Bitplane match
wire [5:0] w_bpl_clx = (bpl_data ^ ~r_MVBP) | (~r_ENBP);

// Odd and even bitplanes match
wire   w_odd_clx  = w_bpl_clx[0] | w_bpl_clx[2] | w_bpl_clx[4];
wire   w_even_clx = w_bpl_clx[1] | w_bpl_clx[3] | w_bpl_clx[5];

// Sprites-sprites collisions
assign w_CLXDAT[14] = w_spr_clx[2] & w_spr_clx[3]; // Sprites #4 and #6
assign w_CLXDAT[13] = w_spr_clx[1] & w_spr_clx[3]; // Sprites #2 and #6
assign w_CLXDAT[12] = w_spr_clx[1] & w_spr_clx[2]; // Sprites #2 and #4
assign w_CLXDAT[11] = w_spr_clx[0] & w_spr_clx[3]; // Sprites #0 and #6
assign w_CLXDAT[10] = w_spr_clx[0] & w_spr_clx[2]; // Sprites #0 and #4
assign w_CLXDAT[9]  = w_spr_clx[0] & w_spr_clx[1]; // Sprites #0 and #2
// Sprites-bitplanes collisions
assign w_CLXDAT[8]  = w_even_clx   & w_spr_clx[3]; // Even and Sprite #6
assign w_CLXDAT[7]  = w_even_clx   & w_spr_clx[2]; // Even and Sprite #4
assign w_CLXDAT[6]  = w_even_clx   & w_spr_clx[1]; // Even and Sprite #2
assign w_CLXDAT[5]  = w_even_clx   & w_spr_clx[0]; // Even and Sprite #0
assign w_CLXDAT[4]  = w_odd_clx    & w_spr_clx[3]; // Odd and Sprite #6
assign w_CLXDAT[3]  = w_odd_clx    & w_spr_clx[2]; // Odd and Sprite #4
assign w_CLXDAT[2]  = w_odd_clx    & w_spr_clx[1]; // Odd and Sprite #2
assign w_CLXDAT[1]  = w_odd_clx    & w_spr_clx[0]; // Odd and Sprite #0
// Bitplanes-bitplanes collisions
assign w_CLXDAT[0]  = w_odd_clx    & w_even_clx;

endmodule