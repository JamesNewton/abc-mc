`ifndef BRAM_V
`define BRAM_V

module bram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8
)(
    input clk,
    
    // Write Port
    input write_en,
    input [ADDR_WIDTH-1:0] write_addr,
    input [DATA_WIDTH-1:0] write_data,
    
    // Read Port
    input [ADDR_WIDTH-1:0] read_addr,
    output reg [DATA_WIDTH-1:0] read_data
);

    // The Memory Array: (2^ADDR_WIDTH) elements, each DATA_WIDTH bits wide
    reg [DATA_WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];

    // Initialize memory to zero (optional, but helps with clean simulation)
    // integer i;
    // initial begin
    //     for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
    //         memory[i] = 0;
    //     end
    // end
    initial begin
        // Loads a hex file into the memory array at compile time
        $readmemh("program.hex", memory);
    end
    // The BRAM Inference Block
    always @(posedge clk) begin
        if (write_en) begin
            memory[write_addr] <= write_data;
        end
        
        // This MUST be inside the posedge clk block for the FPGA to use physical BRAM!
        read_data <= memory[read_addr]; 
    end

endmodule
`endif // BRAM_V