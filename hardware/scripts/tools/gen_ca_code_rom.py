#!/usr/bin/env python3
"""Generate C/A code .coe files for all 32 GPS PRNs"""
import numpy as np
import os

CODE_LENGTH = 1023

G2_TAPS = {
    1: [2,6], 2: [3,7], 3: [4,8], 4: [5,9], 5: [1,9],
    6: [2,10], 7: [1,8], 8: [2,9], 9: [3,10], 10: [2,7],
    11: [3,8], 12: [4,9], 13: [5,10], 14: [1,4], 15: [2,5],
    16: [3,6], 17: [4,7], 18: [5,8], 19: [6,9], 20: [7,10],
    21: [1,2], 22: [3,4], 23: [5,6], 24: [7,8], 25: [9,10],
    26: [1,3], 27: [4,6], 28: [5,7], 29: [6,8], 30: [7,9],
    31: [8,10], 32: [1,5]
}

def generate_ca_code(prn):
    taps = G2_TAPS[prn]
    g1 = [1] * 10
    g2 = [1] * 10
    code = []
    for _ in range(CODE_LENGTH):
        g1_out = g1[-1]
        g2_out = g2[taps[0]-1] ^ g2[taps[1]-1]
        code.append(1 if (g1_out ^ g2_out) else 0)
        g1_new = g1[-1] ^ g1[-3]
        g1 = [g1_new] + g1[:-1]
        g2_new = g2[-1] ^ g2[-3]
        g2 = [g2_new] + g2[:-1]
    return code

os.makedirs("data/rom_data", exist_ok=True)

for prn in range(1, 33):
    code = generate_ca_code(prn)
    filename = f"data/rom_data/ca_code_prn{prn:02d}.coe"
    with open(filename, "w") as f:
        f.write("memory_initialization_radix=2;\n")
        f.write("memory_initialization_vector=\n")
        f.write("".join(str(c) for c in code) + ";\n")

print(f"✓ Generated 32 C/A code ROM files in data/rom_data/")