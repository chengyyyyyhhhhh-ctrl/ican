`timescale 1ns / 1ps

module uart_dri(
    input clk,
    input rst_n,
    input [23:0] i_data, 
    input        i_en,  
    output       o_uart_tx
);

    localparam IDLE    = 3'd0;
    localparam SEND_H  = 3'd1; 
    localparam SEND_D1 = 3'd2; 
    localparam SEND_D2 = 3'd3; 
    localparam SEND_D3 = 3'd4; 
    localparam WAIT    = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;
    reg [7:0] tx_data;
    reg       tx_go;
    wire      tx_done;

    reg [23:0] r_data;
    always @(posedge clk) if(i_en) r_data <= i_data;

    always @(posedge clk) begin
        if(!rst_n) begin
            state <= IDLE;
            tx_go <= 0;
            tx_data <= 0;
        end else begin
            tx_go <= 0;
            case(state)
                IDLE: begin
                    if(i_en) state <= SEND_H;
                end

                SEND_H: begin
                    tx_data <= 8'hA5; 
                    tx_go   <= 1'b1;
                    state   <= WAIT;
                    next_state <= SEND_D1;
                end

                SEND_D1: begin
                    tx_data <= r_data[23:16]; 
                    tx_go   <= 1'b1;
                    state   <= WAIT;
                    next_state <= SEND_D2;
                end

                SEND_D2: begin
                    tx_data <= r_data[15:8];  
                    tx_go   <= 1'b1;
                    state   <= WAIT;
                    next_state <= SEND_D3;
                end

                SEND_D3: begin
                    tx_data <= r_data[7:0];  
                    tx_go   <= 1'b1;
                    state   <= WAIT;
                    next_state <= IDLE;
                end

                WAIT: begin
                    if(tx_done) 
                        state <= next_state;
                end
                default: state <= IDLE;
            endcase
        end
    end

    uart_tx #(
        .BAUD(115200),       
        .CLOCK_FREQ(200000000) 
    ) u_uart_core (
        .clk(clk),
        .rst(rst_n),
        .send_go(tx_go),
        .data(tx_data),
        .uart_tx(o_uart_tx),
        .tx(tx_done)
    );

endmodule
