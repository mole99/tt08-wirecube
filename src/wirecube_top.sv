// SPDX-FileCopyrightText: © 2024 Leo Moser <leo.moser@pm.me>
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module wirecube_top (
    input  logic       clk_i, // 25.175 MHz * 2
    input  logic       rst_ni,
    
    input  logic [7:0] ui_in,
    
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
            subcounter_h <= 'x;
            subcounter_v <= 'x;
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
            pixel_x <= 'x;
            pixel_y <= 'x;
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

    // attributes
    types::fill_type_t background_fill;
    types::fill_type_t cube_fill;
    types::animation_speed_t animation_speed;
    types::animation_t animation;
    types::size_t size;

    logic pixel_set, pixel_set2;
    
    types::line_t my_line;
    logic [types::THRESH_BITS-1:0] my_thresh;
    
    logic [5:0] cur_frame;
    
    always_comb begin
        case (animation_speed ^ ui_in[7:6])
            types::AS_SLOW: cur_frame = frame_cnt[8:3];
            types::AS_NORM: cur_frame = frame_cnt[7:2];
            types::AS_FAST: cur_frame = frame_cnt[6:1];
            types::AS_STOP: cur_frame = 0;
            default:        cur_frame = 'x;
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
        .pixel_set_o    (pixel_set),
        .pixel_set2_o    (pixel_set2)
    );
    
    logic any_line_set, any_line_set2;
    logic final_pixel, final_pixel2;
    
    logic [3:0] linecounter_h;
    
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            any_line_set <= 1'bx;
            final_pixel <= 1'bx;
            linecounter_h <= 'x;
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
                final_pixel2 <= any_line_set2 || pixel_set2;
            end else if (linecounter_h == '0) begin
                any_line_set <= pixel_set;
                any_line_set2 <= pixel_set2;
            end else begin
                any_line_set <= any_line_set || pixel_set;
                any_line_set2 <= any_line_set2 || pixel_set2;
            end
        end
    end

    // Capture output color
    logic [5:0] rgb_d;
    
    logic [3:0] cur_state_cube;
    logic [3:0] cur_state_background;
    
    assign cur_state_cube = frame_cnt[11:8];
    assign cur_state_background = frame_cnt[11:8];
    
    // This is necessary to make iverilog happy
    types::size_t size_small_normal;
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            size_small_normal = types::S_SMALL;
        end else begin
            size_small_normal = types::S_NORMAL;
        end
    end
    
    // Size
    // ~2min -> 1 step ~1s
    always_comb begin
        case (frame_cnt[12:6])
            'd0:  size = types::S_NORMAL;
            'd1:  size = types::S_NORMAL;
            'd2:  size = types::S_NORMAL;
            'd3:  size = types::S_NORMAL;
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
            'd28: size = types::S_NORMAL;
            'd29: size = types::S_NORMAL;
            'd30: size = types::S_NORMAL;
            'd31: size = types::S_NORMAL;
            'd32: size = types::S_NORMAL;
            'd33: size = types::S_NORMAL;
            'd34: size = types::S_NORMAL;
            'd35: size = types::S_NORMAL;
            'd36: size = types::S_NORMAL;
            'd37: size = types::S_NORMAL;
            'd38: size = types::S_NORMAL;
            'd39: size = types::S_NORMAL;
            'd40: size = types::S_NORMAL;
            'd41: size = types::S_NORMAL;
            'd42: size = types::S_NORMAL;
            'd43: size = types::S_NORMAL;
            'd44: size = types::S_NORMAL;
            'd45: size = types::S_NORMAL;
            'd46: size = types::S_NORMAL;
            'd47: size = types::S_NORMAL;
            'd48: size = types::S_NORMAL;
            'd49: size = types::S_NORMAL;
            'd50: size = types::S_NORMAL;
            'd51: size = types::S_NORMAL;
            'd52: size = types::S_SMALL;
            'd53: size = types::S_SMALL;
            'd54: size = types::S_SMALL;
            'd55: size = types::S_SMALL;
            'd56: size = types::S_SMALL;
            'd57: size = types::S_SMALL;
            'd58: size = types::S_SMALL;
            'd59: size = types::S_SMALL;
            'd60: size = types::S_SMALL;
            'd61: size = types::S_SMALL;
            'd62: size = types::S_SMALL;
            'd63: size = types::S_SMALL;
            'd64: size = types::S_SMALL;
            'd65: size = types::S_SMALL;
            'd66: size = types::S_SMALL;
            'd67: size = types::S_SMALL;
            'd68: size = size_small_normal;
            'd69: size = size_small_normal;
            'd70: size = size_small_normal;
            'd71: size = size_small_normal;
            'd72: size = size_small_normal;
            'd73: size = size_small_normal;
            'd74: size = size_small_normal;
            'd75: size = size_small_normal;
            'd76: size = size_small_normal;
            'd77: size = size_small_normal;
            'd78: size = size_small_normal;
            'd79: size = size_small_normal;
            'd80: size = types::S_NORMAL;
            'd81: size = types::S_NORMAL;
            'd82: size = types::S_NORMAL;
            'd83: size = types::S_NORMAL;
            'd84: size = types::S_NORMAL;
            'd85: size = types::S_NORMAL;
            'd86: size = types::S_NORMAL;
            'd87: size = types::S_NORMAL;
            'd88: size = types::S_NORMAL;
            'd89: size = types::S_NORMAL;
            'd90: size = types::S_NORMAL;
            'd91: size = types::S_NORMAL;
            'd92: size = types::S_NORMAL;
            'd93: size = types::S_NORMAL;
            'd94: size = types::S_NORMAL;
            'd95: size = types::S_NORMAL;
            'd96: size = types::S_NORMAL;
            'd97: size = types::S_NORMAL;
            'd98: size = types::S_NORMAL;
            'd99: size = types::S_NORMAL;
            'd100: size = types::S_NORMAL;
            'd101: size = types::S_NORMAL;
            'd102: size = types::S_NORMAL;
            'd103: size = types::S_NORMAL;
            'd104: size = size_small_normal;
            'd105: size = size_small_normal;
            'd106: size = size_small_normal;
            'd107: size = size_small_normal;
            'd108: size = size_small_normal;
            'd109: size = size_small_normal;
            'd110: size = size_small_normal;
            'd111: size = size_small_normal;
            'd112: size = size_small_normal;
            'd113: size = size_small_normal;
            'd114: size = size_small_normal;
            'd115: size = size_small_normal;
            'd116: size = size_small_normal;
            'd117: size = size_small_normal;
            'd118: size = size_small_normal;
            'd119: size = size_small_normal;
            'd120: size = size_small_normal;
            'd121: size = size_small_normal;
            'd122: size = size_small_normal;
            'd123: size = size_small_normal;
            'd124: size = size_small_normal;
            'd125: size = size_small_normal;
            'd126: size = size_small_normal;
            'd127: size = size_small_normal;
            default: size = types::S_UNDEFINED;
        endcase
    end

    // This is necessary to make iverilog happy
    types::animation_speed_t as_norm_stop;
    types::animation_speed_t as_fast_stop;
    types::animation_speed_t as_fast_slow;
    types::animation_speed_t as_fast_norm;
    types::animation_speed_t as_slow_fast;
    types::animation_speed_t as_slow_norm;

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            as_norm_stop = types::AS_NORM;
        end else begin
            as_norm_stop = types::AS_STOP;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            as_fast_stop = types::AS_FAST;
        end else begin
            as_fast_stop = types::AS_STOP;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            as_fast_slow = types::AS_FAST;
        end else begin
            as_fast_slow = types::AS_SLOW;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            as_slow_fast = types::AS_SLOW;
        end else begin
            as_slow_fast = types::AS_FAST;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            as_slow_norm = types::AS_SLOW;
        end else begin
            as_slow_norm = types::AS_NORM;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            as_fast_norm = types::AS_FAST;
        end else begin
            as_fast_norm = types::AS_NORM;
        end
    end

    // animation speed
    // ~2min -> 1 step ~1s
    always_comb begin
        case (frame_cnt[12:6])
            'd0:  animation_speed = types::AS_STOP;
            'd1:  animation_speed = types::AS_STOP;
            'd2:  animation_speed = types::AS_STOP;
            'd3:  animation_speed = types::AS_STOP;
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
            'd20: animation_speed = types::AS_FAST;
            'd21: animation_speed = types::AS_FAST;
            'd22: animation_speed = types::AS_FAST;
            'd23: animation_speed = types::AS_FAST;
            'd24: animation_speed = types::AS_NORM;
            'd25: animation_speed = types::AS_NORM;
            'd26: animation_speed = types::AS_NORM;
            'd27: animation_speed = types::AS_NORM;
            'd28: animation_speed = types::AS_SLOW;
            'd29: animation_speed = types::AS_SLOW;
            'd30: animation_speed = types::AS_SLOW;
            'd31: animation_speed = types::AS_SLOW;
            'd32: animation_speed = types::AS_STOP;
            'd33: animation_speed = types::AS_UNDEFINED;
            'd34: animation_speed = types::AS_UNDEFINED;
            'd35: animation_speed = types::AS_STOP;
            'd36: animation_speed = types::AS_SLOW;
            'd37: animation_speed = types::AS_SLOW;
            'd38: animation_speed = types::AS_SLOW;
            'd39: animation_speed = types::AS_SLOW;
            'd40: animation_speed = types::AS_NORM;
            'd41: animation_speed = types::AS_NORM;
            'd42: animation_speed = types::AS_NORM;
            'd43: animation_speed = types::AS_NORM;
            'd44: animation_speed = types::AS_FAST;
            'd45: animation_speed = types::AS_FAST;
            'd46: animation_speed = types::AS_FAST;
            'd47: animation_speed = types::AS_FAST;
            'd48: animation_speed = types::AS_STOP;
            'd49: animation_speed = types::AS_UNDEFINED;
            'd50: animation_speed = types::AS_UNDEFINED;
            'd51: animation_speed = types::AS_UNDEFINED;
            'd52: animation_speed = types::AS_STOP;
            'd53: animation_speed = types::AS_STOP;
            'd54: animation_speed = types::AS_STOP;
            'd55: animation_speed = types::AS_STOP;
            'd56: animation_speed = types::AS_SLOW;
            'd57: animation_speed = types::AS_SLOW;
            'd58: animation_speed = types::AS_SLOW;
            'd59: animation_speed = types::AS_SLOW;
            'd60: animation_speed = types::AS_NORM;
            'd61: animation_speed = types::AS_NORM;
            'd62: animation_speed = types::AS_NORM;
            'd63: animation_speed = types::AS_NORM;
            'd64: animation_speed = types::AS_FAST;
            'd65: animation_speed = types::AS_FAST;
            'd66: animation_speed = types::AS_FAST;
            'd67: animation_speed = types::AS_FAST;
            'd68: animation_speed = as_fast_slow;
            'd69: animation_speed = as_fast_slow;
            'd70: animation_speed = as_fast_slow;
            'd71: animation_speed = as_fast_slow;
            'd72: animation_speed = types::AS_NORM;
            'd73: animation_speed = types::AS_NORM;
            'd74: animation_speed = types::AS_NORM;
            'd75: animation_speed = types::AS_NORM;
            'd76: animation_speed = as_slow_fast;
            'd77: animation_speed = as_slow_fast;
            'd78: animation_speed = as_slow_fast;
            'd79: animation_speed = as_slow_fast;
            'd80: animation_speed = types::AS_NORM;
            'd81: animation_speed = types::AS_NORM;
            'd82: animation_speed = types::AS_NORM;
            'd83: animation_speed = types::AS_NORM;
            'd84: animation_speed = types::AS_NORM;
            'd85: animation_speed = types::AS_NORM;
            'd86: animation_speed = types::AS_NORM;
            'd87: animation_speed = types::AS_NORM;
            'd88: animation_speed = types::AS_NORM;
            'd89: animation_speed = types::AS_NORM;
            'd90: animation_speed = types::AS_NORM;
            'd91: animation_speed = types::AS_NORM;
            'd92: animation_speed = types::AS_NORM;
            'd93: animation_speed = types::AS_NORM;
            'd94: animation_speed = types::AS_NORM;
            'd95: animation_speed = types::AS_NORM;
            'd96: animation_speed = types::AS_NORM;
            'd97: animation_speed = types::AS_NORM;
            'd98: animation_speed = types::AS_NORM;
            'd99: animation_speed = types::AS_NORM;
            'd100: animation_speed = types::AS_NORM;
            'd101: animation_speed = types::AS_NORM;
            'd102: animation_speed = types::AS_NORM;
            'd103: animation_speed = types::AS_NORM;
            'd104: animation_speed = as_slow_norm;
            'd105: animation_speed = as_slow_norm;
            'd106: animation_speed = as_slow_norm;
            'd107: animation_speed = as_slow_norm;
            'd108: animation_speed = types::AS_NORM;
            'd109: animation_speed = types::AS_NORM;
            'd110: animation_speed = types::AS_NORM;
            'd111: animation_speed = types::AS_NORM;
            'd112: animation_speed = as_fast_norm;
            'd113: animation_speed = as_fast_norm;
            'd114: animation_speed = as_fast_norm;
            'd115: animation_speed = as_fast_norm;
            'd116: animation_speed = types::AS_NORM;
            'd117: animation_speed = types::AS_NORM;
            'd118: animation_speed = types::AS_NORM;
            'd119: animation_speed = types::AS_NORM;
            'd120: animation_speed = as_slow_norm;
            'd121: animation_speed = as_slow_norm;
            'd122: animation_speed = as_slow_norm;
            'd123: animation_speed = as_slow_norm;
            'd124: animation_speed = as_slow_norm;
            'd125: animation_speed = as_slow_norm;
            'd126: animation_speed = as_slow_norm;
            'd127: animation_speed = as_slow_norm;
            default: animation_speed = types::AS_UNDEFINED;
        endcase
    end
    
    logic [5:0] background_color;
    logic [5:0] cube_color, cube_color2;
    
    logic [5:0] color_rainbow;
    logic [5:0] color_diagonal;
    logic [5:0] color_horizontal;
    logic [5:0] color_xor;
    
    assign color_xor = (pixel_x ^ pixel_y) + frame_cnt[7:2];
    
    logic [11:0] counter_diagonal;
    assign counter_diagonal = (counter_h + counter_v) + {4'd0, frame_cnt};
    
    logic [11:0] counter_horizontal;
    assign counter_horizontal = counter_v + {4'd0, frame_cnt};

    assign color_rainbow = counter_horizontal;

    always_comb begin
        case (counter_diagonal[7:6])
            2'd0: color_diagonal = COLOR_1;
            2'd1: color_diagonal = COLOR_2;
            2'd2: color_diagonal = COLOR_3;
            2'd3: color_diagonal = COLOR_4;
            default: color_diagonal = 'x;
        endcase
    end

    always_comb begin
        case (counter_horizontal[6:5])
            2'd0: color_horizontal = COLOR_1;
            2'd1: color_horizontal = COLOR_2;
            2'd2: color_horizontal = COLOR_3;
            2'd3: color_horizontal = COLOR_4;
            default: color_horizontal = 'x;
        endcase
    end

    
    always_comb begin
        case (background_fill ^ ui_in[2:0])
            types::BG_BLACK:    background_color = COLOR_BLACK;
            types::BG_WHITE:    background_color = COLOR_WHITE;
            types::BG_GREEN:    background_color = COLOR_3;
            types::BG_DSTRIPES: background_color = color_diagonal;
            types::BG_HSTRIPES: background_color = color_horizontal;
            types::BG_XOR:      background_color = color_xor;
            types::BG_FRAME:    background_color = frame_cnt[7:2];
            types::BG_TODO:     background_color = color_rainbow;
            default: background_color = 'x;
        endcase
    end
    
    always_comb begin
        case (cube_fill ^ ui_in[5:3])
            types::BG_BLACK:    cube_color = COLOR_BLACK;
            types::BG_WHITE:    cube_color = COLOR_WHITE;
            types::BG_GREEN:    cube_color = COLOR_3;
            types::BG_DSTRIPES: cube_color = color_diagonal;
            types::BG_HSTRIPES: cube_color = color_horizontal;
            types::BG_XOR:      cube_color = color_xor;
            types::BG_FRAME:    cube_color = frame_cnt[7:2];
            types::BG_TODO:     cube_color = color_rainbow;
            default: cube_color = 'x;
        endcase
    end
    
    assign cube_color2 = COLOR_BLACK;

    // This is necessary to make iverilog happy
    types::fill_type_t bg_frame_xor;
    types::fill_type_t bg_diagonal_horizontal;
    types::fill_type_t bg_xor_frame;
    types::fill_type_t bg_todo_xor;
    types::fill_type_t bg_black_white;
    types::fill_type_t bg_white_black;
    types::fill_type_t bg_xor_black;
    types::fill_type_t bg_todo_black;
    types::fill_type_t bg_black_hstripes;
    types::fill_type_t bg_hstripes_black;
    types::fill_type_t bg_black_dstripes;
    types::fill_type_t bg_dstripes_black;

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_frame_xor = types::BG_FRAME;
        end else begin
            bg_frame_xor = types::BG_XOR;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_diagonal_horizontal = types::BG_DSTRIPES;
        end else begin
            bg_diagonal_horizontal = types::BG_HSTRIPES;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_xor_frame = types::BG_XOR;
        end else begin
            bg_xor_frame = types::BG_FRAME;
        end
    end
    
    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_todo_xor = types::BG_TODO;
        end else begin
            bg_todo_xor = types::BG_XOR;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_black_white = types::BG_BLACK;
        end else begin
            bg_black_white = types::BG_WHITE;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_white_black = types::BG_WHITE;
        end else begin
            bg_white_black = types::BG_BLACK;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_xor_black = types::BG_XOR;
        end else begin
            bg_xor_black = types::BG_BLACK;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_todo_black = types::BG_TODO;
        end else begin
            bg_todo_black = types::BG_BLACK;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_black_hstripes = types::BG_HSTRIPES;
        end else begin
            bg_black_hstripes = types::BG_BLACK;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_hstripes_black = types::BG_BLACK;
        end else begin
            bg_hstripes_black = types::BG_HSTRIPES;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_black_dstripes = types::BG_DSTRIPES;
        end else begin
            bg_black_dstripes = types::BG_BLACK;
        end
    end

    always_comb begin
        if (frame_cnt[0] ^ counter_v[0]) begin
            bg_dstripes_black = types::BG_BLACK;
        end else begin
            bg_dstripes_black = types::BG_DSTRIPES;
        end
    end

    // background and cube fill
    // ~2min -> 1 step ~1s
    always_comb begin
        case (frame_cnt[12:6])
            'd0:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd1:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd2:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd3:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd4:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd5:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd6:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd7:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd8:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd9:  begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd10: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd11: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd12: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd13: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd14: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd15: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd16: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd17: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd18: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end 
            'd19: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd20: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end 
            'd21: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd22: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd23: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd24: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd25: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd26: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd27: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd28: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd29: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end 
            'd30: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd31: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd32: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd33: begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd34: begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd35: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd36: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd37: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd38: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd39: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd40: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd41: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd42: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd43: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd44: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd45: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd46: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd47: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd48: begin background_fill = types::BG_WHITE; cube_fill = types::BG_WHITE; end
            'd49: begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd50: begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd51: begin background_fill = types::BG_BLACK; cube_fill = types::BG_BLACK; end
            'd52: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd53: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd54: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd55: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd56: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd57: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd58: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd59: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd60: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd61: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd62: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd63: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd64: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd65: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd66: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd67: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd68: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd69: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd70: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd71: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd72: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd73: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd74: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd75: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd76: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd77: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd78: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd79: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd80: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd81: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd82: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd83: begin background_fill = types::BG_BLACK; cube_fill = types::BG_WHITE; end
            'd84: begin background_fill = types::BG_DSTRIPES; cube_fill = types::BG_WHITE; end
            'd85: begin background_fill = types::BG_DSTRIPES; cube_fill = types::BG_WHITE; end
            'd86: begin background_fill = types::BG_BLACK; cube_fill = types::BG_DSTRIPES; end
            'd87: begin background_fill = types::BG_BLACK; cube_fill = types::BG_DSTRIPES; end
            'd88: begin background_fill = types::BG_HSTRIPES; cube_fill = types::BG_WHITE; end
            'd89: begin background_fill = types::BG_HSTRIPES; cube_fill = types::BG_WHITE; end
            'd90: begin background_fill = types::BG_BLACK; cube_fill = types::BG_HSTRIPES; end
            'd91: begin background_fill = types::BG_BLACK; cube_fill = types::BG_HSTRIPES; end
            'd92: begin background_fill = types::BG_XOR; cube_fill = types::BG_WHITE; end
            'd93: begin background_fill = types::BG_XOR; cube_fill = types::BG_WHITE; end
            'd94: begin background_fill = types::BG_BLACK; cube_fill = types::BG_XOR; end
            'd95: begin background_fill = types::BG_BLACK; cube_fill = types::BG_XOR; end
            'd96: begin background_fill = types::BG_FRAME; cube_fill = types::BG_WHITE; end
            'd97: begin background_fill = types::BG_FRAME; cube_fill = types::BG_WHITE; end
            'd98: begin background_fill = types::BG_BLACK; cube_fill = types::BG_FRAME; end
            'd99: begin background_fill = types::BG_BLACK; cube_fill = types::BG_FRAME; end
            'd100: begin background_fill = types::BG_TODO; cube_fill = types::BG_WHITE; end
            'd101: begin background_fill = types::BG_TODO; cube_fill = types::BG_WHITE; end
            'd102: begin background_fill = types::BG_BLACK; cube_fill = types::BG_TODO; end
            'd103: begin background_fill = types::BG_BLACK; cube_fill = types::BG_TODO; end
            'd104: begin background_fill = types::BG_BLACK; cube_fill = bg_diagonal_horizontal; end
            'd105: begin background_fill = types::BG_BLACK; cube_fill = bg_diagonal_horizontal; end
            'd106: begin background_fill = types::BG_BLACK; cube_fill = bg_diagonal_horizontal; end
            'd107: begin background_fill = types::BG_BLACK; cube_fill = bg_diagonal_horizontal; end
            'd108: begin background_fill = bg_black_white; cube_fill = bg_frame_xor; end
            'd109: begin background_fill = bg_black_white; cube_fill = bg_xor_frame; end
            'd110: begin background_fill = bg_black_white; cube_fill = bg_frame_xor; end
            'd111: begin background_fill = bg_black_white; cube_fill = bg_xor_frame; end
            'd112: begin background_fill = bg_xor_black; cube_fill = bg_frame_xor; end
            'd113: begin background_fill = bg_xor_black; cube_fill = bg_xor_frame; end
            'd114: begin background_fill = bg_xor_black; cube_fill = bg_frame_xor; end
            'd115: begin background_fill = bg_xor_black; cube_fill = bg_xor_frame; end
            'd116: begin background_fill = bg_todo_black; cube_fill = bg_todo_xor; end
            'd117: begin background_fill = bg_todo_black; cube_fill = bg_todo_xor; end
            'd118: begin background_fill = bg_todo_black; cube_fill = bg_todo_xor; end
            'd119: begin background_fill = bg_todo_black; cube_fill = bg_todo_xor; end
            'd120: begin background_fill = bg_black_hstripes; cube_fill = bg_diagonal_horizontal; end
            'd121: begin background_fill = bg_hstripes_black; cube_fill = bg_frame_xor; end
            'd122: begin background_fill = bg_black_hstripes; cube_fill = bg_xor_frame; end
            'd123: begin background_fill = bg_hstripes_black; cube_fill = bg_todo_xor; end
            'd124: begin background_fill = bg_black_dstripes; cube_fill = bg_diagonal_horizontal; end
            'd125: begin background_fill = bg_dstripes_black; cube_fill = bg_frame_xor; end
            'd126: begin background_fill = bg_black_dstripes; cube_fill = bg_xor_frame; end
            'd127: begin background_fill = bg_dstripes_black; cube_fill = bg_todo_xor; end
            default: begin background_fill = types::BG_UNDEFINED; cube_fill = types::BG_UNDEFINED; end
        endcase
    end

    // Final color mixing
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            rgb_d <= 'x;
        end else begin
            rgb_d <= final_pixel ? cube_color : final_pixel2 ? cube_color2: background_color;
            
            // Blanking interval
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

endmodule
