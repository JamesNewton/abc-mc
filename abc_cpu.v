`ifndef ABC_CPU_V
`define ABC_CPU_V

`include "abc_define.vh"
`include "alu_math.v"
`include "bram.v"

// --- CPU MODULE ---
module abc_cpu#(
    // Defining parameters here allows the ports to use them.
    parameter STATE_FETCH      = 0,                    //instruction fetch
    parameter STATE_FETCH_WAIT = STATE_FETCH + 1,
    parameter STATE_DST        = STATE_FETCH_WAIT + 1, //set the destination
    parameter STATE_OP         = STATE_DST + 1,        //set the operation
    parameter STATE_SRC        = STATE_OP + 1,         //set the source
    parameter STATE_NUM        = STATE_SRC + 1,        //accumulate a digit
    parameter STATE_WAIT       = STATE_NUM + 1,        //
    parameter STATE_EXEC       = STATE_WAIT + 1,       //execute dst, op, src
    parameter STATE_MATH       = STATE_EXEC + 1,       //do multi-cycle math
    parameter STATE_MAX        = STATE_MATH + 1,       //counts of states
    parameter STATE_WIDTH      = $clog2(STATE_MAX)    //bits to hold state
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
    // Memory Bus Interface
    input [`REG_DWIDTH-1:0] reg_data_a,     // Data read from Dest register
    input [`REG_DWIDTH-1:0] reg_data_b,     // Data read from Source register
    output reg reg_write_en,                // Trigger to save data
    output reg [`REG_DWIDTH-1:0] reg_write_data, // The data to save
    output reg [7:0] debug
);
    localparam [`REG_AWIDTH-1:0] REG_R_ADDR = "r" - `ASCII_OFFSET;

    reg [STATE_WIDTH-1:0] fsm_state;
    reg [`INST_WIDTH-1:0] next_char;
    reg [STATE_WIDTH-1:0] return_state;
    reg [`REG_AWIDTH-1:0] cpu_radix;

    // --- THE DYNAMIC LEXER ---
    wire is_hex_char = (inst_byte >= "a" && inst_byte <= "f");
    // Only treat a-f as numbers if we are actively expecting a Source or building a Number
    wire parse_as_hex = (cpu_radix == 16) && (fsm_state == STATE_SRC || fsm_state == STATE_NUM);

    // --- INSTRUCTION MEMORY (BRAM) ---
    reg [`IMEM_AWIDTH-1:0] pc;
    wire [`INST_WIDTH-1:0] inst_byte; // The ASCII character fetched from memory

    bram #(
        .DATA_WIDTH(8), // ASCII characters are 8 bits
        .ADDR_WIDTH(`IMEM_AWIDTH)
    ) imem (
        .clk(clk),
        
        // Write Port (Disabled for now)
        .write_en(1'b0),
        .write_addr(8'd0),
        .write_data(8'd0),
        
        // Read Port
        .read_addr(pc),
        .read_data(inst_byte)
    );

    // --- MATH ROUTING ---
    // Dynamically checks if the current operator requires the multi-cycle engine
    wire is_multi_cycle_op = 1'b0
`ifdef MAKE_MUL
        || (op_sel == "*")
`endif
`ifdef MAKE_DIV
        || (op_sel == "/")
`endif
    ;

    // --- THE LEXER ---
    // Instantly evaluates the input byte type; 0 clock cycles
    wire is_num = (inst_byte >= "0" && inst_byte <= "9") || (parse_as_hex && is_hex_char);
    wire is_reg = (inst_byte >= "a" && inst_byte <= "z") && !is_num;
    wire is_eol = (inst_byte == `ASCII_LF || inst_byte == `ASCII_CR);
    wire is_op  = (!is_reg && !is_num && !is_eol); 

    // Extract the numeric value (0-9 or 10-15)
    wire [`REG_DWIDTH-1:0] digit_val = 
        (inst_byte >= "0" && inst_byte <= "9") ? 
        (inst_byte - 8'd48) : 
        (inst_byte - "a" + 8'd10);

    // --- THE ALU (Arithmetic Logic Unit) ---
    
    // The Multiplexer (MUX) for Operand B
    // If the parser flagged a literal, use literal_num. Otherwise, use the source register's data.
    wire [`REG_DWIDTH-1:0] alu_operand_b = src_is_literal ? literal_num : reg_data_b;
    
    // The Math Result
    reg [`REG_DWIDTH-1:0] alu_result;

    // --- THE MULTI-CYCLE MATH ENGINE ---
    reg math_start;
    wire math_done;
    wire [`REG_DWIDTH-1:0] math_result;

`ifdef MULTI_CYCLE_MATH
    alu_math math_engine (
        .clk(clk),
        .reset(reset),
        .start(math_start),
        .op(op_sel),
        .a(reg_data_a),
        .b(alu_operand_b),
        .result(math_result),
        .done(math_done)
    );
`endif

    always @(*) begin
        case (op_sel)
            "+": alu_result = reg_data_a + alu_operand_b;
            "-": alu_result = reg_data_a - alu_operand_b;
            "&": alu_result = reg_data_a & alu_operand_b;
            "|": alu_result = reg_data_a | alu_operand_b;
            "^": alu_result = reg_data_a ^ alu_operand_b; // XOR

`ifdef FAST_MUL
            // Synthesizes into dedicated DSP slices (or heavy LUT logic). Completes in 0 cycles!
            "*": alu_result = reg_data_a * alu_operand_b;
`endif
            // If no valid operator is set (or for direct assignment), just pass Operand B through
            default: alu_result = alu_operand_b; 
        endcase
    end

    // --- THE PARSER FSM ---
    always @(posedge clk) begin
        if (reset) begin
            fsm_state <= STATE_FETCH; // Boot directly into fetch mode
            pc <= 0;                  // Start at address 0
            dst_sel   <= 0;
            op_sel    <= 0;
            src_sel   <= 0;
            literal_num <= 0;
            src_is_literal <= 0;
            reg_write_data <= 0;
            next_char <= 0;
            return_state <= STATE_DST;
            reg_write_en <= 0;
            cpu_radix <= 10;
            math_start <= 0;
        end else begin
            
            // DEFAULT ASSIGNMENT (1-cycle pulse)
            reg_write_en <= 0; 
            // Sniff writes to register 'r' to update the internal radix
            if (reg_write_en && dst_sel == 17) begin
                cpu_radix <= reg_write_data[7:0];
            end

            // THE STALL PIPELINE
            if (fsm_state == STATE_EXEC) begin
                // The memory write is done. 
                // Now evaluate the character that triggered us
                if (next_char == `ASCII_LF || next_char == `ASCII_CR) begin
                    // Consume EOL and start new instruction
                    fsm_state <= STATE_FETCH;
                    return_state <= STATE_DST;
                end else begin
                    // Consume Operator and get source
                    op_sel <= next_char[`OP_AWIDTH-1:0];
                    return_state <= STATE_SRC;
                    fsm_state <= STATE_FETCH;
                end
            end 

            // Independent Math Stall State
            else if (fsm_state == STATE_MATH) begin
                math_start <= 0; // Drop the start pulse
                
`ifdef MULTI_CYCLE_MATH
                if (math_done) begin
                    // The 32 cycles are over. Write the math result to memory!
                    reg_write_en <= 1;
                    reg_write_data <= math_result;
                    fsm_state <= STATE_EXEC;
                end
`else
                fsm_state <= STATE_DST; // Failsafe if compiled incorrectly
`endif
            end

            // FETCH CYCLE
            else if (fsm_state == STATE_FETCH) begin
                // The PC is physically wired to the BRAM's read_addr.
                // We just wait for the BRAM to clock the data out.
                fsm_state <= STATE_FETCH_WAIT;
            end
            else if (fsm_state == STATE_FETCH_WAIT) begin
                // instruction_byte is now valid! 
                // Increment the PC for the next fetch, and move to decode.
                pc <= pc + 1;
                fsm_state <= return_state; // Dynamic return
            end

            // THE STANDARD PIPELINE
            else begin
                case (fsm_state)
                    STATE_DST: begin
                        if (is_reg) begin
                            dst_sel <= inst_byte[`REG_AWIDTH-1:0] - `ASCII_OFFSET; 
                            return_state <= STATE_OP;
                            fsm_state <= STATE_FETCH; // Consume and fetch next
                        end else begin
                            fsm_state <= STATE_FETCH; // Ignore junk, fetch next
                            return_state <= STATE_DST;
                        end
                    end

                    STATE_OP: begin
                        if (is_eol) begin
                            return_state <= STATE_DST;
                            fsm_state <= STATE_FETCH;
                        end else if (is_op) begin
                            op_sel <= inst_byte[`OP_AWIDTH-1:0];        
                            return_state <= STATE_SRC;
                            fsm_state <= STATE_FETCH;
                        end else begin
                            return_state <= STATE_OP;
                            fsm_state <= STATE_FETCH;
                        end
                    end
                    
                    STATE_SRC: begin
                        if (is_reg) begin
                            src_sel <= inst_byte[`REG_AWIDTH-1:0] - `ASCII_OFFSET; 
                            src_is_literal <= 0;
                            return_state <= STATE_WAIT; // Instruction full Wait for the next OP.
                            fsm_state <= STATE_FETCH;
                        end else if (is_num) begin
                            // Grab the first digit and switch to NUM mode
                            literal_num <= digit_val; 
                            src_is_literal <= 1;
                            return_state <= STATE_NUM;
                            fsm_state <= STATE_FETCH;
                        end else begin
                            return_state <= STATE_SRC;
                            fsm_state <= STATE_FETCH;
                        end
                    end

                    STATE_NUM: begin
                        if (is_num) begin
                            if (cpu_radix == 16) literal_num <= (literal_num << 4) + digit_val;
                            else if (cpu_radix == 10) literal_num <= (literal_num << 3) + (literal_num << 1) + digit_val;
                            else if (cpu_radix == 8) literal_num <= (literal_num << 3) + digit_val;
                            else if (cpu_radix == 2) literal_num <= (literal_num << 1) + digit_val;
                            
                            return_state <= STATE_NUM;
                            fsm_state <= STATE_FETCH; // Consume digit, fetch next
                            
                        end else if (is_op || is_eol) begin
                            // Trigger execution.
                            next_char <= inst_byte; // Latch the trigger character
`ifdef MULTI_CYCLE_MATH
                            if ( is_multi_cycle_op ) begin
                                math_start <= 1;          
                                fsm_state <= STATE_MATH;  
                            end else
`endif
                            begin
                                reg_write_en <= 1;
                                reg_write_data <= alu_result;
                                fsm_state <= STATE_EXEC;
                            end
                        end else begin
                            return_state <= STATE_NUM;
                            fsm_state <= STATE_FETCH;
                        end
                    end
                    
                    STATE_WAIT: begin
                        if (is_op || is_eol) begin
                            // Trigger execution.
                            next_char <= inst_byte;
`ifdef MULTI_CYCLE_MATH
                            if (is_multi_cycle_op) begin
                                math_start <= 1;          
                                fsm_state <= STATE_MATH;  
                            end else
`endif
                            begin
                                reg_write_en <= 1;
                                reg_write_data <= alu_result;
                                fsm_state <= STATE_EXEC;
                            end
                        end else begin
                            return_state <= STATE_WAIT;
                            fsm_state <= STATE_FETCH;
                        end
                    end

                    default: fsm_state <= STATE_DST;
                endcase
            end
        end
    end

    always @(*) begin
        state = fsm_state;
        debug = inst_byte;
    end
endmodule
`endif // ABC_CPU_V