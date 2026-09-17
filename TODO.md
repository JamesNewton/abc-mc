## Phase 1: Core Execution & Data Types
Before we break the live-stream paradigm, we must finish the ALU and Lexer capabilities.

**1. Output / Terminal Printing**
 - **Plan**: Instantiate a UART TX module in `top.v`. Map the Terminal device to register `t` via Memory-Mapped IO (MMIO). When the ALU sees a write to `t`, route the data to the TX FIFO instead of RAM.  
- **Test Case**: Send `a:42\nt:a\n`.
- **Assertion**: Hook the testbench to the physical tx_out pin and assert the serial waveform transmits the ASCII characters "42".

**2. Dynamic Radix & Hexadecimal Context**
- **Plan**: Add a `cpu_radix` register that updates when the destination is `r`. Update `STATE_SRC` with a dual-classifier: `if cpu_radix == 16`, intercept `a-f` as digits. Update the shift-and-add logic in `STATE_NUM` to shift by 1, 3, or 4 based on the radix.  
- **Test Case**: Send `r:16\na:f\n`.
- **Assertion**: `assert_register("a", 15)`.

**3. Parameterized Multi-Cycle Math**
- **Plan**: Add compiler directives (`ifdef FAST_MUL_DIV`) in `abc_define.vh`. Build `alu_math.v` as a 32-cycle shift-and-add multiplier/divider. Modify `STATE_EXEC` to stall until a `math_done` flag goes high.
- **Test Case**: Send `a:7*6`
- **Assertion**: Wait for 35 clock cycles, then `assert_register("a", 42)`.

## Phase 2: Memory & Control Flow
Transitioning the CPU from a live UART listener to a stored-program architecture.

**4. Program Memory & Program Counter (p)**
- **Plan**: Instantiate a Block RAM (BRAM). Route incoming UART bytes to sequentially fill this BRAM. Re-wire the CPU's rx_byte input to fetch from the BRAM using the p register as the address. Add logic for [ (start loop) and ] (end loop) to modify p.  
- **Test Case**: Load BRAM with 
```
a:0
[
a+1
a<3~
]
```

- **Assertion**: Run simulation for 100 cycles, `assert_register("a", 3)`.

**5. Main RAM & Data Indexing (@)**
- **Plan**: Instantiate a second BRAM block. Add a memory state to the FSM to handle the @ (index) operator, taking an extra clock cycle to read/write from this expanded data bus.  
- **Test Case**: Send `0@:42\na:0@\n`. (Write 42 to memory address 0, then read it into a).
- **Assertion**: `assert_register("a", 42)`.

**6. Hardware Call Stack (s)**
- **Plan**: Build a 16-deep LIFO buffer in silicon. Wire the push operator `,`, parameter setup `(`, and call operator `)` to increment/decrement the `s` register and push/pop data to the LIFO.  
- **Test Case**: Send `(5,6)`
- **Assertion**: Assert the internal hardware stack has a depth of 2, and the top element is 6.

## Phase 3: System-on-Chip (SoC) Peripherals
Wiring the CPU to the physical world using the crossbar switch.

**7.  MMIO Crossbar & GPIO Allocation**
- **Plan**: Use Verilog `generate` blocks to instantiate a configurable number of `SB_IO` primitives. Expand `dst_sel` to 7 bits to support addresses > 25. Build a demultiplexer to route `D('OUT', pin, value)` commands to the correct `SB_IO` block.  
- **Test Case**: Send `D('OUT', 1, 1)`
 (Assuming the macro maps to a valid numeric sequence).
 - **Assertion**: Assert the physical FPGA pad for pin 1 drives HIGH.
 
 **8. Sigma-Delta Analog Input**
 - **Plan**: Build a digital low-pass filter counter. Wire it to an SB_IO primitive configured as a differential comparator (LVDS). Route it to MMIO so it can be read via `D('ANALOG', pin)`.  
 - **Test Case**: Drive the testbench analog simulation pin with a 50% duty cycle square wave, then execute `a:D('A', 1)`
 (or equivalent compiled byte sequence).
 - **Assertion**: `assert_register("a", 127)` (midpoint of an 8-bit value).
 