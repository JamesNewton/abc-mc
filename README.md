# ABC Silicon Architecture

This project is a hardware implementation of the ABC Virtual Machine, designed in Verilog for synthesis on FPGAs (like the Lattice iCE40). It translates the high-level, string-evaluated C++ ABC language directly into a digital logic pipeline.

## The Execution Pipeline (DST-OP-SRC)
The heart of the processor is a 2-bit Finite State Machine (FSM) tracking the `dst_op_src` sequence. 
* Instructions flow sequentially: incoming bytes are loaded into the **Destination** register, then the FSM increments to expect an **Operation**, and increments again to expect a **Source**.
* Decrementing the FSM back to the Operation state allows for chained mathematics (e.g., `a:b+c`).
* A carriage return (or line end) resets the FSM back to 0 (Destination), ready for a new line of code.

## The Register File
The CPU features an array of 26 wide registers, mapped directly to the alphabet (`a` through `z`). Several registers are hardwired to processor-level functions:
* `p`: Program Counter (Instruction Fetch)
* `s`: Stack Pointer
* `q`: IO Queue / Ring Buffer
* `r`: Radix (Base)

## Instruction Decoding & Accumulation
Raw ASCII bytes from the instruction stream are decoded in hardware using combinational logic.
* **Comparators:** The hardware checks the ASCII range of the incoming byte. If it is a letter, it subtracts `'a'` to generate a 0-25 register index. If it is punctuation, it subtracts `' '` to decode the operation.
* **Number Accumulation:** If the incoming byte is a digit, it bypasses the register selection. The `num` register accumulates the value using a shift-and-add logic block (equivalent to `(num << 3) + (num << 1) + digit`) to multiply by 10 without requiring a massive hardware multiplier.

## Execution & The ALU
* **Pipeline Stalls:** Because numbers can be multiple digits long, the hardware does not know a Source is complete until the *next* Operation (or EOL) arrives. When a new OP arrives, the CPU "stalls" the pipeline for one clock cycle to execute the previous operation before loading the new one.
* **The ALU MUX:** The Arithmetic Logic Unit combines the Destination (Side A) and the Source (Side B). A hardware Multiplexer (MUX) acts as a switch track for Side B, seamlessly routing either the decoded Source Register or the raw `num` accumulator into the ALU based on the instruction type.

