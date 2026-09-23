
`ifndef ABC_CONFIG_VH
`define ABC_CONFIG_VH

// --- ALU CONFIGURATION ---
// Uncomment ONE of the following to set the math hardware capability:
// `define NO_MUL_DIV      // No math support (saves area)
// `define FAST_MUL_DIV    // Uses DSP blocks or heavy combinational logic
`define MAKE_MUL_DIV       // Instantiates the 32-cycle shift-and-add state machine

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