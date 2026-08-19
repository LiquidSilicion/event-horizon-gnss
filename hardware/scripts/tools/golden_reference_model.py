#!/usr/bin/env python3
"""
Golden Reference Model: Recomputes I&D dumps from raw IF data.
This is what your FPGA Verilog MUST match (within ±1 LSB).
"""
import numpy as np
import struct
import csv
import os

# ============== Constants ==============
FS = 4e6
CODE_RATE = 1.023e6
CODE_LENGTH = 1023
SAMPLES_PER_MS = int(FS * 1e-3)
CHIPS_PER_SAMPLE = CODE_RATE / FS

EARLY_LATE_SPACING = 0.5

# Signal parameters (must match generate_synthetic_gps.py)
PRN = 1
TRUE_DOPPLER_HZ = 1250.0
DOPPLER_OFFSET_HZ = 5.0
LOCAL_DOPPLER_HZ = TRUE_DOPPLER_HZ + DOPPLER_OFFSET_HZ
INITIAL_CODE_PHASE = 347.0

# ============== C/A Code Generator ==============
def generate_ca_code(prn):
    G2_TAPS = {
        1: [2,6], 2: [3,7], 3: [4,8], 4: [5,9], 5: [1,9],
        6: [2,10], 7: [1,8], 8: [2,9], 9: [3,10], 10: [2,7],
        11: [3,8], 12: [4,9], 13: [5,10], 14: [1,4], 15: [2,5],
        16: [3,6], 17: [4,7], 18: [5,8], 19: [6,9], 20: [7,10],
        21: [1,2], 22: [3,4], 23: [5,6], 24: [7,8], 25: [9,10],
        26: [1,3], 27: [4,6], 28: [5,7], 29: [6,8], 30: [7,9],
        31: [8,10], 32: [1,5]
    }
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

# ============== Read IF File ==============
def read_if_file(filename, n_samples):
    data = np.fromfile(filename, dtype=np.int16)
    i_samples = data[0::2].astype(np.float32)
    q_samples = data[1::2].astype(np.float32)
    return i_samples, q_samples

# ============== Core Correlator ==============
def compute_idump(i_samples, q_samples, code, carrier_freq_hz, code_phase_chips,
                  carrier_phase_rad=0.0):
    """
    Compute one 1 ms I&D dump.
    Returns: (I_E, Q_E, I_P, Q_P, I_L, Q_L, next_carrier_phase, 
              code_phase_start, code_phase_end_unwrapped, code_phase_wrapped)
    """
    N = len(i_samples)
    
    I_E = Q_E = I_P = Q_P = I_L = Q_L = 0.0
    
    carr_phase = carrier_phase_rad
    code_phase_start = code_phase_chips
    code_phase = code_phase_chips
    carr_phase_incr = 2 * np.pi * carrier_freq_hz / FS
    code_phase_incr = CHIPS_PER_SAMPLE
    
    early_offset = -EARLY_LATE_SPACING
    late_offset = +EARLY_LATE_SPACING
    
    for n in range(N):
        cos_val = np.cos(carr_phase)
        sin_val = np.sin(carr_phase)
        
        i_wiped = i_samples[n] * cos_val + q_samples[n] * sin_val
        q_wiped = q_samples[n] * cos_val - i_samples[n] * sin_val
        
        idx_p = int(np.floor(code_phase)) % CODE_LENGTH
        idx_e = int(np.floor(code_phase + early_offset)) % CODE_LENGTH
        idx_l = int(np.floor(code_phase + late_offset)) % CODE_LENGTH
        
        code_e = code[idx_e]
        code_p = code[idx_p]
        code_l = code[idx_l]
        
        I_E += i_wiped * code_e
        Q_E += q_wiped * code_e
        I_P += i_wiped * code_p
        Q_P += q_wiped * code_p
        I_L += i_wiped * code_l
        Q_L += q_wiped * code_l
        
        carr_phase += carr_phase_incr
        code_phase += code_phase_incr
        
        if carr_phase > 2 * np.pi:
            carr_phase -= 2 * np.pi
    
    code_phase_end_unwrapped = code_phase
    code_phase_wrapped = code_phase % CODE_LENGTH
    
    return (int(round(I_E)), int(round(Q_E)),
            int(round(I_P)), int(round(Q_P)),
            int(round(I_L)), int(round(Q_L)),
            carr_phase, code_phase_start, code_phase_end_unwrapped, code_phase_wrapped)

# ============== Main ==============
def main():
    if_file = "data/iq_samples/synthetic_gps_l1ca.bin"
    # FIXED: Read 400,000 samples = 100 ms = 100 epochs
    n_samples = 400000  # Changed from 40000 to 400000
    i_samples, q_samples = read_if_file(if_file, n_samples)
    
    code = generate_ca_code(PRN)
    
    golden_results = []
    carr_phase = 0.0
    code_phase = INITIAL_CODE_PHASE
    
    n_epochs = n_samples // SAMPLES_PER_MS
    print(f"\nProcessing {n_epochs} epochs with local Doppler = {LOCAL_DOPPLER_HZ} Hz...")
    
    for epoch in range(n_epochs):
        start_idx = epoch * SAMPLES_PER_MS
        end_idx = start_idx + SAMPLES_PER_MS
        
        if end_idx > len(i_samples):
            break
        
        fd_hz = LOCAL_DOPPLER_HZ
        
        I_E, Q_E, I_P, Q_P, I_L, Q_L, carr_phase, code_phase_start, code_phase_end, code_phase_wrapped = compute_idump(
            i_samples[start_idx:end_idx],
            q_samples[start_idx:end_idx],
            code, fd_hz, code_phase, carr_phase
        )
        
        golden_results.append({
            'epoch_ms': epoch,
            'I_E': I_E, 'Q_E': Q_E,
            'I_P': I_P, 'Q_P': Q_P,
            'I_L': I_L, 'Q_L': Q_L,
            'fd_hz': fd_hz,
            'coff_chips_start': code_phase_start,
            'coff_chips_end': code_phase_end,
        })
        
        # Use WRAPPED value for next epoch
        code_phase = code_phase_wrapped
        
        if epoch % 10 == 0:
            print(f"  Epoch {epoch:4d} ms: I_P={I_P:6d}, Q_P={Q_P:6d}, "
                  f"code_phase: {code_phase_start:.3f} → {code_phase_end:.3f}")
    
    output_file = "data/golden_files/golden_ref_data.csv"
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    
    with open(output_file, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=golden_results[0].keys())
        writer.writeheader()
        writer.writerows(golden_results)
    
    print(f"\n✓ Results saved to {output_file}")
    print(f"✓ Generated {len(golden_results)} epochs")

if __name__ == "__main__":
    main()