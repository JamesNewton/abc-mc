## Phase 1: Core Execution & Data Types
Before we break the live-stream paradigm, we must finish the ALU and Lexer capabilities.

**Output / Terminal Printing** DONE
 - **Plan**: Instantiate a UART TX module in `top.v`. Map the Terminal device to register `t` via Memory-Mapped IO (MMIO). When the ALU sees a write to `t`, route the data to the TX FIFO instead of RAM.  
- **Test**: `a:42\nt:a\n`.
- **Assertion**: Assert the serial waveform transmits the ASCII characters "42".

**Dynamic Radix & Hexadecimal Context** DONE
- **Plan**: Add a `cpu_radix` register that updates when the destination is `r`. Update `STATE_SRC` with a dual-classifier: `if cpu_radix == 16`, intercept `a-f` as digits. Update the shift-and-add logic in `STATE_NUM` to shift by 1, 3, or 4 based on the radix.  
- **Test**: `r:16\na:f\n`.
- **Assertion**: `assert_register("a", 15)`.

**Parameterized Multi-Cycle Math** DONE
- **Plan**: Add compiler directives (`ifdef FAST_MUL_DIV`) in `abc_define.vh`. Build `alu_math.v` as a 32-cycle shift-and-add multiplier/divider. Modify `STATE_EXEC` to stall until a `math_done` flag goes high.
- **Test**: `a:7*6`
- **Assertion**: Wait for 35 clock cycles, then `assert_register("a", 42)`.

## Phase 2: Memory & Control Flow
Transitioning the CPU from a live UART listener to a stored-program architecture.

**Program Memory** DONE
- **Plan**: Instantiate a Block RAM (BRAM).  DONE

**Program Counter (p)** DONE
- **Plan**: Decouple the execution FSM to handle memory pipeline latency. Route incoming UART bytes to sequentially fill this BRAM. Re-wire the CPU's rx_byte input to fetch from the BRAM using the p register as the address. 

**Build a text-to-hex assembler script.** DONE

**Re-implement test cases into a program.txt software suite** DONE

**Stack** DONE
- **Plan**: Build a LIFO buffer in silicon. Wire the push operator `,`
- **Test**: `s:0\n z,42\n` s will be 1, z will be 0, and TOS 42

**The Condition Flag:** DONE
- **Plan**: A dedicated 1-bit flip-flop (e.g., cmp_flag) that gets set or cleared by the comparison operators (<, >, =)

**The Return Address:** DONE
- **Plan**: Push the pc value to the stack when we see a [, so we know exactly where to jump back to when we hit a ].

**The Jump Mechanic:** DONE
- **Plan**: The ability to physically overwrite the Program Counter (pc) during execution, rather than just passively letting it increment.

**Implement Looping** DONE
Add logic for [ (start loop) and ] (end loop) to modify p.  

- **Test**: Load BRAM with 
```
a:0
[
a+1
a<3~
]
```

**Implement Conditionals** DONE
- **Plan**: Add skip_flag, STATE_DST skips if set. '?' sets it if false, '!' sets it otherwise, and EOL clears it.

**Main RAM & Data Indexing (@)** DONE
- **Plan**: Instantiate a second BRAM block. Add a memory state to the FSM to handle the @ (index) operator, taking an extra clock cycle to read/write from this expanded data bus.  
- **Test Case**: Send `a@1:2\nc:3\nc:a@b`. (Write 2 to memory address a+1 aka b, set c to 3, write a@b (aka c) to d).
- **Assertion**: `assert_register("b", 2); assert_register("d", 3);`.

**Hardware Call Stack & Subroutines (`(`, `)`, `.`)**
- **Plan**: Wire `(` to prepare the FSM for arguments. Wire `)` to push the final argument to the stack, push the current `pc` (return address), and overwrite the `pc` with the target address stored in the destination register. Wire `.` to pop the return address from the BRAM stack back into the `pc`, returning execution to the caller.
- **Test Case**: Jump over a subroutine to the main code. Assign the subroutine's physical memory address to a register (e.g., `f`). Call `f(5)`. Inside the subroutine, perform math, save the result to a global variable, and return `.`.
- **Assertion**: Assert the global variable contains the correct math result, and assert the stack pointer `s` has perfectly returned to 0 (proving a clean frame cleanup).

## Phase 3: System-on-Chip (SoC) Peripherals
Wiring the CPU to the physical world using the crossbar switch.

**MMIO Crossbar & GPIO Allocation**
- **Plan**: Use Verilog `generate` blocks to instantiate a configurable number of `SB_IO` primitives. Expand `dst_sel` to 7 bits to support addresses > 25. Build a demultiplexer to route `D('OUT', pin, value)` commands to the correct `SB_IO` block.  
- **Test Case**: Send `D('OUT', 1, 1)`
 (Assuming the macro maps to a valid numeric sequence).
 - **Assertion**: Assert the physical FPGA pad for pin 1 drives HIGH.
 
 **Sigma-Delta Analog Input**
 - **Plan**: Build a digital low-pass filter counter. Wire it to an SB_IO primitive configured as a differential comparator (LVDS). Route it to MMIO so it can be read via `D('ANALOG', pin)`.  
 - **Test Case**: Drive the testbench analog simulation pin with a 50% duty cycle square wave, then execute `a:D('A', 1)`
 (or equivalent compiled byte sequence).
 - **Assertion**: `assert_register("a", 127)` (midpoint of an 8-bit value).
 
 ## Future Explorations: Boot & Initialization
**SPI Flash Bootloader**
- **Plan**: Expand the FSM with a `STATE_BOOT` sequence that runs on power-up. Configure an SPI peripheral to read a raw text file from an external Flash chip (standard on iCE40 boards) and stream it directly into the Instruction BRAM before transitioning to `STATE_FETCH`.

**Bootloader Label Back-filling (`$`)**
- **Plan**: Implement a dynamic hardware linker operator (`$`). E.g., `f:000 ... f$a:a+1.` 
- **Mechanic**: When the FSM encounters `$`, it halts execution, scans the BRAM for the matching destination pattern (e.g., `f:000`), overwrites those zeros with the current `pc` address, and then resumes normal execution.