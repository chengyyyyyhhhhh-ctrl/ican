`timescale 1ns / 1ps

module atop(
    input           clk_100m,    
    input           rst_p,      
    input           iis_sd_x,   
    input           iis_sd_y,   
    output          iis_sck,    
    output          iis_ws,     
    output          motor_stp, 
    output          motor_dir, 
    output          motor_en,
    output          o_uart_tx,
    
    input  wire         BOARD_CLK_148M_P,
    input  wire         BOARD_CLK_148M_N,
    input  wire         SDI_RX_P,
    input  wire         SDI_RX_N,

    input  wire         sys_clk_p,
    input  wire         sys_clk_n,
    inout  wire [63:0]  ddr3_dq,
    inout  wire [7:0]   ddr3_dqs_n,
    inout  wire [7:0]   ddr3_dqs_p,
    output wire [14:0]  ddr3_addr,
    output wire [2:0]   ddr3_ba,
    output wire         ddr3_ras_n,
    output wire         ddr3_cas_n,
    output wire         ddr3_we_n,
    output wire         ddr3_reset_n,
    output wire [0:0]   ddr3_ck_p,
    output wire [0:0]   ddr3_ck_n,
    output wire [0:0]   ddr3_cke,
    output wire [0:0]   ddr3_cs_n,
    output wire [7:0]   ddr3_dm,
    output wire [0:0]   ddr3_odt,

    input  wire         hpdin,
    output wire         tmds_clk_p,
    output wire         tmds_clk_n,
    output wire [2:0]   tmds_data_p,
    output wire [2:0]   tmds_data_n,

    output wire         sdi_locked,
    output wire         init_calib_complete
);

//top u_top(
//.clk_100m (clk_100m ),
//.rst_p    (rst_p    ),
//.iis_sd_x (iis_sd_x ),
//.iis_sd_y (iis_sd_y ),
//.iis_sck  (iis_sck  ),
//.iis_ws   (iis_ws   ),
//.motor_stp(motor_stp),
//.motor_dir(motor_dir),
//.motor_en (motor_en ),
//.o_uart_tx(o_uart_tx)
//);

camera_top u_camera_top(
.clk_100m           (clk_100m           ),
.sys_rst            (rst_p              ),
.BOARD_CLK_148M_P   (BOARD_CLK_148M_P   ),
.BOARD_CLK_148M_N   (BOARD_CLK_148M_N   ),
.SDI_RX_P           (SDI_RX_P           ),
.SDI_RX_N           (SDI_RX_N           ),                
.sys_clk_p          (sys_clk_p          ),
.sys_clk_n          (sys_clk_n          ),
.ddr3_dq            (ddr3_dq            ),
.ddr3_dqs_n         (ddr3_dqs_n         ),
.ddr3_dqs_p         (ddr3_dqs_p         ),
.ddr3_addr          (ddr3_addr          ),
.ddr3_ba            (ddr3_ba            ),
.ddr3_ras_n         (ddr3_ras_n         ),
.ddr3_cas_n         (ddr3_cas_n         ),
.ddr3_we_n          (ddr3_we_n          ),
.ddr3_reset_n       (ddr3_reset_n       ),
.ddr3_ck_p          (ddr3_ck_p          ),
.ddr3_ck_n          (ddr3_ck_n          ),
.ddr3_cke           (ddr3_cke           ),
.ddr3_cs_n          (ddr3_cs_n          ),
.ddr3_dm            (ddr3_dm            ),
.ddr3_odt           (ddr3_odt           ),                
.hpdin              (hpdin              ),
.tmds_clk_p         (tmds_clk_p         ),
.tmds_clk_n         (tmds_clk_n         ),
.tmds_data_p        (tmds_data_p        ),
.tmds_data_n        (tmds_data_n        ),                 
.sdi_locked         (sdi_locked         ),
.init_calib_complete(init_calib_complete)
);

endmodule
