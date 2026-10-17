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
    reg [4:0] arg_count;
    reg [4:0] func_ptr; // NEW: Safely anchors the function pointer while parsing arguments!
    
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
    // FIXED: Removed ',' from exclusion so it routes normally and evaluates its source
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
                    if (is_eol) in_comment <= 0;
                    fsm_state <= STATE_FETCH;
                end 
                else if (inst_byte == "(") begin
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
                        num <= pc + 1; //Point to the first inside char
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
                        // Both are 0: This is a function return! Trigger standalone operator.
                        op <= inst_byte;
                        op_count <= 4; // Currently takes 4 cycles to extract the frame 
                        fsm_state <= STATE_EXEC; 
                    end
                end
                else if (skip_depth > 0) begin
                    fsm_state <= STATE_FETCH; // Ignore instructions while skipping
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
                    else if (is_op) begin
                        // Standalone Operators (like [ and ])
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
                        source <= inst_byte - `REG_START;
                        source_type <= TYPE_REG;
                        fsm_state <= STATE_FETCH;
                    end 
                    // POINTER SHADOW INTERCEPT
                    else if (inst_byte == "@" && !has_shadow) begin
                        shadow_dest <= dest;
                        shadow_op <= op;
                        has_shadow <= 1;
                        
                        dest <= source; // Promote the array variable to the base destination
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

                        // Rewind PC if this character is NOT intentionally consumed by the cleanup block!
                        if (!(is_eol || inst_byte == "+" || inst_byte == "-" || inst_byte == "&" || inst_byte == "|" || inst_byte == "^" || inst_byte == "*" || inst_byte == "/" || inst_byte == "<" || inst_byte == ">" || inst_byte == "=" || inst_byte == "," || inst_byte == ":" || inst_byte == "@")) begin
                            pc <= pc - 1; 
                        end
                    end
                end
            end 

            // 5. EXECUTION
            else if (fsm_state == STATE_EXEC) begin
                // $display("[HW DEBUG] Time: %0t | PC: %d | OP: %c | OpC: %d | S: %d | W_EN: %b | W_ADDR: %d | R_DATA: %x", 
                //     $time, pc, op, op_count, registers["s" - `REG_START], stack_write_en, stack_write_addr, stack_read_data
                // );
                if (op_count > 0) begin
                    if (op == "<" || op == ">" || op == "=") begin
                        cmp_flag <= alu_result[0];
                    end else if (op == "[") begin 
                        // Start loop: push current PC to stack
                        stack_write_en <= 1;
                        stack_write_addr <= registers["s" - `REG_START][7:0];
                        stack_write_data <= {20'd0, pc}; // Save PC
                        registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                    end else if (op == "]") begin 
                        // End loop: jump or pop
                        if (cmp_flag) begin
                            pc <= stack_read_data[11:0]; // Jump back to loop start
                        end else begin
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - 32'd1; 
                        end
                    end else if (op == "(") begin 
/* From the C++ version 
    stack[sp++] = dst.raw;
    stack[sp++] = src.raw;
    stack[sp++] = state_flags;
    stack[sp++] = frame_pointer;      // Save caller's frame
    stack[sp++] = arg_count;  // Save caller's arg count
    stack[sp++] = indent.raw;         // Save the caller's indentation state
    frame_pointer = sp; // New frame starts here
*/
                        stack_write_en <= 1;
                        stack_write_addr <= registers["s" - `REG_START][7:0];
                        if (op_count == 2) begin
                            stack_write_data <= dest; 
                            func_ptr <= dest; // SAVE the function pointer safely!
                        end 
                        else if (op_count == 1) begin
                            stack_write_data <= {24'd0, shadow_op}; 
                            arg_count <= 0; // reset argument count
                        end
                        registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                        op_count <= op_count - 1;
                    end else if (op == ",") begin // Push NUM as argument to stack
                        // stack[sp++] = num;
                        // FIXED: Reverted back to perfectly pushing alu_operand_b (source)
                        stack_write_en <= 1;
                        stack_write_addr <= registers["s" - `REG_START][7:0];
                        stack_write_data <= alu_operand_b; 
                        registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                        // current_arg_count++; //arg count for variable argument functions
                        arg_count <= arg_count + 5'd1;
                    end else if (op == ")") begin 
/*
    stack[sp++] = num;
    current_arg_count++;
      stack[sp++] = (long)pc_ptr; // Push Return Address to the stack
      // OFFSET BY -1 because the evaluateABC loop will automatically do pc_ptr++ right after this
      pc_ptr = &code_ram[func_src.meta.value] - 1; 
      
      // Lock in the lexical scope for the new function!
      scope_frame_pointer = frame_pointer;
      scope_arg_count = current_arg_count;
*/
                        if (op_count == 2) begin
                            if (dest_type != TYPE_NONE) begin // Only push if there's an actual argument
                                stack_write_en <= 1;
                                stack_write_addr <= registers["s" - `REG_START][7:0];
                                stack_write_data <= (dest_type == TYPE_NUM) ? num : registers[dest]; 
                                registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                                arg_count <= arg_count + 5'd1; 
                            end else begin
                                stack_write_en <= 0; // Empty args like f()
                            end
                        end else if (op_count == 1) begin
                            stack_write_en <= 1;
                            stack_write_addr <= registers["s" - `REG_START][7:0];
                            stack_write_data <= {20'd0, pc}; 
                            registers["s" - `REG_START] <= registers["s" - `REG_START] + 32'd1;
                            pc <= registers[func_ptr][11:0]; // Jump to anchored pointer!
                        end
                        op_count <= op_count - 1;
                    end else if (op == ".") begin
/*
  pc_ptr = (const char*)stack[--sp]; // Pop Return Address
  sp = frame_pointer;   // Restore previous frame
  indent.raw        = stack[frame_pointer - FRAME_OFFSET_INDENT];
  current_arg_count = stack[frame_pointer - FRAME_OFFSET_ARGC];
  long old_fp       = stack[frame_pointer - FRAME_OFFSET_FP];
  long state_flags  = stack[frame_pointer - FRAME_OFFSET_FLAGS];
  src.raw           = stack[frame_pointer - FRAME_OFFSET_SRC];
  dst.raw           = stack[frame_pointer - FRAME_OFFSET_DST];
  sp = frame_pointer - FRAME_HEADER_SIZE; // Drop the header
  frame_pointer = old_fp;
  src_dst = (state_flags & 1) != 0;
  op = (state_flags >> 8) & 0xFF;
  num = ret_val; 
  src.raw = 0;   
  call_depth--;
*/
                        if (op_count == 4) begin 
                            pc <= stack_read_data[11:0]; //return address; restore pc
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - arg_count - 32'd1; // skip args
                        end else if (op_count == 3) begin
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - 32'd1;
                        end else if (op_count == 2) begin //restore op (?)
                            shadow_op <= stack_read_data[7:0];
                            registers["s" - `REG_START] <= registers["s" - `REG_START] - 32'd1;
                        end else if (op_count == 1) begin //restore dest
                            dest <= stack_read_data[4:0];
                            func_ptr <= stack_read_data[4:0]; // Restore func_ptr to handle nested functions cleanly
                        end
                        op_count <= op_count - 1;
                    end else if (op == "@") begin
                        if (has_shadow) begin
                            // Evaluate memory, restore the shadow, and trigger the original operation!
                            num <= registers[dest + alu_operand_b[4:0]];
                            source_type <= TYPE_NUM;
                            dest <= shadow_dest;
                            op <= shadow_op;
                            has_shadow <= 0;
                            // Keeping op_count > 0 perfectly syncs the restored operation to the next clock!
                        end else begin
                            // Modify destination pointer in-place and quietly fetch the real operation
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
                        op_count <= op_count - 1;
                    end
                end else begin
                    // CLEANUP & ROUTE PENDING CHAR
                    stack_write_en <= 0; // De-assert stack write pulse
                    
                    if (   pending_char == "\n" 
                        || pending_char == ";" 
                        || pending_char == 8'd0 
                        || pending_char == ")" 
                        || pending_char == "."
                     ) begin
                        dest_type <= TYPE_NONE;
                        op <= 0;
                    end 
                    else if (pending_char == "+" || pending_char == "-" 
                        || pending_char == "&" || pending_char == "|" || pending_char == "^" 
                        || pending_char == "*" || pending_char == "/" 
                        || pending_char == "<" || pending_char == ">" || pending_char == "=" 
                        || pending_char == "," || pending_char == ":" || pending_char == "@" 
                        || pending_char == "("
                        ) begin
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

    // --- WATCHDOG TIMER ---
    reg [31:0] watchdog;
    always @(posedge clk) begin
        if (reset) begin
            watchdog <= 0;
        end else begin
            watchdog <= watchdog + 1;
            if (watchdog > 5000) begin 
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