// SPDX-FileCopyrightText: © 2024 Leo Moser <leo.moser@pm.me>
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module wirecube_top (
    input  logic       clk_i, // 25.175 MHz * 2
    input  logic       rst_ni,
    
    // VGA signals
    output logic [5:0] rrggbb_o,
    output logic       hsync_o,
    output logic       vsync_o,
    output logic       next_vertical_o,
    output logic       next_frame_o
);
    localparam PIPELINE_LATENCY = 2;
    
    localparam COLOR_BLACK = 6'h00;
    localparam COLOR_DARK_GRAY = 6'h15;
    localparam COLOR_GRAY = 6'h2A;
    localparam COLOR_WHITE = 6'h3F;

    localparam COLOR_BOLD_RED = 6'h30;
    localparam COLOR_RED = 6'h20;
    localparam COLOR_LIGHT_RED = 6'h10;

    localparam COLOR_BOLD_GREEN = 6'h0C;
    localparam COLOR_GREEN = 6'h08;
    localparam COLOR_LIGHT_GREEN = 6'h04;

    localparam COLOR_BOLD_BLUE = 6'h03;
    localparam COLOR_BLUE = 6'h02;
    localparam COLOR_LIGHT_BLUE = 6'h01;

    localparam COLOR_PINK = 6'h31;
    localparam COLOR_DARK_PINK = 6'h21;
    
    localparam COLOR_1 = COLOR_BOLD_RED | COLOR_LIGHT_BLUE;
    localparam COLOR_2 = COLOR_LIGHT_RED | COLOR_LIGHT_GREEN | COLOR_LIGHT_BLUE;
    localparam COLOR_3 = COLOR_BOLD_GREEN;
    localparam COLOR_4 = COLOR_RED | COLOR_BOLD_GREEN;
    
    /*
        VGA 640x480 @ 60 Hz
        clock = 25.175 MHz
    */

    localparam WIDTH    = 640;
    localparam HEIGHT   = 480;
    
    localparam HFRONT   = 16;
    localparam HSYNC    = 96;
    localparam HBACK    = 48;

    localparam VFRONT   = 10;
    localparam VSYNC    = 2;
    localparam VBACK    = 33;
    
    localparam HTOTAL = WIDTH + HFRONT + HSYNC + HBACK;
    localparam VTOTAL = HEIGHT + VFRONT + VSYNC + VBACK;

    localparam DIVIDE = 6;
    localparam NUM_LINES = 2*DIVIDE;

    /* Horizontal and Vertical Timing */
    
    logic signed [$clog2(HTOTAL) : 0] counter_h;
    logic signed [$clog2(VTOTAL) : 0] counter_v;
    
    logic hblank;
    logic vblank;
    logic hsync;
    logic vsync;
    logic next_vertical;
    logic next_frame;

    logic next_horizontal;
    //assign next_horizontal = 1'b1;

    // Half the frequency for VGA
    /*always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            next_horizontal <= 1'b0;
        end else begin
            next_horizontal <= !next_horizontal;
        end
    end*/

    // Horizontal timing, doubled for double the frequency
    timing #(
        .RESOLUTION     (WIDTH*2),
        .FRONT_PORCH    (HFRONT*2),
        .SYNC_PULSE     (HSYNC*2),
        .BACK_PORCH     (HBACK*2),
        .TOTAL          (HTOTAL*2),
        .POLARITY       (1'b0)
    ) timing_hor (
        .clk        (clk_i),
        .enable     (1'b1),
        .reset_n    (rst_ni),
        .inc_1_or_4 (1'b0),
        .sync       (hsync),
        .blank      (hblank),
        .next       (next_vertical),
        .counter    (counter_h)
    );

    // Vertical timing
    timing #(
        .RESOLUTION     (HEIGHT),
        .FRONT_PORCH    (VFRONT),
        .SYNC_PULSE     (VSYNC),
        .BACK_PORCH     (VBACK),
        .TOTAL          (VTOTAL),
        .POLARITY       (1'b0)
    ) timing_ver (
        .clk        (clk_i),
        .enable     (next_vertical),
        .reset_n    (rst_ni),
        .inc_1_or_4 (1'b0),
        .sync       (vsync),
        .blank      (vblank),
        .next       (next_frame),
        .counter    (counter_v)
    );
    
    
    // Frame counter for animations
    
    logic [15:0] frame_cnt;
    
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            frame_cnt <= '0;
        end else begin
            if (next_frame) begin
                frame_cnt <= frame_cnt + 1;
            end
        end
    end
    
    logic [types::LINE_BITS-1:0]  pixel_x;
    logic [types::LINE_BITS-1:0]  pixel_y;
    
    logic [3:0] subcounter_h;
    logic [2:0] subcounter_v;
    
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            subcounter_h <= '0;
            subcounter_v <= '0;
        end else begin
        
            if (counter_h == -PIPELINE_LATENCY-NUM_LINES-1) begin
                subcounter_h <= '0;
            end else begin
                subcounter_h <= subcounter_h + 1;
                
                if (subcounter_h == NUM_LINES-1) begin
                    subcounter_h <= '0;
                end
            end
        
        
            if (counter_v == -1) begin
                subcounter_v <= '0;
            end else begin
                if (next_vertical) begin
                    subcounter_v <= subcounter_v + 1;
                    
                    if (subcounter_v == DIVIDE-1) begin
                        subcounter_v <= '0;
                    end
                end
            end
        end
    end
    
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            pixel_x <= '0;
            pixel_y <= '0;
        end else begin
            if (subcounter_h == NUM_LINES-1) begin
                pixel_x <= pixel_x + 1;
            end
        
            if (next_vertical && subcounter_v == DIVIDE-1) begin
                pixel_y <= pixel_y + 1;
            end
            

            if (counter_h == -PIPELINE_LATENCY-NUM_LINES-1) begin
                pixel_x <= '0;
            end
            
            if (counter_v == 0) begin
                pixel_y <= '0;
            end
        end
    end

    logic pixel_set;
    
    types::line_t my_line;
    logic [types::THRESH_BITS-1:0] my_thresh;
    
    logic [5:0] cur_frame;
    
    always_comb begin
        case (animation_speed)
            types::AS_SLOW: cur_frame = frame_cnt[7:2];
            types::AS_NORM: cur_frame = frame_cnt[6:1];
            types::AS_FAST: cur_frame = frame_cnt[5:0];
            types::AS_STOP: cur_frame = 0;
        endcase
    end
    
    line_rom line_rom_inst (
        .frame_i    (cur_frame),    // 64 frames
        .line_i     (subcounter_h), // 12 lines
        
        .my_line    (my_line),
        .my_thresh  (my_thresh)
    );
    
    types::line_t my_line_adjusted;
    logic [types::THRESH_BITS-1:0] my_thresh_adjusted;

    always_comb begin
        if (size == types::S_SMALL) begin
            my_line_adjusted.x0 = (my_line.x0 >> 2) + WIDTH/DIVIDE/2  - 28/2;
            my_line_adjusted.y0 = (my_line.y0 >> 2) + HEIGHT/DIVIDE/2 - 26/2;
            my_line_adjusted.x1 = (my_line.x1 >> 2) + WIDTH/DIVIDE/2  - 28/2;
            my_line_adjusted.y1 = (my_line.y1 >> 2) + HEIGHT/DIVIDE/2 - 26/2;
            
            my_thresh_adjusted = my_thresh >> 2;
        end else begin
            my_line_adjusted = my_line;
            my_thresh_adjusted = my_thresh;
        end
    end
    
    edge_function edge_function_inst (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .my_line        (my_line_adjusted),
        .my_thresh      (my_thresh_adjusted),

        .pixel_x_i      (pixel_x),
        .pixel_y_i      (pixel_y),
        .pixel_set_o    (pixel_set)
    );
    
    logic any_line_set;
    logic final_pixel;
    
    logic [3:0] linecounter_h;
    
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            any_line_set <= 1'b0;
            final_pixel <= 1'b0;
            linecounter_h <= '0;
        end else begin
        
            if (counter_h == -NUM_LINES-1) begin
                linecounter_h <= '0;
            end else begin
                linecounter_h <= linecounter_h + 1;
                
                if (linecounter_h == NUM_LINES-1) begin
                    linecounter_h <= '0;
                end
            end
        
            if (linecounter_h == NUM_LINES-1) begin
                final_pixel <= any_line_set || pixel_set;
            end else if (linecounter_h == '0) begin
                any_line_set <= pixel_set;
            end else begin
                any_line_set <= any_line_set || pixel_set;
            end
        end
    end
    
    types::fill_type_t background_fill;
    types::fill_type_t cube_fill;
    types::animation_speed_t animation_speed;
    types::animation_t animation;
    types::thickness_t thickness;
    types::size_t size;

    // Capture output color
    logic [5:0] rgb_d;
    
    logic [3:0] cur_state_cube;
    logic [3:0] cur_state_background;
    
    assign cur_state_cube = frame_cnt[11:8];
    assign cur_state_background = frame_cnt[11:8];
    
    // Size
    // ~1min -> 1 step ~1s
    always_comb begin
        case (frame_cnt[11:6])
            'd0:  size = 'x;
            'd1:  size = 'x;
            'd2:  size = 'x;
            'd3:  size = 'x;
            'd4:  size = types::S_NORMAL;
            'd5:  size = types::S_NORMAL;
            'd6:  size = types::S_NORMAL;
            'd7:  size = types::S_NORMAL;
            'd8:  size = types::S_NORMAL;
            'd9:  size = types::S_NORMAL;
            'd10: size = types::S_NORMAL;
            'd11: size = types::S_NORMAL;
            'd12: size = types::S_NORMAL;
            'd13: size = types::S_NORMAL;
            'd14: size = types::S_NORMAL;
            'd15: size = types::S_NORMAL;
            'd16: size = types::S_NORMAL;
            'd17: size = types::S_NORMAL;
            'd18: size = types::S_NORMAL;
            'd19: size = types::S_NORMAL;
            'd20: size = types::S_NORMAL;
            'd21: size = types::S_NORMAL;
            'd22: size = types::S_NORMAL;
            'd23: size = types::S_NORMAL;
            'd24: size = types::S_NORMAL;
            'd25: size = types::S_NORMAL;
            'd26: size = types::S_NORMAL;
            'd27: size = types::S_NORMAL;
            'd28: size = 'x;
            'd29: size = 'x;
            'd30: size = 'x;
            'd31: size = 'x;
            'd32: size = types::S_SMALL;
            'd33: size = types::S_SMALL;
            'd34: size = types::S_SMALL;
            'd35: size = types::S_SMALL;
            'd36: size = types::S_SMALL;
            'd37: size = types::S_SMALL;
            'd38: size = types::S_SMALL;
            'd39: size = types::S_SMALL;
            'd40: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd41: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd42: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd43: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd44: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd45: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd46: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd47: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd48: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd49: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd50: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd51: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd52: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd53: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd54: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd55: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd56: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd57: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd58: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd59: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd60: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd61: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd62: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
            'd63: size = frame_cnt[0] ^ counter_v[0] ? types::S_SMALL : types::S_NORMAL;
        endcase
    end

    // animation speed
    // ~1min -> 1 step ~1s
    always_comb begin
        case (frame_cnt[11:6])
            'd0:  animation_speed = 'x;
            'd1:  animation_speed = 'x;
            'd2:  animation_speed = 'x;
            'd3:  animation_speed = 'x;
            'd4:  animation_speed = types::AS_STOP;
            'd5:  animation_speed = types::AS_STOP;
            'd6:  animation_speed = types::AS_STOP;
            'd7:  animation_speed = types::AS_STOP;
            'd8:  animation_speed = types::AS_SLOW;
            'd9:  animation_speed = types::AS_SLOW;
            'd10: animation_speed = types::AS_SLOW;
            'd11: animation_speed = types::AS_SLOW;
            'd12: animation_speed = types::AS_NORM;
            'd13: animation_speed = types::AS_NORM;
            'd14: animation_speed = types::AS_NORM;
            'd15: animation_speed = types::AS_NORM;
            'd16: animation_speed = types::AS_FAST;
            'd17: animation_speed = types::AS_FAST;
            'd18: animation_speed = types::AS_FAST;
            'd19: animation_speed = types::AS_FAST;
            'd20: animation_speed = types::AS_NORM;
            'd21: animation_speed = types::AS_NORM;
            'd22: animation_speed = types::AS_NORM;
            'd23: animation_speed = types::AS_NORM;
            'd24: animation_speed = types::AS_SLOW;
            'd25: animation_speed = types::AS_SLOW;
            'd26: animation_speed = types::AS_SLOW;
            'd27: animation_speed = types::AS_SLOW;
            'd28: animation_speed = 'x;
            'd29: animation_speed = 'x;
            'd30: animation_speed = 'x;
            'd31: animation_speed = 'x;
            'd32: animation_speed = types::AS_STOP;
            'd33: animation_speed = types::AS_STOP;
            'd34: animation_speed = types::AS_STOP;
            'd35: animation_speed = types::AS_STOP;
            'd36: animation_speed = types::AS_SLOW;
            'd37: animation_speed = types::AS_SLOW;
            'd38: animation_speed = types::AS_SLOW;
            'd39: animation_speed = types::AS_SLOW;
            'd40: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_NORM : types::AS_STOP;
            'd41: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_NORM : types::AS_STOP;
            'd42: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_NORM : types::AS_STOP;
            'd43: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_NORM : types::AS_STOP;
            'd44: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_STOP;
            'd45: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_STOP;
            'd46: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_STOP;
            'd47: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_STOP;
            'd48: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_SLOW;
            'd49: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_SLOW;
            'd50: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_SLOW;
            'd51: animation_speed = frame_cnt[0] ^ counter_v[0] ? types::AS_FAST : types::AS_SLOW;
            'd52: animation_speed = types::AS_NORM;
            'd53: animation_speed = types::AS_NORM;
            'd54: animation_speed = types::AS_NORM;
            'd55: animation_speed = types::AS_NORM;
            'd56: animation_speed = types::AS_NORM;
            'd57: animation_speed = types::AS_NORM;
            'd58: animation_speed = types::AS_NORM;
            'd59: animation_speed = types::AS_NORM;
            'd60: animation_speed = types::AS_NORM;
            'd61: animation_speed = types::AS_NORM;
            'd62: animation_speed = types::AS_NORM;
            'd63: animation_speed = types::AS_NORM;
        endcase
    end
    
    logic [5:0] color0;
    logic [5:0] color1;
    
    logic [5:0] background_color;
    logic [5:0] cube_color;
    
    logic [5:0] color_rainbow;
    logic [5:0] color_xor;
    
    always_comb begin
        case (pixel_y[1:0] + cur_frame[1:0])
            2'd0: color_rainbow = COLOR_1;
            2'd1: color_rainbow = COLOR_2;
            2'd2: color_rainbow = COLOR_3;
            2'd3: color_rainbow = COLOR_4;
        endcase
    end
    
    assign color_xor = (pixel_x ^ pixel_y) + frame_cnt[7:2];
    
    always_comb begin
        case (background_fill)
            types::BG_COLOR0:   background_color = color0;
            types::BG_COLOR1:   background_color = color1;
            types::BG_STRIPES:  background_color = color_rainbow;
            types::BG_SPECIAL:  background_color = color_xor;
        endcase
    end
    
    always_comb begin
        case (cube_fill)
            types::BG_COLOR0:   cube_color = color0;
            types::BG_COLOR1:   cube_color = color1;
            types::BG_STRIPES:  cube_color = frame_cnt[5:0];
            types::BG_SPECIAL:  cube_color = color_xor;//frame_cnt[5:0];
        endcase
    end

    assign color0 = COLOR_BLACK;
    assign color1 = COLOR_WHITE;
    
    // background fill
    // ~1min -> 1 step ~1s
    always_comb begin
        case (frame_cnt[11:6])
            'd0:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end
            'd1:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end
            'd2:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end
            'd3:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end // --- show cube
            'd4:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd5:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd6:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd7:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end // --- start rotation, faster
            'd8:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd9:  begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd10: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd11: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd12: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd13: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd14: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd15: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd16: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd17: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd18: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end 
            'd19: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end // --- change cube color
            'd20: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end 
            'd21: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end
            'd22: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end
            'd23: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end // --- change background color
            'd24: begin background_fill = types::BG_SPECIAL; cube_fill = types::BG_COLOR1; end
            'd25: begin background_fill = types::BG_SPECIAL; cube_fill = types::BG_COLOR1; end
            'd26: begin background_fill = types::BG_SPECIAL; cube_fill = types::BG_COLOR1; end
            'd27: begin background_fill = types::BG_SPECIAL; cube_fill = types::BG_COLOR1; end // --- hide
            'd28: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end
            'd29: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end 
            'd30: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end
            'd31: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR0; end // --- show small cube, stop
            'd32: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd33: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd34: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd35: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end // --- rotate small cube slow
            'd36: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd37: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd38: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd39: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end // --- show both cubes, large is stop
            'd40: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd41: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd42: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd43: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end // --- rotate large cube
            'd44: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd45: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd46: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd47: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd48: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd49: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd50: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd51: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd52: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end
            'd53: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_COLOR1; end // - colors
            'd54: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end
            'd55: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end
            'd56: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end
            'd57: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end
            'd58: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_SPECIAL; end
            'd59: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_SPECIAL; end
            'd60: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_SPECIAL; end
            'd61: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_SPECIAL; end
            'd62: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end
            'd63: begin background_fill = types::BG_COLOR0; cube_fill = types::BG_STRIPES; end // --- end
        endcase
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            rgb_d <= '0;
        end else begin
            rgb_d <= final_pixel ? cube_color : background_color;
            
            // Blanking intervall
            if (hblank || vblank) begin
                rgb_d <= '0;
            end
        end
    end
    
    assign rrggbb_o = rgb_d;
    
    // Delay output signals
    // to account for rgb_d and other delays

    localparam OUTPUT_DELAY = PIPELINE_LATENCY-2;
    
    delay #(
        .DELAY_CYCLES(OUTPUT_DELAY)
    ) delay_inst_hsync (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .in_i   (hsync),
        .out_o  (hsync_o)
    );

    delay #(
        .DELAY_CYCLES(OUTPUT_DELAY)
    ) delay_inst_vsync (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .in_i   (vsync),
        .out_o  (vsync_o)
    );

    delay #(
        .DELAY_CYCLES(OUTPUT_DELAY)
    ) delay_inst_next_vertical (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .in_i   (next_vertical),
        .out_o  (next_vertical_o)
    );

    delay #(
        .DELAY_CYCLES(OUTPUT_DELAY)
    ) delay_inst_next_frame (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .in_i   (next_frame),
        .out_o  (next_frame_o)
    );
    
    /*
    always_ff @(posedge clk_i) begin
        hsync_o         <= hsync;
        vsync_o         <= vsync;
        next_vertical_o <= next_vertical;
        next_frame_o    <= next_frame;
    end
    */

endmodule
