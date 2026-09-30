`timescale 1ns / 1ps

module frame_window(
input clk,
input rst_n,
input [23:0] i_data,
input i_en,
input i_rd_start,
input i_ready,
output reg o_last,
output reg [23:0] o_data,
output reg o_vld,
output reg o_ready
);

reg  [8:0] wr_addr;
reg        rd_busy;
reg  [8:0] rd_cnt;
wire [8:0]  rom_rd_addr;
wire [8:0]  ram_rd_addr;
(* mark_debug = "true" *) wire [23:0] ram_data_out;
(* mark_debug = "true" *) wire [15:0] rom_data_out;
(* mark_debug = "true" *) reg  [23:0] ram_data_out_d1;
reg  [2:0]  vld_dly;
reg  [2:0]  last_dly;
(* mark_debug = "true" *) wire signed [39:0] mult_res;
// Register the DSP result so the BRAM-to-DSP-to-output path spans two cycles.
reg signed [39:0] mult_res_d1;

assign rom_rd_addr = rd_cnt;
assign ram_rd_addr = wr_addr+rd_cnt;
assign mult_res = $signed(ram_data_out_d1) * $signed({1'b0,rom_data_out});

reg ram_full_once;
    always @(posedge clk) begin
        if(!rst_n) ram_full_once <= 0;
        else if(wr_addr == 9'd511) ram_full_once <= 1; 
    end

    always @(posedge clk)  
        begin
            if(!rst_n)
                o_ready<=0;
            else if(i_en && ((wr_addr == 9'd255 && ram_full_once) || wr_addr == 9'd511)) 
                o_ready<=1;
            else if(i_rd_start)
                o_ready<=0;
        end

    always @(posedge clk)          
        begin                                        
            if(!rst_n)                               
                wr_addr<=0;                                   
            else if(i_en)
                wr_addr<=wr_addr+1;                                   
            else                                     
                wr_addr<=wr_addr;                             
        end

    always @(posedge clk)          
        begin                                        
            if(!rst_n)                               
                rd_busy<=0;                                   
            else if(i_rd_start )
                rd_busy<=1;                                   
            else if(rd_cnt == 9'd511 && i_ready)
                rd_busy<=0;                                                                
        end 

    always @(posedge clk) begin                                        
        if(!rst_n) begin
            rd_cnt <= 0;    
        end else if (!rd_busy) begin
            rd_cnt <= 0;       
        end else if (i_ready) begin
            rd_cnt <= rd_cnt + 1; 
        end                                                        
    end

    bram_port #(
        .C_ADDR_WIDTH(9), 
        .C_DATA_WIDTH(24)
    ) inst_bram_port (
        .a_clk     (clk),
        .a_en      (i_en),          
        .a_addr    (wr_addr),
        .a_datin   (i_data),
        .a_dataout (),               
        
        .b_clk     (clk),
        .b_en      (1'b0),           
        .b_addr    (ram_rd_addr),
        .b_datin   (24'b0),
        .b_dataout (ram_data_out) 
    );    

    blk_mem_gen_0 inst_blk_mem_gen_0 (
      .clka(clk),    // input wire clka
      .addra(rom_rd_addr),  // input wire [8 : 0] addra
      .douta(rom_data_out)  // output wire [15 : 0] douta
    );            

    always @(posedge clk) 
    begin
        if(!rst_n) begin
            ram_data_out_d1<=0;
            mult_res_d1<=0;
            vld_dly <=0;
            last_dly <= 0;
        end
        else if(i_ready) begin
            ram_data_out_d1<= ram_data_out;
            mult_res_d1<= mult_res;
            vld_dly <= {vld_dly[1:0],rd_busy};
            last_dly <= {last_dly[1:0], (rd_cnt == 9'd511 && rd_busy)};
        end
    end   

    always @(posedge clk)          
        begin                                        
            if(!rst_n) begin
                o_data <= 0;
                o_vld <= 0;
                o_last <= 0;
            end                                                             
            else if(i_ready) begin
                o_data <= mult_res_d1[38:15];
                o_vld <= vld_dly[2];
                o_last <= last_dly[2];
            end                                   
        end                                                                             

endmodule
