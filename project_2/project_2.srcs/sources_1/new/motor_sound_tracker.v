`timescale 1ns / 1ps

// Standalone stepper-motor controller for the sound-source angle produced by
// cordic_loc.v.  This file is intentionally outside demod.srcs and therefore
// is not part of the current Vivado project until it is added manually.
module motor_sound_tracker #(
    parameter integer CLK_FREQ_HZ      = 200_000_000,
    parameter integer STEP_FREQ_HZ     = 1_000,
    parameter integer PULSES_PER_REV   = 3_200,
    parameter integer DEADBAND_DEG     = 5,
    parameter integer DIR_SETUP_US     = 2_000,
    parameter         DIR_POSITIVE_LEVEL = 1'b1,
    parameter         EN_ACTIVE_LEVEL  = 1'b1,
    parameter         HOLD_WHEN_IDLE   = 1'b1
)(
    input                    clk,
    input                    rst_n,
    input      signed [23:0] i_angle,     // signed Q3.21 radians, normally [-pi, +pi]
    input                    i_angle_en,  // one-clock pulse when i_angle is valid
    output reg               motor_stp,
    output reg               motor_dir,
    output                   motor_en,
    output reg               o_busy,
    output reg signed [31:0] o_current_pos
);

    localparam integer HALF_REV_STEPS = PULSES_PER_REV / 2;
    localparam integer DEADBAND_STEPS = (PULSES_PER_REV * DEADBAND_DEG) / 360;
    localparam integer HALF_PERIOD_CLKS = CLK_FREQ_HZ / (STEP_FREQ_HZ * 2);
    localparam integer DIR_SETUP_CLKS = (CLK_FREQ_HZ / 1_000_000) * DIR_SETUP_US;

    // i_angle is radians * 2^21.  The wanted result is
    // angle * PULSES_PER_REV / (2*pi).  Multiplication followed by >>24 is
    // inexpensive in FPGA logic.  904/710 approximates 4/pi, giving 4074 for
    // the default 3200 pulses/revolution.
    localparam integer ANGLE_TO_STEP_K = (PULSES_PER_REV * 904) / 710;

    localparam [1:0] S_IDLE    = 2'd0;
    localparam [1:0] S_PREPARE = 2'd1;
    localparam [1:0] S_RUN     = 2'd2;

    reg [1:0] state;
    reg [31:0] step_clk_cnt;
    reg [31:0] setup_cnt;
    reg signed [31:0] target_pos;

    // Pipeline the angle conversion.  At 200 MHz the former combinational
    // path (DSP multiply -> normalize -> wrapped error -> deadband compare)
    // was substantially longer than one clock period.
    reg signed [55:0] angle_product_pipe;
    reg               angle_product_valid;
    reg signed [31:0] normalized_target_pipe;
    reg               normalized_target_valid;
    reg signed [31:0] candidate_target_pipe;
    reg signed [31:0] candidate_delta_pipe;
    reg signed [32:0] raw_delta_pipe;
    reg               candidate_calc_valid;
    reg               candidate_delta_valid;

    // Register the position error as well, so the state-machine enables do
    // not contain a 32-bit circular subtract/compare path.
    reg signed [31:0] drive_error;

    wire signed [31:0] converted_pos_pipe = angle_product_pipe >>> 24;

    // Keep positions in [-half revolution, +half revolution).  This makes the
    // wrap at -180/+180 degrees explicit and keeps the counters bounded.
    function signed [31:0] normalize_pos;
        input signed [31:0] value;
        begin
            if (value >= HALF_REV_STEPS)
                normalize_pos = value - PULSES_PER_REV;
            else if (value < -HALF_REV_STEPS)
                normalize_pos = value + PULSES_PER_REV;
            else
                normalize_pos = value;
        end
    endfunction

    // Signed shortest-path error on a circular axis.
    function signed [31:0] wrapped_error;
        input signed [31:0] destination;
        input signed [31:0] position;
        reg   signed [32:0] raw_error;
        begin
            raw_error = destination - position;
            if (raw_error > HALF_REV_STEPS)
                wrapped_error = raw_error - PULSES_PER_REV;
            else if (raw_error < -HALF_REV_STEPS)
                wrapped_error = raw_error + PULSES_PER_REV;
            else
                wrapped_error = raw_error[31:0];
        end
    endfunction

    // Complete the circular correction after the raw subtraction has been
    // registered.  This keeps the long subtract/compare path out of one
    // clock period.
    function signed [31:0] wrapped_raw_error;
        input signed [32:0] raw_error;
        begin
            if (raw_error > HALF_REV_STEPS)
                wrapped_raw_error = raw_error - PULSES_PER_REV;
            else if (raw_error < -HALF_REV_STEPS)
                wrapped_raw_error = raw_error + PULSES_PER_REV;
            else
                wrapped_raw_error = raw_error[31:0];
        end
    endfunction

    function [31:0] abs_signed;
        input signed [31:0] value;
        begin
            abs_signed = value[31] ? -value : value;
        end
    endfunction

    // The input is always an absolute azimuth measured from the fixed X axis.
    wire signed [31:0] normalized_target_next =
        normalize_pos(converted_pos_pipe);
    wire [31:0] candidate_abs_delta = abs_signed(candidate_delta_pipe);
    wire desired_dir = drive_error[31] ? ~DIR_POSITIVE_LEVEL
                                       :  DIR_POSITIVE_LEVEL;

    // Always disable the driver during reset, regardless of active polarity.
    wire enable_request = rst_n && (o_busy || HOLD_WHEN_IDLE);
    assign motor_en = enable_request ? EN_ACTIVE_LEVEL : ~EN_ACTIVE_LEVEL;

    // The product data itself does not require reset because its valid bit is
    // reset below.  Keeping this register free of asynchronous reset allows
    // Vivado to absorb it into the DSP48 output pipeline register.
    always @(posedge clk) begin
        if (i_angle_en)
            angle_product_pipe <= i_angle * ANGLE_TO_STEP_K;
    end
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            step_clk_cnt  <= 32'd0;
            setup_cnt     <= 32'd0;
            target_pos    <= 32'sd0;
            angle_product_valid    <= 1'b0;
            normalized_target_pipe <= 32'sd0;
            normalized_target_valid <= 1'b0;
            candidate_target_pipe  <= 32'sd0;
            candidate_delta_pipe   <= 32'sd0;
            raw_delta_pipe         <= 33'sd0;
            candidate_calc_valid   <= 1'b0;
            candidate_delta_valid  <= 1'b0;
            drive_error             <= 32'sd0;
            o_current_pos <= 32'sd0;
            motor_stp     <= 1'b0;
            motor_dir     <= 1'b0;
            o_busy        <= 1'b0;
        end else begin
            // Stage 1: use a DSP output register for the constant multiply.
            angle_product_valid <= i_angle_en;

            // Stage 2: scale the fixed-point product and normalize the angle.
            normalized_target_valid <= angle_product_valid;
            if (angle_product_valid) begin
                normalized_target_pipe <= normalized_target_next;
            end

            // Stage 3: register the raw position difference.
            candidate_calc_valid <= normalized_target_valid;
            if (normalized_target_valid) begin
                candidate_target_pipe <= normalized_target_pipe;
                raw_delta_pipe        <= $signed(normalized_target_pipe) - $signed(target_pos);
            end

            // Stage 4: apply the circular wrap correction.
            candidate_delta_valid <= candidate_calc_valid;
            if (candidate_calc_valid) begin
                candidate_delta_pipe <= wrapped_raw_error(raw_delta_pipe);
            end

            // Stage 5: apply the deadband and commit the new absolute target.
            if (candidate_delta_valid) begin
                if (candidate_abs_delta > DEADBAND_STEPS)
                    target_pos <= candidate_target_pipe;
            end

            // One registered control stage isolates the motor state machine
            // from the circular position arithmetic.
            drive_error <= wrapped_error(target_pos, o_current_pos);

            case (state)
                S_IDLE: begin
                    motor_stp    <= 1'b0;
                    step_clk_cnt <= 32'd0;
                    setup_cnt    <= 32'd0;
                    o_busy       <= 1'b0;

                    if (drive_error != 0) begin
                        motor_dir <= desired_dir;
                        state     <= S_PREPARE;
                        o_busy    <= 1'b1;
                    end
                end

                S_PREPARE: begin
                    motor_stp <= 1'b0;
                    o_busy    <= 1'b1;

                    if (drive_error == 0) begin
                        state <= S_IDLE;
                    end else if (motor_dir != desired_dir) begin
                        // A new sound angle reversed the requested direction.
                        // Restart the setup interval before issuing STEP.
                        motor_dir <= desired_dir;
                        setup_cnt <= 32'd0;
                    end else if ((DIR_SETUP_CLKS == 0) ||
                                 (setup_cnt >= DIR_SETUP_CLKS - 1)) begin
                        setup_cnt    <= 32'd0;
                        step_clk_cnt <= 32'd0;
                        state        <= S_RUN;
                    end else begin
                        setup_cnt <= setup_cnt + 1'b1;
                    end
                end

                S_RUN: begin
                    o_busy <= 1'b1;

                    // Stop or reverse only while STEP is low, preserving the
                    // full high pulse width expected by the driver.
                    if (!motor_stp && (drive_error == 0)) begin
                        state        <= S_IDLE;
                        step_clk_cnt <= 32'd0;
                    end else if (!motor_stp && (motor_dir != desired_dir)) begin
                        motor_dir    <= desired_dir;
                        step_clk_cnt <= 32'd0;
                        setup_cnt    <= 32'd0;
                        state        <= S_PREPARE;
                    end else if ((HALF_PERIOD_CLKS <= 1) ||
                                 (step_clk_cnt >= HALF_PERIOD_CLKS - 1)) begin
                        step_clk_cnt <= 32'd0;
                        motor_stp    <= ~motor_stp;

                        // This design counts a step on STEP's rising edge.
                        if (!motor_stp) begin
                            if (motor_dir == DIR_POSITIVE_LEVEL) begin
                                if (o_current_pos >= HALF_REV_STEPS - 1)
                                    o_current_pos <= -HALF_REV_STEPS;
                                else
                                    o_current_pos <= o_current_pos + 1'b1;
                            end else begin
                                if (o_current_pos <= -HALF_REV_STEPS)
                                    o_current_pos <= HALF_REV_STEPS - 1;
                                else
                                    o_current_pos <= o_current_pos - 1'b1;
                            end
                        end
                    end else begin
                        step_clk_cnt <= step_clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state     <= S_IDLE;
                    motor_stp <= 1'b0;
                    o_busy    <= 1'b0;
                end
            endcase
        end
    end

endmodule
