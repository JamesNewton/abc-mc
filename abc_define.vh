
`ifndef ABC_CONFIG_VH
`define ABC_CONFIG_VH

// --- ALU CONFIGURATION ---
// Comment out a define to remove it from the silicon and save area.
`define MAKE_MUL      // Instantiates multi-cycle shift-and-add multiplier
// `define FAST_MUL   // Uses DSP blocks or heavy combinational logic for multiplication
`define MAKE_DIV      // Instantiates a multi-cycle Restoring Division state machine

// Internal macro to flag if the multi-cycle engine is needed at all
`ifdef MAKE_MUL
    `define MULTI_CYCLE_MATH
`endif
`ifdef MAKE_DIV
    `ifndef MULTI_CYCLE_MATH
        `define MULTI_CYCLE_MATH
    `endif
`endif

`define RX_WIDTH 8
`define REG_AWIDTH 5
`define REG_DWIDTH 8
`define OP_AWIDTH 8

// In macros, we have to be careful with math, 
// but the compiler will evaluate this literal perfectly.
`define ASCII_OFFSET ("a" - "`")

`define ASCII_CR 8'd13
`define ASCII_LF 8'd10
//`define ASCII_NULL 8'd0 stupid. Thinks macro is undefined because it's null

`endif