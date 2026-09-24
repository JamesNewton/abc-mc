`ifndef ALU_MATH_V
`define ALU_MATH_V

`include "abc_define.vh"

module alu_math(
    input clk,
    input reset,
    input start,
    input [7:0] op,
    input [`REG_DWIDTH-1:0] a,
    input [`REG_DWIDTH-1:0] b,
    output reg [`REG_DWIDTH-1:0] result,
    output reg done
);

    reg [5:0] cycle_count;
    reg [`REG_DWIDTH-1:0] m_reg; // Divisor / Multiplicand
    reg [`REG_DWIDTH-1:0] q_reg; // Quotient / Multiplier
    reg [`REG_DWIDTH-1:0] acc;   // Accumulator (Remainder)
    reg busy;

// --- RESTORING DIVISION LOGIC ---
    // Shift left, pulling the MSB of q_reg into the LSB of acc
    wire [`REG_DWIDTH-1:0] next_acc = (acc << 1) | (q_reg >> (`REG_DWIDTH-1));
    wire [`REG_DWIDTH-1:0] sub_acc = next_acc - m_reg;
    wire can_sub = (next_acc >= m_reg);

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            busy <= 0;
            result <= 0;
            cycle_count <= 0;
        end else begin
            
            // Default pulse: done only stays high for 1 clock cycle
            done <= 0; 
            
            if (start) begin
                // Latch the operands and begin the cycle
                m_reg <= b; // The Divisor (or Multiplicand)
                q_reg <= a; // The Dividend (or Multiplier)
                acc <= 0;
                cycle_count <= `REG_DWIDTH;
                busy <= 1;
                        
            end else if (busy) begin
                
                if (cycle_count > 0) begin
                    // 1. Shift-and-Add Multiplication
                    if (op == "*") begin
                        m_reg <= m_reg << 1;
                        q_reg <= q_reg >> 1;
                        if (q_reg[0]) acc <= acc + m_reg;
                    end 
                    
                    // 2. Restoring Division
                    else if (op == "/") begin
                        if (can_sub) begin
                            acc <= sub_acc;
                            q_reg <= (q_reg << 1) | 1'b1; // Shift 1 into quotient
                        end else begin
                            acc <= next_acc;              // Restore (no subtraction)
                            q_reg <= (q_reg << 1);        // Shift 0 into quotient
                        end
                    end
                    
                    cycle_count <= cycle_count - 1;
                    
                end else begin
                    // 32 cycles are complete. Output the correct register!
                    // Multiplication stores the answer in 'acc'. Division stores it in 'q_reg'.
                    result <= (op == "/") ? q_reg : acc; 
                    done <= 1;
                    busy <= 0;
                end
                
            end
        end
    end
endmodule
`endif // ALU_MATH_V
