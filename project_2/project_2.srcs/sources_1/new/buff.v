`timescale 1ns / 1ps

module buff(
input clk,
input rst_n,
input [23:0] i_fir1_data,i_fir2_data,i_fir3_data,i_fir4_data,
input i_en,
input i_fft_ready,
output [23:0] i_fft_data,
output i_fft_vld,
output i_fft_last
);

wire        ready0, ready1, ready2, ready3;
wire [23:0] out0, out1, out2, out3;
wire        vld0, vld1, vld2, vld3;
wire        last0, last1, last2, last3;
reg         start0, start1, start2, start3;

localparam IDLE=3'd0, CH0=3'd1, CH1=3'd2, CH2=3'd3, CH3=3'd4;
reg [2:0] state;

frame_window inst_frame_window_0 (
  .clk(clk),                              // input wire clk
  .rst_n(rst_n),                          // input wire rst_n
  .i_data(i_fir1_data),                    // input wire [23 : 0] i_data
  .i_en(i_en),                        // input wire i_en
  .i_rd_start(start0),          // input wire i_rd_start
  .i_ready(i_fft_ready),
  .o_last(last0),                      // output wire o_last
  .o_data(out0),                        // output wire [23 : 0] o_data
  .o_vld(vld0),                        // output wire o_vld
  .o_ready(ready0)                      // output wire o_ready
);

frame_window inst_frame_window_1 (
  .clk(clk),                              // input wire clk
  .rst_n(rst_n),                          // input wire rst_n
  .i_data(i_fir2_data),                    // input wire [23 : 0] i_data
  .i_en(i_en),                        // input wire i_en
  .i_rd_start(start1),          // input wire i_rd_start
  .i_ready(i_fft_ready),
  .o_last(last1),                      // output wire o_last
  .o_data(out1),                        // output wire [23 : 0] o_data
  .o_vld(vld1),                        // output wire o_vld
  .o_ready(ready1)                      // output wire o_ready
);

frame_window inst_frame_window_2 (
  .clk(clk),                              // input wire clk
  .rst_n(rst_n),                          // input wire rst_n
  .i_data(i_fir3_data),                    // input wire [23 : 0] i_data
  .i_en(i_en),                        // input wire i_en
  .i_rd_start(start2),          // input wire i_rd_start
  .i_ready(i_fft_ready),
  .o_last(last2),                      // output wire o_last
  .o_data(out2),                        // output wire [23 : 0] o_data
  .o_vld(vld2),                        // output wire o_vld
  .o_ready(ready2)                      // output wire o_ready
);

frame_window inst_frame_window_3 (
  .clk(clk),                              // input wire clk
  .rst_n(rst_n),                          // input wire rst_n
  .i_data(i_fir4_data),                    // input wire [23 : 0] i_data
  .i_en(i_en),                        // input wire i_en
  .i_rd_start(start3),          // input wire i_rd_start
  .i_ready(i_fft_ready),
  .o_last(last3),                      // output wire o_last
  .o_data(out3),                        // output wire [23 : 0] o_data
  .o_vld(vld3),                        // output wire o_vld
  .o_ready(ready3)                      // output wire o_ready
);

    always @(posedge clk)          
        begin                                        
            if(!rst_n) begin
                state<=IDLE;
                start0<=0; start1<=0; start2<=0; start3<=0;
            end        
            else begin
                start0<=0; start1<=0; start2<=0; start3<=0;
                case (state)
                    IDLE: begin
                        if(ready0) begin
                            state<=CH0;
                            start0<=1;
                        end
                    end
                    CH0:begin
                        if(vld0 && last0 && i_fft_ready) begin
                            state<=CH1;
                            start1<=1;
                        end
                    end
                    CH1:begin
                        if(vld1 && last1 && i_fft_ready) begin
                            state<=CH2;
                            start2<=1;
                        end
                    end
                    CH2:begin
                        if(vld2 && last2 && i_fft_ready) begin
                            state<=CH3;
                            start3<=1;
                        end
                    end
                    CH3:begin
                        if(vld3 && last3 && i_fft_ready) begin
                            state<=IDLE;
                        end
                    end
                    default: state<=IDLE;
                endcase
            end                                                        
        end     

assign i_fft_data = vld0 ? out0 : (vld1 ? out1 : (vld2 ? out2 : (vld3 ? out3 : 24'd0))); 
assign i_fft_vld = vld0 | vld1 | vld2 | vld3;
assign i_fft_last = (vld0 && last0) | (vld1 && last1) | (vld2 && last2) | (vld3 && last3);  
                                  
endmodule
