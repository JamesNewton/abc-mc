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
    
    // Simulates sending a single character via UART
    task send_byte(input [7:0] char);
    begin
        // Wait for the falling edge of the clock to change inputs
        // (This prevents race conditions with the CPU's posedge clk)
        @(negedge clk); 
        rx_byte = char;
        rx_ready = 1;
        
        @(negedge clk);
        rx_ready = 0;
        
        // Give the CPU FSM 2 full clock cycles to process the byte
        repeat(2) @(negedge clk); 
    end
    endtask

    // Simulates typing a string of up to 16 characters
    task send_string(input [127:0] str);
        integer i;
        reg [7:0] current_char;
    begin
        // Loop through the 16 possible characters, from MSB to LSB
        for (i = 15; i >= 0; i = i - 1) begin
            // Shift the string right to isolate the specific byte
            current_char = (str >> (i * 8)) & 8'hFF;
            
            // Only send valid characters (skip the zero-padding)
            if (current_char != 8'h00) begin
                send_byte(current_char);
            end
        end
    end
    endtask

    // Simulates sending a string (character by character)
    // Note: Verilog-2001 doesn't handle strings elegantly, so we 
    // sequence individual bytes to mimic typing "a+42\n".
    task send_command(
        input [7:0] c1, input [7:0] c2, input [7:0] c3, input [7:0] c4, input [7:0] c5
    );
    begin
        if (c1) send_byte(c1);
        if (c2) send_byte(c2);
        if (c3) send_byte(c3);
        if (c4) send_byte(c4);
        if (c5) send_byte(c5);
    end
    endtask

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
        repeat(2) @(negedge clk);

        $display("\n--- Direct Assignment ---");
        // Because : isn't a defined operator, the ALU defaults to passing the literal through!
        send_string("b:5\n");
        send_string("c:10\n");
        assert_register("b", 5);
        assert_register("c", 10);

        $display("\n--- Addition and chaining ---");
        // This will execute:
        // 1. a:b (a becomes 5)
        // 2. a+c (a becomes 5 + 10)
        // 3. \n  (Executes the addition, saving 15 to a)
        send_string("a:b+c\n"); 
        
        assert_register("a", 15);

        $display("\n--- ALL TESTS COMPLETED SUCCESSFULLY ---");

        $display("\n--- Terminal Output ---");
        send_string("a:65\n"); // Load 'a' with 65 ASCII for 'A'
        assert_register("a", 65);

        send_string("t:a\n"); // Send the value of 'a' to the terminal 't'
        @(posedge clk); // 1 extra clock cycle; pipeline hits STATE_EXEC
        if (tx_data === 8'd65) begin
            $display("[PASS] Terminal received 65 ('A')");
        end else begin
            $display("[FAIL] Terminal did not receive data. Got trigger: %b, data: %d", tx_trigger, tx_data);
            $finish;
        end

        send_string("r:16\n"); 
        assert_register("r", 16);
        send_string("f:10\n"); 
        assert_register("f", 16);
        send_string("g:f\n");
        assert_register("g", 15);
        // Reset to Base 10. Note that we are in hex, so 10 is a
        send_string("r:a\n");

// `ifdef NO_MUL_DIV
        send_string("a:7*6\n"); 
`ifdef MAKE_MUL
        // Keep the simulation running long enough to finish the work. 
        repeat(`REG_DWIDTH + 8 ) @(posedge clk);
        $display("Multi-Cycle Multiplication test:");
`endif
`ifdef FAST_MUL
        $display("Fast Logic Multiplication (high cost):");
`endif
        assert_register("a", 42);
// `endif

`ifdef MAKE_DIV
        send_string("a:42/6\n");
        repeat(`REG_DWIDTH + 8) @(posedge clk);
        $display("Multi-Cycle Division test:");
        assert_register("a", 7);
`endif

        $finish; 
    end

endmodule
