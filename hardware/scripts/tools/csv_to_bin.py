#!/usr/bin/env python3
"""Convert golden_ref_data.csv to binary for Verilog testbench (Big-Endian)"""
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
        # '>' forces Big-Endian. This matches Verilog's $fread MSB-first loading.
        data = struct.pack('>iiiiii',
            int(row['I_E']), 
            int(row['Q_E']),
            int(row['I_P']), 
            int(row['Q_P']),
            int(row['I_L']), 
            int(row['Q_L']))
        fout.write(data)
        count += 1

print(f"✓ Generated {output_file} (Big-Endian)")