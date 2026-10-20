`default_nettype none
`include "abc_define.vh"

module top (
    input wire clk,
    input wire reset,
    
    // Legacy ports expected by testbench.v
    input wire [`RX_WIDTH-1:0] rx_byte,
    input wire rx_ready,
    output wire [7:0] debug,
    output wire tx_trigger,
    output wire [7:0] tx_data
);

    wire [1:0] cpu_state;

    // --- THE STREAM CPU ---
    abc_cpu cpu (
        .clk(clk),
        .reset(reset),
        
        .rx_byte(rx_byte),
        .rx_ready(rx_ready),
        .state(cpu_state),
        
        // These are legacy output ports left in the CPU definition, 
        // we can safely leave them unconnected here since the register 
        // file is now internal.
        .dst_sel(),
        .op_sel(),
        .src_sel(),
        .literal_num(),
        .src_is_literal(),
        
        // Tie off legacy unused inputs
        .reg_data_a(32'd0),
        .reg_data_b(32'd0),
        
        .reg_write_en(),
        .reg_write_data(),
        .debug(debug)
    );

    // Stub out the unused legacy outputs so the testbench compiles
    assign tx_trigger = 1'b0;
    assign tx_data = 8'd0;

endmodule