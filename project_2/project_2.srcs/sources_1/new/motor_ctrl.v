module motor_ctrl (

    input           clk,          

    input           rst_n,

    input  signed [23:0] i_angle,    

    input                i_angle_en, 

    output reg      motor_stp,

    output       motor_dir,

    output       motor_en

);



parameter CLK_FREQ = 200_000_000;

parameter MAX_STEP_FREQ = 1000;  

parameter PULSES_PER_REV = 3200;      

//parameter PULSES_PER_REV = 40;       

parameter DEADBAND_DEG = 5;



reg signed [31:0] target_pos;      // ???¦Ë??

reg signed [31:0] current_pos;     // ???¦Ë??

reg signed [31:0] last_run_pos;    // ????????????????¦Ë??



reg [31:0] clk_cnt;

wire [31:0] div_limit = CLK_FREQ / (MAX_STEP_FREQ * 2);

wire signed [31:0] diff_from_stop = (target_pos > last_run_pos) ? (target_pos - last_run_pos) : (last_run_pos - target_pos);





wire signed [47:0] mult_tmp;

assign mult_tmp = i_angle * PULSES_PER_REV;

wire signed [31:0] calc_pos;

assign calc_pos = mult_tmp / 360;



always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        target_pos <= 0;

    end else if (i_angle_en) begin

        target_pos <= calc_pos;

    end

end



localparam signed [31:0] THRESHOLD = (PULSES_PER_REV * DEADBAND_DEG) / 360; //????????





reg move_en;

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        move_en <= 1'b0;

      //  last_run_pos <= 0;

    end

    else if (current_pos == target_pos) begin

        move_en <= 1'b0;

    end

    else begin

        // ??????

        if (!move_en) begin

            if (diff_from_stop > THRESHOLD) begin

                move_en <= 1'b1;

            end

        end

    end

end

assign motor_en = move_en;





reg dir_reg;

always @(posedge clk or negedge rst_n) begin

    if (!rst_n)

        dir_reg <= 1'b0;

    else if (!move_en)

        dir_reg <= (target_pos > current_pos);

end

assign motor_dir = dir_reg;



always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        motor_stp   <= 1'b0;

        current_pos <= 0;

        clk_cnt     <= 0;
        last_run_pos <= 0;

    end

    else if (move_en) begin

        if (clk_cnt >= div_limit) begin

            clk_cnt   <= 0;
    
            motor_stp <= ~motor_stp;

            // STEP?????????¦Ë??

            if (motor_stp == 1'b0) begin

                // ??????????

                if (current_pos == target_pos) begin

                    last_run_pos <= current_pos;

                end

                // ???

                else if (dir_reg) begin

                    current_pos <= current_pos + 1;

                end

                // ???

                else if (!dir_reg)begin

                    current_pos <= current_pos - 1;

                end

            end 

        end 

        else begin

            clk_cnt<=clk_cnt+1'b1;

        end

    end 

    else if(!move_en) begin

        motor_stp <= 1'b0;

        clk_cnt   <= 0;

    end

end



endmodule