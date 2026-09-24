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
    reg [`REG_DWIDTH-1:0] m_reg; // Multiplicand
    reg [`REG_DWIDTH-1:0] q_reg; // Multiplier
    reg [`REG_DWIDTH-1:0] acc;   // Accumulator
    reg busy;

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
                m_reg <= a;
                q_reg <= b;
                acc <= 0;
                cycle_count <= `REG_DWIDTH;
                busy <= 1;
                
            end else if (busy) begin
                
                if (cycle_count > 0) begin
                    // Shift-and-Add Multiplication Algorithm
                    if (op == "*") begin
                        m_reg <= m_reg << 1;
                        q_reg <= q_reg >> 1;
                        if (q_reg[0]) begin
                            acc <= acc + m_reg;
                        end
                    end
                    // (Division algorithm will go here eventually)
                    
                    cycle_count <= cycle_count - 1;
                    
                end else begin
                    // 32 cycles are complete. Output result and pulse done.
                    result <= acc;
                    done <= 1;
                    busy <= 0;
                end
                
            end
        end
    end
endmodule
`endif // ALU_MATH_V
