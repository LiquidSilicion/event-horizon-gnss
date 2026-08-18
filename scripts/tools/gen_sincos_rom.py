#!/usr/bin/env python3
"""Generate sine/cosine ROM .coe file for carrier_nco.v"""
import numpy as np
import os

N_ENTRIES = 4096
OUTPUT_BITS = 18
MAX_VAL = 2**(OUTPUT_BITS - 1) - 1  # 131071

os.makedirs("data/rom_data", exist_ok=True)

# Generate sine and cosine tables
with open("data/rom_data/sincos_table.coe", "w") as f:
    f.write("memory_initialization_radix=10;\n")
    f.write("memory_initialization_vector=\n")
    for i in range(N_ENTRIES):
        phase = i * 2 * np.pi / N_ENTRIES
        sin_val = int(round(np.sin(phase) * MAX_VAL))
        cos_val = int(round(np.cos(phase) * MAX_VAL))
        # Store as: sin,cos pairs (or use two separate ROMs)
        f.write(f"{sin_val}, {cos_val}")
        if i < N_ENTRIES - 1:
            f.write(",\n")
        else:
            f.write(";\n")

print("✓ Generated data/rom_data/sincos_table.coe")
print(f"  {N_ENTRIES} entries, {OUTPUT_BITS}-bit signed values")