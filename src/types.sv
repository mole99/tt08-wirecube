// SPDX-FileCopyrightText: © 2024 Leo Moser <leomoser99@gmail.com>
// SPDX-License-Identifier: Apache-2.0

package types;

    parameter LINE_BITS = 7;
    
    // Threshold = length of the line
    // at max sqrt(HEIGHT^2*WIDTH^2)
    parameter THRESH_BITS = LINE_BITS+1;

    typedef struct packed {
        // Point 0 - Start
        logic [LINE_BITS-1:0] x0;
        logic [LINE_BITS-1:0] y0;
        // Point 1 - Stop
        logic [LINE_BITS-1:0] x1;
        logic [LINE_BITS-1:0] y1;
    } line_t;
    
    typedef enum logic[2:0] {
        BG_UNDEFINED='x,
        BG_BLACK=0,
        BG_WHITE,
        BG_GREEN,
        BG_DSTRIPES,
        BG_HSTRIPES,
        BG_XOR,
        BG_FRAME,
        BG_TODO
    } fill_type_t;
    
    typedef enum logic[1:0] {
        AS_UNDEFINED='x,
        AS_SLOW=0,
        AS_NORM,
        AS_FAST,
        AS_STOP
    } animation_speed_t;
    
    typedef enum logic[0:0] {
        A_UNDEFINED='x,
        A_ROTATE=0,
        A_BOUNCE
    } animation_t;

    typedef enum logic[1:0] {
        S_UNDEFINED='x,
        S_NONE=0,
        S_NORMAL,
        S_SMALL,
        S_BOTH
    } size_t;


endpackage
