`include "abc_define.vh"

module top(
    input clk,
    input reset,
    input [`RX_WIDTH-1:0] rx_byte,
    input rx_ready,
    output [7:0] debug
);

    // --- Internal Motherboard Wires ---
    wire [`REG_AWIDTH-1:0] dst_addr;
    wire [`REG_AWIDTH-1:0] src_addr;
    wire [`REG_DWIDTH-1:0] reg_data_a;
    wire [`REG_DWIDTH-1:0] reg_data_b;
    wire reg_write_en;
    wire [`REG_DWIDTH-1:0] reg_write_data;
    
    // (We will leave op_sel and literal_num internal to the CPU for now)

    // --- The CPU Chip ---
    abc_cpu cpu (
        .clk(clk),
        .reset(reset),
        .rx_byte(rx_byte),
        .rx_ready(rx_ready),
        .debug(debug),
        
        .dst_sel(dst_addr),
        .src_sel(src_addr),
        
        // Connect the memory bus
        .reg_data_a(reg_data_a),
        .reg_data_b(reg_data_b),
        .reg_write_en(reg_write_en),
        .reg_write_data(reg_write_data)
    );

    // --- The Register File Chip ---
    register_file regs (
        .clk(clk),
        .reset(reset),
        
        // Write Port (Driven by CPU)
        .write_enable(reg_write_en),
        .write_addr(dst_addr),
        .write_data(reg_write_data),
        
        // Read Ports (Feeding into CPU)
        .read_addr_a(dst_addr),
        .read_data_a(reg_data_a),
        .read_addr_b(src_addr),
        .read_data_b(reg_data_b)
    );

endmodule