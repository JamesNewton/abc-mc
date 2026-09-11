`include "abc_define.vh"

// --- CPU MODULE ---
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
    // Memory Bus Interface
    input [`REG_DWIDTH-1:0] reg_data_a,     // Data read from Dest register
    input [`REG_DWIDTH-1:0] reg_data_b,     // Data read from Source register
    output reg reg_write_en,                // Trigger to save data
    output reg [`REG_DWIDTH-1:0] reg_write_data, // The data to save
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
            reg_write_en <= 0;
            reg_write_data <= 0;

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
