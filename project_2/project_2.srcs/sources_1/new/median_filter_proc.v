`timescale 1ns / 1ps

// Three-stage 3x3 median filter for an 8-bit monochrome stream. Border pixels
// pass through unchanged, preserving the exact input frame dimensions.
module median_filter_proc #(
    parameter [10:0] IMG_HDISP = 11'd640,
    parameter [10:0] IMG_VDISP = 11'd480
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       per_img_vsync,
    input  wire       per_img_href,
    input  wire [7:0] per_img_gray,
    output wire       post_img_vsync,
    output wire       post_img_href,
    output wire [7:0] post_img_gray
);

wire matrix_img_vsync;
wire matrix_img_href;
wire matrix_top_edge_flag;
wire matrix_bottom_edge_flag;
wire matrix_left_edge_flag;
wire matrix_right_edge_flag;
wire [7:0] matrix_p11, matrix_p12, matrix_p13;
wire [7:0] matrix_p21, matrix_p22, matrix_p23;
wire [7:0] matrix_p31, matrix_p32, matrix_p33;

Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP)
) u_matrix (
    .clk(clk),
    .rst_n(rst_n),
    .per_img_vsync(per_img_vsync),
    .per_img_href(per_img_href),
    .per_img_gray(per_img_gray),
    .matrix_img_vsync(matrix_img_vsync),
    .matrix_img_href(matrix_img_href),
    .matrix_top_edge_flag(matrix_top_edge_flag),
    .matrix_bottom_edge_flag(matrix_bottom_edge_flag),
    .matrix_left_edge_flag(matrix_left_edge_flag),
    .matrix_right_edge_flag(matrix_right_edge_flag),
    .matrix_p11(matrix_p11), .matrix_p12(matrix_p12),
    .matrix_p13(matrix_p13), .matrix_p21(matrix_p21),
    .matrix_p22(matrix_p22), .matrix_p23(matrix_p23),
    .matrix_p31(matrix_p31), .matrix_p32(matrix_p32),
    .matrix_p33(matrix_p33)
);

function [7:0] min3;
    input [7:0] a, b, c;
    begin
        min3 = (a <= b && a <= c) ? a
             : ((b <= a && b <= c) ? b : c);
    end
endfunction

function [7:0] max3;
    input [7:0] a, b, c;
    begin
        max3 = (a >= b && a >= c) ? a
             : ((b >= a && b >= c) ? b : c);
    end
endfunction

function [7:0] med3;
    input [7:0] a, b, c;
    begin
        if ((a >= b && a <= c) || (a <= b && a >= c))
            med3 = a;
        else if ((b >= a && b <= c) || (b <= a && b >= c))
            med3 = b;
        else
            med3 = c;
    end
endfunction

reg [7:0] row1_min, row1_med, row1_max;
reg [7:0] row2_min, row2_med, row2_max;
reg [7:0] row3_min, row3_med, row3_max;
reg [7:0] max_of_min, med_of_med, min_of_max;
reg [7:0] median_pixel;

always @(posedge clk) begin
    row1_min <= min3(matrix_p11, matrix_p12, matrix_p13);
    row1_med <= med3(matrix_p11, matrix_p12, matrix_p13);
    row1_max <= max3(matrix_p11, matrix_p12, matrix_p13);
    row2_min <= min3(matrix_p21, matrix_p22, matrix_p23);
    row2_med <= med3(matrix_p21, matrix_p22, matrix_p23);
    row2_max <= max3(matrix_p21, matrix_p22, matrix_p23);
    row3_min <= min3(matrix_p31, matrix_p32, matrix_p33);
    row3_med <= med3(matrix_p31, matrix_p32, matrix_p33);
    row3_max <= max3(matrix_p31, matrix_p32, matrix_p33);

    max_of_min <= max3(row1_min, row2_min, row3_min);
    med_of_med <= med3(row1_med, row2_med, row3_med);
    min_of_max <= min3(row1_max, row2_max, row3_max);

    median_pixel <= med3(max_of_min, med_of_med, min_of_max);
end

reg [2:0] vsync_pipe;
reg [2:0] href_pipe;
reg [2:0] edge_pipe;
reg [7:0] center_d0, center_d1, center_d2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vsync_pipe <= 3'b000;
        href_pipe  <= 3'b000;
        edge_pipe  <= 3'b000;
        center_d0  <= 8'd0;
        center_d1  <= 8'd0;
        center_d2  <= 8'd0;
    end else begin
        vsync_pipe <= {vsync_pipe[1:0], matrix_img_vsync};
        href_pipe  <= {href_pipe[1:0], matrix_img_href};
        edge_pipe  <= {edge_pipe[1:0], matrix_top_edge_flag |
                                           matrix_bottom_edge_flag |
                                           matrix_left_edge_flag |
                                           matrix_right_edge_flag};
        center_d0 <= matrix_p22;
        center_d1 <= center_d0;
        center_d2 <= center_d1;
    end
end

assign post_img_vsync = vsync_pipe[2];
assign post_img_href  = href_pipe[2];
assign post_img_gray  = edge_pipe[2] ? center_d2 : median_pixel;

endmodule
