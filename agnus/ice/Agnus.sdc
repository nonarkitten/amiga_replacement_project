set_multicycle_path -setup -from [get_registers *\|clocks_gen*\|cck]                 -to [get_registers Agnus*\|r_*] 3
set_multicycle_path -hold  -from [get_registers *\|clocks_gen*\|cck]                 -to [get_registers Agnus*\|r_*] 2

# Address decoding (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_rga_p4*]            -to [get_registers regs_decode*\|r_?regs_*_p1] 12
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_rga_p4*]            -to [get_registers regs_decode*\|r_?regs_*_p1] 11
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_rga_p4*]            -to [get_registers regs_decode*\|r_rga_p1*] 12
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_rga_p4*]            -to [get_registers regs_decode*\|r_rga_p1*] 11

# Register memory write (latched on CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_rga_p1*]             -to [get_registers Agnus*\|r_regs_wr_p2] 12
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_rga_p1*]             -to [get_registers Agnus*\|r_regs_wr_p2] 11
set_multicycle_path -setup -from [get_registers regs_decode*\|r_rga_p1*]             -to [get_registers Agnus*\|r_rga_p2*] 12
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_rga_p1*]             -to [get_registers Agnus*\|r_rga_p2*] 11
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_db_in*] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_db_in*] 11

# DMACON register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_dmac_p1]       -to [get_registers Agnus*\|r_*EN] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_dmac_p1]       -to [get_registers Agnus*\|r_*EN] 23
#set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_dmac_p1]       -to [get_registers Agnus*\|r_BLTPRI] 24
#set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_dmac_p1]       -to [get_registers Agnus*\|r_BLTPRI] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_*EN] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_*EN] 11
#set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_BLTPRI] 12
#set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_BLTPRI] 11

# FMODE register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_fmod_p1]       -to [get_registers Agnus*\|r_BSTMODE*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_fmod_p1]       -to [get_registers Agnus*\|r_BSTMODE*] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_BSTMODE*] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_BSTMODE*] 11

# BEAMCON register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_beam_p1]       -to [get_registers Agnus*\|r_PAL] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_beam_p1]       -to [get_registers Agnus*\|r_PAL] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_PAL] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_PAL] 11

# BPLCON0 register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_bplc_p1*]      -to [get_registers Agnus*\|r_BPLCON0*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_bplc_p1*]      -to [get_registers Agnus*\|r_BPLCON0*] 23
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_bplc_p1*]      -to [get_registers Agnus*\|r_LACE] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_bplc_p1*]      -to [get_registers Agnus*\|r_LACE] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_BPLCON0*] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_BPLCON0*] 11
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_LACE] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_LACE] 11

# DIWSTRT register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_diwb_p1]       -to [get_registers Agnus*\|r_VDIWSTRT*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_diwb_p1]       -to [get_registers Agnus*\|r_VDIWSTRT*] 23
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_diwh_p1]       -to [get_registers Agnus*\|r_VDIWSTRT*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_diwh_p1]       -to [get_registers Agnus*\|r_VDIWSTRT*] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_VDIWSTRT*] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_VDIWSTRT*] 11

# DIWSTOP register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_diwe_p1]       -to [get_registers Agnus*\|r_VDIWSTOP*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_diwe_p1]       -to [get_registers Agnus*\|r_VDIWSTOP*] 23
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_diwh_p1]       -to [get_registers Agnus*\|r_VDIWSTOP*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_diwh_p1]       -to [get_registers Agnus*\|r_VDIWSTOP*] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_VDIWSTOP*] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_VDIWSTOP*] 11

# Vertical display window enable (latched on CCK = 0 and CDAC rise)
set_multicycle_path -setup -from [get_registers *\|beam_ctr*\|r_vpos_ctr*]           -to [get_registers Agnus*\|r_vdiw_soft_ena] 24
set_multicycle_path -hold  -from [get_registers *\|beam_ctr*\|r_vpos_ctr*]           -to [get_registers Agnus*\|r_vdiw_soft_ena] 23
set_multicycle_path -setup -from [get_registers Agnus*\|r_VDIWSTRT*]                 -to [get_registers Agnus*\|r_vdiw_soft_ena] 12
set_multicycle_path -hold  -from [get_registers Agnus*\|r_VDIWSTRT*]                 -to [get_registers Agnus*\|r_vdiw_soft_ena] 11
set_multicycle_path -setup -from [get_registers Agnus*\|r_VDIWSTOP*]                 -to [get_registers Agnus*\|r_vdiw_soft_ena] 12
set_multicycle_path -hold  -from [get_registers Agnus*\|r_VDIWSTOP*]                 -to [get_registers Agnus*\|r_vdiw_soft_ena] 11
set_multicycle_path -setup -from [get_registers Agnus*\|r_vdiw_soft_ena]             -to [get_registers Agnus*\|r_vdiw_ena] 24
set_multicycle_path -hold  -from [get_registers Agnus*\|r_vdiw_soft_ena]             -to [get_registers Agnus*\|r_vdiw_ena] 23
set_multicycle_path -setup -from [get_registers *\|beam_ctr*\|r_str_fsm*]            -to [get_registers Agnus*\|r_vdiw_ena] 24
set_multicycle_path -hold  -from [get_registers *\|beam_ctr*\|r_str_fsm*]            -to [get_registers Agnus*\|r_vdiw_ena] 23

# DDFSTRT register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_ddfb_p1]       -to [get_registers Agnus*\|r_DDFSTRT*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_ddfb_p1]       -to [get_registers Agnus*\|r_DDFSTRT*] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_DDFSTRT*] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_DDFSTRT*] 11

# DDFSTOP register (latched on CCK = 1 and CDAC rise)
set_multicycle_path -setup -from [get_registers regs_decode*\|r_wregs_ddfe_p1]       -to [get_registers Agnus*\|r_DDFSTOP*] 24
set_multicycle_path -hold  -from [get_registers regs_decode*\|r_wregs_ddfe_p1]       -to [get_registers Agnus*\|r_DDFSTOP*] 23
set_multicycle_path -setup -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_DDFSTOP*] 12
set_multicycle_path -hold  -from [get_registers *\|cache_ram*\|altsyncram*\|*\|q_a*] -to [get_registers Agnus*\|r_DDFSTOP*] 11

# Display data fetch enable (latched on CCK = 0 and CDAC rise)
set_multicycle_path -setup -from [get_registers *\|beam_ctr*\|r_hpos_ctr*]           -to [get_registers Agnus*\|r_ddf_soft_ena] 24
set_multicycle_path -hold  -from [get_registers *\|beam_ctr*\|r_hpos_ctr*]           -to [get_registers Agnus*\|r_ddf_soft_ena] 23
set_multicycle_path -setup -from [get_registers Agnus*\|r_DDFSTRT*]                  -to [get_registers Agnus*\|r_ddf_soft_ena] 12
set_multicycle_path -hold  -from [get_registers Agnus*\|r_DDFSTRT*]                  -to [get_registers Agnus*\|r_ddf_soft_ena] 11
set_multicycle_path -setup -from [get_registers Agnus*\|r_DDFSTOP*]                  -to [get_registers Agnus*\|r_ddf_soft_ena] 12
set_multicycle_path -hold  -from [get_registers Agnus*\|r_DDFSTOP*]                  -to [get_registers Agnus*\|r_ddf_soft_ena] 11
set_multicycle_path -setup -from [get_registers *\|beam_ctr*\|r_hpos_ctr*]           -to [get_registers Agnus*\|r_ddf_hard_ena] 24
set_multicycle_path -hold  -from [get_registers *\|beam_ctr*\|r_hpos_ctr*]           -to [get_registers Agnus*\|r_ddf_hard_ena] 23
set_multicycle_path -setup -from [get_registers Agnus*\|r_vdiw_ena]                  -to [get_registers Agnus*\|r_ddf_hard_ena] 24
set_multicycle_path -hold  -from [get_registers Agnus*\|r_vdiw_ena]                  -to [get_registers Agnus*\|r_ddf_hard_ena] 23

# Address computation (latched on CCK = 0 and CDAC rise)
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_dma_cop_p3]         -to [get_registers Agnus*\|r_addr_out*] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_dma_cop_p3]         -to [get_registers Agnus*\|r_addr_out*] 23
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_cop_pc*]            -to [get_registers Agnus*\|r_addr_out*] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_cop_pc*]            -to [get_registers Agnus*\|r_addr_out*] 23
set_multicycle_path -setup -from [get_registers *\|cust_regs_mp*\|ptr_rd_val*]       -to [get_registers Agnus*\|r_addr_out*] 6
set_multicycle_path -hold  -from [get_registers *\|cust_regs_mp*\|ptr_rd_val*]       -to [get_registers Agnus*\|r_addr_out*] 5

set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_dma_cop_p3]         -to [get_registers Agnus*\|r_cache_hit] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_dma_cop_p3]         -to [get_registers Agnus*\|r_cache_hit] 23
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_cop_hit]            -to [get_registers Agnus*\|r_cache_hit] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_cop_hit]            -to [get_registers Agnus*\|r_cache_hit] 23
set_multicycle_path -setup -from [get_registers Agnus*\|r_BSTMODE*]                  -to [get_registers Agnus*\|r_cache_hit] 12
set_multicycle_path -hold  -from [get_registers Agnus*\|r_BSTMODE*]                  -to [get_registers Agnus*\|r_cache_hit] 11
set_multicycle_path -setup -from [get_registers *\|cust_regs_mp*\|ptr_rd_val[0]]     -to [get_registers Agnus*\|r_cache_hit] 6
set_multicycle_path -hold  -from [get_registers *\|cust_regs_mp*\|ptr_rd_val[0]]     -to [get_registers Agnus*\|r_cache_hit] 5
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_dsk_we_p3]          -to [get_registers Agnus*\|r_cache_hit] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_dsk_we_p3]          -to [get_registers Agnus*\|r_cache_hit] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_rga_blt_p3*]          -to [get_registers Agnus*\|r_cache_hit] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_rga_blt_p3*]          -to [get_registers Agnus*\|r_cache_hit] 23
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_bst_ena_p3]         -to [get_registers Agnus*\|r_cache_hit] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_bst_ena_p3]         -to [get_registers Agnus*\|r_cache_hit] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_dma_blt_p3]           -to [get_registers Agnus*\|r_cache_hit] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_dma_blt_p3]           -to [get_registers Agnus*\|r_cache_hit] 23

set_multicycle_path -setup -from [get_registers *\|blitter*\|r_last_cyc_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_last_cyc_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_fpix_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_fpix_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_mod_rd_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_mod_rd_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_ptr_rd_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_ptr_rd_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_pinc_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_pinc_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_pdec_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_pdec_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_madd_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_madd_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_msub_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_msub_blt_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|cust_regs_mp*\|ptr_rd_val*]       -to [get_registers Agnus*\|r_flush_line] 6
set_multicycle_path -hold  -from [get_registers *\|cust_regs_mp*\|ptr_rd_val*]       -to [get_registers Agnus*\|r_flush_line] 5
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_bst_ena_p3]         -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_bst_ena_p3]         -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_dma_blt_p3]           -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_dma_blt_p3]           -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers Agnus*\|r_BSTMODE*]                  -to [get_registers Agnus*\|r_flush_line] 12
set_multicycle_path -hold  -from [get_registers Agnus*\|r_BSTMODE*]                  -to [get_registers Agnus*\|r_flush_line] 11
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_dsk_we_p3]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_dsk_we_p3]          -to [get_registers Agnus*\|r_flush_line] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_rga_blt_p3*]          -to [get_registers Agnus*\|r_flush_line] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_rga_blt_p3*]          -to [get_registers Agnus*\|r_flush_line] 23

set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_dsk_we_p3]          -to [get_registers Agnus*\|r_bus_we] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_dsk_we_p3]          -to [get_registers Agnus*\|r_bus_we] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_rga_blt_p3*]          -to [get_registers Agnus*\|r_bus_we] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_rga_blt_p3*]          -to [get_registers Agnus*\|r_bus_we] 23

set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_mod_rd_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_mod_rd_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 23
set_multicycle_path -setup -from [get_registers *\|dma_sched*\|r_ptr_rd_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 24
set_multicycle_path -hold  -from [get_registers *\|dma_sched*\|r_ptr_rd_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_pinc_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_pinc_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_pdec_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_pdec_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_madd_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_madd_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 23
set_multicycle_path -setup -from [get_registers *\|blitter*\|r_msub_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 24
set_multicycle_path -hold  -from [get_registers *\|blitter*\|r_msub_blt_p3]          -to [get_registers Agnus*\|r_ptr_wr_val*] 23
set_multicycle_path -setup -from [get_registers *\|cust_regs_mp*\|ptr_rd_val*]       -to [get_registers Agnus*\|r_ptr_wr_val*] 6
set_multicycle_path -hold  -from [get_registers *\|cust_regs_mp*\|ptr_rd_val*]       -to [get_registers Agnus*\|r_ptr_wr_val*] 5
set_multicycle_path -setup -from [get_registers *\|cust_regs_mp*\|mod_rd_val*]       -to [get_registers Agnus*\|r_ptr_wr_val*] 3
set_multicycle_path -hold  -from [get_registers *\|cust_regs_mp*\|mod_rd_val*]       -to [get_registers Agnus*\|r_ptr_wr_val*] 2
