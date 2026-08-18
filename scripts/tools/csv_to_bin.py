#!/usr/bin/env python3
"""Convert golden_ref_data.csv to binary for Verilog testbench"""
import csv
import struct
import os

input_file = "data/golden_files/golden_ref_data.csv"
output_file = "data/golden_files/golden_ref_data.bin"

os.makedirs(os.path.dirname(output_file), exist_ok=True)

with open(input_file, "r") as fin, open(output_file, "wb") as fout:
    reader = csv.DictReader(fin)
    count = 0
    for row in reader:
        # Pack: epoch_ms, I_E, Q_E, I_P, Q_P, I_L, Q_L (all int32)
        data = struct.pack("<iiiiiii",
            int(row['epoch_ms']),
            int(row['I_E']), int(row['Q_E']),
            int(row['I_P']), int(row['Q_P']),
            int(row['I_L']), int(row['Q_L']))
        fout.write(data)
        count += 1

print(f"✓ Generated {output_file}")
print(f"✓ Converted {count} epochs to binary format")