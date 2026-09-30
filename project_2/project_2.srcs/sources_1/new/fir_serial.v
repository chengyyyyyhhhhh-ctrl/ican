`timescale 1ns / 1ps

module fir_serial (
    input                 clk,     
    input                 rst_n,   
    input                 en,      
    input  [23:0]         xin,     
    output reg            valid,   
    output reg  [47:0]    yout  
);

    // 1. 存储输入数据 
    reg signed [23:0] data_reg [0:219];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<220; i=i+1) data_reg[i] <= 24'd0;
        end else if (en) begin
            data_reg[0] <= xin;
            for (i=0; i<219; i=i+1) data_reg[i+1] <= data_reg[i];
        end
    end

    // 2. 状态控制与计数器 
    reg [6:0] cnt;
    reg       busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 7'd0;
            busy <= 1'b0;
        end else if (en) begin
            busy <= 1'b1;
            cnt <= 7'd0;
        end else if (cnt == 7'd109) begin
            busy <= 1'b0;
            cnt <= 7'd0;
        end else if (busy) begin
            cnt <= cnt + 1'b1;
        end
    end

    // 3. 系数存储 
    reg signed [15:0] coe;
    always @(*) begin
        case(cnt)
            7'h00: coe = 16'hfd68; 7'h01: coe = 16'hfd40; 7'h02: coe = 16'hfc5a; 7'h03: coe = 16'hfbc9;
            7'h04: coe = 16'hfbc4; 7'h05: coe = 16'hfc70; 7'h06: coe = 16'hfdd4; 7'h07: coe = 16'hffcf;
            7'h08: coe = 16'h021d; 7'h09: coe = 16'h0462; 7'h0a: coe = 16'h063b; 7'h0b: coe = 16'h0756;
            7'h0c: coe = 16'h0783; 7'h0d: coe = 16'h06c4; 7'h0e: coe = 16'h054c; 7'h0f: coe = 16'h0374;
            7'h10: coe = 16'h01a8; 7'h11: coe = 16'h004b; 7'h12: coe = 16'hffa3; 7'h13: coe = 16'hffc3;
            7'h14: coe = 16'h008c; 7'h15: coe = 16'h01b3; 7'h16: coe = 16'h02d6; 7'h17: coe = 16'h0399;
            7'h18: coe = 16'h03be; 7'h19: coe = 16'h0333; 7'h1a: coe = 16'h021c; 7'h1b: coe = 16'h00c3;
            7'h1c: coe = 16'hff87; 7'h1d: coe = 16'hfebe; 7'h1e: coe = 16'hfe9a; 7'h1f: coe = 16'hff20;
            7'h20: coe = 16'h0020; 7'h21: coe = 16'h0147; 7'h22: coe = 16'h0237; 7'h23: coe = 16'h029f;
            7'h24: coe = 16'h0258; 7'h25: coe = 16'h016f; 7'h26: coe = 16'h0021; 7'h27: coe = 16'hfecc;
            7'h28: coe = 16'hfdd1; 7'h29: coe = 16'hfd78; 7'h2a: coe = 16'hfdd7; 7'h2b: coe = 16'hfed0;
            7'h2c: coe = 16'h0014; 7'h2d: coe = 16'h0139; 7'h2e: coe = 16'h01e0; 7'h2f: coe = 16'h01cb;
            7'h30: coe = 16'h00f3; 7'h31: coe = 16'hff90; 7'h32: coe = 16'hfe02; 7'h33: coe = 16'hfcbb;
            7'h34: coe = 16'hfc19; 7'h35: coe = 16'hfc4b; 7'h36: coe = 16'hfd41; 7'h37: coe = 16'hfead;
            7'h38: coe = 16'h001a; 7'h39: coe = 16'h0111; 7'h3a: coe = 16'h0139; 7'h3b: coe = 16'h0077;
            7'h3c: coe = 16'hfef6; 7'h3d: coe = 16'hfd1d; 7'h3e: coe = 16'hfb73; 7'h3f: coe = 16'hfa73;
            7'h40: coe = 16'hfa6a; 7'h41: coe = 16'hfb5a; 7'h42: coe = 16'hfcfa; 7'h43: coe = 16'hfec6;
            7'h44: coe = 16'h0029; 7'h45: coe = 16'h00a7; 7'h46: coe = 16'h0007; 7'h47: coe = 16'hfe65;
            7'h48: coe = 16'hfc2f; 7'h49: coe = 16'hfa05; 7'h4a: coe = 16'hf88b; 7'h4b: coe = 16'hf834;
            7'h4c: coe = 16'hf920; 7'h4d: coe = 16'hfb0b; 7'h4e: coe = 16'hfd60; 7'h4f: coe = 16'hff60;
            7'h50: coe = 16'h005e; 7'h51: coe = 16'hfff4; 7'h52: coe = 16'hfe27; 7'h53: coe = 16'hfb6b;
            7'h54: coe = 16'hf884; 7'h55: coe = 16'hf650; 7'h56: coe = 16'hf584; 7'h57: coe = 16'hf66d;
            7'h58: coe = 16'hf8d7; 7'h59: coe = 16'hfc10; 7'h5a: coe = 16'hff1c; 7'h5b: coe = 16'h00f8;
            7'h5c: coe = 16'h00ef; 7'h5d: coe = 16'hfed6; 7'h5e: coe = 16'hfb24; 7'h5f: coe = 16'hf6da;
            7'h60: coe = 16'hf341; 7'h61: coe = 16'hf18a; 7'h62: coe = 16'hf26a; 7'h63: coe = 16'hf5dd;
            7'h64: coe = 16'hfb0e; 7'h65: coe = 16'h0083; 7'h66: coe = 16'h047f; 7'h67: coe = 16'h0580;
            7'h68: coe = 16'h02bc; 7'h69: coe = 16'hfc71; 7'h6a: coe = 16'hf403; 7'h6b: coe = 16'hfebb;
            7'h6c: coe = 16'hfe64; 7'h6d: coe = 16'hfe61; 7'h6e: coe = 16'hfecc; 7'h6f: coe = 16'hfa82;
            7'h70: coe = 16'h0de5; 7'h71: coe = 16'h242b; 7'h72: coe = 16'h39ae; 7'h73: coe = 16'h4aaa;
            7'h74: coe = 16'h5406;
            default: coe = 16'd0;
        endcase
    end

    // 4. 算术流水线 
    reg signed [24:0] add_res;    
    reg signed [15:0] coe_reg;    
    reg signed [40:0] mult_res;   
    reg signed [47:0] sum;        
    reg [2:0] pipeline_v;         

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_res <= 25'd0;
            mult_res <= 41'd0;
            sum <= 48'd0;
            coe_reg <= 16'd0;
            pipeline_v <= 3'b0;
        end else if (busy || pipeline_v != 0) begin
            add_res <= data_reg[cnt] + data_reg[219-cnt];
            coe_reg <= coe;
            mult_res <= add_res * coe_reg;
            if (pipeline_v[1] && !pipeline_v[2]) begin 
                sum <= mult_res;
            end else if (pipeline_v[2]) begin
                sum <= sum + mult_res;
            end
            pipeline_v <= {pipeline_v[1:0], busy};
        end else begin
            pipeline_v <= 3'b0;
        end
    end

    // 5. 输出结果锁定
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            yout <= 48'd0;
            valid <= 1'b0;
        end else if (pipeline_v[2] && !pipeline_v[1]) begin 
            yout <= sum;
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

endmodule