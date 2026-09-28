import sys
import os

def build_toolchain(input_file, hex_file, assert_file, memory_size=256):
    if not os.path.exists(input_file):
        raise SystemExit(f"Error: Could not find {input_file}")

    hex_bytes = []
    assert_lines = []
    pc_counter = 0 # Tracks the current memory address

    with open(input_file, 'r') as f:
        for line in f:
            # Capture and sanitize the original line for Verilog printing
            original_line = line.strip().replace('"', '\\"') 
            code_part = line.split('#')[0]
            comment_part = line.split('#')[1] if '#' in line else ""
            
            # 1. Parse Silicon Code & Advance PC
            code_text = code_part.rstrip()
            if code_text:
                code_text += '\n'
                pc_counter += len(code_text) # Advance the simulated PC
                hex_bytes.extend([f"{ord(c):02X}" for c in code_text])

            # 2. Parse Assertions
            tokens = comment_part.split()
            if "now" in tokens and "is" in tokens:
                reg = tokens[tokens.index("now") + 1]
                val = tokens[tokens.index("is") + 1]

                # Write the synchronization locks into the testbench
                assert_lines.append(f'        // Sync to line: {original_line}')
                assert_lines.append(f'        wait(system_top.cpu.pc == {pc_counter} && system_top.cpu.fsm_state == 0);')
                assert_lines.append(f'        @(posedge clk); // Give memory 1 tick to save')
                assert_lines.append(f'        assert_register("{reg}", {val}, "{original_line}");\n')
    
    if len(hex_bytes) > memory_size:
        print(f"Error: Program ({len(hex_bytes)} bytes) exceeds memory!")
        return
        
    # Pad the rest of the memory with zeros to silence Verilog warnings
    hex_bytes.extend(["00"] * (memory_size - len(hex_bytes)))
    
    # Write the HEX file for the BRAM
    with open(hex_file, 'w') as f:
        for i in range(0, len(hex_bytes), 16): # limit line width
            f.write(" ".join(hex_bytes[i:i+16]) + "\n")
            
    # Write the Verilog Header for the Testbench
    with open(assert_file, 'w') as f:
        f.write("\n".join(assert_lines) + "\n")
            
    print(f"[SUCCESS] Assembled {len(hex_bytes)-hex_bytes.count('00')} bytes. Generated {len(assert_lines)} synchronized asserts.")

if __name__ == "__main__":
    build_toolchain('program.txt', 'program.hex', 'asserts.vh')