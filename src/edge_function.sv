// SPDX-FileCopyrightText: © 2024 Leo Moser <leo.moser@pm.me>
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module edge_function (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  types::line_t      my_line,
    input  logic [types::THRESH_BITS-1:0] my_thresh,

    input  logic [types::LINE_BITS-1:0]   pixel_x_i,
    input  logic [types::LINE_BITS-1:0]   pixel_y_i,
    output logic                          pixel_set_o,
    output logic                          pixel_set2_o
);
    
    localparam PIPELINE_LATENCY = 2;
    
    // Calculate the edge function for the current pixel position and the line
    // E(P) = (P.x - V0.x) * (V1.y - V0.y) - (P.y - V0.y) * (V1.x - V0.x)
    // Points are already sorted (P0.y <= P1.y)
    
    // Step 0: left or right side?
    
    types::line_t ordered_line;
    
    logic swap_points;
    assign swap_points = my_line.y0 > my_line.y1;
    
    always_comb begin
        // Swap points
        if (swap_points) begin
            ordered_line = {my_line.x1, my_line.y1, my_line.x0, my_line.y0};
        // Already ordered
        end else begin
            ordered_line = my_line;
        end
    end
    

    // Step 1: Calculate all subtractions
    // Terms are reordered, no negative values possible
    logic [types::LINE_BITS-1:0] term0, term1, term2, term3;
    
    // Is the pixel above, below, right or left to the line?
    logic left_or_right; // 0 = left, 1 = right
    assign left_or_right = ordered_line.x1 >= ordered_line.x0;
    
    // Store the visibility until the very end
    logic visible, not_visible_y, not_visible_x;
    
    assign not_visible_y = pixel_y_i > ordered_line.y1 || pixel_y_i <ordered_line.y0;
    assign not_visible_x = left_or_right ? pixel_x_i > ordered_line.x1 || pixel_x_i < ordered_line.x0
                                       : pixel_x_i < ordered_line.x1 || pixel_x_i > ordered_line.x0;
    
    always_ff @(posedge clk_i) begin
        // Left side
        if (left_or_right == 1'b0) begin
            term0 <= ordered_line.x0 - pixel_x_i;
            term1 <= ordered_line.y1 - pixel_y_i;
            term2 <= pixel_x_i - ordered_line.x1;
            term3 <= pixel_y_i - ordered_line.y0;
        
        // Right side
        end else begin
            term0 <= pixel_x_i - ordered_line.x0;
            term1 <= ordered_line.y1 - pixel_y_i;
            term2 <= ordered_line.x1 - pixel_x_i;
            term3 <= pixel_y_i - ordered_line.y0;

        end
        
        visible <= !(not_visible_y || not_visible_x);
    end
    
    // Step 2: Multiplication + Subtraction
    logic [types::LINE_BITS*2-1:0] mul1, mul2;
    logic [types::LINE_BITS*2-1:0] absolute;
    
    logic visible_2;
    
    assign mul1 = term0 * term1;
    assign mul2 = term2 * term3;
    
    always_ff @(posedge clk_i) begin
        // Get the absolute difference, sign does not matter
        if (mul1 > mul2) begin
            absolute <= mul1 - mul2;
        end else begin
            absolute <= mul2 - mul1;
        end
        
        visible_2 <= visible;
    end
    
    // Step 3: Subtraction
    
    /*logic visible_3;
    
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            absolute <= '0;
            visible_3 <= 1'b0;
        end else begin
        
            // Get the absolute difference, sign does not matter
            if (mul1 > mul2) begin
                absolute <= mul1 - mul2;
            end else begin
                absolute <= mul2 - mul1;
            end
            
            visible_3 <= visible_2;
        end
    end*/
    
    // Step 4: Is the pixel visible and inside the threshold?
    
    assign pixel_set_o = visible_2 && absolute < my_thresh;
    // Thicker line
    assign pixel_set2_o = visible_2 && absolute < (my_thresh*2);

endmodule
