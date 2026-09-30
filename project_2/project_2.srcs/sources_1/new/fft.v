`timescale 1ns / 1ps

module fft(

input clk,
input rst_n,
input [23:0] i_data,
input i_last,
input i_vld,
output [23:0] o_fft_real,
output [23:0] o_fft_imag,
output o_fft_vld,
output o_fft_last,
output reg [1:0] o_fft_id,
output o_fft_ready
);

wire [15:0] fft_config_data = 16'b000000_010101010_1;//??
wire [47:0] s_axis_data_tdata = {24'd0, i_data};
wire [47:0] m_axis_data_tdata;
(* mark_debug = "true" *) reg         fft_config_vld;
(* mark_debug = "true" *) wire        config_ready; 
(* mark_debug = "true" *) wire        data_in_ready;
wire        event_fft_overflow;

assign o_fft_real = m_axis_data_tdata[23:0];
assign o_fft_imag = m_axis_data_tdata[47:24];
assign o_fft_ready = data_in_ready;

always @(posedge clk) begin                                        
    if(!rst_n) begin
        fft_config_vld <= 1'b1; 
    end else if(fft_config_vld && config_ready) begin
        fft_config_vld <= 1'b0; 
    end
end
 
xfft_0 inst_xfft_0 (
  .aclk(clk),                                                // input wire aclk
  .aclken(1'b1),                                            // input wire aclken
  .aresetn(rst_n),                                          // input wire aresetn
  .s_axis_config_tdata(fft_config_data),                  // input wire [15 : 0] s_axis_config_tdata
  .s_axis_config_tvalid(fft_config_vld),                // input wire s_axis_config_tvalid
  .s_axis_config_tready(config_ready),                // output wire s_axis_config_tready
  .s_axis_data_tdata(s_axis_data_tdata),                      // input wire [47 : 0] s_axis_data_tdata
  .s_axis_data_tvalid(i_vld),                    // input wire s_axis_data_tvalid
  .s_axis_data_tready(data_in_ready),                    // output wire s_axis_data_tready
  .s_axis_data_tlast(i_last),                      // input wire s_axis_data_tlast
  .m_axis_data_tdata(m_axis_data_tdata),                      // output wire [47 : 0] m_axis_data_tdata
  .m_axis_data_tvalid(o_fft_vld),                    // output wire m_axis_data_tvalid
  .m_axis_data_tready(1'b1),                    // input wire m_axis_data_tready
  .m_axis_data_tlast(o_fft_last),     
  .m_axis_status_tdata(),         
  .m_axis_status_tvalid(),         
  .m_axis_status_tready(1'b1),     
  .event_fft_overflow(event_fft_overflow),                  // output wire m_axis_data_tlast
  .event_frame_started(),                  // output wire event_frame_started
  .event_tlast_unexpected(),            // output wire event_tlast_unexpected
  .event_tlast_missing(),                  // output wire event_tlast_missing
  .event_status_channel_halt(),      // output wire event_status_channel_halt
  .event_data_in_channel_halt(),    // output wire event_data_in_channel_halt
  .event_data_out_channel_halt()  // output wire event_data_out_channel_halt
);

    always @(posedge clk)          
        begin                                        
            if(!rst_n)                               
                o_fft_id<=0;                                   
            else if(o_fft_vld && o_fft_last)
                o_fft_id<=o_fft_id+1;                                   
            else                                     
                o_fft_id<=o_fft_id;                             
         end      

endmodule
