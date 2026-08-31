#!/usr/bin/env python3
"""
Generates Sine and Cosine ROM files for a Numerically Controlled Oscillator (NCO).
Output format is compatible with Verilog $readmemh.
"""

import numpy as np
import os
import math

# ============================================================================
# Configuration Parameters
# ============================================================================
ROM_SIZE = 4096          # Number of entries (must be power of 2, e.g., 4096)
DATA_WIDTH = 18          # Bit width of each sample (e.g., 18 bits)
OUTPUT_DIR = './rom_data' # Directory to save the .hex files

# ============================================================================
# Helper Function: Format integer to two's complement hex
# ============================================================================
def to_hex(val, width):
    """Converts a signed integer to a zero-padded two's complement hex string."""
    # Mask to keep only 'width' bits (handles negative numbers via two's complement)
    mask = (1 << width) - 1
    val_masked = val & mask
    # Calculate number of hex digits needed (e.g., 18 bits -> 5 hex digits)
    hex_digits = math.ceil(width / 4)
    return f"{val_masked:0{hex_digits}X}"

# ============================================================================
# Main Generation Logic
# ============================================================================
def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    print(f"Generating {ROM_SIZE}-point NCO ROMs with {DATA_WIDTH}-bit resolution...")
    
    # Maximum positive amplitude for signed integer (e.g., 2^17 - 1 = 131071 for 18-bit)
    max_amp = (1 << (DATA_WIDTH - 1)) - 1
    
    # Generate phase angles from 0 to 2*pi (exclusive of 2*pi to avoid duplicate 0 point)
    phase = np.linspace(0, 2 * np.pi, ROM_SIZE, endpoint=False)
    
    # Calculate cosine and sine, scale to max amplitude, and round to nearest integer
    cos_vals = np.round(np.cos(phase) * max_amp).astype(int)
    sin_vals = np.round(np.sin(phase) * max_amp).astype(int)
    
    cos_file = os.path.join(OUTPUT_DIR, 'nco_cos.hex')
    sin_file = os.path.join(OUTPUT_DIR, 'nco_sin.hex')
    
    print(f"Writing Cosine ROM to: {cos_file}")
    with open(cos_file, 'w') as f:
        for val in cos_vals:
            f.write(to_hex(val, DATA_WIDTH) + '\n')
            
    print(f"Writing Sine ROM to: {sin_file}")
    with open(sin_file, 'w') as f:
        for val in sin_vals:
            f.write(to_hex(val, DATA_WIDTH) + '\n')
            
    print("✅ NCO ROM generation complete!")
    print(f"   - Cosine min/max: {np.min(cos_vals)} / {np.max(cos_vals)}")
    print(f"   - Sine min/max:   {np.min(sin_vals)} / {np.max(sin_vals)}")

if __name__ == '__main__':
    main()