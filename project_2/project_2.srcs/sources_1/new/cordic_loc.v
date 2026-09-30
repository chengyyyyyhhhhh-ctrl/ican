`timescale 1ns / 1ps

module cordic_loc #(
    // 48.077 kHz / 512 points: 1557 Hz is located between Bin 16 and Bin 17.
    parameter [8:0]  SEARCH_BIN_MIN = 9'd10,
    parameter [8:0]  SEARCH_BIN_MAX = 9'd11,
    parameter [23:0] MAG_THRESHOLD  = 24'h000200
)(
    input             clk,
    input             rst_n,
    input      [23:0] i_fft_real,
    input      [23:0] i_fft_imag,
    input             i_fft_vld,
    input             i_fft_last,
    input      [1:0]  i_fft_id,
    output reg [23:0] o_angle,
    output reg        o_angle_en
);

    // Radian phase format used by the CORDIC IP is signed Q3.21.
    localparam signed [24:0] PI_Q3_21     = 25'sd6588397;
    localparam signed [24:0] TWO_PI_Q3_21 = 25'sd13176795;

    // The phase subtraction is registered before this function is evaluated.
    // Keeping the subtract and the +/-pi wrap in separate pipeline stages
    // prevents a long BRAM -> subtract -> compare -> add path at 200 MHz.
    function [23:0] wrap_raw_phase_diff;
        input signed [24:0] raw_diff;
        reg   signed [24:0] wrapped_diff;
        begin
            if(raw_diff > PI_Q3_21)
                wrapped_diff = raw_diff - TWO_PI_Q3_21;
            else if(raw_diff < -PI_Q3_21)
                wrapped_diff = raw_diff + TWO_PI_Q3_21;
            else
                wrapped_diff = raw_diff;

            wrap_raw_phase_diff = wrapped_diff[23:0];
        end
    endfunction

    // ------------------------------------------------------------------------
    // CORDIC 0: FFT Cartesian data -> magnitude and phase.
    // ------------------------------------------------------------------------
    wire [47:0] c0_data;
    wire [7:0]  c0_user;
    wire        c0_vld;
    wire        c0_last;

    cordic_0 inst_fft_to_phase (
        .aclk                    (clk),
        .s_axis_cartesian_tvalid (i_fft_vld),
        .s_axis_cartesian_tuser  ({6'd0, i_fft_id}),
        .s_axis_cartesian_tlast  (i_fft_last),
        .s_axis_cartesian_tdata  ({i_fft_imag, i_fft_real}),
        .m_axis_dout_tvalid      (c0_vld),
        .m_axis_dout_tuser       (c0_user),
        .m_axis_dout_tlast       (c0_last),
        .m_axis_dout_tdata       (c0_data)
    );

    wire [23:0] cur_phase;
    wire [23:0] cur_mag;
    wire [1:0]  cur_id;

    assign cur_phase = c0_data[47:24];
    assign cur_mag   = c0_data[23:0];
    assign cur_id    = c0_user[1:0];

    // Restart the bin index at every FFT TLAST instead of relying on 9-bit wrap.
    reg [8:0] bin_cnt;
    always @(posedge clk) begin
        if(!rst_n)
            bin_cnt <= 9'd0;
        else if(c0_vld) begin
            if(c0_last)
                bin_cnt <= 9'd0;
            else
                bin_cnt <= bin_cnt + 1'b1;
        end
    end

    // Channels 0..2 arrive before channel 3. Store their phase and magnitude
    // by bin, then compare all four channels when channel 3 arrives.
    (* ram_style = "block" *) reg [23:0] phase_mem0 [0:511];
    (* ram_style = "block" *) reg [23:0] phase_mem1 [0:511];
    (* ram_style = "block" *) reg [23:0] phase_mem2 [0:511];
    (* ram_style = "block" *) reg [23:0] mag_mem0   [0:511];
    (* ram_style = "block" *) reg [23:0] mag_mem1   [0:511];
    (* ram_style = "block" *) reg [23:0] mag_mem2   [0:511];

    always @(posedge clk) begin
        if(c0_vld) begin
            case(cur_id)
                2'd0: begin
                    phase_mem0[bin_cnt] <= cur_phase;
                    mag_mem0[bin_cnt]   <= cur_mag;
                end
                2'd1: begin
                    phase_mem1[bin_cnt] <= cur_phase;
                    mag_mem1[bin_cnt]   <= cur_mag;
                end
                2'd2: begin
                    phase_mem2[bin_cnt] <= cur_phase;
                    mag_mem2[bin_cnt]   <= cur_mag;
                end
                default: begin
                end
            endcase
        end
    end

    // Stage 1: synchronous memory read for channel 3's current bin.
    reg        s1_valid;
    reg        s1_last;
    reg [8:0]  s1_bin;
    reg [23:0] s1_phase0, s1_phase1, s1_phase2, s1_phase3;
    reg [23:0] s1_mag0,   s1_mag1,   s1_mag2,   s1_mag3;

    always @(posedge clk) begin
        if(!rst_n) begin
            s1_valid  <= 1'b0;
            s1_last   <= 1'b0;
            s1_bin    <= 9'd0;
            s1_phase0 <= 24'd0;
            s1_phase1 <= 24'd0;
            s1_phase2 <= 24'd0;
            s1_phase3 <= 24'd0;
            s1_mag0   <= 24'd0;
            s1_mag1   <= 24'd0;
            s1_mag2   <= 24'd0;
            s1_mag3   <= 24'd0;
        end else begin
            s1_valid <= 1'b0;
            s1_last  <= 1'b0;

            if(c0_vld && cur_id == 2'd3) begin
                s1_valid  <= 1'b1;
                s1_last   <= c0_last;
                s1_bin    <= bin_cnt;
                s1_phase0 <= phase_mem0[bin_cnt];
                s1_phase1 <= phase_mem1[bin_cnt];
                s1_phase2 <= phase_mem2[bin_cnt];
                s1_phase3 <= cur_phase;
                s1_mag0   <= mag_mem0[bin_cnt];
                s1_mag1   <= mag_mem1[bin_cnt];
                s1_mag2   <= mag_mem2[bin_cnt];
                s1_mag3   <= cur_mag;
            end
        end
    end

    // Stage 2A: register the raw opposite-microphone phase differences and
    // pairwise magnitude minima. This is the added timing pipeline stage.
    reg               s2a_valid;
    reg               s2a_last;
    reg        [8:0]  s2a_bin;
    reg signed [24:0] s2a_dx_raw;
    reg signed [24:0] s2a_dy_raw;
    reg        [23:0] s2a_mag_min01;
    reg        [23:0] s2a_mag_min23;

    always @(posedge clk) begin
        if(!rst_n) begin
            s2a_valid     <= 1'b0;
            s2a_last      <= 1'b0;
            s2a_bin       <= 9'd0;
            s2a_dx_raw    <= 25'sd0;
            s2a_dy_raw    <= 25'sd0;
            s2a_mag_min01 <= 24'd0;
            s2a_mag_min23 <= 24'd0;
        end else begin
            s2a_valid <= s1_valid;
            s2a_last  <= s1_last;

            if(s1_valid) begin
                s2a_bin    <= s1_bin;
                s2a_dx_raw <= $signed({s1_phase2[23], s1_phase2})
                            - $signed({s1_phase0[23], s1_phase0});
                s2a_dy_raw <= $signed({s1_phase3[23], s1_phase3})
                            - $signed({s1_phase1[23], s1_phase1});
                s2a_mag_min01 <= (s1_mag0 < s1_mag1) ? s1_mag0 : s1_mag1;
                s2a_mag_min23 <= (s1_mag2 < s1_mag3) ? s1_mag2 : s1_mag3;
            end
        end
    end

    // Stage 2B: wrap the registered differences into [-pi, +pi] and finish
    // the four-channel minimum-magnitude score. The numerical result is
    // identical to the original single-stage implementation.
    reg        vld_d2;
    reg        last_d2;
    reg [8:0]  bin_cnt_d2;
    reg [23:0] dx_sub;
    reg [23:0] dy_sub;
    reg [23:0] mag_d2;

    always @(posedge clk) begin
        if(!rst_n) begin
            vld_d2    <= 1'b0;
            last_d2   <= 1'b0;
            bin_cnt_d2 <= 9'd0;
            dx_sub    <= 24'd0;
            dy_sub    <= 24'd0;
            mag_d2    <= 24'd0;
        end else begin
            vld_d2  <= s2a_valid;
            last_d2 <= s2a_last;

            if(s2a_valid) begin
                bin_cnt_d2 <= s2a_bin;
                dx_sub     <= wrap_raw_phase_diff(s2a_dx_raw);
                dy_sub     <= wrap_raw_phase_diff(s2a_dy_raw);
                mag_d2     <= (s2a_mag_min01 < s2a_mag_min23)
                            ? s2a_mag_min01 : s2a_mag_min23;
            end
        end
    end

    // Search the configured frequency band. Using the minimum magnitude of
    // the four microphones rejects bins whose phase is noise on any channel.
    reg [23:0] max_mag_val;
    reg [23:0] best_dx;
    reg [23:0] best_dy;
    reg [8:0]  best_bin;
    reg        frame_valid;
    reg        calc_trigger;
    reg [23:0] cordic_x;
    reg [23:0] cordic_y;

    always @(posedge clk) begin
        if(!rst_n) begin
            max_mag_val <= 24'd0;
            best_dx     <= 24'd0;
            best_dy     <= 24'd0;
            best_bin    <= 9'd0;
            frame_valid <= 1'b0;
            calc_trigger <= 1'b0;
            cordic_x    <= 24'd0;
            cordic_y    <= 24'd0;
        end else begin
            calc_trigger <= 1'b0;

            if(vld_d2) begin
                // Channel 3 Bin 0 marks the start of a new four-channel result.
                if(bin_cnt_d2 == 9'd0) begin
                    max_mag_val <= 24'd0;
                    best_bin    <= 9'd0;
                    frame_valid <= 1'b0;
                end

                if(bin_cnt_d2 >= SEARCH_BIN_MIN &&
                   bin_cnt_d2 <= SEARCH_BIN_MAX &&
                   mag_d2 > MAG_THRESHOLD &&
                   mag_d2 > max_mag_val) begin
                    max_mag_val <= mag_d2;
                    best_dx     <= dx_sub;
                    best_dy     <= dy_sub;
                    best_bin    <= bin_cnt_d2;
                    frame_valid <= 1'b1;
                end

                if(last_d2) begin
                    if(frame_valid) begin
                        // Latch the vector before asserting valid to CORDIC 1.
                        // CORDIC 1 Cartesian inputs use SignedFraction format.
                        // Scale both Q3.21 phase differences equally into the
                        // legal input range; the common scale does not change
                        // atan2(y, x).
                        cordic_x     <= $signed(best_dx) >>> 2;
                        cordic_y     <= $signed(best_dy) >>> 2;
                        calc_trigger <= 1'b1;
                    end
                    frame_valid <= 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // CORDIC 1: wrapped X/Y phase differences -> direction angle.
    // ------------------------------------------------------------------------
    wire [47:0] c1_data;
    wire [7:0]  c1_user_unused;
    wire        c1_last_unused;
    wire        c1_out_vld;

    cordic_1 inst_phase_to_angle (
        .aclk                    (clk),
        .s_axis_cartesian_tvalid (calc_trigger),
        .s_axis_cartesian_tuser  (8'd0),
        .s_axis_cartesian_tlast  (calc_trigger),
        .s_axis_cartesian_tdata  ({cordic_y, cordic_x}),
        .m_axis_dout_tvalid      (c1_out_vld),
        .m_axis_dout_tuser       (c1_user_unused),
        .m_axis_dout_tlast       (c1_last_unused),
        .m_axis_dout_tdata       (c1_data)
    );

    always @(posedge clk) begin
        if(!rst_n) begin
            o_angle    <= 24'd0;
            o_angle_en <= 1'b0;
        end else begin
            o_angle_en <= 1'b0;

            if(c1_out_vld) begin
                o_angle    <= c1_data[47:24];
                o_angle_en <= 1'b1;
            end
        end
    end

endmodule
