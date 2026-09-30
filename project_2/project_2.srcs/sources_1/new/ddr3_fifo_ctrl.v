`timescale 1ns / 1ps

// Pixel-clock/UI-clock bridges for the native 512-bit MIG interface.
// DDR stores one 8-bit Y sample per byte, so one MIG beat contains 64 pixels.
module ddr3_fifo_ctrl(
    input  wire         rst_n,
    input  wire         wr_clk,
    input  wire         rd_clk,
    input  wire         clk_100,
    input  wire         datain_valid,
    input  wire [7:0]   datain,
    input  wire         aux_datain_valid,
    input  wire [7:0]   aux_datain,
    input  wire [511:0] rfifo_din,
    input  wire         rdata_req,
    input  wire         rfifo_wren,
    input  wire         wfifo_rden,
    input  wire         aux_wfifo_rden,
    input  wire         rd_load,
    input  wire         wr_load,
    input  wire         aux_wr_load,
    output wire [511:0] wfifo_dout,
    output wire [10:0]  wfifo_rcount,
    output wire [511:0] aux_wfifo_dout,
    output wire [10:0]  aux_wfifo_rcount,
    output wire [10:0]  rfifo_wcount,
    output reg  [7:0]   pic_data
);

reg  [511:0] pixel_pack;
reg  [5:0]   pack_count;
reg  [511:0] aux_pixel_pack;
reg  [5:0]   aux_pack_count;
reg  [5:0]   unpack_count;

wire [511:0] wfifo_din;
wire [511:0] aux_wfifo_din;
wire [511:0] rfifo_dout;
wire         wfifo_full;
wire         wfifo_empty;
wire         aux_wfifo_full;
wire         aux_wfifo_empty;
wire         rfifo_full;
wire         rfifo_empty;
wire         wfifo_wr_rst_busy;
wire         wfifo_rd_rst_busy;
wire         aux_wfifo_wr_rst_busy;
wire         aux_wfifo_rd_rst_busy;
wire         rfifo_wr_rst_busy;
wire         rfifo_rd_rst_busy;
wire         wfifo_wren;
wire         aux_wfifo_wren;
wire         rfifo_rden;
wire         pixel_read_valid;

// Wait for the first complete 1024x768 output frame after FIFO reset. MIG may
// finish calibration while the scaler is already in the middle of a frame;
// accepting pixels immediately would permanently splice two camera frames at
// a fixed horizontal line in every DDR page.
reg wr_load_d;
reg main_frame_armed;
reg main_stream_started;

wire main_frame_start = main_frame_armed && wr_load && !wr_load_d;
wire main_pack_valid = datain_valid &&
                       (main_stream_started || main_frame_start);

// The FIFO samples wfifo_din on the same edge as the 64th input pixel.
assign wfifo_din = {pixel_pack[503:0], datain};
assign wfifo_wren = main_pack_valid && (pack_count == 6'd63) &&
                    !wfifo_full && !wfifo_wr_rst_busy;

always @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_load_d           <= 1'b0;
        main_frame_armed    <= 1'b0;
        main_stream_started <= 1'b0;
        pixel_pack          <= 512'd0;
        pack_count          <= 6'd0;
    end else begin
        wr_load_d <= wr_load;

        if (!wr_load)
            main_frame_armed <= 1'b1;

        if (main_frame_start) begin
            main_stream_started <= 1'b1;
            pixel_pack          <= 512'd0;
            pack_count          <= 6'd0;
        end

        if (main_pack_valid) begin
            pixel_pack <= wfifo_din;
            pack_count <= (pack_count == 6'd63)
                        ? 6'd0 : pack_count + 1'b1;
        end
    end
end

// Wait for the first complete 256x256 output frame after FIFO reset. MIG may
// finish calibration while the scaler is already in the middle of a frame;
// starting immediately would permanently rotate the image in DDR.
reg aux_wr_load_d;
reg aux_frame_armed;
reg aux_stream_started;

wire aux_frame_start = aux_frame_armed && aux_wr_load && !aux_wr_load_d;
wire aux_pack_valid = aux_datain_valid &&
                      (aux_stream_started || aux_frame_start);

assign aux_wfifo_din = {aux_pixel_pack[503:0], aux_datain};
assign aux_wfifo_wren = aux_pack_valid && (aux_pack_count == 6'd63) &&
                        !aux_wfifo_full && !aux_wfifo_wr_rst_busy;

always @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
        aux_wr_load_d      <= 1'b0;
        aux_frame_armed    <= 1'b0;
        aux_stream_started <= 1'b0;
        aux_pixel_pack     <= 512'd0;
        aux_pack_count     <= 6'd0;
    end else begin
        aux_wr_load_d <= aux_wr_load;

        if (!aux_wr_load)
            aux_frame_armed <= 1'b1;

        if (aux_frame_start)
            aux_stream_started <= 1'b1;

        if (aux_pack_valid) begin
            aux_pixel_pack <= aux_wfifo_din;
            aux_pack_count <= (aux_pack_count == 6'd63)
                            ? 6'd0 : aux_pack_count + 1'b1;
        end
    end
end

// Generate a reset window only when the scheduler actually changes the DDR
// display page. Replaying the same page needs no reset and stays continuously
// aligned because one HDMI active frame consumes exactly one stored frame.
(* ASYNC_REG = "TRUE" *) reg rd_load_meta;
(* ASYNC_REG = "TRUE" *) reg rd_load_sync;
reg        rd_load_sync_d;
reg [4:0]  rd_fifo_rst_count;

always @(posedge clk_100 or negedge rst_n) begin
    if (!rst_n) begin
        rd_load_meta      <= 1'b0;
        rd_load_sync      <= 1'b0;
        rd_load_sync_d    <= 1'b0;
        rd_fifo_rst_count <= 5'd0;
    end else begin
        rd_load_meta   <= rd_load;
        rd_load_sync   <= rd_load_meta;
        rd_load_sync_d <= rd_load_sync;

        if (rd_load_sync && !rd_load_sync_d)
            rd_fifo_rst_count <= 5'd31;
        else if (rd_fifo_rst_count != 5'd0)
            rd_fifo_rst_count <= rd_fifo_rst_count - 1'b1;
    end
end

wire rd_fifo_frame_rst = (rd_fifo_rst_count != 5'd0);

// FWFT mode keeps the current 512-bit word visible. Pop the word only after
// its final (64th) Y sample has been consumed.
assign pixel_read_valid = rdata_req && !rfifo_empty && !rfifo_rd_rst_busy;
assign rfifo_rden = pixel_read_valid && (unpack_count == 6'd63);

always @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
        pic_data     <= 8'd0;
        unpack_count <= 6'd0;
    end else if (rfifo_rd_rst_busy) begin
        pic_data     <= 8'd0;
        unpack_count <= 6'd0;
    end else if (pixel_read_valid) begin
        pic_data <= rfifo_dout[511 - unpack_count * 8 -: 8];
        unpack_count <= (unpack_count == 6'd63) ? 6'd0 : unpack_count + 1'b1;
    end else if (rfifo_empty) begin
        pic_data <= 8'd0;
    end
end

// The write FIFO crosses from the scaler clock to the MIG UI clock.
xpm_fifo_async #(
    .CDC_SYNC_STAGES(2),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("block"),
    .FIFO_READ_LATENCY(0),
    .FIFO_WRITE_DEPTH(1024),
    .FULL_RESET_VALUE(1),
    .PROG_EMPTY_THRESH(10),
    .PROG_FULL_THRESH(1014),
    .RD_DATA_COUNT_WIDTH(11),
    .READ_DATA_WIDTH(512),
    .READ_MODE("fwft"),
    .RELATED_CLOCKS(0),
    .USE_ADV_FEATURES("0707"),
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH(512),
    .WR_DATA_COUNT_WIDTH(11)
) u_write_fifo (
    .rst(~rst_n),
    .wr_clk(wr_clk),
    .wr_en(wfifo_wren),
    .din(wfifo_din),
    .full(wfifo_full),
    .almost_full(),
    .prog_full(),
    .overflow(),
    .wr_ack(),
    .wr_data_count(),
    .wr_rst_busy(wfifo_wr_rst_busy),
    .rd_clk(clk_100),
    .rd_en(wfifo_rden && !wfifo_empty && !wfifo_rd_rst_busy),
    .dout(wfifo_dout),
    .empty(wfifo_empty),
    .almost_empty(),
    .prog_empty(),
    .underflow(),
    .data_valid(),
    .rd_data_count(wfifo_rcount),
    .rd_rst_busy(wfifo_rd_rst_busy),
    .sbiterr(),
    .dbiterr(),
    .sleep(1'b0),
    .injectsbiterr(1'b0),
    .injectdbiterr(1'b0)
);

// The NPU stream uses its own FIFO so it can never consume or reorder HDMI
// frame data. Both write FIFOs are drained independently by the MIG scheduler.
xpm_fifo_async #(
    .CDC_SYNC_STAGES(2),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("block"),
    .FIFO_READ_LATENCY(0),
    .FIFO_WRITE_DEPTH(1024),
    .FULL_RESET_VALUE(1),
    .PROG_EMPTY_THRESH(10),
    .PROG_FULL_THRESH(1014),
    .RD_DATA_COUNT_WIDTH(11),
    .READ_DATA_WIDTH(512),
    .READ_MODE("fwft"),
    .RELATED_CLOCKS(0),
    .USE_ADV_FEATURES("0707"),
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH(512),
    .WR_DATA_COUNT_WIDTH(11)
) u_aux_write_fifo (
    .rst(~rst_n),
    .wr_clk(wr_clk),
    .wr_en(aux_wfifo_wren),
    .din(aux_wfifo_din),
    .full(aux_wfifo_full),
    .almost_full(),
    .prog_full(),
    .overflow(),
    .wr_ack(),
    .wr_data_count(),
    .wr_rst_busy(aux_wfifo_wr_rst_busy),
    .rd_clk(clk_100),
    .rd_en(aux_wfifo_rden && !aux_wfifo_empty &&
           !aux_wfifo_rd_rst_busy),
    .dout(aux_wfifo_dout),
    .empty(aux_wfifo_empty),
    .almost_empty(),
    .prog_empty(),
    .underflow(),
    .data_valid(),
    .rd_data_count(aux_wfifo_rcount),
    .rd_rst_busy(aux_wfifo_rd_rst_busy),
    .sbiterr(),
    .dbiterr(),
    .sleep(1'b0),
    .injectsbiterr(1'b0),
    .injectdbiterr(1'b0)
);

// The read FIFO crosses from the MIG UI clock to the HDMI pixel clock.
xpm_fifo_async #(
    .CDC_SYNC_STAGES(2),
    .DOUT_RESET_VALUE("0"),
    .ECC_MODE("no_ecc"),
    .FIFO_MEMORY_TYPE("block"),
    .FIFO_READ_LATENCY(0),
    .FIFO_WRITE_DEPTH(1024),
    .FULL_RESET_VALUE(1),
    .PROG_EMPTY_THRESH(10),
    .PROG_FULL_THRESH(1014),
    .RD_DATA_COUNT_WIDTH(11),
    .READ_DATA_WIDTH(512),
    .READ_MODE("fwft"),
    .RELATED_CLOCKS(0),
    .USE_ADV_FEATURES("0707"),
    .WAKEUP_TIME(0),
    .WRITE_DATA_WIDTH(512),
    .WR_DATA_COUNT_WIDTH(11)
) u_read_fifo (
    .rst(~rst_n | rd_fifo_frame_rst),
    .wr_clk(clk_100),
    .wr_en(rfifo_wren && !rfifo_full && !rfifo_wr_rst_busy),
    .din(rfifo_din),
    .full(rfifo_full),
    .almost_full(),
    .prog_full(),
    .overflow(),
    .wr_ack(),
    .wr_data_count(rfifo_wcount),
    .wr_rst_busy(rfifo_wr_rst_busy),
    .rd_clk(rd_clk),
    .rd_en(rfifo_rden),
    .dout(rfifo_dout),
    .empty(rfifo_empty),
    .almost_empty(),
    .prog_empty(),
    .underflow(),
    .data_valid(),
    .rd_data_count(),
    .rd_rst_busy(rfifo_rd_rst_busy),
    .sbiterr(),
    .dbiterr(),
    .sleep(1'b0),
    .injectsbiterr(1'b0),
    .injectdbiterr(1'b0)
);

endmodule
