// --- 1. THE CPU MODULE ---
module abc_cpu(
    input clk,
    input reset,
    input [7:0] rx_byte,
    input rx_ready,
    output reg [1:0] state,
    output reg [7:0] debug,
    output reg [4:0] dst_sel, 
    output reg [7:0] op_sel,
    output reg [4:0] src_sel
);

    localparam STATE_DST = 2'd0;
    localparam STATE_OP  = 2'd1;
    localparam STATE_SRC = 2'd2; 

    reg [1:0] fsm_state;

    always @(posedge clk) begin
        if (reset) begin
            fsm_state <= STATE_DST;
            dst_sel   <= 0;
            op_sel    <= 0;
            src_sel   <= 0;
        end else if (rx_ready) begin
            case (fsm_state)
                STATE_DST: begin
                    dst_sel <= rx_byte[4:0] - 5'd1; 
                    fsm_state <= STATE_OP;
                end
                
                STATE_OP: begin
                    op_sel <= rx_byte;        
                    fsm_state <= STATE_SRC;
                end
                
                STATE_SRC: begin
                    if (rx_byte == 8'd10 || rx_byte == 8'd13) begin
                        fsm_state <= STATE_DST;
                    end else begin
                        src_sel <= rx_byte[4:0] - 5'd1; 
                        fsm_state <= STATE_OP;
                    end
                end
                default: fsm_state <= STATE_DST;
            endcase
        end
    end

    always @(*) begin
        state = fsm_state;
        debug = rx_byte;
    end
endmodule


// --- 2. THE TESTBENCH (Standard Icarus Verilog) ---
module testbench(); // No ports on standard testbenches!

    // We generate the clock and reset ourselves
    reg clk = 0;
    reg reset = 1;
    
    // Wires to hook up to the CPU outputs
    wire [1:0] state;   
    wire [7:0] debug;
    wire [4:0] dst_sel;
    wire [7:0] op_sel;
    wire [4:0] src_sel;

    // Registers to feed the CPU inputs
    reg [7:0] rx_byte = 0;
    reg rx_ready = 0;

    reg [7:0] rom [0:255];
    reg [7:0] pc = 0;       
    reg [7:0] cycle = 0;    

    abc_cpu cpu (
        .clk(clk),
        .reset(reset),
        .rx_byte(rx_byte),
        .rx_ready(rx_ready),
        .state(state),
        .debug(debug),
        .dst_sel(dst_sel),  
        .op_sel(op_sel),    
        .src_sel(src_sel)   
    );

    // Generate a physical clock (toggles every 5 time units)
    always #5 clk = ~clk;

    initial begin
        // Let the simulator know to track waveforms if supported
        $dumpfile("dump.vcd");
        $dumpvars(0, testbench);

        rom[0] = "a";
        rom[1] = "+";
        rom[2] = "5";
        rom[3] = 8'd10; // Newline (\n)
        rom[4] = 8'd0;  // Null terminator
        
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
                
                // IT WORKS HERE! %0t prints the exact simulation time
                $display("[%0t] INJECT: '%c' (0x%h) | FSM stepping to: %d", $time, rom[pc], rom[pc], state);
                pc <= pc + 1;
            end 
            else if (rom[pc] == 0 && cycle[1:0] == 2'b00) begin
                $display("\n--- TEST COMPLETE ---");
                if (state == 2'd0) begin
                    $display("[PASS] FSM successfully returned to STATE_DST.");
                end else begin
                    $display("[FAIL] CPU is stuck in state: %d", state);
                end
                
                $finish; // Stop the simulator
            end
        end
    end
endmodule
