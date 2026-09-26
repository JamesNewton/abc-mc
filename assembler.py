import sys
import os

def txt_to_hex(input_file, output_file, memory_size=256):
    if not os.path.exists(input_file):
        print(f"Error: Could not find {input_file}")
        return

    with open(input_file, 'r') as f:
        text = f.read()
        
    # Convert each character to its 2-digit uppercase hex value
    hex_bytes = [f"{ord(c):02X}" for c in text]
    
    if len(hex_bytes) > memory_size:
        print(f"Error: Program ({len(hex_bytes)} bytes) exceeds {memory_size}-byte memory!")
        return
        
    # Pad the rest of the memory with zeros to silence Verilog warnings
    hex_bytes.extend(["00"] * (memory_size - len(hex_bytes)))
    
    with open(output_file, 'w') as f:
        # Write 16 bytes per line for clean formatting
        for i in range(0, len(hex_bytes), 16):
            f.write(" ".join(hex_bytes[i:i+16]) + "\n")
            
    print(f"[SUCCESS] Assembled {len(text)} bytes into {output_file}")

if __name__ == "__main__":
    txt_to_hex('program.txt', 'program.hex')