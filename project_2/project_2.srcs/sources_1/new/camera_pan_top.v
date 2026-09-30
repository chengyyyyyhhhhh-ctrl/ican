`timescale 1ns / 1ps

// Camera pan-axis top level.
//
// i_azimuth is an ABSOLUTE direction measured from the fixed X axis and uses
// the same signed Q3.21-radian format as cordic_loc.o_angle.
//
// The default mechanics assume a 10:1 reduction: the motor makes 10 turns for
// one camera-platform turn.  Therefore one camera revolution requires
// 3200 * 10 = 32000 STEP rising edges.
module camera_pan_top #(
    parameter integer CLK_FREQ_HZ                = 25_000_000,
    parameter integer STEP_FREQ_HZ               = 1_000,
    parameter integer MOTOR_PULSES_PER_REV        = 3_200,
    parameter integer MOTOR_TURNS_PER_CAMERA_TURN = 10,
    parameter integer DEADBAND_DEG                = 5,
    parameter integer DIR_SETUP_US                = 2_000,
    parameter         DIR_POSITIVE_LEVEL          = 1'b1,
    parameter         EN_ACTIVE_LEVEL             = 1'b1,
    parameter         HOLD_WHEN_IDLE              = 1'b1
)(
    input                    clk,
    input                    rst_n,
    input      signed [23:0] i_azimuth,
    input                    i_azimuth_en,
    output                   motor_stp,
    output                   motor_dir,
    output                   motor_en,
    output                   motor_busy,
    output signed [31:0]     motor_position
);

    localparam integer PULSES_PER_CAMERA_REV =
        MOTOR_PULSES_PER_REV * MOTOR_TURNS_PER_CAMERA_TURN;

    motor_sound_tracker #(
        .CLK_FREQ_HZ       (CLK_FREQ_HZ),
        .STEP_FREQ_HZ      (STEP_FREQ_HZ),
        .PULSES_PER_REV    (PULSES_PER_CAMERA_REV),
        .DEADBAND_DEG      (DEADBAND_DEG),
        .DIR_SETUP_US      (DIR_SETUP_US),
        .DIR_POSITIVE_LEVEL(DIR_POSITIVE_LEVEL),
        .EN_ACTIVE_LEVEL   (EN_ACTIVE_LEVEL),
        .HOLD_WHEN_IDLE    (HOLD_WHEN_IDLE)
    ) u_motor (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_angle      (i_azimuth),
        .i_angle_en   (i_azimuth_en),
        .motor_stp    (motor_stp),
        .motor_dir    (motor_dir),
        .motor_en     (motor_en),
        .o_busy       (motor_busy),
        .o_current_pos(motor_position)
    );

endmodule