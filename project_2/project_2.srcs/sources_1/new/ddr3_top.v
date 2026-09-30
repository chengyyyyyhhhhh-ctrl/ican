`timescale 1ns / 1ps

module ddr3_top(
    input  wire         sys_clk_p,
    input  wire         sys_clk_n,
    input  wire         sys_rst_n,
    input  wire         sys_init_done,

    input  wire [28:0]  app_addr_rd_min,
    input  wire [28:0]  app_addr_rd_max,
    input  wire [7:0]   rd_bust_len,
    input  wire [28:0]  app_addr_wr_min,
    input  wire [28:0]  app_addr_wr_max,
    input  wire [7:0]   wr_bust_len,
    input  wire [28:0]  app_addr_aux_wr_min,
    input  wire [28:0]  app_addr_aux_wr_max,
    input  wire [7:0]   aux_wr_bust_len,

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

    input  wire         ddr3_read_valid,
    input  wire         ddr3_pingpang_en,
    input  wire         wr_clk,
    input  wire         rd_clk,
    input  wire         datain_valid,
    input  wire [7:0]   datain,
    input  wire         aux_datain_valid,
    input  wire [7:0]   aux_datain,
    input  wire         rdata_req,
    input  wire         rd_load,
    input  wire         wr_load,
    input  wire         aux_wr_load,
    output wire [7:0]   dataout,
    output wire [1:0]   main_completed_page,
    output wire         main_completed_valid,
    output wire         aux_completed_page,
    output wire         aux_completed_valid,
    output wire         init_calib_complete
);

wire         ui_clk;
wire         ui_clk_sync_rst;
wire [28:0]  app_addr;
wire [2:0]   app_cmd;
wire         app_en;
wire         app_rdy;
wire [511:0] app_rd_data;
wire         app_rd_data_end;
wire         app_rd_data_valid;
wire [511:0] app_wdf_data;
wire         app_wdf_end;
wire [63:0]  app_wdf_mask;
wire         app_wdf_rdy;
wire         app_wdf_wren;
wire         app_sr_active;
wire         app_ref_ack;
wire         app_zq_ack;
wire         rfifo_wren;
wire [10:0]  wfifo_rcount;
wire [10:0]  aux_wfifo_rcount;
wire [10:0]  rfifo_wcount;
wire [511:0] wfifo_dout;
wire [511:0] aux_wfifo_dout;
wire         wfifo_rden;
wire         aux_wfifo_rden;
wire         write_data_aux;
wire         read_restart;

assign app_wdf_data = write_data_aux ? aux_wfifo_dout : wfifo_dout;

ddr3_rw u_ddr3_rw (
    .ui_clk              (ui_clk),
    .ui_clk_sync_rst     (ui_clk_sync_rst),
    .init_calib_complete (init_calib_complete),
    .app_rdy             (app_rdy),
    .app_wdf_rdy         (app_wdf_rdy),
    .app_rd_data_valid   (app_rd_data_valid),
    .wfifo_rcount        (wfifo_rcount),
    .aux_wfifo_rcount    (aux_wfifo_rcount),
    .rfifo_wcount        (rfifo_wcount),
    .rd_load             (rd_load),
    .wr_load             (wr_load),
    .app_addr_rd_min     (app_addr_rd_min),
    .app_addr_rd_max     (app_addr_rd_max),
    .rd_bust_len         (rd_bust_len),
    .app_addr_wr_min     (app_addr_wr_min),
    .app_addr_wr_max     (app_addr_wr_max),
    .wr_bust_len         (wr_bust_len),
    .app_addr_aux_wr_min (app_addr_aux_wr_min),
    .app_addr_aux_wr_max (app_addr_aux_wr_max),
    .aux_wr_bust_len     (aux_wr_bust_len),
    .ddr3_read_valid     (ddr3_read_valid),
    .ddr3_pingpang_en    (ddr3_pingpang_en),
    .rfifo_wren          (rfifo_wren),
    .wfifo_rden          (wfifo_rden),
    .aux_wfifo_rden      (aux_wfifo_rden),
    .write_data_aux      (write_data_aux),
    .main_completed_page (main_completed_page),
    .main_completed_valid(main_completed_valid),
    .aux_completed_page  (aux_completed_page),
    .aux_completed_valid (aux_completed_valid),
    .read_restart        (read_restart),
    .app_addr            (app_addr),
    .app_en              (app_en),
    .app_wdf_wren        (app_wdf_wren),
    .app_wdf_end         (app_wdf_end),
    .app_cmd             (app_cmd),
    .app_wdf_mask        (app_wdf_mask)
);

mig_7series_0 u_mig_7series_0 (
    .ddr3_addr           (ddr3_addr),
    .ddr3_ba             (ddr3_ba),
    .ddr3_cas_n          (ddr3_cas_n),
    .ddr3_ck_n           (ddr3_ck_n),
    .ddr3_ck_p           (ddr3_ck_p),
    .ddr3_cke            (ddr3_cke),
    .ddr3_ras_n          (ddr3_ras_n),
    .ddr3_reset_n        (ddr3_reset_n),
    .ddr3_we_n           (ddr3_we_n),
    .ddr3_dq             (ddr3_dq),
    .ddr3_dqs_n          (ddr3_dqs_n),
    .ddr3_dqs_p          (ddr3_dqs_p),
    .ddr3_cs_n           (ddr3_cs_n),
    .ddr3_dm             (ddr3_dm),
    .ddr3_odt            (ddr3_odt),
    .sys_clk_p           (sys_clk_p),
    .sys_clk_n           (sys_clk_n),
    .sys_rst             (sys_rst_n),
    .app_addr            (app_addr),
    .app_cmd             (app_cmd),
    .app_en              (app_en),
    .app_wdf_data        (app_wdf_data),
    .app_wdf_end         (app_wdf_end),
    .app_wdf_mask        (app_wdf_mask),
    .app_wdf_wren        (app_wdf_wren),
    .app_rd_data         (app_rd_data),
    .app_rd_data_end     (app_rd_data_end),
    .app_rd_data_valid   (app_rd_data_valid),
    .app_rdy             (app_rdy),
    .app_wdf_rdy         (app_wdf_rdy),
    .app_sr_req          (1'b0),
    .app_ref_req         (1'b0),
    .app_zq_req          (1'b0),
    .app_sr_active       (app_sr_active),
    .app_ref_ack         (app_ref_ack),
    .app_zq_ack          (app_zq_ack),
    .ui_clk              (ui_clk),
    .ui_clk_sync_rst     (ui_clk_sync_rst),
    .init_calib_complete (init_calib_complete),
    .device_temp         ()
);

ddr3_fifo_ctrl u_ddr3_fifo_ctrl (
    .rst_n        (sys_rst_n && sys_init_done && init_calib_complete),
    .wr_clk       (wr_clk),
    .rd_clk       (rd_clk),
    .clk_100      (ui_clk),
    .datain_valid (datain_valid),
    .datain       (datain),
    .aux_datain_valid(aux_datain_valid),
    .aux_datain   (aux_datain),
    .rfifo_din    (app_rd_data),
    .rdata_req    (rdata_req),
    .rfifo_wren   (rfifo_wren),
    .wfifo_rden   (wfifo_rden),
    .aux_wfifo_rden(aux_wfifo_rden),
    .rd_load      (read_restart),
    .wr_load      (wr_load),
    .aux_wr_load  (aux_wr_load),
    .wfifo_dout   (wfifo_dout),
    .wfifo_rcount (wfifo_rcount),
    .aux_wfifo_dout(aux_wfifo_dout),
    .aux_wfifo_rcount(aux_wfifo_rcount),
    .rfifo_wcount (rfifo_wcount),
    .pic_data     (dataout)
);

endmodule
