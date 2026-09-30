`timescale 1ns / 1ps

module Matrix_Generate_3X3_8Bit #(
    parameter [10:0] IMG_HDISP = 11'd640,
    parameter [10:0] IMG_VDISP = 11'd480,
    parameter [10:0] DELAY_NUM = 11'd10
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       per_img_vsync,
    input  wire       per_img_href,
    input  wire [7:0] per_img_gray,
    output wire       matrix_img_vsync,
    output wire       matrix_img_href,
    output wire       matrix_top_edge_flag,
    output wire       matrix_bottom_edge_flag,
    output wire       matrix_left_edge_flag,
    output wire       matrix_right_edge_flag,
    output reg  [7:0] matrix_p11,
    output reg  [7:0] matrix_p12,
    output reg  [7:0] matrix_p13,
    output reg  [7:0] matrix_p21,
    output reg  [7:0] matrix_p22,
    output reg  [7:0] matrix_p23,
    output reg  [7:0] matrix_p31,
    output reg  [7:0] matrix_p32,
    output reg  [7:0] matrix_p33
);

reg [10:0] hcnt;
reg [10:0] vcnt;
reg        per_img_href_dly;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        hcnt <= 11'd0;
    else if (per_img_href)
        hcnt <= hcnt + 1'b1;
    else
        hcnt <= 11'd0;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        per_img_href_dly <= 1'b0;
    else
        per_img_href_dly <= per_img_href;
end

wire img_href_neg = !per_img_href && per_img_href_dly;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        vcnt <= 11'd0;
    else if (!per_img_vsync)
        vcnt <= 11'd0;
    else if (img_href_neg)
        vcnt <= vcnt + 1'b1;
end

// Emit one synthetic final line after the source frame so the bottom border
// is produced without borrowing pixels from the following frame.
reg [10:0] extend_last_row_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        extend_last_row_cnt <= 11'd0;
    else if (per_img_href && vcnt == IMG_VDISP-1'b1 &&
             hcnt == IMG_HDISP-1'b1)
        extend_last_row_cnt <= 11'd1;
    else if (extend_last_row_cnt > 0 &&
             extend_last_row_cnt < DELAY_NUM + IMG_HDISP)
        extend_last_row_cnt <= extend_last_row_cnt + 1'b1;
    else
        extend_last_row_cnt <= 11'd0;
end

wire extend_last_row_en = extend_last_row_cnt > DELAY_NUM;

// Clear both line-buffer pointers after the final extension pixel has been
// sampled. The next frame therefore always begins at line-buffer address zero.
wire line_fifo_frame_done =
    (extend_last_row_cnt == DELAY_NUM + IMG_HDISP);
wire line_fifo_rst = ~rst_n || line_fifo_frame_done;

wire [7:0] fifo1_rdata;
wire [7:0] fifo2_rdata;
wire fifo1_wenb = per_img_href;
wire fifo1_renb = (per_img_href && vcnt > 0) || extend_last_row_en;
wire fifo2_wenb = per_img_href && vcnt > 0;
wire fifo2_renb = (per_img_href && vcnt > 1) || extend_last_row_en;

sync_fifo #(
    .C_FIFO_WIDTH(8),
    .C_FIFO_DEPTH(IMG_HDISP)
) u_fifo1 (
    .rst(line_fifo_rst), .clk(clk),
    .wr_en(fifo1_wenb), .din(per_img_gray), .full(),
    .rd_en(fifo1_renb), .dout(fifo1_rdata), .empty(), .data_count()
);

sync_fifo #(
    .C_FIFO_WIDTH(8),
    .C_FIFO_DEPTH(IMG_HDISP)
) u_fifo2 (
    .rst(line_fifo_rst), .clk(clk),
    .wr_en(fifo2_wenb), .din(fifo1_rdata), .full(),
    .rd_en(fifo2_renb), .dout(fifo2_rdata), .empty(), .data_count()
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        {matrix_p11, matrix_p12, matrix_p13} <= 24'd0;
        {matrix_p21, matrix_p22, matrix_p23} <= 24'd0;
        {matrix_p31, matrix_p32, matrix_p33} <= 24'd0;
    end else begin
        {matrix_p11, matrix_p12, matrix_p13} <=
            {matrix_p12, matrix_p13, fifo2_rdata};
        {matrix_p21, matrix_p22, matrix_p23} <=
            {matrix_p22, matrix_p23, fifo1_rdata};
        {matrix_p31, matrix_p32, matrix_p33} <=
            {matrix_p32, matrix_p33, per_img_gray};
    end
end

reg [1:0] vsync;
reg [1:0] href;
reg [1:0] top_edge_flag;
reg [1:0] bottom_edge_flag;
reg [1:0] left_edge_flag;
reg [1:0] right_edge_flag;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        vsync <= 2'b00;
    else begin
        if (per_img_href && vcnt == 1 && hcnt == 0)
            vsync[0] <= 1'b1;
        else if (!per_img_vsync && extend_last_row_cnt == 0)
            vsync[0] <= 1'b0;
        vsync[1] <= vsync[0];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        href             <= 2'b00;
        top_edge_flag    <= 2'b00;
        bottom_edge_flag <= 2'b00;
        left_edge_flag   <= 2'b00;
        right_edge_flag  <= 2'b00;
    end else begin
        href[0] <= (per_img_href && vcnt > 0) || extend_last_row_en;
        top_edge_flag[0] <= per_img_href && vcnt == 1;
        bottom_edge_flag[0] <= extend_last_row_en;
        left_edge_flag[0] <= (per_img_href && vcnt > 0 && hcnt == 0)
                          || (extend_last_row_cnt == DELAY_NUM + 1'b1);
        right_edge_flag[0] <=
            (per_img_href && vcnt > 0 && hcnt == IMG_HDISP-1'b1)
            || (extend_last_row_cnt == DELAY_NUM + IMG_HDISP);
        href[1]             <= href[0];
        top_edge_flag[1]    <= top_edge_flag[0];
        bottom_edge_flag[1] <= bottom_edge_flag[0];
        left_edge_flag[1]   <= left_edge_flag[0];
        right_edge_flag[1]  <= right_edge_flag[0];
    end
end

assign matrix_img_vsync        = vsync[1];
assign matrix_img_href         = href[1];
assign matrix_top_edge_flag    = top_edge_flag[1];
assign matrix_bottom_edge_flag = bottom_edge_flag[1];
assign matrix_left_edge_flag   = left_edge_flag[1];
assign matrix_right_edge_flag  = right_edge_flag[1];

endmodule
