`default_nettype none
`include "abc_define.vh"
`include "bram.v"

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

    wire [7:0] current_inst;
    wire inst_valid = 1'b1; // Tie high for now, assuming memory is always ready
    wire fetch_next;

    // --- INSTRUCTION MEMORY ---
    reg [11:0] program_counter;
    
    always @(posedge clk) begin
        if (reset) program_counter <= 0;
        else if (fetch_next) program_counter <= program_counter + 1;
    end

    bram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(12)
    ) imem (
        .clk(clk),
        .write_en(1'b0),
        .write_addr(12'd0),
        .write_data(8'd0),
        .read_addr(program_counter),
        .read_data(current_inst)
    );

    // --- THE STREAM CPU ---
    abc_cpu cpu (
        .clk(clk),
        .reset(reset),
        
        .next_inst(current_inst),
        .inst_valid(inst_valid),
        .fetch_next(fetch_next),
        
        .debug_state(debug)
    );

    // Stub out the unused legacy outputs so the testbench compiles
    assign tx_trigger = 1'b0;
    assign tx_data = 8'd0;

endmodule