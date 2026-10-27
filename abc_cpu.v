`ifndef ABC_CPU_V
`define ABC_CPU_V

`include "abc_define.vh"
`include "bram.v"

// `define DEBUG_EXE
// `define DEBUG_REG
// `define DEBUG_ALU
// `define DEBUG_JMP

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
    reg [4:0] arg_count;
    reg [4:0] func_ptr; 
    
    // --- SHADOW REGISTERS (For Pointer Indirection) ---
    reg [4:0] shadow_dest;
    reg [7:0] shadow_op;
    reg has_shadow;
    
    // Control & Context Trackers
    reg in_comment;
    reg in_string;
    reg cmp_flag;
    reg [3:0] exec_depth;
    reg [3:0] skip_depth;

    // --- THE REGISTER FILE ---
    reg [31:0] registers [0:25]; 
    wire [31:0] radix = registers["r" - `REG_START];

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
        .read_addr(registers["s" - `REG_START][7:0] - 8'd1), // Prep read for top-of-stack
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
    
    // Exclude string modifiers and function triggers from operators
    wire is_op  = (!is_alpha && !is_digit && !is_eol && !is_space 
        && inst_byte != "#" && inst_byte != "?" && inst_byte != "!" && inst_byte != "." 
        && inst_byte != "@" && inst_byte != "\"" && inst_byte != "(" && inst_byte != ")"
    );

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
            
            shadow_dest <= 0;
            shadow_op <= 0;
            has_shadow <= 0;
            
            in_comment <= 0;
            in_string <= 0;
            cmp_flag <= 0;
            exec_depth <= 0;
            skip_depth <= 0;
            
            stack_write_en <= 0;
            stack_write_addr <= 0;
            func_ptr <= 0;
            
            registers["r" - `REG_START] <= 32'd10; // Default radix
            registers["s" - `REG_START] <= 32'd0; // Initialize stack pointer
        end else begin
            
            if (fsm_state == STATE_FETCH) begin
                fsm_state <= STATE_FETCH_WAIT;
            end 
            
            else if (fsm_state == STATE_FETCH_WAIT) begin
                pc <= pc + 1; // Default advance PC
                
                if (in_comment) begin
                    if (is_eol) begin
                        in_comment <= 0;
                        pending_char <= inst_byte;
                        op_count <= 1;
                        fsm_state <= STATE_EXEC;
                    end else begin
                        fsm_state <= STATE_FETCH;
                    end
                end 
                else if (inst_byte == "(") begin
                    shadow_op <= op;      
                    shadow_dest <= dest; 
                    op <= "(";
                    op_count <= 2; 
                    fsm_state <= STATE_EXEC;
                end
                else if (inst_byte == ")") begin
                    op <= ")";
                    op_count <= 2; 
                    fsm_state <= STATE_EXEC;
                end
                else if (in_string) begin
                    if (inst_byte == "\"") in_string <= 0; 
                    fsm_state <= STATE_FETCH;
                end
                else if (inst_byte == "\"") begin
                    in_string <= 1; 
                    if (dest_type != TYPE_NONE && op != 0 && source_type == TYPE_NONE) begin
                        num <= pc + 1; 
                        source_type <= TYPE_NUM;
                    end
                    fsm_state <= STATE_FETCH;
                end
                // --- CONDITIONAL LOGIC ---
                // Control chars MUST force pending instructions to execute first.
                // We only process them if we are skipping, or if the pipeline is empty.
                else if ((skip_depth > 0 || dest_type == TYPE_NONE) && inst_byte == "#") begin
                    in_comment <= 1;
                    fsm_state <= STATE_FETCH;
                end 
                else if ((skip_depth > 0 || dest_type == TYPE_NONE) && inst_byte == "?") begin
                    if (skip_depth == 0) begin
                        if (cmp_flag) exec_depth <= exec_depth + 1;
                        else skip_depth <= 1;
                    end else begin
                        skip_depth <= skip_depth + 1;
                    end
                    fsm_state <= STATE_FETCH;
                end
                else if ((skip_depth > 0 || dest_type == TYPE_NONE) && inst_byte == "!") begin
                    if (skip_depth == 1) begin
                        skip_depth <= 0;
                        exec_depth <= exec_depth + 1;
                    end else if (skip_depth == 0 && exec_depth > 0) begin
                        exec_depth <= exec_depth - 1;
                        skip_depth <= 1;
                    end
                    fsm_state <= STATE_FETCH;
                end
                else if ((skip_depth > 0 || dest_type == TYPE_NONE) && inst_byte == ".") begin
                    if (skip_depth > 0) begin
                        skip_depth <= skip_depth - 1;
                        fsm_state <= STATE_FETCH;
                    end else if (exec_depth > 0) begin
                        exec_depth <= exec_depth - 1;
                        fsm_state <= STATE_FETCH;
                    end else begin
                        op <= inst_byte;
                        op_count <= 4; 
                        fsm_state <= STATE_EXEC; 
                    end
                end
                else if (skip_depth > 0) begin
                    fsm_state <= STATE_FETCH; 
                end
                // --- END CONDITIONAL LOGIC ---
                
                else if (is_space) begin
                    fsm_state <= STATE_FETCH;
                end 
                // DESTINATION ROUTING
                else if (dest_type == TYPE_NONE) begin
                    if (is_reg) begin
                        dest <= inst_byte - `REG_START;
                        dest_type <= TYPE_REG;
                        fsm_state <= STATE_FETCH;
                    end 
                    else if (is_digit) begin 
                        num <= digit_val;
                        dest_type <= TYPE_NUM;
                        fsm_state <= STATE_FETCH;
                    end
                    else if (is_op) begin
                        op <= inst_byte;
                        op_count <= 1;            
                        fsm_state <= STATE_EXEC;  
                    end
                    else begin
                        fsm_state <= STATE_FETCH;
                    end
                end 
                // OPERATION ROUTING
                else if (op == 0) begin
                    if (is_op) op <= inst_byte;
                    else if (inst_byte == "@") begin 
                        op <= "@";
                        has_shadow <= 0; 
                    end
                    else if (dest_type == TYPE_NUM && is_digit) begin
                        num <= (num * radix) + digit_val;
                    end
                    fsm_state <= STATE_FETCH;
                end 
                // SOURCE ROUTING
                else begin
                    if (is_num && (source_type == TYPE_NONE || source_type == TYPE_NUM)) begin
                        num <= (num * radix) + digit_val; 
                        source_type <= TYPE_NUM;
                        fsm_state <= STATE_FETCH;
                    end 
                    else if (is_reg && source_type == TYPE_NONE) begin
                        `ifdef DEBUG_REG
                        $display("[DEBUG REG] Read Reg: %c | Global Value: %d | Current ArgCount: %d | Stack Ptr: %d", 
                            inst_byte, registers[inst_byte - `REG_START], arg_count, registers["s" - `REG_START]);
                        `endif
                        source <= inst_byte - `REG_START;
                        source_type <= TYPE_REG;
                        fsm_state <= STATE_FETCH;
                    end 
                    // POINTER SHADOW INTERCEPT
                    else if (inst_byte == "@" && !has_shadow) begin
                        shadow_dest <= dest;
                        shadow_op <= op;
                        has_shadow <= 1;
                        
                        dest <= source; 
                        dest_type <= TYPE_REG;
                        op <= "@";
                        source_type <= TYPE_NONE;
                        num <= 0;
                        fsm_state <= STATE_FETCH;
                    end
                    // STREAM TRIGGER
                    else begin
                        pending_char <= inst_byte;
                        op_count <= 1;            
                        fsm_state <= STATE_EXEC;  

                        if (!(is_eol || inst_byte == "+" || inst_byte == "-" || inst_byte == "&" || inst_byte == "|" || inst_byte == "^" || inst_byte == "*" || inst_byte == "/" || inst_byte == "<" || inst_byte == ">" || inst_byte == "=" || inst_byte == "," || inst_byte == ":" || inst_byte == "@")) begin
                            pc <= pc; 
                        end
                    end
                end
            end 

            // 5. EXECUTION
            else if (fsm_state == STATE_EXEC) begin
                `ifdef DEBUG_EXE
                $display("[DEBUG EXE] Time: %0t | PC: %d | OP: %c | OpC: %d | S: %d", 
                    $time, pc, op, op_count, registers["s" - `REG_START]
                );
                `endif
                if (op_count > 0) begin
                    `ifdef DEBUG_ALU
                    if (op_count == 1 && op != 0 && op != "(" && op != ")" && op != "[" && op != "]" && op != "." && op != "@" && op != ",") begin
                        $display("[DEBUG ALU] Math: %d %c %d = %d", alu_operand_a, op, alu_operand_b, alu_result);
                    end
                   `endif
                    if (op == "<" || op == ">" || op == "=") begin
                        cmp_flag <= alu_result[0];
                    end else if (op == "[") begin 
                        stack_write_en <= 1;
                        stack_write_addr <= registers["s" - `REG_START][7:0];
                        stack_write_data <= {20'd0, pc}; 
                        registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                    end else if (op == "]") begin 
                        if (cmp_flag) begin
                            pc <= stack_read_data[11:0]; 
                        end else begin
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - 32'd1; 
                        end
                    end else if (op == "(") begin 
                        stack_write_en <= 1;
                        stack_write_addr <= registers["s" - `REG_START][7:0];
                        if (op_count == 2) begin
                            stack_write_data <= shadow_dest; 
                            func_ptr <= (shadow_op != 0) ? source : shadow_dest; 
                        end 
                        else if (op_count == 1) begin
                            stack_write_data <= {24'd0, shadow_op}; 
                            arg_count <= 0; 
                        end
                        registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                        op_count <= op_count - 1;
                    end else if (op == ",") begin 
                        stack_write_en <= 1;
                        stack_write_addr <= registers["s" - `REG_START][7:0];
                        stack_write_data <= alu_operand_b; 
                        registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                        arg_count <= arg_count + 5'd1;
                    end else if (op == ")") begin 
                        if (op_count == 2) begin
                            if (source_type != TYPE_NONE) begin 
                                stack_write_en <= 1;
                                stack_write_addr <= registers["s" - `REG_START][7:0];
                                stack_write_data <= (source_type == TYPE_NUM) ? num : registers[source]; 
                                registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                                arg_count <= arg_count + 5'd1; 
                            end else if (dest_type != TYPE_NONE) begin 
                                stack_write_en <= 1;
                                stack_write_addr <= registers["s" - `REG_START][7:0];
                                stack_write_data <= (dest_type == TYPE_NUM) ? num : registers[dest]; 
                                registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                                arg_count <= arg_count + 5'd1; 
                            end else begin
                                stack_write_en <= 0; 
                            end
                        end else if (op_count == 1) begin
                            `ifdef DEBUG_JMP
                            $display("[DEBUG JUMP] Jumping to FuncPtr: %d | Passed %d Args | Stack Ptr (s): %d", 
                                func_ptr, arg_count, registers["s" - `REG_START] + 32'd1
                            );
                            `endif
                            stack_write_en <= 1;
                            stack_write_addr <= registers["s" - `REG_START][7:0];
                            stack_write_data <= {20'd0, pc}; // THE FIX: Restore original exact pc anchor!
                            registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                            pc <= registers[func_ptr][11:0]; 
                            
                            num <= 0;
                            source_type <= TYPE_NONE;
                            dest_type <= TYPE_NONE;
                            op <= 0;
                        end
                        op_count <= op_count - 1;
                    end else if (op == ".") begin
                        if (op_count == 4) begin 
                            num <= (dest_type == TYPE_REG) ? registers[dest] : num;
                            source_type <= TYPE_NUM; 
                            
                            pc <= stack_read_data[11:0]; 
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - arg_count - 32'd1; 
                        end else if (op_count == 3) begin
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - 32'd1;
                        end else if (op_count == 2) begin 
                            shadow_op <= stack_read_data[7:0]; 
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - 32'd1;
                        end else if (op_count == 1) begin 
                            dest <= stack_read_data[4:0];
                            dest_type <= (shadow_op != 0) ? TYPE_REG : TYPE_NONE; 
                            func_ptr <= stack_read_data[4:0]; 
                            op <= shadow_op; 
                            pending_char <= 0; 
                            
                            if (shadow_op == 0) begin
                                source_type <= TYPE_NONE;
                                num <= 0;
                            end
                            
                            op_count <= 0;
                            fsm_state <= STATE_FETCH; 
                        end
                        
                        if (op_count > 1) op_count <= op_count - 1; 
                    end else if (op == "@") begin
                        if (has_shadow) begin
                            num <= registers[dest + alu_operand_b[4:0]];
                            source_type <= TYPE_NUM;
                            dest <= shadow_dest;
                            op <= shadow_op;
                            has_shadow <= 0;
                        end else begin
                            dest <= dest + alu_operand_b[4:0];
                            op <= 0;
                            source_type <= TYPE_NONE;
                            num <= 0;
                            op_count <= op_count - 1;
                        end
                    end else begin
                        registers[dest] <= alu_result;
                    end
                    
                    if (op != "@" || !has_shadow) begin
                        if (op != ".") op_count <= op_count - 1; 
                    end
                end else begin
                    stack_write_en <= 0; 
                    
                    if (   pending_char == "\n" 
                        || pending_char == ";" 
                        || pending_char == 8'd0 
                        || pending_char == ")" 
                     ) begin 
                        dest_type <= TYPE_NONE;
                        op <= 0;
                        source_type <= TYPE_NONE;
                        num <= 0;
                        fsm_state <= STATE_FETCH;
                    end 
                    else if (pending_char == ".") begin
                        op <= ".";
                        op_count <= 4;
                        fsm_state <= STATE_EXEC;
                    end
                    else if (pending_char == "+" || pending_char == "-" 
                        || pending_char == "&" || pending_char == "|" || pending_char == "^" 
                        || pending_char == "*" || pending_char == "/" 
                        || pending_char == "<" || pending_char == ">" || pending_char == "=" 
                        || pending_char == "," || pending_char == ":" || pending_char == "@" 
                        || pending_char == "("
                        ) begin
                        op <= pending_char;
                        source_type <= TYPE_NONE;
                        num <= 0;
                        fsm_state <= STATE_FETCH;
                    end 
                    else begin
                        dest_type <= TYPE_NONE;
                        op <= 0;
                        source_type <= TYPE_NONE;
                        num <= 0;
                        fsm_state <= STATE_FETCH;
                    end
                end
            end
        end
    end

    // --- WATCHDOG TIMER ---
    reg [31:0] watchdog;
    always @(posedge clk) begin
        if (reset) begin
            watchdog <= 0;
        end else begin
            watchdog <= watchdog + 1;
            if (watchdog > 2000) begin 
                $display("[FATAL] Watchdog timeout reached. Killing simulation.");
                $finish;
            end
        end
    end

    always @(*) begin
        state = fsm_state;
        debug = inst_byte;
    end

endmodule
`endif