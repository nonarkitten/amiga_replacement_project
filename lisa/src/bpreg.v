module bpreg (
    input        C28M, // Bitplane Clock

    input [31:0] D,  // Parallel Data Inputs

    input        XF, // Transfer signal   
    input        SC, // Shift Control     

    input        LD, // Write Data signal 

    input        WD1, // Write Data signal
    input        WD2, // Write Data signal

    output       BP
);

    wire [65:0] si;

    bpbit bit00(D[0],  1'b0,   WD1, LD, XF, SC, si[0] );
    bpbit bit01(D[1],  si[0],  WD1, LD, XF, SC, si[1] );
    bpbit bit02(D[2],  si[1],  WD1, LD, XF, SC, si[2] );
    bpbit bit03(D[3],  si[2],  WD1, LD, XF, SC, si[3] );
    bpbit bit04(D[4],  si[3],  WD1, LD, XF, SC, si[4] );
    bpbit bit05(D[5],  si[4],  WD1, LD, XF, SC, si[5] );
    bpbit bit06(D[6],  si[5],  WD1, LD, XF, SC, si[6] );
    bpbit bit07(D[7],  si[6],  WD1, LD, XF, SC, si[7] );
    bpbit bit08(D[8],  si[7],  WD1, LD, XF, SC, si[8] );
    bpbit bit09(D[9],  si[8],  WD1, LD, XF, SC, si[9] );
    bpbit bit10(D[10], si[9],  WD1, LD, XF, SC, si[10]);
    bpbit bit11(D[11], si[10], WD1, LD, XF, SC, si[11]);
    bpbit bit12(D[12], si[11], WD1, LD, XF, SC, si[12]);
    bpbit bit13(D[13], si[12], WD1, LD, XF, SC, si[13]);
    bpbit bit14(D[14], si[13], WD1, LD, XF, SC, si[14]);
    bpbit bit15(D[15], si[14], WD1, LD, XF, SC, si[15]);
    bpbit bit16(D[16], si[15], WD1, LD, XF, SC, si[16]);
    bpbit bit17(D[17], si[16], WD1, LD, XF, SC, si[17]);
    bpbit bit18(D[18], si[17], WD1, LD, XF, SC, si[18]);
    bpbit bit19(D[19], si[18], WD1, LD, XF, SC, si[19]);
    bpbit bit20(D[20], si[19], WD1, LD, XF, SC, si[20]);
    bpbit bit21(D[21], si[20], WD1, LD, XF, SC, si[21]);
    bpbit bit22(D[22], si[21], WD1, LD, XF, SC, si[22]);
    bpbit bit23(D[23], si[22], WD1, LD, XF, SC, si[23]);
    bpbit bit24(D[24], si[23], WD1, LD, XF, SC, si[24]);
    bpbit bit25(D[25], si[24], WD1, LD, XF, SC, si[25]);
    bpbit bit26(D[26], si[25], WD1, LD, XF, SC, si[26]);
    bpbit bit27(D[27], si[26], WD1, LD, XF, SC, si[27]);
    bpbit bit28(D[28], si[27], WD1, LD, XF, SC, si[28]);
    bpbit bit29(D[29], si[28], WD1, LD, XF, SC, si[29]);
    bpbit bit30(D[30], si[29], WD1, LD, XF, SC, si[30]);
    bpbit bit31(D[31], si[30], WD1, LD, XF, SC, si[31]);
    bpbit bit32(D[0],  si[31], WD2, LD, XF, SC, si[32]);
    bpbit bit33(D[1],  si[32], WD2, LD, XF, SC, si[33]);
    bpbit bit34(D[2],  si[33], WD2, LD, XF, SC, si[34]);
    bpbit bit35(D[3],  si[34], WD2, LD, XF, SC, si[35]);
    bpbit bit36(D[4],  si[35], WD2, LD, XF, SC, si[36]);
    bpbit bit37(D[5],  si[36], WD2, LD, XF, SC, si[37]);
    bpbit bit38(D[6],  si[37], WD2, LD, XF, SC, si[38]);
    bpbit bit39(D[7],  si[38], WD2, LD, XF, SC, si[39]);
    bpbit bit40(D[8],  si[39], WD2, LD, XF, SC, si[40]);
    bpbit bit41(D[9],  si[40], WD2, LD, XF, SC, si[41]);
    bpbit bit42(D[10], si[41], WD2, LD, XF, SC, si[42]);
    bpbit bit43(D[11], si[42], WD2, LD, XF, SC, si[43]);
    bpbit bit44(D[12], si[43], WD2, LD, XF, SC, si[44]);
    bpbit bit45(D[13], si[44], WD2, LD, XF, SC, si[45]);
    bpbit bit46(D[14], si[45], WD2, LD, XF, SC, si[46]);
    bpbit bit47(D[15], si[46], WD2, LD, XF, SC, si[47]);
    bpbit bit48(D[16], si[47], WD2, LD, XF, SC, si[48]);
    bpbit bit49(D[17], si[48], WD2, LD, XF, SC, si[49]);
    bpbit bit50(D[18], si[49], WD2, LD, XF, SC, si[50]);
    bpbit bit51(D[19], si[50], WD2, LD, XF, SC, si[51]);
    bpbit bit52(D[20], si[51], WD2, LD, XF, SC, si[52]);
    bpbit bit53(D[21], si[52], WD2, LD, XF, SC, si[53]);
    bpbit bit54(D[22], si[53], WD2, LD, XF, SC, si[54]);
    bpbit bit55(D[23], si[54], WD2, LD, XF, SC, si[55]);
    bpbit bit56(D[24], si[55], WD2, LD, XF, SC, si[56]);
    bpbit bit57(D[25], si[56], WD2, LD, XF, SC, si[57]);
    bpbit bit58(D[26], si[57], WD2, LD, XF, SC, si[58]);
    bpbit bit59(D[27], si[58], WD2, LD, XF, SC, si[59]);
    bpbit bit60(D[28], si[59], WD2, LD, XF, SC, si[60]);
    bpbit bit61(D[29], si[60], WD2, LD, XF, SC, si[61]);
    bpbit bit62(D[30], si[61], WD2, LD, XF, SC, si[62]);

    bpmsb bit63(D[31], si[62], WD2, LD, XF, SC, C28M, si[63]);

    bpout bpout(si[63], C28M, si[64]);

    assign BP = si[64];

endmodule
