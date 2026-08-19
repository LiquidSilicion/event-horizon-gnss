#!/usr/bin/env python3
"""
Generate a synthetic GPS L1CA IF signal for a single PRN.
Output: 10 seconds of complex I/Q samples at 4 MHz (complex int16).
"""
import numpy as np
import struct
import os

# ============== GPS L1CA Constants ==============
FS = 4e6              # Sampling frequency (Hz)
CODE_RATE = 1.023e6   # C/A code chip rate (chips/sec)
CODE_LENGTH = 1023    # C/A code length (chips)

# ============== Signal Parameters (known truth) ==============
PRN = 1
DOPPLER_HZ = 1250.0       # True Doppler in signal (Hz)
DOPPLER_OFFSET_HZ = 5.0   # Offset so local NCO doesn't perfectly match
CODE_PHASE_CHIPS = 347.0  # Initial code phase (chips, 0 to 1022.999)
CARRIER_PHASE_RAD = 0.0   # Initial carrier phase (radians)
DURATION_S = 10.0         # 10 seconds
AMPLITUDE = 1000          # Signal amplitude (fits in int16)

# ============== C/A Code Generator (GPS L1CA) ==============
def generate_ca_code(prn):
    """Generate the 1023-chip GPS C/A code for a given PRN using G1/G2 LFSRs."""
    G2_TAPS = {
        1: [2,6], 2: [3,7], 3: [4,8], 4: [5,9], 5: [1,9],
        6: [2,10], 7: [1,8], 8: [2,9], 9: [3,10], 10: [2,7],
        11: [3,8], 12: [4,9], 13: [5,10], 14: [1,4], 15: [2,5],
        16: [3,6], 17: [4,7], 18: [5,8], 19: [6,9], 20: [7,10],
        21: [1,2], 22: [3,4], 23: [5,6], 24: [7,8], 25: [9,10],
        26: [1,3], 27: [4,6], 28: [5,7], 29: [6,8], 30: [7,9],
        31: [8,10], 32: [1,5]
    }
    if prn not in G2_TAPS:
        raise ValueError(f"PRN {prn} not implemented")
    
    taps = G2_TAPS[prn]
    g1 = [1] * 10
    g2 = [1] * 10
    
    code = np.zeros(CODE_LENGTH, dtype=np.int8)
    for i in range(CODE_LENGTH):
        g1_out = g1[-1]
        g2_out = g2[taps[0]-1] ^ g2[taps[1]-1]
        code[i] = 1 if (g1_out ^ g2_out) else -1
        
        g1_new = g1[-1] ^ g1[-3]
        g1 = [g1_new] + g1[:-1]
        
        g2_new = g2[-1] ^ g2[-3]
        g2 = [g2_new] + g2[:-1]
    
    return code

# ============== Generate the Signal ==============
print(f"Generating synthetic GPS L1CA signal:")
print(f"  PRN: {PRN}, Doppler: {DOPPLER_HZ} Hz, Code phase: {CODE_PHASE_CHIPS} chips")
print(f"  Sample rate: {FS/1e6} MHz, Duration: {DURATION_S} s")

N_SAMPLES = int(FS * DURATION_S)
code = generate_ca_code(PRN)

t = np.arange(N_SAMPLES) / FS

chips_per_sample = CODE_RATE / FS
code_phase_samples = np.arange(N_SAMPLES) * chips_per_sample + CODE_PHASE_CHIPS * (FS/CODE_RATE)
code_indices = np.floor(code_phase_samples).astype(int) % CODE_LENGTH
code_waveform = code[code_indices].astype(np.float32)

carrier = np.exp(1j * 2 * np.pi * DOPPLER_HZ * t + 1j * CARRIER_PHASE_RAD).astype(np.complex64)

signal = AMPLITUDE * code_waveform * carrier

signal_i = np.real(signal).astype(np.int16)
signal_q = np.imag(signal).astype(np.int16)

output_file = "data/iq_samples/synthetic_gps_l1ca.bin"
os.makedirs(os.path.dirname(output_file), exist_ok=True)

with open(output_file, "wb") as f:
    for i, q in zip(signal_i, signal_q):
        f.write(struct.pack("<hh", i, q))

print(f"✓ Wrote {N_SAMPLES} samples to {output_file}")
print(f"  File size: {N_SAMPLES * 4 / 1e6:.2f} MB")
print(f"\n=== TRUTH PARAMETERS ===")
print(f"  PRN: {PRN}")
print(f"  True Doppler: {DOPPLER_HZ} Hz")
print(f"  Local Doppler (for tracking): {DOPPLER_HZ + DOPPLER_OFFSET_HZ} Hz")
print(f"  Code phase: {CODE_PHASE_CHIPS} chips")
print(f"  Sample rate: {FS} Hz")
print(f"  Samples per 1ms epoch: {int(FS * 1e-3)}")