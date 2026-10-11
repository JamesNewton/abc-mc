`ifndef ABC_CPU_V
`define ABC_CPU_V

`include "abc_define.vh"
`include "bram.v"

// --- CPU MODULE ---
module abc_cpu#(
    parameter STATE_FETCH      = 0,
    parameter STATE_FETCH_WAIT = 1,
    parameter STATE_EXEC       = 2,
    parameter STATE_WIDTH      = 2
)(
    input clk,
    input reset,
    
    // Legacy Ports
    input [`RX_WIDTH-1:0] rx_byte,
    input rx_ready,
    output reg [STATE_WIDTH-1:0] state,

    output reg [`REG_AWIDTH-1:0] dst_sel,
    output reg [`OP_AWIDTH-1:0] op_sel,
    output reg [`REG_AWIDTH-1:0] src_sel,
    output reg [`REG_DWIDTH-1:0] literal_num,
    output reg src_is_literal,
    input [`REG_DWIDTH-1:0] reg_data_a,
    input [`REG_DWIDTH-1:0] reg_data_b,
    output reg reg_write_en,
    output reg [`REG_DWIDTH-1:0] reg_write_data,
    
    output reg [7:0] debug
);

    // --- INTERNAL REGISTERS ---
    reg [STATE_WIDTH-1:0] fsm_state;
    reg [11:0] pc;
    wire [7:0] inst_byte;

    // --- INSTRUCTION MEMORY (BRAM) ---
    bram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(12)
    ) imem (
        .clk(clk),
        .write_en(1'b0),
        .write_addr(12'd0),
        .write_data(8'd0),
        .read_addr(pc),
        .read_data(inst_byte)
    );

    // --- STREAM PIPELINE REGISTERS ---
    localparam TYPE_NONE = 2'd0;
    localparam TYPE_REG  = 2'd1;
    localparam TYPE_NUM  = 2'd2;

    reg [4:0] dest;
    reg [1:0] dest_type;
    reg [7:0] op;
    reg [4:0] source;
    reg [31:0] num;
    reg [1:0] source_type;
    
    reg [7:0] op_count;
    reg [7:0] pending_char;
    reg in_comment;
    reg cmp_flag;

    // --- THE REGISTER FILE ---
    reg [31:0] registers [0:25]; 
    wire [31:0] radix = registers["r" - 8'd97];

    // --- STACK MEMORY (BRAM) ---
    wire [31:0] stack_read_data;
    reg stack_write_en;
    reg [31:0] stack_write_data;
    reg [7:0] stack_write_addr;

    bram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(8)
    ) stack_mem (
        .clk(clk),
        .write_en(stack_write_en),
        .write_addr(stack_write_addr),
        .write_data(stack_write_data),
        .read_addr(registers["s" - 8'd97][7:0] - 8'd1), 
        .read_data(stack_read_data)
    );

    // --- THE DYNAMIC LEXER ---
    wire is_alpha = (inst_byte >= "a" && inst_byte <= "z");
    wire is_digit = (inst_byte >= "0" && inst_byte <= "9");
    wire is_hex   = (radix == 16) && (inst_byte >= "a" && inst_byte <= "f");
    
    wire is_num = is_digit || (is_hex && dest_type != TYPE_NONE && op != 0);
    wire is_reg = is_alpha && !is_num;
    
    wire is_eol = (inst_byte == "\n" || inst_byte == ";" || inst_byte == 8'd0);
    wire is_space = (inst_byte == " " || inst_byte == "\t");
    wire is_op  = (!is_alpha && !is_digit && !is_eol && !is_space && inst_byte != "#");

    wire [31:0] digit_val = (inst_byte >= "0" && inst_byte <= "9") ? 
                            (inst_byte - 8'd48) : 
                            (inst_byte - 8'd87);

    // --- THE ALU ---
    wire [31:0] alu_operand_a = registers[dest];
    wire [31:0] alu_operand_b = (source_type == TYPE_NUM) ? num : registers[source];
    reg  [31:0] alu_result;

    always @(*) begin
        case (op)
            ":": alu_result = alu_operand_b;
            "+": alu_result = alu_operand_a + alu_operand_b;
            "-": alu_result = alu_operand_a - alu_operand_b;
            "&": alu_result = alu_operand_a & alu_operand_b;
            "|": alu_result = alu_operand_a | alu_operand_b;
            "^": alu_result = alu_operand_a ^ alu_operand_b;
            "*": alu_result = alu_operand_a * alu_operand_b;
            "/": alu_result = alu_operand_a / alu_operand_b;
            "<": alu_result = (alu_operand_a < alu_operand_b) ? 32'd1 : 32'd0;
            ">": alu_result = (alu_operand_a > alu_operand_b) ? 32'd1 : 32'd0;
            "=": alu_result = (alu_operand_a == alu_operand_b) ? 32'd1 : 32'd0;
            default: alu_result = alu_operand_a; 
        endcase
    end

    // --- THE PIPELINE FSM ---
    always @(posedge clk) begin
        if (reset) begin
            fsm_state <= STATE_FETCH;
            pc <= 0;
            dest_type <= TYPE_NONE;
            source_type <= TYPE_NONE;
            op <= 0;
            num <= 0;
            op_count <= 0;
            in_comment <= 0;
            cmp_flag <= 0;
            stack_write_en <= 0;
            
            registers["r" - 8'd97] <= 32'd10; // Default radix
        end else begin
            
            if (fsm_state == STATE_FETCH) begin
                fsm_state <= STATE_FETCH_WAIT;
            end 
            
            else if (fsm_state == STATE_FETCH_WAIT) begin
                pc <= pc + 1; // Default advance PC

                if (in_comment) begin
                    if (is_eol) in_comment <= 0;
                    fsm_state <= STATE_FETCH;
                end 
                else if (inst_byte == "#") begin
                    in_comment <= 1;
                    fsm_state <= STATE_FETCH;
                end 
                else if (is_space) begin
                    fsm_state <= STATE_FETCH;
                end 
                // 1. DESTINATION ROUTING
                else if (dest_type == TYPE_NONE) begin
                    if (is_reg) begin
                        dest <= inst_byte - 8'd97;
                        dest_type <= TYPE_REG;
                    end
                    fsm_state <= STATE_FETCH;
                end 
                // 2. OPERATION ROUTING
                else if (op == 0) begin
                    if (is_op) op <= inst_byte;
                    fsm_state <= STATE_FETCH;
                end 
                // 3. SOURCE ROUTING
                else begin
                    if (is_num && (source_type == TYPE_NONE || source_type == TYPE_NUM)) begin
                        num <= (num * radix) + digit_val; 
                        source_type <= TYPE_NUM;
                        fsm_state <= STATE_FETCH;
                    end 
                    else if (is_reg && source_type == TYPE_NONE) begin
                        source <= inst_byte - 8'd97;
                        source_type <= TYPE_REG;
                        fsm_state <= STATE_FETCH;
                    end 
                    // 4. STREAM TRIGGER
                    else begin
                        pending_char <= inst_byte;
                        op_count <= 1;            
                        fsm_state <= STATE_EXEC;  
                        
                        // If it's a new destination (e.g. 'f' in f:7f:f+3), rewind PC so we don't lose it!
                        if (!is_eol && !is_op) begin
                            pc <= pc; 
                        end
                    end
                end
            end 
            
            // 5. EXECUTION
            else if (fsm_state == STATE_EXEC) begin
                if (op_count > 0) begin
                    if (op == "<" || op == ">" || op == "=") begin
                        cmp_flag <= alu_result[0];
                    end else if (op == ",") begin // Push NUM as argument to stack
                        stack_write_en <= 1;
                        stack_write_addr <= registers["s" - 8'd97][7:0];
                        stack_write_data <= alu_operand_b;
                        registers["s" - 8'd97] <= registers["s" - 8'd97] + 32'd1;
                    end else begin
                        registers[dest] <= alu_result;
                    end
                    op_count <= op_count - 1;
                end else begin
                    // CLEANUP & ROUTE PENDING CHAR
                    stack_write_en <= 0; // De-assert stack write pulse

                    if (pending_char == "\n" || pending_char == ";" || pending_char == 8'd0) begin
                        dest_type <= TYPE_NONE;
                        op <= 0;
                    end 
                    else if (pending_char == "+" || pending_char == "-" || pending_char == "&" || pending_char == "|" || pending_char == "^" || pending_char == "*" || pending_char == "/" || pending_char == "<" || pending_char == ">" || pending_char == "=" || pending_char == ",") begin
                        op <= pending_char;
                    end 
                    else begin
                        dest_type <= TYPE_NONE;
                        op <= 0;
                    end
                    
                    source_type <= TYPE_NONE;
                    num <= 0;
                    
                    // Dropping to FETCH perfectly synchronizes fsm_state == 0 with your assertions!
                    fsm_state <= STATE_FETCH;
                end
            end
        end
    end

    always @(*) begin
        state = fsm_state;
        debug = inst_byte;
    end

endmodule
`endif