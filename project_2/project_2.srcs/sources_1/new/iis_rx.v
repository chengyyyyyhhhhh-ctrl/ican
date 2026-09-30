`timescale 1ns / 1ps

module iis_rx(
    input             clk,
    input             rst_n,
    input             iis_sd_x,
    input             iis_sd_y,
    output            iis_sck,
    output reg        iis_ws,
    output reg [23:0] data_mic1,
    output reg [23:0] data_mic3,
    output reg [23:0] data_mic2,
    output reg [23:0] data_mic4,
    output reg        data_valid
);

localparam  idle  = 3'b001 ;      
localparam  left  = 3'b010 ;
localparam  right = 3'b100 ; 

reg        sd_x_d0, sd_x_d1;
reg        sd_y_d0, sd_y_d1;
reg  [2:0] cur_state;
reg  [2:0] nxt_state;
reg  [9:0] cnt_sck;
reg  [4:0] cnt_R;
reg  [4:0] cnt_L;
reg        re_sck;

reg [23:0] data_mic1_temp;
reg [23:0] data_mic2_temp;
reg [23:0] data_mic3_temp;
reg [23:0] data_mic4_temp;

localparam    iis_sck_time   = 325 ;
localparam    clk_sys_freq   = 200 ;
localparam    N              = iis_sck_time*clk_sys_freq/1000;
localparam    N_mid          = N/2 ;

assign iis_sck = re_sck;

    always @(posedge clk) begin                                        
        if(!rst_n)                               
            cnt_sck <= 0;                                   
        else if(cnt_sck == N-1)                         
            cnt_sck <= 0;                                   
        else                                     
            cnt_sck <= cnt_sck + 1;
    end    

    always @(posedge clk) begin                                        
        if(!rst_n)                               
            re_sck <= 0;                                   
        else if(cnt_sck == N-1)                         
            re_sck <= 0;                                   
        else if(cnt_sck == N_mid-1)                         
            re_sck <= 1;      
        else                                     
            re_sck <= re_sck;                             
    end                                                                        

    always @(posedge clk) begin                                        
        if(!rst_n) begin
            sd_x_d0 <= 0;  sd_x_d1 <= 0;
            sd_y_d0 <= 0;  sd_y_d1 <= 0;
        end                              
        else begin
            sd_x_d0 <= iis_sd_x;  sd_x_d1 <= sd_x_d0;
            sd_y_d0 <= iis_sd_y;  sd_y_d1 <= sd_y_d0;
        end
    end                                  

    always @(posedge clk) begin                                        
        if(!rst_n) begin
            cur_state <= idle;
        end                              
        else begin
            cur_state <= nxt_state;
        end
    end
    
    always @(*) begin
        case(cur_state)
        idle: begin
            nxt_state = left;
        end
        left: begin
            if(cnt_L == 31 && cnt_sck == N-1) begin
                nxt_state = right;
            end
            else begin
                nxt_state = left;
            end
        end
        right: begin
            if(cnt_R == 31 && cnt_sck == N-1) begin
                nxt_state = left;
            end
            else begin
                nxt_state = right;
            end
        end
        default: begin
            nxt_state = idle;
        end
        endcase
    end

    always @(posedge clk) begin                                        
        if(!rst_n) begin
            iis_ws          <= 0;
            data_mic1       <= 0;
            data_mic2       <= 0;
            data_mic3       <= 0;
            data_mic4       <= 0;
            data_mic1_temp  <= 0;
            data_mic2_temp  <= 0;
            data_mic3_temp  <= 0;
            data_mic4_temp  <= 0;
            data_valid      <= 0;
            cnt_L           <= 0;
            cnt_R           <= 0;
        end                                                                 
        else begin
            data_valid <= 0;

            case (cur_state)
                idle: begin
                    iis_ws          <= 0;
                    data_mic1_temp  <= 0;
                    data_mic2_temp  <= 0;
                    data_mic3_temp  <= 0;
                    data_mic4_temp  <= 0;
                    cnt_L           <= 0;
                    cnt_R           <= 0;
                end
                
                left: begin
                    iis_ws <= (cnt_sck == N-1 && cnt_L == 31) ? 1 : 0;
                    
                    if (cnt_sck == N_mid-1 && cnt_L >= 1 && cnt_L <= 24) begin
                        data_mic1_temp <= {data_mic1_temp[22:0], sd_x_d1};
                        data_mic2_temp <= {data_mic2_temp[22:0], sd_y_d1};
                    end
                    
                    cnt_L <= (cnt_sck == N-1) ? cnt_L + 1 : cnt_L;
                    cnt_R <= 0;
                end
                
                right: begin
                    iis_ws <= (cnt_sck == N-1 && cnt_R == 31) ? 0 : 1;
                    
                    if (cnt_sck == N_mid-1 && cnt_R >= 1 && cnt_R <= 24) begin
                        data_mic3_temp <= {data_mic3_temp[22:0], sd_x_d1};
                        data_mic4_temp <= {data_mic4_temp[22:0], sd_y_d1};
                    end
                    
                    if (cnt_R == 24 && cnt_sck == N-1) begin
                        data_mic1  <= data_mic1_temp;
                        data_mic2  <= data_mic2_temp;
                        data_mic3  <= data_mic3_temp;
                        data_mic4  <= data_mic4_temp;
                        data_valid <= 1'b1;
                    end
                    
                    cnt_L <= 0;
                    cnt_R <= (cnt_sck == N-1) ? cnt_R + 1 : cnt_R;
                end
                
                default: begin
                    iis_ws <= 0;
                    cnt_L  <= 0;
                    cnt_R  <= 0;
                end
            endcase
        end                                    
    end                                          

endmodule
