`timescale 1ns / 1ps

// Synchronous fall-through FIFO used by the video line buffers. A read is
// allowed to replace an item on the same cycle that a full FIFO is written;
// this is required for a continuous one-pixel-per-clock video line.
module sync_fifo #(
    parameter integer C_FIFO_WIDTH = 8,
    parameter integer C_FIFO_DEPTH = 16
)(
    input  wire                            rst,
    input  wire                            clk,
    input  wire                            wr_en,
    input  wire [C_FIFO_WIDTH-1:0]         din,
    output reg                             full,
    input  wire                            rd_en,
    output wire [C_FIFO_WIDTH-1:0]         dout,
    output reg                             empty,
    output reg  [clogb2(C_FIFO_DEPTH-1):0] data_count
);

localparam integer PTR_WIDTH = clogb2(C_FIFO_DEPTH-1);

reg [C_FIFO_WIDTH-1:0] mem [0:C_FIFO_DEPTH-1];
reg [PTR_WIDTH-1:0] write_pointer;
reg [PTR_WIDTH-1:0] read_pointer;

wire read_valid  = rd_en && !empty;
wire write_valid = wr_en && (!full || read_valid);

assign dout = mem[read_pointer];

always @(posedge clk) begin
    if (rst) begin
        write_pointer <= {PTR_WIDTH{1'b0}};
        read_pointer  <= {PTR_WIDTH{1'b0}};
        data_count    <= {(PTR_WIDTH+1){1'b0}};
        full          <= 1'b0;
        empty         <= 1'b1;
    end else begin
        if (write_valid) begin
            mem[write_pointer] <= din;
            if (write_pointer == C_FIFO_DEPTH - 1)
                write_pointer <= {PTR_WIDTH{1'b0}};
            else
                write_pointer <= write_pointer + 1'b1;
        end

        if (read_valid) begin
            if (read_pointer == C_FIFO_DEPTH - 1)
                read_pointer <= {PTR_WIDTH{1'b0}};
            else
                read_pointer <= read_pointer + 1'b1;
        end

        case ({write_valid, read_valid})
            2'b10: begin
                data_count <= data_count + 1'b1;
                empty <= 1'b0;
                full <= (data_count == C_FIFO_DEPTH - 1);
            end
            2'b01: begin
                data_count <= data_count - 1'b1;
                full <= 1'b0;
                empty <= (data_count == 1);
            end
            default: begin
                data_count <= data_count;
                full <= full;
                empty <= empty;
            end
        endcase
    end
end

function integer clogb2;
    input integer depth;
    begin
        for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
            depth = depth >> 1;
    end
endfunction

endmodule
