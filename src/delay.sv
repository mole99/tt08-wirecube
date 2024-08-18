// SPDX-FileCopyrightText: © 2024 Leo Moser <leo.moser@pm.me>
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module delay #(
    parameter DELAY_CYCLES=1
)(
    input  logic clk_i,   // clock
    input  logic rst_ni,  // reset, negative
    input  logic in_i,    // input
    output logic out_o    // delayed output
);

    logic [DELAY_CYCLES-1:0] pipe;

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            pipe <= '0;
        end else begin
        
            if (DELAY_CYCLES == 1) begin
                pipe <= in_i;
            end else begin
                pipe <= {pipe[DELAY_CYCLES-2:0], in_i};
            end
        end
    end
    
    assign out_o = pipe[DELAY_CYCLES-1];

endmodule
