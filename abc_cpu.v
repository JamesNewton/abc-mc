`ifndef ABC_CPU_V
`define ABC_CPU_V

`include "abc_define.vh"

// --- CPU MODULE ---
module abc_cpu#(
    // Defining parameters here allows the ports to use them.
    parameter STATE_DST = 0,
    parameter STATE_OP  = STATE_DST + 1,
    parameter STATE_SRC = STATE_OP + 1,
    parameter STATE_NUM = STATE_SRC + 1,
    parameter STATE_WAIT = STATE_NUM + 1,
    parameter STATE_EXEC = STATE_WAIT + 1,
    parameter STATE_MAX = STATE_EXEC + 1,
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
    // Memory Bus Interface
    input [`REG_DWIDTH-1:0] reg_data_a,     // Data read from Dest register
    input [`REG_DWIDTH-1:0] reg_data_b,     // Data read from Source register
    output reg reg_write_en,                // Trigger to save data
    output reg [`REG_DWIDTH-1:0] reg_write_data, // The data to save
    output reg [7:0] debug
);

    reg [STATE_WIDTH-1:0] fsm_state;
    reg [7:0] next_char;

    // --- THE LEXER ---
    // Instantly evaluates the input byte type; 0 clock cycles
    wire is_reg = (rx_byte >= "a" && rx_byte <= "z");
    wire is_num = (rx_byte >= "0" && rx_byte <= "9");
    wire is_eol = (rx_byte == `ASCII_LF || rx_byte == `ASCII_CR);
    wire is_op  = (!is_reg && !is_num && !is_eol); 

    // --- THE ALU (Arithmetic Logic Unit) ---
    
    // The Multiplexer (MUX) for Operand B
    // If the parser flagged a literal, use literal_num. Otherwise, use the source register's data.
    wire [`REG_DWIDTH-1:0] alu_operand_b = src_is_literal ? literal_num : reg_data_b;
    
    // The Math Result
    reg [`REG_DWIDTH-1:0] alu_result;
    
    always @(*) begin
        case (op_sel)
            "+": alu_result = reg_data_a + alu_operand_b;
            "-": alu_result = reg_data_a - alu_operand_b;
            "&": alu_result = reg_data_a & alu_operand_b;
            "|": alu_result = reg_data_a | alu_operand_b;
            "^": alu_result = reg_data_a ^ alu_operand_b; // XOR
            
            // If no valid operator is set (or for direct assignment), just pass Operand B through
            default: alu_result = alu_operand_b; 
        endcase
    end

    // --- THE PARSER FSM ---
    always @(posedge clk) begin
        if (reset) begin
            fsm_state <= STATE_DST;
            dst_sel   <= 0;
            op_sel    <= 0;
            src_sel   <= 0;
            literal_num <= 0;
            src_is_literal <= 0;
            reg_write_data <= 0;
            next_char <= 0;
            reg_write_en <= 0;
        end else begin
            
            // DEFAULT ASSIGNMENT (1-cycle pulse)
            reg_write_en <= 0; 

            // THE STALL PIPELINE
            if (fsm_state == STATE_EXEC) begin
                // The memory write was triggered on the previous clock edge. 
                // Now, load the latched character into the next pipeline stage!
                if (next_char == `ASCII_LF || next_char == `ASCII_CR) begin
                    fsm_state <= STATE_DST;
                end else begin
                    op_sel <= next_char[`OP_AWIDTH-1:0];
                    fsm_state <= STATE_SRC;
                end
            end 
            
            // THE STANDARD PIPELINE
            else if (rx_ready) begin
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
                            fsm_state <= STATE_WAIT; // Instruction full Wait for the next OP.
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
                            literal_num <= (literal_num << 3) + (literal_num << 1) + (rx_byte[`REG_DWIDTH-1:0] - 8'd48);
                        end else if (is_op || is_eol) begin
                            // Execute the instruction
                            next_char <= rx_byte;
                            reg_write_en <= 1;
                            reg_write_data <= alu_result;
                            fsm_state <= STATE_EXEC;
                        end
                    end
                    
                    STATE_WAIT: begin
                        if (is_op || is_eol) begin
                            // Execute the instruction
                            next_char <= rx_byte;
                            reg_write_en <= 1;
                            reg_write_data <= alu_result;
                            fsm_state <= STATE_EXEC;
                        end
                    end
                    
                    default: fsm_state <= STATE_DST;
                endcase
            end
        end
    end

    always @(*) begin
        state = fsm_state;
        debug = rx_byte;
    end
endmodule
`endif // ABC_CPU_V