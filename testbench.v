`include "abc_define.vh"

// --- THE TESTBENCH ---
module testbench(); 

    // We generate the clock and reset ourselves
    reg clk = 0;
    reg reset = 1;
    
    // We only need the wires that are actually exposed by top.v
    wire [7:0] debug;
    // Registers to feed the CPU inputs
    reg [`RX_WIDTH-1:0] rx_byte = 0;
    reg rx_ready = 0;

    reg [7:0] rom [0:255];
    reg [7:0] pc = 0;       
    reg [7:0] cycle = 0;    

    // Instantiate the Motherboard, NOT the CPU!
    top system_top (
        .clk(clk),
        .reset(reset),
        .rx_byte(rx_byte),
        .rx_ready(rx_ready),
        .debug(debug)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, testbench);

        // Test a multi-digit number: a + 42 \n
        rom[0] = "a";
        rom[1] = "+";
        rom[2] = "4";
        rom[3] = "2";
        rom[4] = `ASCII_LF; 
        rom[5] = 8'd0;  // Null terminator

        // Hold reset for a moment, then let the CPU boot
        #15 reset = 0;
    end

    // The Automated Test Feeder
    always @(posedge clk) begin
        if (reset) begin
            pc <= 0;
            cycle <= 0;
            rx_ready <= 0;
        end else begin
            cycle <= cycle + 1;
            rx_ready <= 0; 

            if (cycle[1:0] == 2'b00 && rom[pc] != 0) begin
                rx_byte <= rom[pc];
                rx_ready <= 1;
                
                // SPYING ON INTERNAL SIGNALS: 
                // We use system_top.cpu... to peek inside the motherboard and CPU!
                $display("[%0t] INJECT: '%c' | FSM: %d | LITERAL_NUM: %d", 
                         $time, 
                         rom[pc], 
                         system_top.cpu.state, 
                         system_top.cpu.literal_num);
                pc <= pc + 1;
            end 
            else if (rom[pc] == 0 && cycle[1:0] == 2'b00) begin
                $display("\n--- TEST COMPLETE ---");
                if (system_top.cpu.state == 0) begin
                    $display("[PASS] Final Literal Num parsed as: %d", system_top.cpu.literal_num);
                end else begin
                    $display("[FAIL] CPU is stuck in state: %d", system_top.cpu.state);
                end
                
                $finish; // Stop the simulator
            end
        end
    end
endmodule
