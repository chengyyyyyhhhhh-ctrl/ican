`timescale 1ns / 1ps

// Native MIG scheduler for 512-bit beats. DDR stores 8-bit Y samples and
// therefore each accepted command transfers 64 pixels.
module ddr3_rw(
    input  wire         ui_clk,
    input  wire         ui_clk_sync_rst,
    input  wire         init_calib_complete,
    input  wire         app_rdy,
    input  wire         app_wdf_rdy,
    input  wire         app_rd_data_valid,
    input  wire [10:0]  wfifo_rcount,
    input  wire [10:0]  aux_wfifo_rcount,
    input  wire [10:0]  rfifo_wcount,
    input  wire         rd_load,
    input  wire         wr_load,
    input  wire [28:0]  app_addr_rd_min,
    input  wire [28:0]  app_addr_rd_max,
    input  wire [7:0]   rd_bust_len,
    input  wire [28:0]  app_addr_wr_min,
    input  wire [28:0]  app_addr_wr_max,
    input  wire [7:0]   wr_bust_len,
    input  wire [28:0]  app_addr_aux_wr_min,
    input  wire [28:0]  app_addr_aux_wr_max,
    input  wire [7:0]   aux_wr_bust_len,
    input  wire         ddr3_read_valid,
    input  wire         ddr3_pingpang_en,
    output wire         rfifo_wren,
    output wire         wfifo_rden,
    output wire         aux_wfifo_rden,
    output wire         write_data_aux,
    output wire [1:0]   main_completed_page,
    output wire         main_completed_valid,
    output wire         aux_completed_page,
    output wire         aux_completed_valid,
    output wire         read_restart,
    output wire [28:0]  app_addr,
    output wire         app_en,
    output wire         app_wdf_wren,
    output wire         app_wdf_end,
    output wire [2:0]   app_cmd,
    output wire [63:0]  app_wdf_mask
);

localparam [4:0] IDLE      = 5'b00001;
localparam [4:0] READY     = 5'b00010;
localparam [4:0] WRITE     = 5'b00100;
localparam [4:0] READ      = 5'b01000;
localparam [4:0] AUX_WRITE = 5'b10000;

localparam [11:0] RFIFO_DEPTH  = 12'd1024;
localparam [11:0] RFIFO_MARGIN = 12'd16;

wire rst_n = ~ui_clk_sync_rst;

reg [4:0]  state_cnt;
reg [7:0]  wr_cmd_count;
reg [7:0]  aux_wr_cmd_count;
reg [7:0]  rd_cmd_count;
reg [11:0] rd_outstanding;

reg [28:0] app_addr_rd_offset;
reg [28:0] app_addr_wr_offset;
reg [28:0] app_addr_aux_wr_offset;
reg [28:0] app_addr_rd_min_a;
reg [28:0] app_addr_rd_max_a;
reg [28:0] app_addr_wr_min_a;
reg [28:0] app_addr_wr_max_a;
reg [28:0] app_addr_aux_wr_min_a;
reg [28:0] app_addr_aux_wr_max_a;
reg [7:0]  rd_bust_len_a;
reg [7:0]  wr_bust_len_a;
reg [7:0]  aux_wr_bust_len_a;

(* ASYNC_REG = "TRUE" *) reg rd_load_meta;
(* ASYNC_REG = "TRUE" *) reg rd_load_sync;
reg rd_load_sync_d;
reg        read_restart_pending;
reg [10:0] read_restart_count;

reg [1:0] write_page;
reg [1:0] read_page;
reg [1:0] completed_page;
reg completed_valid;
reg aux_write_page;
reg aux_completed_page_reg;
reg aux_completed_valid_reg;

function [28:0] frame_page_offset;
    input [1:0]  page;
    input [28:0] frame_span;
    begin
        case (page)
            2'd1: frame_page_offset = frame_span;
            2'd2: frame_page_offset = frame_span << 1;
            default: frame_page_offset = 29'd0;
        endcase
    end
endfunction

function [1:0] select_free_page;
    input [1:0] display_page;
    input [1:0] newest_page;
    begin
        if ((display_page != 2'd0) && (newest_page != 2'd0))
            select_free_page = 2'd0;
        else if ((display_page != 2'd1) && (newest_page != 2'd1))
            select_free_page = 2'd1;
        else
            select_free_page = 2'd2;
    end
endfunction

wire rd_frame_start = rd_load_sync && !rd_load_sync_d;
wire read_page_switch = rd_frame_start && completed_valid &&
                        (completed_page != read_page);
wire [28:0] rd_frame_span = app_addr_rd_max_a - app_addr_rd_min_a;
wire [28:0] wr_frame_span = app_addr_wr_max_a - app_addr_wr_min_a;
wire [28:0] aux_frame_span = app_addr_aux_wr_max_a -
                             app_addr_aux_wr_min_a;

wire [28:0] rd_page_offset =
    ddr3_pingpang_en ? frame_page_offset(read_page, rd_frame_span) : 29'd0;
wire [28:0] wr_page_offset =
    ddr3_pingpang_en ? frame_page_offset(write_page, wr_frame_span) : 29'd0;
wire [28:0] aux_wr_page_offset =
    aux_write_page ? aux_frame_span : 29'd0;

wire [1:0] allocation_read_page =
    read_page_switch ? completed_page : read_page;

wire main_write_cmd_accept =
    (state_cnt == WRITE) && app_rdy && app_wdf_rdy;
wire aux_write_cmd_accept =
    (state_cnt == AUX_WRITE) && app_rdy && app_wdf_rdy;
wire read_cmd_accept =
    (state_cnt == READ) && !read_page_switch &&
    !read_restart_pending && app_rdy;

wire [11:0] read_reservation =
    {1'b0, rfifo_wcount} + rd_outstanding +
    {4'd0, rd_bust_len_a} + RFIFO_MARGIN;
wire rfifo_has_space = (read_reservation <= RFIFO_DEPTH);

assign app_addr = (state_cnt == READ)
                ? app_addr_rd_offset + rd_page_offset
                : (state_cnt == AUX_WRITE)
                    ? app_addr_aux_wr_offset + aux_wr_page_offset
                    : app_addr_wr_offset + wr_page_offset;

assign app_en = main_write_cmd_accept || aux_write_cmd_accept ||
                read_cmd_accept;
assign app_wdf_wren = main_write_cmd_accept || aux_write_cmd_accept;
assign app_wdf_end = app_wdf_wren;
assign app_cmd = (state_cnt == READ) ? 3'd1 : 3'd0;
assign app_wdf_mask = 64'b0;
assign wfifo_rden = main_write_cmd_accept;
assign aux_wfifo_rden = aux_write_cmd_accept;
assign write_data_aux = (state_cnt == AUX_WRITE);
assign main_completed_page = completed_page;
assign main_completed_valid = completed_valid;
assign aux_completed_page = aux_completed_page_reg;
assign aux_completed_valid = aux_completed_valid_reg;
assign read_restart = read_page_switch;
assign rfifo_wren = app_rd_data_valid && !read_page_switch &&
                    !read_restart_pending;

// Synchronize frame indicators and capture the address configuration. These
// configuration buses are expected to remain constant while the controller
// is active.
always @(posedge ui_clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_load_meta       <= 1'b0;
        rd_load_sync       <= 1'b0;
        rd_load_sync_d     <= 1'b0;
        app_addr_rd_min_a  <= 29'd0;
        app_addr_rd_max_a  <= 29'd0;
        app_addr_wr_min_a  <= 29'd0;
        app_addr_wr_max_a  <= 29'd0;
        app_addr_aux_wr_min_a <= 29'd0;
        app_addr_aux_wr_max_a <= 29'd0;
        rd_bust_len_a      <= 8'd0;
        wr_bust_len_a      <= 8'd0;
        aux_wr_bust_len_a  <= 8'd0;
    end else begin
        rd_load_meta   <= rd_load;
        rd_load_sync   <= rd_load_meta;
        rd_load_sync_d <= rd_load_sync;
        app_addr_rd_min_a <= app_addr_rd_min;
        app_addr_rd_max_a <= app_addr_rd_max;
        app_addr_wr_min_a <= app_addr_wr_min;
        app_addr_wr_max_a <= app_addr_wr_max;
        app_addr_aux_wr_min_a <= app_addr_aux_wr_min;
        app_addr_aux_wr_max_a <= app_addr_aux_wr_max;
        rd_bust_len_a     <= rd_bust_len;
        wr_bust_len_a     <= wr_bust_len;
        aux_wr_bust_len_a <= aux_wr_bust_len;
    end
end

// Track read commands whose return data has not yet arrived. MIG read data
// cannot be back-pressured, so this count is included in the FIFO reservation.
always @(posedge ui_clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_outstanding <= 12'd0;
    end else begin
        case ({read_cmd_accept, app_rd_data_valid})
            2'b10: rd_outstanding <= rd_outstanding + 1'b1;
            2'b01: rd_outstanding <= (rd_outstanding != 12'd0)
                                        ? rd_outstanding - 1'b1
                                        : 12'd0;
            default: rd_outstanding <= rd_outstanding;
        endcase
    end
end

// Allow the read FIFO reset to finish and all old MIG returns to drain before
// starting the new display frame.
always @(posedge ui_clk or negedge rst_n) begin
    if (!rst_n) begin
        read_restart_pending <= 1'b0;
        read_restart_count   <= 11'd0;
    end else if (read_page_switch) begin
        read_restart_pending <= 1'b1;
        read_restart_count   <= 11'd0;
    end else if (read_restart_pending) begin
        if ((read_restart_count >= 11'd1000) && (rd_outstanding == 12'd0)) begin
            read_restart_pending <= 1'b0;
            read_restart_count   <= read_restart_count;
        end else begin
            read_restart_count <= read_restart_count + 1'b1;
        end
    end else begin
        read_restart_count <= 11'd0;
    end
end

// Main scheduler. The HDMI stream uses three frame pages. The auxiliary NPU
// stream uses two pages and publishes a page only after all 256x256 pixels have
// reached DDR; the following frame is then written into the opposite page.
always @(posedge ui_clk or negedge rst_n) begin
    if (!rst_n) begin
        state_cnt          <= IDLE;
        wr_cmd_count       <= 8'd0;
        aux_wr_cmd_count   <= 8'd0;
        rd_cmd_count       <= 8'd0;
        app_addr_wr_offset <= 29'd0;
        app_addr_aux_wr_offset <= 29'd0;
        app_addr_rd_offset <= 29'd0;
        write_page         <= 2'd1;
        read_page          <= 2'd0;
        completed_page     <= 2'd0;
        completed_valid    <= 1'b0;
        aux_write_page     <= 1'b0;
        aux_completed_page_reg <= 1'b0;
        aux_completed_valid_reg <= 1'b0;
    end else begin
        // The display page and read offset change only at a display-frame
        // boundary. The READ state below is also aborted on this event so a
        // later increment cannot overwrite the frame-start address.
        if (read_page_switch) begin
            app_addr_rd_offset <= app_addr_rd_min_a;
            read_page <= completed_page;
        end

        case (state_cnt)
            IDLE: begin
                wr_cmd_count <= 8'd0;
                aux_wr_cmd_count <= 8'd0;
                rd_cmd_count <= 8'd0;
                if (init_calib_complete) begin
                    state_cnt          <= READY;
                    app_addr_wr_offset <= app_addr_wr_min_a;
                    app_addr_aux_wr_offset <= app_addr_aux_wr_min_a;
                    app_addr_rd_offset <= app_addr_rd_min_a;
                end
            end

            READY: begin
                wr_cmd_count <= 8'd0;
                aux_wr_cmd_count <= 8'd0;
                rd_cmd_count <= 8'd0;

                if (!init_calib_complete) begin
                    state_cnt <= IDLE;
                end else if (app_addr_wr_offset >= app_addr_wr_max_a) begin
                    app_addr_wr_offset <= app_addr_wr_min_a;
                    completed_page     <= write_page;
                    completed_valid    <= 1'b1;
                    if (ddr3_pingpang_en)
                        write_page <= select_free_page(allocation_read_page,
                                                       write_page);
                end else if (app_addr_aux_wr_offset >=
                             app_addr_aux_wr_max_a) begin
                    app_addr_aux_wr_offset <= app_addr_aux_wr_min_a;
                    aux_completed_page_reg <= aux_write_page;
                    aux_completed_valid_reg <= 1'b1;
                    aux_write_page <= ~aux_write_page;
                end else if (app_addr_rd_offset >= app_addr_rd_max_a) begin
                    app_addr_rd_offset <= app_addr_rd_min_a;
                end else if ((wr_bust_len_a != 8'd0) &&
                             (wfifo_rcount >= {3'd0, wr_bust_len_a})) begin
                    state_cnt    <= WRITE;
                    wr_cmd_count <= 8'd0;
                end else if ((aux_wr_bust_len_a != 8'd0) &&
                             (aux_wfifo_rcount >=
                              {3'd0, aux_wr_bust_len_a})) begin
                    state_cnt        <= AUX_WRITE;
                    aux_wr_cmd_count <= 8'd0;
                end else if (!read_page_switch && !read_restart_pending &&
                             ddr3_read_valid &&
                             completed_valid && (rd_bust_len_a != 8'd0) &&
                             rfifo_has_space) begin
                    state_cnt    <= READ;
                    rd_cmd_count <= 8'd0;
                end
            end

            WRITE: begin
                if (main_write_cmd_accept) begin
                    app_addr_wr_offset <= app_addr_wr_offset + 29'd8;
                    if (wr_cmd_count == wr_bust_len_a - 1'b1) begin
                        state_cnt    <= READY;
                        wr_cmd_count <= 8'd0;
                    end else begin
                        wr_cmd_count <= wr_cmd_count + 1'b1;
                    end
                end
            end

            AUX_WRITE: begin
                if (aux_write_cmd_accept) begin
                    app_addr_aux_wr_offset <= app_addr_aux_wr_offset + 29'd8;
                    if (aux_wr_cmd_count == aux_wr_bust_len_a - 1'b1) begin
                        state_cnt        <= READY;
                        aux_wr_cmd_count <= 8'd0;
                    end else begin
                        aux_wr_cmd_count <= aux_wr_cmd_count + 1'b1;
                    end
                end
            end

            READ: begin
                if (read_page_switch) begin
                    state_cnt    <= READY;
                    rd_cmd_count <= 8'd0;
                end else if (read_cmd_accept) begin
                    app_addr_rd_offset <= app_addr_rd_offset + 29'd8;
                    if (rd_cmd_count == rd_bust_len_a - 1'b1) begin
                        state_cnt    <= READY;
                        rd_cmd_count <= 8'd0;
                    end else begin
                        rd_cmd_count <= rd_cmd_count + 1'b1;
                    end
                end
            end

            default: state_cnt <= IDLE;
        endcase
    end
end

// wr_load is intentionally retained for top-level compatibility but does not
// reset a live FIFO or an in-progress transfer.
wire unused_wr_load = wr_load;

endmodule
