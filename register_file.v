`include "abc_define.vh"

module register_file (
    input clk,
    input reset,

    // Write Port (Used when saving the final math result)
    input write_enable,
    input [`REG_AWIDTH-1:0] write_addr,
    input [`REG_DWIDTH-1:0] write_data,

    // Read Port A (For checking the destination's current value)
    input [`REG_AWIDTH-1:0] read_addr_a,
    output reg [`REG_DWIDTH-1:0] read_data_a,

    // Read Port B (For checking the source's current value)
    input [`REG_AWIDTH-1:0] read_addr_b,
    output reg [`REG_DWIDTH-1:0] read_data_b
);

    // This is the actual 2D hardware array!
    // It creates 32 slots (1 << 5), each 8 bits wide.
    reg [`REG_DWIDTH-1:0] memory [0:(1<<`REG_AWIDTH)-1];

    integer i;

    // Synchronous Writes (Happens on the clock edge)
    always @(posedge clk) begin
        if (reset) begin
            // Clear all registers to 0 on boot
            for (i = 0; i < (1<<`REG_AWIDTH); i = i + 1) begin
                memory[i] <= 0;
            end
        end else if (write_enable) begin
            memory[write_addr] <= write_data;
        end
    end

    // Asynchronous Reads (Outputs update instantly when address changes)
    always @(*) begin
        read_data_a = memory[read_addr_a];
        read_data_b = memory[read_addr_b];
    end

endmodule
