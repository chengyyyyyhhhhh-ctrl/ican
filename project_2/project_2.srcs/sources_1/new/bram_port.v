
module bram_port
#(
    parameter C_ADDR_WIDTH  = 8,
    parameter C_DATA_WIDTH  = 8
)(
    input wire a_clk,
    input wire a_en,
    input wire [C_ADDR_WIDTH-1:0] a_addr,
    input wire [C_DATA_WIDTH-1:0] a_datin,
    output reg [C_DATA_WIDTH-1:0] a_dataout,

    input wire b_clk,
    input wire b_en,
    input wire [C_ADDR_WIDTH-1:0] b_addr,
    input wire [C_DATA_WIDTH-1:0] b_datin,
    output reg [C_DATA_WIDTH-1:0] b_dataout
);

localparam C_MEM_DEPTH = {C_ADDR_WIDTH{1'b1}};
reg [C_DATA_WIDTH-1:0] mem [C_MEM_DEPTH:0];
integer i;

initial begin
    for(i=0; i<=C_MEM_DEPTH; i=i+1)
        mem[i] = 0;
end

    always @(posedge a_clk)           
        begin                                                                      
            if(a_en)                                
                mem[a_addr] <= a_datin;                                     
            else         
                a_dataout <= mem[a_addr];                            
        end      

    always @(posedge b_clk)
        begin
            if(b_en)
                mem[b_addr] <= b_datin;
            else
                b_dataout <= mem[b_addr];
        end
        
endmodule
