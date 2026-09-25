`include "abc_define.vh"
`include "top.v"

// --- THE TESTBENCH ---
module testbench(); 

    // We generate the clock and reset ourselves
    reg clk = 0;
    reg reset = 1;
    
    // We only need the wires that are actually exposed by top.v
    wire [7:0] debug;
    // Registers to take CPU outputs
    wire tx_trigger;
    wire [7:0] tx_data;
    // Registers to feed the CPU inputs
    reg [`RX_WIDTH-1:0] rx_byte = 0;
    reg rx_ready = 0;

    top system_top (
        .clk(clk),
        .reset(reset),
        .rx_byte(rx_byte),
        .rx_ready(rx_ready),
        .debug(debug),
        .tx_trigger(tx_trigger),
        .tx_data(tx_data)
    );

    // Generate physical clock
    always #5 clk = ~clk;

    // ==========================================
    // TEST API (Helper Functions)
    // ==========================================
    
    // Our Assertion Framework
    task assert_literal(input [`REG_DWIDTH-1:0] expected);
    begin
        // We peek into the motherboard to check the CPU state
        if (system_top.cpu.literal_num !== expected) begin
            $display("[FAIL] Expected %d, but got %d", expected, system_top.cpu.literal_num);
            $finish;
        end else begin
            $display("[PASS] Literal accumulated correctly: %d", expected);
        end
    end
    endtask

    // Peeks directly into the Register File memory grid to check a value!
    task assert_register(input [7:0] reg_char, input [`REG_DWIDTH-1:0] expected);
        integer addr;
        reg [`REG_DWIDTH-1:0] actual;
    begin
        // Calculate the same address the CPU uses
        addr = reg_char[`REG_AWIDTH-1:0] - `ASCII_OFFSET; 
        
        // Wait 1 extra clock cycle for the Writeback pulse to finish saving to silicon
        @(posedge clk); 
        
        actual = system_top.regs.memory[addr];
        
        if (actual !== expected) begin
            $display("[FAIL] Register '%c': Expected %d, but got %d", reg_char, expected, actual);
            $finish;
        end else begin
            $display("[PASS] Register '%c' successfully stored: %d", reg_char, expected);
        end
    end
    endtask

    // ==========================================
    // TEST EXECUTION SEQUENCE
    // ==========================================
initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, testbench);

        #15 reset = 0;
        repeat(60) @(posedge clk);
        assert_register("a", 42);
        $finish; 
    end

endmodule
