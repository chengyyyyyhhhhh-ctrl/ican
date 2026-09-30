`timescale 1ns / 1ps

module fir(
input clk,
input rst_n,
input [23:0] i_data_l,
input [23:0] i_data_r,
input i_vld,
output reg o_en,
output reg signed [23:0] o_data_l,
output reg signed [23:0] o_data_r
);

wire        m_axis_data_tvalid_l;
wire        m_axis_data_tvalid_r;
wire [47:0] m_axis_data_tdata_l; 
wire [47:0] m_axis_data_tdata_r; 

reg en_d0;

fir_compiler_0 inst_fir_compiler_0 (
  .aclk(clk),                              // input wire aclk
  .s_axis_data_tvalid(i_vld),  // input wire s_axis_data_tvalid
  .s_axis_data_tready(),  // output wire s_axis_data_tready
  .s_axis_data_tdata(i_data_l),    // input wire [23 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid_l),  // output wire m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata_l)    // output wire [47 : 0] m_axis_data_tdata
);

fir_compiler_1 inst_fir_compiler_1 (
  .aclk(clk),                              // input wire aclk
  .s_axis_data_tvalid(i_vld),  // input wire s_axis_data_tvalid
  .s_axis_data_tready(),  // output wire s_axis_data_tready
  .s_axis_data_tdata(i_data_r),    // input wire [23 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid_r),  // output wire m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata_r)    // output wire [47 : 0] m_axis_data_tdata
);

    always @(posedge clk)          
        begin                                        
            if(!rst_n)                               
                o_data_l <= 0;
            else if(m_axis_data_tvalid_l)
                o_data_l <= m_axis_data_tdata_l[40:17];                                   
        end   

    always @(posedge clk)          
        begin                                        
            if(!rst_n)                             
                o_data_r <= 0;
            else if(m_axis_data_tvalid_r)
                o_data_r <= m_axis_data_tdata_r[40:17];                              
        end        
        
    always @(posedge clk)    
        begin
            if(!rst_n) begin
                en_d0<=0;
                o_en<=0;
            end
            else begin
                en_d0<=m_axis_data_tvalid_r;
                o_en<=m_axis_data_tvalid_r && !en_d0;
            end
        end                     

endmodule
