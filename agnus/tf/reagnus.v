
module reagnus(
	       output [20:1] A,
	       input 	    AS_N,
	       input 	    BLISS_N,
	       input 	    CASL_N,
	       input 	    CASU_N,
	       input 	    CDAC_N,
	       input 	    CSYNC_N,
	       input 	    HSYNC_N,
	       input 	    INTR_N,
	       input 	    LDS_N,
	       input 	    UDS_N,
	       input 	    LPEN_N,
	       input 	    RAMEN_N,
	       input 	    RAS_N,
	       input 	    REGEN_N,
	       input 	    RESET_N,
	       input 	    VSYNC_N,
	       input 	    WE_N,
	       input 	    XCLKEN_N,
	       output 	    BUSEN,
	       input 	    BLIT,
	       input 	    CCK,
	       input 	    CCKQ,
	       input 	    CLK7M,
	       input 	    CLK28M,
	       input 	    DMAL, 
	       input [9:0]  DRA,
	       input [15:0] DRD,
	       input 	    PAL_NTSC,
	       input [8:1]  RGA,
	       input 	    RW
	       );


   assign A = {19'b1010_1010_1010_1010_101};
   assign BUSEN = 1'b0;
   

endmodule
