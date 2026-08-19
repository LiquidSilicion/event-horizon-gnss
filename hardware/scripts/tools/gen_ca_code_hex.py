#!/usr/bin/env python3
"""Generate a single hex file containing all 32 PRN C/A codes"""
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

# Generate all 32 PRNs and write to a single hex file
# Format: one bit per line (Verilog $readmemh expects this for 1-bit wide ROM)
with open("data/rom_data/ca_code_all_prns.hex", "w") as f:
    for prn in range(1, 33):
        code = generate_ca_code(prn)
        for chip in code:
            f.write(f"{chip}\n")

print("✓ Generated data/rom_data/ca_code_all_prns.hex")
print(f"  Total entries: {32 * CODE_LENGTH} (32 PRNs × 1023 chips)")