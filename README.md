# ABC Silicon Architecture

This project is a hardware implementation of the [ABC Virtual](https://github.com/JamesNewton/ABC) Machine, designed in Verilog for synthesis on FPGAs (like the Lattice iCE40). It translates the high-level, string-evaluated C++ ABC language directly into a digital logic pipeline.

## The Execution Pipeline (DST-OP-SRC)
The heart of the processor is a Finite State Machine (FSM) tracking the `dst_op_src` sequence. 
* Instructions flow sequentially: incoming bytes are pre-fetched and then loaded into the **Destination** (`dst`) register, then the FSM increments to expect an **Operation** (`op`), and increments again to expect a **Source** (`src`).
* The CPU uses delayed execution. When a complete `dst_op_src` set is loaded, it waits. When the next `op` (or EOL) arrives, the FSM stalls to execute the pending math, commits the result to the `dst`, and then shifts the newly arrived Operation into the `op` register, clearing the `src`.
* After each execution, decrementing the FSM back to the Operation state allows for chained mathematics (e.g., `a:b+c\n`).
* A carriage return (or line end) is an op which resets the FSM back to 0 (dst), ready for a new line of code.

## The Register File
The CPU features an array of 26 wide registers, mapped directly to the alphabet (`a` through `z`). Several registers are hardwired to processor-level functions:
* `p`: Program Counter (Instruction Fetch)
* `q`: IO Queue / Ring Buffer
* `r`: Radix (Base)
* `s`: Stack Pointer
* `t`: Terminal

Note on Radix & Hexadecimal: Hex parsing can use a context-aware dual-classifier to resolve the a-f ambiguity. In STATE_DST, a-z are strictly registers. In STATE_SRC, if the radix register (r) is 16, a-f are intercepted as numeric literals and jump to STATE_NUM. Math accumulation dynamically shifts by 1, 3, or 4 based on r.

## Instruction Decoding & Accumulation
Raw ASCII bytes from the instruction stream are decoded in hardware using combinational logic.
* **Comparators:** The hardware checks the ASCII range of the incoming byte. If it is a letter, it subtracts `'a'` to generate a 0-25 register index. If it is punctuation, it subtracts `' '` to decode the operation.
* **Number Accumulation:** If the incoming byte is a digit, it bypasses the register selection. The `num` register accumulates the value using a shift-and-add logic block (equivalent to the current radix, e.g. for 10: `(num << 3) + (num << 1) + digit`) to multiply by one digit place without requiring a massive hardware multiplier.

## Execution & The ALU
* **Pipeline Stalls:** Because numbers can be multiple digits long, the hardware does not know a Source is complete until the *next* Operation (or EOL) arrives. When a new OP arrives, the CPU "stalls" the pipeline for one clock cycle to execute the previous operation before loading the new one.
* **The ALU MUX:** The Arithmetic Logic Unit combines the Destination (Side A) and the Source (Side B). A hardware Multiplexer (MUX) acts as a switch track for Side B, seamlessly routing either the decoded Source Register or the raw `num` accumulator into the ALU based on the instruction type.

<hr>
&nbsp;
<hr>

# The Original Language

ABC has already been implemented as a C++ byte code interpreter: https://github.com/JamesNewton/ABC 
This copy of the commands, taken from that implementation, serve as a goal for this project.

## Commands

| Command | Description |
| :---: | :--- |
| `0`-`9` | (and lowercase `a` up when radix > 10) these accumulate base 'r' digits into NUM. All numbers are 32 bit ints, no floats. See `%` below for fixed place. |
| `a`-`z` | Variables/Registers (SRC or DST). Some registers have special meanings:<br>• `p` Program Counter aka PC.<br>• `q` Queue length (RX ring buffer). Read/Write to manage incoming stream.<br>• `r` Radix (Default 10). >10 treat 'a' on as digits. e.g. a-f for hex if r=16.<br>• `s` Stack Pointer aka SP.<br>• `t` Terminal Device (Default serial output/input). |
| `:` | Copy / assignment. `a:5` sets register 0 to 5. `a:b` copies the value of b to a. |
| `@` | index. Address for a device (dynamixel, I2C, ...) or an offset for an array. |
| `'` | (Single Quote) ASCII literal or hash. Numeric decimal value of a char (`'A'` is 65) or the hash of a string (`'PWM'` is 0x151FA2). |
| `"` | (Quote) Text. Each following char is copied to the DST until the ending quote. If the DST is a variable, the chars are copied into memory and the var is set to the starting address of the string in memory. If the operation was already `"` when a new starting `"` is seen, put a `"` into the dest then enter text mode. `Push ""START""` prints `Push "START"`. Can also be used to match incoming text. e.g. `t="HELLO"?t:"HI"`. |
| `%` | Format. Converts the value of source to digits (radix r) and copies it to DST. Uses a previous num as length and following num as precision. e.g. `a:250;t:8%2a` -> `____2.50`. Also dumps FLASH to out. e.g. `a:"HELLO"; t:%a;` will print `HELLO`. |
| `+` | set operation to add. `a+b` adds b to a. `a:b+5` sets a to b then adds 5. If there is no SRC, the NUM is used as the SRC. `a+1` increments a. |
| `-` | set operation to subtract. `a:b-3` a becomes b less 3. `a-1` decrements a. |
| `&` | set operation to bitwise AND. `a-&b` ANDs a with NOT b. |
| `\|` | set operation to bitwise OR. |
| `=` | set compare type to equal. |
| `<` | set compare type to less than. |
| `>` | set compare type to greater than. |
| `{` | Less than or equal (ASCII value of `<` plus `=` less 63). |
| `}` | Greater than or equal (ASCII value of `>` plus `=` less 63). |
| `~` | Not. Toggle true/false flag. Use with greater less and equal. e.g. `a<b~` will set the true flag if a is greater than or equal to b. `>~` is less than or equal too. `<~` is greater than or equal too. `=~` is not equal. |
| `?` | If the comparison fails skip to the next line and past indented sections or until a `!` (not TRUE).|
| `!` | else. If the prior comparison succeeded, skip to the next line and past indented sections. |
| `(` | params. Prep for a function call by pushing state. |
| `,` | push NUM as an argument to the stack and increment SP. |
| `)` | call. Push final argument, push PC, set PC to DST, calling the function. |
| `[` | Start loop. |
| `]` | End loop if true flag is not set. |
| `.` | return. Cleanup stack, restore PC. |
| `;` | Line end. Same as `\n`. |
| `#` | Comment. Runs to the end of the line.
| `A` | set Port pin in SRC to read analog values in e.g. `a:2A`. |
| `D` | Device. Complex device like Stepper Motor, I2C, SPI, etc.. See below for details. |
| `I` | (In) set the Port or Port pin in SRC to an Input. E.g. `a:7I` reads pin 7 to a. |
| `H` | (High) set the Pin in DST to high. e.g. `1H` sets pin 1 high. |
| `L` | (Low) set the Pin in DST to low. |
| `P` | (PWM) set Pin in DST to output PWM in SRC. e.g. `2P100`. |
| `R` | (RC Servo) set Port pin in DST to drive RC servo to position in SRC. e.g. `1R90`. |
| `U` | (Up) set Pin in DST to inputs with internal pull-up. |
| `W` | Wait. Delay for NUM microseconds. Clears DST. e.g. `100W 1H L H L`. |


Unused (for now)
$	
^	power? 
_	label? sub-element?


Devices: These are the mnemonic character literals passed to the D (Device) function to allocate and configure hardware peripherals:

| Command | Description |
| :--- | :--- |
| `D('ANALOG', pin)` | Analog Input. `i:D('A',2);i>128?"High";` |
| `D('DYNAMIXEL', id, baud)` | Dynamixel Servo. No pin number because there is only one bus. Address the control table with the `@` operator. e.g. `65@d:1` to turn on the LED. The default address is Goal Position on write, Current Position on read. |
| `D('IIC', SCLpin, SDApin, address)` | IIC Bus. Set address with `@`. `i:D('i', 5, 4, 104);1@i : 123` Write 123 to register 1 in the I2C device attached to pin 4 and 5 (SDA, SCL) with address 104. `x : 0 @ 2 i` streams 2 bytes into RAM, and `x @ 1` dereferences that memory. |
| `D('IN', pin, pull)` | Digital Input use `I`, or `U`. |
| `D('OUT', pin, value)` | Digital Output or use `H`, `L`. |
| `D('PWM', pin, value)` | PWM Output or use `P`. |
| `D('ENCODER', pinA, pinB)` | Quadrature Encoder |
| `D('SERVO', pin, angle)` | RC Servo. |
| `D('SPI', MISOpin, MOSIpin, SCKpin)` | SPI Bus. **TODO** |
| `D('STEPPER', STEPpin, DIRpin, velocity, accel)` | Stepper Motor. Write a goal position. `m:D('S', 3, 4, 1000, 5000);m:100` Run the stepper driver connected to pins 3 and 4 (step and direction) forward 100 steps, at 1K steps per second, with an acceleration of 5K steps per second per second. |
| `D('UART', TXpin, RXpin, baud)` | UART / Serial. **TODO** |
| `D('FLASH')` | Serialize variables, strings, and functions directly into non-volatile memory so they survive a reboot. |

## Matching
In addition to device and digital IO, we can do input stream pattern matching. 
When the double quotes are at the start of the line (as a destination) they work
to match incoming text. e.g. 
```
"hello"?t:"hi"
"goodbye"?t:"laters"
```

The `q` register is used to control the input matching queue. Imagine the user just typed "hello" into the terminal. The ring buffer now holds 5 unread characters.
```
a:q; 'a' is assigned 5, because there are 5 chars ("hello") in the queue.
q-1; We subtract 1 from 'q'. The VM pops the oldest char ('h'). 
b:q; 'b' is assigned 4. The queue now holds "ello".
q-3; We subtract 3 from 'q'. The VM pops 'e', 'l', and 'l'.
c:q; 'c' is assigned 1. The queue now holds just "o".
q:0; Assigning 0 to 'q' flushes the queue completely.
```
This feature is quite useful when combined with the string matching operator (=). If you are searching a data stream for a specific keyword but get a partial match or an irrelevant character, you can pop exactly the amount of characters you need to discard before checking the stream again.
