`timescale 1ns / 1ps

module cam_sdi (
    input  wire        BOARD_CLK_148M_P,  
    input  wire        BOARD_CLK_148M_N,  
    input  wire        SDI_RX_P,          
    input  wire        SDI_RX_N,          

    input  wire        clk_100m,         
    input  wire        sys_rst_n,          

    output wire        cam_clk,          // 74.25 MHz 
    output reg         cam_de,           
    output reg         cam_vsync,        // Active-frame indicator, high for active video lines
    output reg         cam_hsync,        
    output reg  [9:0]  cam_data_y,       
    output reg  [9:0]  cam_data_c,       
    output wire        sdi_locked         
);

    wire        sdi_rx_clk;               
    wire [19:0] gtx_rx_data_out;          
    wire        rx_mode_locked;           
    wire [10:0] rx_line_a;                
    wire [9:0]  rx_ds1a;                  
    wire [9:0]  rx_ds2a;                  
    wire        rx_eav;                   
    wire        rx_sav;                   
    wire        cpll_lock;
    wire        cpll_fbclk_lost;
    wire        gt_rx_fsm_reset_done;
    wire        gt_rx_reset_done;
    wire        rx_trs_dbg;
    wire        rx_t_locked_dbg;
         
    wire        sdi_core_rst;
    
    assign sdi_core_rst = (!sys_rst_n) || (!cpll_lock);

    assign cam_clk  = sdi_rx_clk;
    assign sdi_locked = rx_mode_locked;

    gtwizard_0 gtwizard_0_i (
        .q0_clk1_gtrefclk_pad_p_in  (BOARD_CLK_148M_P),
        .q0_clk1_gtrefclk_pad_n_in  (BOARD_CLK_148M_N),
        .sysclk_in                  (clk_100m),
        .gt0_gtxrxp_in              (SDI_RX_P),
        .gt0_gtxrxn_in              (SDI_RX_N),
        .gt0_rxusrclk2_out          (sdi_rx_clk),
        .gt0_rxdata_out             (gtx_rx_data_out),

        .soft_reset_rx_in           (!sys_rst_n),           
        .soft_reset_tx_in           (!sys_rst_n),
        .dont_reset_on_data_error_in(1'b1),
        .gt0_data_valid_in          (1'b1),
        .gt0_rxuserrdy_in           (1'b1),
        .gt0_rx_fsm_reset_done_out  (gt_rx_fsm_reset_done),
        .gt0_cplllock_out           (cpll_lock),

        .gt0_cpllreset_in(1'b0), .gt0_gtnorthrefclk0_in(1'b0), .gt0_gtnorthrefclk1_in(1'b0), .gt0_gtsouthrefclk0_in(1'b0), .gt0_gtsouthrefclk1_in(1'b0),
        .gt0_drpaddr_in(9'b0), .gt0_drpdi_in(16'b0), .gt0_drpen_in(1'b0), .gt0_drpwe_in(1'b0), .gt0_loopback_in(3'b000), .gt0_rxrate_in(3'b000),
        .gt0_eyescanreset_in(1'b0), .gt0_eyescantrigger_in(1'b0), .gt0_rxcdrhold_in(1'b0), .gt0_rxbufreset_in(1'b0), .gt0_rxdfelpmreset_in(1'b0),
        .gt0_rxmonitorsel_in(2'b00), .gt0_gtrxreset_in(1'b0), .gt0_rxpmareset_in(1'b0), .gt0_txpostcursor_in(5'b00000), .gt0_txprecursor_in(5'b00000),
        .gt0_gttxreset_in(1'b0), .gt0_txuserrdy_in(1'b1), .gt0_txrate_in(3'b000), .gt0_txdiffctrl_in(4'b0000), .gt0_txdata_in(20'b0),
        .gt0_txpcsreset_in(1'b0), .gt0_txpmareset_in(1'b0), .gt0_drpaddr_common_in(8'b0), .gt0_drpdi_common_in(16'b0), .gt0_drpen_common_in(1'b0), .gt0_drpwe_common_in(1'b0),

        .gt0_tx_fsm_reset_done_out(), .gt0_txusrclk_out(), .gt0_txusrclk2_out(), .gt0_rxusrclk_out(), .gt0_cpllfbclklost_out(cpll_fbclk_lost), .gt0_drpdo_out(),
        .gt0_drprdy_out(), .gt0_dmonitorout_out(), .gt0_eyescandataerror_out(), .gt0_rxbufstatus_out(), .gt0_rxmonitorout_out(), .gt0_rxratedone_out(),
        .gt0_rxoutclkfabric_out(), .gt0_rxresetdone_out(gt_rx_reset_done), .gt0_txbufstatus_out(), .gt0_gtxtxn_out(), .gt0_gtxtxp_out(), .gt0_txoutclkfabric_out(),
        .gt0_txoutclkpcs_out(), .gt0_txratedone_out(), .gt0_txresetdone_out(), .gt0_drpdo_common_out(), .gt0_drprdy_common_out(),
        .gt0_qplloutclk_out(), .gt0_qplloutrefclk_out()
    );

    v_smpte_sdi_0 v_smpte_sdi_0_i (
        .rx_rst                 (sdi_core_rst),           
        .rx_usrclk              (sdi_rx_clk),             
        .rx_data_in             (gtx_rx_data_out),        
        .rx_frame_en            (1'b1),                   
        .rx_mode_en             (3'b001),                 
        .rx_mode_detect_en      (1'b0),                   
        .rx_forced_mode         (2'b00),                  
        .rx_bit_rate            (1'b0),                   

        .rx_mode_locked         (rx_mode_locked),         
        .rx_line_a              (rx_line_a),              
        .rx_ds1a                (rx_ds1a),                
        .rx_ds2a                (rx_ds2a),                
        .rx_eav                 (rx_eav),                 
        .rx_sav                 (rx_sav),                 

        .rx_sd_data_in(10'b0), .rx_sd_data_strobe(1'b0), .rx_edh_errcnt_en(16'b0), .rx_edh_clr_errcnt(1'b0),
        .tx_rst(1'b1), .tx_usrclk(sdi_rx_clk), .tx_ce(3'b0), .tx_din_rdy(1'b0), .tx_mode(2'b0), .tx_level_b_3g(1'b0), 
        .tx_insert_crc(1'b0), .tx_insert_ln(1'b0), .tx_insert_edh(1'b0), .tx_insert_vpid(1'b0), .tx_overwrite_vpid(1'b0), 
        .tx_video_a_y_in(10'b0), .tx_video_a_c_in(10'b0), .tx_video_b_y_in(10'b0), .tx_video_b_c_in(10'b0), 
        .tx_line_a(11'b0), .tx_line_b(11'b0), .tx_vpid_byte1(8'b0), .tx_vpid_byte2(8'b0), .tx_vpid_byte3(8'b0), 
        .tx_vpid_byte4a(8'b0), .tx_vpid_byte4b(8'b0), .tx_vpid_line_f1(11'b0), .tx_vpid_line_f2(11'b0), 
        .tx_vpid_line_f2_en(1'b0), .tx_use_dsin(1'b0), .tx_ds1a_in(10'b0), .tx_ds2a_in(10'b0), .tx_ds1b_in(10'b0), 
        .tx_ds2b_in(10'b0), .tx_sd_bitrep_bypass(1'b0),

        .rx_trs(rx_trs_dbg), .rx_mode(), .rx_mode_hd(), .rx_mode_sd(), .rx_mode_3g(), .rx_t_locked(rx_t_locked_dbg), .rx_t_family(), 
        .rx_t_rate(), .rx_t_scan(), .rx_level_b_3g(), .rx_ce_sd(), .rx_nsp(), .rx_line_b(), .rx_a_vpid(), 
        .rx_a_vpid_valid(), .rx_b_vpid(), .rx_b_vpid_valid(), .rx_crc_err_a(), .rx_crc_err_b(), .rx_dout_rdy_3g(), 
        .rx_ds1b(), .rx_ds2b(), .rx_edh_ap(), .rx_edh_ff(), .rx_edh_anc(), .rx_edh_ap_flags(), .rx_edh_ff_flags(), 
        .rx_edh_anc_flags(), .rx_edh_packet_flags(), .rx_edh_errcnt(), .tx_ds1a_out(), .tx_ds2a_out(), 
        .tx_ds1b_out(), .tx_ds2b_out(), .tx_txdata(), .tx_ce_align_err()
    );

    wire line_active;
    assign line_active = (rx_line_a >= 11'd42) && (rx_line_a <= 11'd1121); 

    reg pixel_active; 
    always @(posedge sdi_rx_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            pixel_active <= 1'b0;
        end else if (rx_sav) begin
            pixel_active <= 1'b1; 
        end else if (rx_eav) begin
            pixel_active <= 1'b0;
        end
    end

    always @(posedge sdi_rx_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cam_de     <= 1'b0;
            cam_vsync  <= 1'b0;
            cam_hsync  <= 1'b0;
            cam_data_y <= 10'd0;
            cam_data_c <= 10'd0;
        end else if (rx_mode_locked) begin
            cam_de     <= pixel_active && line_active;
            // bilinear_interpolation expects vsync to stay high for the whole
            // active frame, rather than being a short vertical-sync pulse.
            cam_vsync  <= line_active;
            cam_hsync  <= !pixel_active;                               
            cam_data_y <= rx_ds1a;
            cam_data_c <= rx_ds2a;
        end else begin
            cam_de     <= 1'b0;
            cam_vsync  <= 1'b0;
            cam_hsync  <= 1'b0;
            cam_data_y <= 10'd0;
            cam_data_c <= 10'd0;
        end
    end 

endmodule
