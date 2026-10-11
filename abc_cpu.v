`ifndef ABC_CPU_V
`define ABC_CPU_V

module abc_cpu (
    input clk,
    input reset,
    
    // The incoming instruction stream
    input [7:0] next_inst,
    input inst_valid,
    output reg fetch_next, // Tells the memory/stream to advance
    
    output reg [7:0] debug_state
);

    // --- TYPES & STATES ---
    localparam TYPE_NONE = 2'd0;
    localparam TYPE_REG  = 2'd1;
    localparam TYPE_NUM  = 2'd2;
    // TYPE_FUNC can be added here later

    localparam STATE_LOAD = 1'b0;
    localparam STATE_EXEC = 1'b1;

    reg fsm_state;

    // --- THE PIPELINE REGISTERS ---
    reg [4:0] dest;
    reg [1:0] dest_type;
    
    reg [7:0] op;
    
    reg [4:0] source;
    reg [31:0] num;       // 32-bit integers as specified in the README
    reg [1:0] source_type;
    
    reg [7:0] op_count;
    reg [7:0] pending_char; // Holds the character that triggered execution

    // --- THE REGISTER FILE ---
    // 26 wide registers mapped directly to the alphabet
    reg [31:0] registers [0:25];

    // Hardware shortcuts to specific registers
    wire [31:0] radix = registers["r" - 8'd97];
    
    // --- THE DYNAMIC LEXER ---
    // Evaluates the incoming next_inst byte combinationally
    wire is_alpha = (next_inst >= "a" && next_inst <= "z");
    wire is_digit = (next_inst >= "0" && next_inst <= "9");
    wire is_hex   = (radix == 16) && (next_inst >= "a" && next_inst <= "f");
    
    // We only treat a-f as numbers if we already have a destination!
    wire is_num = is_digit || (is_hex && dest_type != TYPE_NONE && op != 0);
    wire is_reg = is_alpha && !is_num;
    
    wire is_eol = (next_inst == "\n" || next_inst == ";" || next_inst == 8'd0);
    wire is_space = (next_inst == " " || next_inst == "\t");
    wire is_op  = (!is_alpha && !is_digit && !is_eol && !is_space);

    wire [31:0] digit_val = (next_inst >= "0" && next_inst <= "9") ? 
                            (next_inst - 8'd48) : 
                            (next_inst - 8'd87); // 'a' is 97, 97-87 = 10

    // --- THE ALU ---
    // MUX for Side B: seamlessly routes either the decoded Source Register or the raw num accumulator
    wire [31:0] alu_operand_a = registers[dest];
    wire [31:0] alu_operand_b = (source_type == TYPE_NUM) ? num : registers[source];
    reg  [31:0] alu_result;

    always @(*) begin
        case (op)
            ":": alu_result = alu_operand_b;
            "+": alu_result = alu_operand_a + alu_operand_b;
            "-": alu_result = alu_operand_a - alu_operand_b;
            default: alu_result = alu_operand_a; 
        endcase
    end

    // --- THE PIPELINE FSM ---
    always @(posedge clk) begin
        if (reset) begin
            fsm_state <= STATE_LOAD;
            fetch_next <= 1;
            dest_type <= TYPE_NONE;
            source_type <= TYPE_NONE;
            op <= 0;
            num <= 0;
            op_count <= 0;
            
            // Initialize Radix to 10
            registers["r" - 8'd97] <= 32'd10;
        end else begin
            
            if (fsm_state == STATE_LOAD && inst_valid) begin
                if (is_space) begin
                    fetch_next <= 1; // Ignore and fetch next
                end 
                // 1. DESTINATION ROUTING
                else if (dest_type == TYPE_NONE) begin
                    if (is_reg) begin
                        dest <= next_inst - 8'd97;
                        dest_type <= TYPE_REG;
                    end
                    fetch_next <= 1;
                end 
                // 2. OPERATION ROUTING
                else if (op == 0) begin
                    if (is_op) begin
                        op <= next_inst;
                    end
                    fetch_next <= 1;
                end 
                // 3. SOURCE ROUTING & EXECUTION TRIGGER
                else begin
                    // If a new character matches an OP or EOL, we trigger execution!
                    if (source_type != TYPE_NONE && (is_op || is_eol)) begin
                        pending_char <= next_inst;
                        op_count <= 1;            
                        fetch_next <= 0;          // Stall the pipeline!
                        fsm_state <= STATE_EXEC;  // Switch to execution mode
                    end 
                    // Accumulate Number
                    else if (is_num) begin
                        num <= (num * radix) + digit_val; 
                        source_type <= TYPE_NUM;
                        fetch_next <= 1;
                    end 
                    // Assign Source Register
                    else if (is_reg) begin
                        source <= next_inst - 8'd97;
                        source_type <= TYPE_REG;
                        fetch_next <= 1;
                    end
                end
            end 
            
            // 4. THE EXECUTION STATE
            else if (fsm_state == STATE_EXEC) begin
                if (op_count > 0) begin
                    // Perform the operation and save to the destination register
                    registers[dest] <= alu_result;
                    op_count <= op_count - 1;
                end else begin
                    // Cleanup based on what triggered the execution
                    if (pending_char == "\n" || pending_char == ";") begin
                        // Newline: clear destination and start over on a new line
                        dest_type <= TYPE_NONE;
                        op <= 0;
                    end else begin
                        // Chained operation: replace OP with the pending character
                        op <= pending_char;
                    end
                    
                    // Always clear the source so the next character routes correctly
                    source_type <= TYPE_NONE;
                    num <= 0;
                    
                    fetch_next <= 1; // Unstall the pipeline
                    fsm_state <= STATE_LOAD;
                end
            end
            
        end
    end

    always @(*) begin
        debug_state = fsm_state;
    end

endmodule
`endif