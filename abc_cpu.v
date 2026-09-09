`include "abc_define.vh"

// --- 1. THE CPU MODULE ---
module abc_cpu#(
    // Defining parameters here allows the ports to use them.
    parameter STATE_DST = 0,
    parameter STATE_OP  = STATE_DST + 1,
    parameter STATE_SRC = STATE_OP + 1,
    parameter STATE_NUM = STATE_SRC + 1, // NEW STATE!
    parameter STATE_MAX = STATE_NUM + 1,
    parameter STATE_WIDTH = $clog2(STATE_MAX)
)(
    input clk,
    input reset,
    input [`RX_WIDTH-1:0] rx_byte,
    input rx_ready,
    
    output reg [STATE_WIDTH-1:0] state, 
    //heart of the cpu. Directs inst bytes to:
    // 0. Destination select (dst_sel)
    // 1. Operation select (op_sel)
    // 2. Source select (src_sel)
    // and then back to op_sel until the op is carriage return.
    
    output reg [`REG_AWIDTH-1:0] dst_sel, //where the result will go 
    output reg [`OP_AWIDTH-1:0] op_sel,  //the operation to perform
    output reg [`REG_AWIDTH-1:0] src_sel, //the data source
    
    // Literal number tracking
    output reg [`REG_DWIDTH-1:0] literal_num,
    output reg src_is_literal, 

    output reg [7:0] debug
);

    reg [STATE_WIDTH-1:0] fsm_state;

    // --- THE LEXER ---
    // Instantly evaluates the input byte type; 0 clock cycles
    wire is_reg = (rx_byte >= "a" && rx_byte <= "z");
    wire is_num = (rx_byte >= "0" && rx_byte <= "9");
    wire is_eol = (rx_byte == `ASCII_LF || rx_byte == `ASCII_CR);
    wire is_op  = (!is_reg && !is_num && !is_eol); 

    // --- THE PARSER FSM ---
    always @(posedge clk) begin
        if (reset) begin
            fsm_state <= STATE_DST;
            dst_sel   <= 0;
            op_sel    <= 0;
            src_sel   <= 0;
            literal_num <= 0;
            src_is_literal <= 0;
        end else if (rx_ready) begin
            case (fsm_state)
                
                STATE_DST: begin
                    if (is_reg) begin
                        dst_sel <= rx_byte[`REG_AWIDTH-1:0] - `ASCII_OFFSET; 
                        fsm_state <= STATE_OP;
                    end
                end
                
                STATE_OP: begin
                    if (is_eol) begin
                        fsm_state <= STATE_DST;
                    end else if (is_op) begin
                        op_sel <= rx_byte[`OP_AWIDTH-1:0];        
                        fsm_state <= STATE_SRC;
                    end
                end
                
                STATE_SRC: begin
                    if (is_reg) begin
                        src_sel <= rx_byte[`REG_AWIDTH-1:0] - `ASCII_OFFSET; 
                        src_is_literal <= 0;
                        fsm_state <= STATE_OP;
                    end else if (is_num) begin
                        // Grab the first digit and switch to NUM mode
                        literal_num <= rx_byte[`REG_DWIDTH-1:0] - 8'd48; 
                        // "0" is 48 in ASCII
                        src_is_literal <= 1;
                        fsm_state <= STATE_NUM;
                    end
                end

                STATE_NUM: begin
                    if (is_num) begin
                        // The Hardware *10: (num * 8) + (num * 2) + new_digit
                        literal_num <= (literal_num << 3) + (literal_num << 1)
                         + (rx_byte[`REG_DWIDTH-1:0] - 8'd48);
                    end else if (is_op) begin
                        // An operator. Lock in the number and process the op
                        op_sel <= rx_byte[`OP_AWIDTH-1:0];
                        fsm_state <= STATE_SRC;
                    end else if (is_eol) begin
                        // End of line. Lock in the number and go back to start
                        fsm_state <= STATE_DST;
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


// --- 2. THE TESTBENCH ---
module testbench(); // No ports on standard testbenches

    // We generate the clock and reset ourselves
    reg clk = 0;
    reg reset = 1;
    
    // Wires to hook up to the CPU outputs
    wire [`STATE_WIDTH-1:0] state;   
    wire [7:0] debug;
    wire [`REG_AWIDTH-1:0] dst_sel;
    wire [`OP_AWIDTH-1:0] op_sel;
    wire [`REG_AWIDTH-1:0] src_sel;
    wire [`REG_DWIDTH-1:0] literal_num;
    wire src_is_literal;

    // Registers to feed the CPU inputs
    reg [`RX_WIDTH-1:0] rx_byte = 0;
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
        .src_sel(src_sel),
        .literal_num(literal_num), // Wire up the new ports
        .src_is_literal(src_is_literal)
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
                
                $display("[%0t] INJECT: '%c' | FSM: %d | LITERAL_NUM: %d", $time, rom[pc], state, literal_num);
                pc <= pc + 1;
            end 
            else if (rom[pc] == 0 && cycle[1:0] == 2'b00) begin
                $display("\n--- TEST COMPLETE ---");
                if (state == 0) begin
                    $display("[PASS] Final Literal Num parsed as: %d", literal_num);
                end else begin
                    $display("[FAIL] CPU is stuck in state: %d", state);
                end
                
                $finish; // Stop the simulator
            end
        end
    end
endmodule
