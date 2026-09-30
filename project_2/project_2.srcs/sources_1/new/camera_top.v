`timescale 1ns / 1ps

// SDI 1920x1080 Y -> parallel 1024x768 and 256x256 scalers. The 1024x768
// stream is triple-buffered for HDMI, while the 256x256 stream is stored in
// a separate DDR3 region reserved for NPU processing.
module camera_top (
    input  wire         clk_100m,
    input  wire         sys_rst,

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

localparam [28:0] FRAME_ADDR_SPAN = 29'd98304;
localparam [7:0]  LINE_BURST_LEN  = 8'd16;
// Each 256x256 page occupies 8192 MIG address units (64 KiB). The auxiliary
// writer uses two consecutive pages: byte offsets 0x240000 and 0x250000.
localparam [28:0] NPU_FRAME_ADDR_MIN = 29'd294912;
localparam [28:0] NPU_FRAME_ADDR_MAX = 29'd303104;
localparam [7:0]  NPU_BURST_LEN      = 8'd16;

wire pixel_clk;
wire pixel_clk_5x;
wire hdmi_clk_locked;
wire clkfb;
wire clkfb_buf;
wire pixel_clk_mmcm;
wire pixel_clk_5x_mmcm;
wire tmds_oen_unused;
wire hpdout_unused;
wire sys_rst_n    = ~sys_rst;
wire global_rst_n = sys_rst_n && hdmi_clk_locked;

// 100 MHz -> 650 MHz VCO -> 65 MHz pixel clock and 325 MHz serializer clock.
MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(10.000),
    .DIVCLK_DIVIDE(1),
    .CLKFBOUT_MULT_F(6.500),
    .CLKOUT0_DIVIDE_F(10.000),
    .CLKOUT1_DIVIDE(2),
    .STARTUP_WAIT("FALSE")
) u_hdmi_mmcm (
    .CLKIN1(clk_100m),
    .CLKFBIN(clkfb_buf),
    .RST(~sys_rst_n),
    .PWRDWN(1'b0),
    .CLKFBOUT(clkfb),
    .CLKFBOUTB(),
    .CLKOUT0(pixel_clk_mmcm),
    .CLKOUT1(pixel_clk_5x_mmcm),
    .CLKOUT0B(),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .LOCKED(hdmi_clk_locked)
);

BUFG u_clkfb_buf (
    .I(clkfb),
    .O(clkfb_buf)
);

BUFG u_pixel_clk_buf (
    .I(pixel_clk_mmcm),
    .O(pixel_clk)
);

BUFG u_pixel_clk_5x_buf (
    .I(pixel_clk_5x_mmcm),
    .O(pixel_clk_5x)
);

wire        cam_clk;
wire        cam_de;
wire        cam_vsync;
wire        cam_hsync;
wire [9:0]  cam_data_y;
wire [9:0]  cam_data_c;

cam_sdi u_cam_sdi (
    .BOARD_CLK_148M_P(BOARD_CLK_148M_P),
    .BOARD_CLK_148M_N(BOARD_CLK_148M_N),
    .SDI_RX_P(SDI_RX_P),
    .SDI_RX_N(SDI_RX_N),
    .clk_100m(clk_100m),
    .sys_rst_n(global_rst_n),
    .cam_clk(cam_clk),
    .cam_de(cam_de),
    .cam_vsync(cam_vsync),
    .cam_hsync(cam_hsync),
    .cam_data_y(cam_data_y),
    .cam_data_c(cam_data_c),
    .sdi_locked(sdi_locked)
);

wire       scaled_vsync;
wire       scaled_href;
wire       scaled_valid;
wire [7:0] scaled_y;
wire       filtered_vsync;
wire       filtered_href;
wire [7:0] filtered_y;
wire       npu_scaled_vsync;
wire       npu_scaled_href;
wire       npu_scaled_valid;
wire [7:0] npu_scaled_y;

wire       video_rst_n = global_rst_n && sdi_locked;

bilinear_interpolation #(
    .C_SRC_IMG_WIDTH(11'd1920),
    .C_SRC_IMG_HEIGHT(11'd1080),
    .C_DST_IMG_WIDTH(11'd1024),
    .C_DST_IMG_HEIGHT(11'd768),
    .C_X_RATIO(19'd122880),
    .C_Y_RATIO(19'd92160)
) u_bilinear_interpolation (
    .clk_in1(cam_clk),
    .clk_in2(pixel_clk),
    .rst_n(video_rst_n),
    .per_img_valid(cam_de),
    .per_img_vsync(cam_vsync),
    .per_img_href(cam_de),
    .per_img_gray(cam_data_y[9:2]),
    .post_img_vsync(scaled_vsync),
    .post_img_href(scaled_href),
    .post_img_gray(scaled_y),
    .post_img_valid(scaled_valid)
);

// Apply the 3x3 median filter to the complete 1024x768 stream before DDR.
// Border pixels pass through unchanged, so every frame still contains exactly
// 1024*768 samples and remains aligned with the DDR frame-page boundaries.
median_filter_proc #(
    .IMG_HDISP(11'd1024),
    .IMG_VDISP(11'd768)
) u_display_median_filter (
    .clk(pixel_clk),
    .rst_n(video_rst_n),
    .per_img_vsync(scaled_vsync),
    .per_img_href(scaled_valid),
    .per_img_gray(scaled_y),
    .post_img_vsync(filtered_vsync),
    .post_img_href(filtered_href),
    .post_img_gray(filtered_y)
);

bilinear_interpolation #(
    .C_SRC_IMG_WIDTH(11'd1920),
    .C_SRC_IMG_HEIGHT(11'd1080),
    .C_DST_IMG_WIDTH(11'd256),
    .C_DST_IMG_HEIGHT(11'd256),
    .C_X_RATIO(19'd491520),
    .C_Y_RATIO(19'd276480)
) u_npu_bilinear_interpolation (
    .clk_in1(cam_clk),
    .clk_in2(pixel_clk),
    .rst_n(video_rst_n),
    .per_img_valid(cam_de),
    .per_img_vsync(cam_vsync),
    .per_img_href(cam_de),
    .per_img_gray(cam_data_y[9:2]),
    .post_img_vsync(npu_scaled_vsync),
    .post_img_href(npu_scaled_href),
    .post_img_gray(npu_scaled_y),
    .post_img_valid(npu_scaled_valid)
);

wire [7:0] ddr_y;
wire [1:0] main_ddr_completed_page;
wire       main_ddr_completed_valid;
wire       npu_ddr_completed_page;
wire       npu_ddr_completed_valid;
wire       hdmi_vsync;
wire       hdmi_hsync;
wire       hdmi_de;
wire       hdmi_data_req;
wire [10:0] hdmi_h_disp;
wire [10:0] hdmi_v_disp;
wire [10:0] hdmi_xpos;
wire [10:0] hdmi_ypos;
wire [15:0] hdmi_gray_rgb565 = {ddr_y[7:3], ddr_y[7:2], ddr_y[7:3]};

ddr3_top u_ddr3_top (
    .sys_clk_p(sys_clk_p),
    .sys_clk_n(sys_clk_n),
    .sys_rst_n(global_rst_n),
    .sys_init_done(1'b1),
    .app_addr_rd_min(29'd0),
    .app_addr_rd_max(FRAME_ADDR_SPAN),
    .rd_bust_len(LINE_BURST_LEN),
    .app_addr_wr_min(29'd0),
    .app_addr_wr_max(FRAME_ADDR_SPAN),
    .wr_bust_len(LINE_BURST_LEN),
    .app_addr_aux_wr_min(NPU_FRAME_ADDR_MIN),
    .app_addr_aux_wr_max(NPU_FRAME_ADDR_MAX),
    .aux_wr_bust_len(NPU_BURST_LEN),
    .ddr3_dq(ddr3_dq),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_addr(ddr3_addr),
    .ddr3_ba(ddr3_ba),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_cs_n(ddr3_cs_n),
    .ddr3_dm(ddr3_dm),
    .ddr3_odt(ddr3_odt),
    .ddr3_read_valid(1'b1),
    .ddr3_pingpang_en(1'b1),
    .wr_clk(pixel_clk),
    .rd_clk(pixel_clk),
    .datain_valid(filtered_href),
    .datain(filtered_y),
    .aux_datain_valid(npu_scaled_valid),
    .aux_datain(npu_scaled_y),
    .rdata_req(hdmi_data_req),
    .rd_load(hdmi_vsync),
    .wr_load(filtered_vsync),
    .aux_wr_load(npu_scaled_vsync),
    .dataout(ddr_y),
    .main_completed_page(main_ddr_completed_page),
    .main_completed_valid(main_ddr_completed_valid),
    .aux_completed_page(npu_ddr_completed_page),
    .aux_completed_valid(npu_ddr_completed_valid),
    .init_calib_complete(init_calib_complete)
);

hdmi_top u_hdmi_top (
    .pixel_clk(pixel_clk),
    .pixel_clk_5x(pixel_clk_5x),
    .sys_rst_n(global_rst_n && init_calib_complete),
    .hpdin(hpdin),
    .tmds_clk_p(tmds_clk_p),
    .tmds_clk_n(tmds_clk_n),
    .tmds_data_p(tmds_data_p),
    .tmds_data_n(tmds_data_n),
    .tmds_oen(tmds_oen_unused),
    .hpdout(hpdout_unused),
    .video_hs_i(hdmi_hsync),
    .video_vs_i(hdmi_vsync),
    .video_de_i(hdmi_de),
    .video_vs(hdmi_vsync),
    .video_hs(hdmi_hsync),
    .video_de(hdmi_de),
    .h_disp(hdmi_h_disp),
    .v_disp(hdmi_v_disp),
    .pixel_xpos(hdmi_xpos),
    .pixel_ypos(hdmi_ypos),
    .data_in(hdmi_gray_rgb565),
    .data_req(hdmi_data_req)
);

wire unused_cam_hsync = cam_hsync;
wire [9:0] unused_cam_data_c = cam_data_c;
wire unused_scaled_href = scaled_href;
wire unused_npu_scaled_href = npu_scaled_href;
wire [4:0] unused_completed_page_status = {
    main_ddr_completed_page,
    main_ddr_completed_valid,
    npu_ddr_completed_page,
    npu_ddr_completed_valid
};

endmodule
