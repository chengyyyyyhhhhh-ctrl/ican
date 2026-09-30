`timescale 1ns / 1ps

module top(

    input           clk_100m,    
    input           rst_p,      
    input           iis_sd_x,   
    input           iis_sd_y,   
    output          iis_sck,    
    output          iis_ws,     
    output          motor_stp, 
    output          motor_dir, 
    output          motor_en,
    output          o_uart_tx
       
);


    wire clk_200m;
    wire pll_locked;
    wire sys_rst_n;

    // Keep the asynchronous reset tree small.  sys_rst_n only resets these
    // local distribution flops; all functional logic uses their synchronous
    // active-low reset outputs.
    (* max_fanout = 64 *) reg rst_iis_n;
    (* max_fanout = 64 *) reg rst_fir_x_n;
    (* max_fanout = 64 *) reg rst_fir_y_n;
    (* max_fanout = 64 *) reg rst_buff_n;
    (* max_fanout = 64 *) reg rst_fft_n;
    (* max_fanout = 64 *) reg rst_loc_n;
    (* max_fanout = 64 *) reg rst_motor_n;
    (* max_fanout = 64 *) reg rst_uart_n;

    clk_wiz_0 inst_pll (
        .clk_in1(clk_100m),
        .clk_out1(clk_200m),
        .reset(!rst_p),
        .locked(pll_locked)
    );
(* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync;

always @(posedge clk_200m or negedge pll_locked) begin
    if(!pll_locked)
        rst_sync <= 2'b00;
    else
        rst_sync <= {rst_sync[0], 1'b1};
end

assign sys_rst_n = rst_sync[1];
    //assign sys_rst_n = pll_locked;

always @(posedge clk_200m or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        rst_iis_n   <= 1'b0;
        rst_fir_x_n <= 1'b0;
        rst_fir_y_n <= 1'b0;
        rst_buff_n  <= 1'b0;
        rst_fft_n   <= 1'b0;
        rst_loc_n   <= 1'b0;
        rst_motor_n <= 1'b0;
        rst_uart_n  <= 1'b0;
    end else begin
        rst_iis_n   <= 1'b1;
        rst_fir_x_n <= 1'b1;
        rst_fir_y_n <= 1'b1;
        rst_buff_n  <= 1'b1;
        rst_fft_n   <= 1'b1;
        rst_loc_n   <= 1'b1;
        rst_motor_n <= 1'b1;
        rst_uart_n  <= 1'b1;
    end
end

    wire [23:0] ad_mic1, ad_mic3;            
    wire [23:0] ad_mic2, ad_mic4;         
    wire vld_sync;     

    iis_rx u_iis_rx (
        .clk(clk_200m),        
        .rst_n(rst_iis_n),       
        .iis_sd_x(iis_sd_x),
        .iis_sd_y(iis_sd_y),
        .iis_sck(iis_sck),        
        .iis_ws(iis_ws),       
        .data_mic1(ad_mic1),         
        .data_mic3(ad_mic3),        
        .data_mic2(ad_mic2),
        .data_mic4(ad_mic4),
        .data_valid(vld_sync)        
    );            

    wire [23:0] f_mic1, f_mic3;
    wire [23:0] f_mic2, f_mic4;
    wire fv_x, fv_y;

    fir u_fir_x (
        .clk(clk_200m),
        .rst_n(rst_fir_x_n),
        .i_data_l(ad_mic1),
        .i_data_r(ad_mic3),
        .i_vld(vld_sync),
        .o_data_l(f_mic1),
        .o_data_r(f_mic3),
        .o_en(fv_x)
    );

    fir u_fir_y (
        .clk(clk_200m),
        .rst_n(rst_fir_y_n),
        .i_data_l(ad_mic2),
        .i_data_r(ad_mic4),
        .i_vld(vld_sync),
        .o_data_l(f_mic2),
        .o_data_r(f_mic4),
        .o_en(fv_y)
    );
    
    
    (* mark_debug = "true" *) wire fft_ready;

    (* mark_debug = "true" *) wire [23:0] fft_in;

    (* mark_debug = "true" *) wire fft_in_vld;
    (* mark_debug = "true" *) wire fft_in_last;

    buff u_buff (
        .clk(clk_200m),
        .rst_n(rst_buff_n),
        .i_fir1_data(f_mic1), 
        .i_fir2_data(f_mic2), 
        .i_fir3_data(f_mic3), 
        .i_fir4_data(f_mic4),          
        .i_en(fv_x),    
        .i_fft_ready(fft_ready),     
        .i_fft_data(fft_in),                       
        .i_fft_vld(fft_in_vld),                    
        .i_fft_last(fft_in_last)         
    );

    wire [23:0] xk_re, xk_im;
    wire xk_vld;
    wire xk_last;
    wire [1:0] xk_id;

    fft u_fft (
        .clk(clk_200m),         
        .rst_n(rst_fft_n),             
        .i_data(fft_in),         
        .i_vld(fft_in_vld),
        .i_last(fft_in_last),
        .o_fft_ready(fft_ready),
        .o_fft_real(xk_re),
        .o_fft_imag(xk_im),
        .o_fft_vld(xk_vld),
        .o_fft_last(xk_last),
        .o_fft_id(xk_id)
    );


    wire [23:0] res_angle;
    wire res_en;

    cordic_loc u_loc (
        .clk(clk_200m),
        .rst_n(rst_loc_n),
        .i_fft_real(xk_re),
        .i_fft_imag(xk_im),
        .i_fft_vld(xk_vld),
        .i_fft_last(xk_last),
        .i_fft_id(xk_id),
        .o_angle(res_angle),
        .o_angle_en(res_en)
    );
    
    camera_pan_top #(
        .CLK_FREQ_HZ                (200000000),
        .STEP_FREQ_HZ               (5000),
        .MOTOR_PULSES_PER_REV        (3_200),
        .MOTOR_TURNS_PER_CAMERA_TURN (10),
        .DEADBAND_DEG                (5),
        .DIR_SETUP_US                (2000),
        .DIR_POSITIVE_LEVEL          (1'b0),
        .EN_ACTIVE_LEVEL             (1'b1),
        .HOLD_WHEN_IDLE              (1'b1)
    ) u_camera_pan (
        .clk           (clk_200m),
        .rst_n         (rst_motor_n),
        .i_azimuth     (res_angle),
        .i_azimuth_en  (res_en),
        .motor_stp     (motor_stp),
        .motor_dir     (motor_dir),
        .motor_en      (motor_en),
        .motor_busy    (),
        .motor_position()
    );
    
    uart_dri u_uart_dri(
        .clk(clk_200m),
        .rst_n(rst_uart_n),
        .i_data(res_angle),
        .i_en(res_en),
        .o_uart_tx(o_uart_tx)
    );

endmodule
