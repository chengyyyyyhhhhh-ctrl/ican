`timescale 1ns / 1ps

// 1024x768 median-filter wrapper intended for insertion immediately before
// the DDR write-side pixel packer.
//
// Input stream requirements:
//   * per_img_vsync is high for the complete active frame.
//   * per_img_valid is high for exactly 1024 pixels on each active line.
//   * each frame contains exactly 768 active lines.
//
// DDR-side mapping:
//   ddr_wr_load      -> ddr3_top.wr_load
//   ddr_datain_valid -> ddr3_top.datain_valid
//   ddr_datain       -> ddr3_top.datain
module median_filter_ddr_top #(
    parameter [10:0] IMG_HDISP = 11'd1024,
    parameter [10:0] IMG_VDISP = 11'd768
)(
    input  wire       pixel_clk,
    input  wire       rst_n,

    input  wire       per_img_vsync,
    input  wire       per_img_valid,
    input  wire [7:0] per_img_gray,

    output wire       ddr_wr_load,
    output wire       ddr_datain_valid,
    output wire [7:0] ddr_datain
);

    wire filtered_vsync;
    wire filtered_href;
    wire [7:0] filtered_gray;

    median_filter_proc #(
        .IMG_HDISP(IMG_HDISP),
        .IMG_VDISP(IMG_VDISP)
    ) u_median_filter (
        .clk            (pixel_clk),
        .rst_n          (rst_n),
        .per_img_vsync  (per_img_vsync),
        .per_img_href   (per_img_valid),
        .per_img_gray   (per_img_gray),
        .post_img_vsync (filtered_vsync),
        .post_img_href  (filtered_href),
        .post_img_gray  (filtered_gray)
    );

    assign ddr_wr_load      = filtered_vsync;
    assign ddr_datain_valid = filtered_href;
    assign ddr_datain       = filtered_gray;

endmodule

