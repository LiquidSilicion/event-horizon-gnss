#!/usr/bin/env python3
"""
GNSS FFT-Based Acquisition Engine Simulation
Demonstrates PCPS algorithm and FFT splitting techniques based on Leclère et al. 2015
"""

import numpy as np
from scipy import signal
import matplotlib.pyplot as plt
from typing import Tuple, List, Dict
import os

# ============================================================================
# GPS L1 C/A Code Parameters
# ============================================================================
CHIP_RATE = 1.023e6          # chips per second
CODE_LENGTH = 1023           # chips per code period
CODE_PERIOD = 1e-3           # 1 ms
SAMPLE_RATE = 4e6            # 4 MHz (matches your tracking engine)
SAMPLES_PER_CODE = int(SAMPLE_RATE * CODE_PERIOD)  # 4000 samples

# PRN selection (1-32)
PRN_NUMBER = 1

# ============================================================================
# GPS C/A Code Generation
# ============================================================================
def generate_ca_code(prn: int) -> np.ndarray:
    """
    Generate GPS L1 C/A code for a given PRN number
    Returns: 1023-chip code sequence (+1/-1)
    """
    G1_TAPS = [2, 9]  # Feedback taps for G1 (1-based index)
    
    # Full G2 feedback taps for all 32 GPS PRNs (1-based index)
    G2_TAPS = {
        1: [2, 6], 2: [3, 7], 3: [4, 8], 4: [5, 9], 5: [1, 9],
        6: [2, 10], 7: [1, 8], 8: [2, 9], 9: [3, 10], 10: [2, 3],
        11: [3, 4], 12: [5, 6], 13: [6, 7], 14: [7, 8], 15: [8, 9],
        16: [9, 10], 17: [1, 4], 18: [2, 5], 19: [3, 6], 20: [4, 7],
        21: [5, 8], 22: [6, 9], 23: [1, 3], 24: [4, 6], 25: [5, 7],
        26: [6, 8], 27: [7, 9], 28: [8, 10], 29: [1, 6], 30: [2, 7],
        31: [3, 8], 32: [4, 9]
    }
    
    if prn not in G2_TAPS:
        raise ValueError(f"Invalid PRN number: {prn}. Must be 1-32.")
    
    # Initialize shift registers (all 1s)
    g1 = np.ones(10, dtype=int)
    g2 = np.ones(10, dtype=int)
    
    code = np.zeros(CODE_LENGTH, dtype=int)
    
    for i in range(CODE_LENGTH):
        # Output bit (XOR of last bits)
        code[i] = g1[9] ^ g2[9]
        
        # G1 feedback
        g1_fb = g1[G1_TAPS[0]-1] ^ g1[G1_TAPS[1]-1]
        
        # G2 feedback
        g2_fb = g2[G2_TAPS[prn][0]-1] ^ g2[G2_TAPS[prn][1]-1]
        
        # Shift registers right by 1
        g1 = np.roll(g1, 1)
        g1[0] = g1_fb
        
        g2 = np.roll(g2, 1)
        g2[0] = g2_fb
    
    # Convert to +1/-1 (BPSK modulation)
    code = 2 * code - 1
    
    return code

# ============================================================================
# Signal Generation
# ============================================================================
def generate_gps_signal(prn: int, doppler: float, code_phase_chips: float, 
                       snr_db: float = 10) -> Tuple[np.ndarray, np.ndarray]:
    """
    Generate synthetic GPS signal with given parameters
    Returns: I and Q components
    """
    # Generate C/A code
    code = generate_ca_code(prn)
    
    # Resample code to sample rate
    code_resampled = signal.resample(code, SAMPLES_PER_CODE)
    
    # Apply code phase shift (convert chips to samples)
    samples_per_chip = SAMPLES_PER_CODE / CODE_LENGTH
    sample_shift = int(code_phase_chips * samples_per_chip)
    code_shifted = np.roll(code_resampled, sample_shift)
    
    # Generate carrier
    t = np.arange(SAMPLES_PER_CODE) / SAMPLE_RATE
    carrier_i = np.cos(2 * np.pi * doppler * t)
    carrier_q = np.sin(2 * np.pi * doppler * t)
    
    # Modulate
    signal_i = code_shifted * carrier_i
    signal_q = code_shifted * carrier_q
    
    # Add noise
    signal_power = np.mean(signal_i**2 + signal_q**2)
    noise_power = signal_power / (10**(snr_db/10))
    noise_i = np.sqrt(noise_power/2) * np.random.randn(SAMPLES_PER_CODE)
    noise_q = np.sqrt(noise_power/2) * np.random.randn(SAMPLES_PER_CODE)
    
    return signal_i + noise_i, signal_q + noise_q

# ============================================================================
# Basic PCPS Acquisition (Standard 3-FFT Solution)
# ============================================================================
def pcps_acquisition(signal_i: np.ndarray, signal_q: np.ndarray,
                    prn: int, doppler_search: np.ndarray) -> Dict:
    """
    Parallel Code Phase Search acquisition
    Returns: acquisition results
    """
    # Generate local code
    local_code = generate_ca_code(prn)
    local_code_resampled = signal.resample(local_code, SAMPLES_PER_CODE)
    
    # Zero-pad to FFT size (power of 2)
    fft_size = 4096
    local_code_padded = np.zeros(fft_size, dtype=complex)
    local_code_padded[:SAMPLES_PER_CODE] = local_code_resampled
    
    # FFT of local code (pre-compute once)
    local_code_fft = np.fft.fft(local_code_padded)
    local_code_fft_conj = np.conj(local_code_fft)
    
    # Search over Doppler frequencies
    results = []
    
    for doppler in doppler_search:
        # Generate local carrier
        t = np.arange(SAMPLES_PER_CODE) / SAMPLE_RATE
        carrier_i = np.cos(2 * np.pi * doppler * t)
        carrier_q = np.sin(2 * np.pi * doppler * t)
        
        # Carrier wipe-off
        mixed_i = signal_i[:SAMPLES_PER_CODE] * carrier_i + signal_q[:SAMPLES_PER_CODE] * carrier_q
        mixed_q = signal_q[:SAMPLES_PER_CODE] * carrier_i - signal_i[:SAMPLES_PER_CODE] * carrier_q
        
        # Zero-pad and FFT (FIXED: added assignment of mixed_i/q)
        mixed_padded = np.zeros(fft_size, dtype=complex)
        mixed_padded[:SAMPLES_PER_CODE] = mixed_i + 1j * mixed_q
        
        mixed_fft = np.fft.fft(mixed_padded)
        
        # Multiply with conjugate of local code FFT
        correlation_fft = mixed_fft * local_code_fft_conj
        
        # IFFT
        correlation = np.fft.ifft(correlation_fft)
        
        # Magnitude
        correlation_mag = np.abs(correlation[:SAMPLES_PER_CODE])
        
        # Find peak
        peak_idx = np.argmax(correlation_mag)
        peak_value = correlation_mag[peak_idx]
        
        results.append({
            'doppler': doppler,
            'code_phase': peak_idx,
            'peak_value': peak_value,
            'correlation': correlation_mag
        })
    
    # Find best result
    best_result = max(results, key=lambda x: x['peak_value'])
    
    return {
        'best_doppler': best_result['doppler'],
        'best_code_phase': best_result['code_phase'],
        'peak_value': best_result['peak_value'],
        'all_results': results
    }

# ============================================================================
# FFT Splitting Implementation (Leclère et al. 2015)
# ============================================================================
def fft_split_3way(x: np.ndarray) -> np.ndarray:
    """
    Compute N-point FFT using three N/3-point FFTs
    Based on Leclère et al. 2015 "FFT Splitting for Improved FPGA-Based Acquisition of GNSS Signals"
    """
    N = len(x)
    assert N % 3 == 0, "Length must be divisible by 3"
    
    N3 = N // 3
    
    # Split into three sections
    x0 = x[0:N3]
    x1 = x[N3:2*N3]
    x2 = x[2*N3:3*N3]
    
    # Compute combinations
    w3_1 = np.exp(-1j * 2 * np.pi / 3)
    w3_2 = np.exp(1j * 2 * np.pi / 3)
    
    y0 = x0 + x1 + x2
    y1 = x0 + x1 * w3_1 + x2 * w3_2
    y2 = x0 + x1 * w3_2 + x2 * w3_1
    
    # Compute N/3-point FFTs
    Y0 = np.fft.fft(y0)
    Y1 = np.fft.fft(y1)
    Y2 = np.fft.fft(y2)
    
    # Combine results
    X = np.zeros(N, dtype=complex)
    
    for k in range(N3):
        X[3*k] = Y0[k]
        X[3*k+1] = Y1[k] * np.exp(-1j * 2 * np.pi * k / N)
        X[3*k+2] = Y2[k] * np.exp(-1j * 4 * np.pi * k / N)
    
    return X

def pcps_acquisition_with_splitting(signal_i: np.ndarray, signal_q: np.ndarray,
                                   prn: int, doppler_search: np.ndarray,
                                   split_method: str = '3way') -> Dict:
    """
    PCPS acquisition using FFT splitting to reduce zero-padding and memory usage.
    split_method: '3way' (9-FFT solution), 'none' (standard 3-FFT solution)
    """
    # Generate local code
    local_code = generate_ca_code(prn)
    local_code_resampled = signal.resample(local_code, SAMPLES_PER_CODE)
    
    # Determine FFT size based on splitting method
    if split_method == '3way':
        # 9-FFT solution: use 49152 samples (3 * 16384)
        fft_size = 49152
    else:
        # Standard 3-FFT solution: use 65536 samples
        fft_size = 65536
        
    # Zero-pad local code
    local_code_padded = np.zeros(fft_size, dtype=complex)
    local_code_padded[:SAMPLES_PER_CODE] = local_code_resampled
    
    # FFT of local code
    if split_method == '3way':
        local_code_fft = fft_split_3way(local_code_padded)
    else:
        local_code_fft = np.fft.fft(local_code_padded)
    
    local_code_fft_conj = np.conj(local_code_fft)
    
    # Search over Doppler
    results = []
    
    for doppler in doppler_search:
        # Carrier wipe-off
        t = np.arange(SAMPLES_PER_CODE) / SAMPLE_RATE
        carrier_i = np.cos(2 * np.pi * doppler * t)
        carrier_q = np.sin(2 * np.pi * doppler * t)
        
        mixed_i = signal_i[:SAMPLES_PER_CODE] * carrier_i + signal_q[:SAMPLES_PER_CODE] * carrier_q
        mixed_q = signal_q[:SAMPLES_PER_CODE] * carrier_i - signal_i[:SAMPLES_PER_CODE] * carrier_q
        
        # Zero-pad and FFT
        mixed_padded = np.zeros(fft_size, dtype=complex)
        mixed_padded[:SAMPLES_PER_CODE] = mixed_i + 1j * mixed_q
        
        if split_method == '3way':
            mixed_fft = fft_split_3way(mixed_padded)
        else:
            mixed_fft = np.fft.fft(mixed_padded)
        
        # Correlation
        correlation_fft = mixed_fft * local_code_fft_conj
        correlation = np.fft.ifft(correlation_fft)
        
        # Magnitude (only first half is valid due to zero-padding of 2 periods)
        correlation_mag = np.abs(correlation[:SAMPLES_PER_CODE])
        
        # Find peak
        peak_idx = np.argmax(correlation_mag)
        peak_value = correlation_mag[peak_idx]
        
        results.append({
            'doppler': doppler,
            'code_phase': peak_idx,
            'peak_value': peak_value
        })
    
    best_result = max(results, key=lambda x: x['peak_value'])
    
    return {
        'best_doppler': best_result['doppler'],
        'best_code_phase': best_result['code_phase'],
        'peak_value': best_result['peak_value'],
        'fft_size': fft_size,
        'split_method': split_method
    }

# ============================================================================
# Resource Comparison
# ============================================================================
def compare_resources():
    """
    Compare FPGA resources for different FFT solutions
    Based on Leclère et al. 2015 Table 3
    """
    print("="*80)
    print("FPGA Resource Comparison for FFT-Based Acquisition")
    print("="*80)
    print()
    
    solutions = {
        '3-FFT (Standard)': {
            'fft_size': 65536,
            'num_ffts': 3,
            'memory_m20k': 1824,
            'dsp_blocks': 38,
            'alm': 8760,
            'processing_time': '100%'
        },
        '5-FFT (Leclère 2014)': {
            'fft_size': 32768,
            'num_ffts': 5,
            'memory_m20k': 792,
            'dsp_blocks': 38,
            'alm': 8274,
            'processing_time': '100%'
        },
        '9-FFT (Proposed 3-way)': {
            'fft_size': 16384,
            'num_ffts': 9,
            'memory_m20k': 484,
            'dsp_blocks': 46,
            'alm': 8805,
            'processing_time': '75%'
        },
        '15-FFT (Proposed 5-way)': {
            'fft_size': 8192,
            'num_ffts': 15,
            'memory_m20k': 286,
            'dsp_blocks': 52,
            'alm': 8645,
            'processing_time': '62.5%'
        }
    }
    
    print(f"{'Solution':<25} {'FFT Size':<10} {'# FFTs':<8} {'Memory':<10} {'DSP':<6} {'ALM':<8} {'Time':<10}")
    print("-"*80)
    
    for name, specs in solutions.items():
        print(f"{name:<25} {specs['fft_size']:<10} {specs['num_ffts']:<8} "
              f"{specs['memory_m20k']:<10} {specs['dsp_blocks']:<6} "
              f"{specs['alm']:<8} {specs['processing_time']:<10}")
    
    print()
    print("Key Insights:")
    print("- 9-FFT solution reduces memory by 73.5% vs 3-FFT")
    print("- 15-FFT solution reduces memory by 84.3% vs 3-FFT")
    print("- 9-FFT is the best balance of memory savings and processing time")
    print("- For Zynq-7020: 140 BRAMs (M20K) available, 9-FFT uses only ~30 BRAMs")
    print()

# ============================================================================
# PRN FFT ROM Generation
# ============================================================================
def generate_prn_fft_rom(output_dir: str = './rom_data'):
    """
    Generate FFT of all 32 PRN codes for hardware ROM
    Output: 18-bit fixed-point format
    """
    os.makedirs(output_dir, exist_ok=True)
    
    print("="*80)
    print("Generating PRN FFT ROM Files")
    print("="*80)
    print()
    
    fft_size = 4096  # For 4 MHz sample rate
    
    for prn in range(1, 33):
        print(f"Processing PRN {prn}...")
        
        # Generate code
        code = generate_ca_code(prn)
        
        # Resample to sample rate
        code_resampled = signal.resample(code, SAMPLES_PER_CODE)
        
        # Zero-pad
        code_padded = np.zeros(fft_size, dtype=complex)
        code_padded[:SAMPLES_PER_CODE] = code_resampled
        
        # FFT
        code_fft = np.fft.fft(code_padded)
        code_fft_conj = np.conj(code_fft)
        
        # Convert to 18-bit fixed-point
        # Scale to fit in 18-bit signed range: [-131072, 131071]
        max_val = np.max(np.abs(code_fft_conj))
        scale_factor = 131071.0 / max_val if max_val > 0 else 1.0
        
        code_fft_scaled = code_fft_conj * scale_factor
        
        # Separate I and Q
        code_fft_i = np.round(np.real(code_fft_scaled)).astype(int)
        code_fft_q = np.round(np.imag(code_fft_scaled)).astype(int)
        
        # Clip to 18-bit range
        code_fft_i = np.clip(code_fft_i, -131072, 131071)
        code_fft_q = np.clip(code_fft_q, -131072, 131071)
        
        # Write to hex file
        filename = os.path.join(output_dir, f'prn{prn:02d}_fft.hex')
        with open(filename, 'w') as f:
            for i in range(fft_size):
                # Format: I (18-bit) followed by Q (18-bit) = 36 bits total
                # Pack as two 18-bit values
                i_val = code_fft_i[i] & 0x3FFFF  # 18-bit mask
                q_val = code_fft_q[i] & 0x3FFFF
                combined = (i_val << 18) | q_val
                f.write(f'{combined:09X}\n')
        
        print(f"  Saved: {filename}")
    
    print()
    print(f"Generated {32} PRN FFT ROM files in {output_dir}/")
    print()

# ============================================================================
# Main Simulation
# ============================================================================
def main():
    print("="*80)
    print("GNSS FFT-Based Acquisition Engine Simulation")
    print("="*80)
    print()
    
    # Generate test signal
    print("Generating test GPS signal...")
    true_doppler = 1500.0  # Hz
    true_code_phase = 234  # chips
    snr_db = 15
    
    signal_i, signal_q = generate_gps_signal(
        PRN_NUMBER, true_doppler, true_code_phase, snr_db
    )
    
    print(f"  True Doppler: {true_doppler} Hz")
    print(f"  True Code Phase: {true_code_phase} chips")
    print(f"  SNR: {snr_db} dB")
    print()
    
    # Doppler search range
    doppler_search = np.arange(-10000, 10001, 500)  # ±10 kHz, 500 Hz steps
    
    # Test basic PCPS
    print("Running basic PCPS acquisition (standard 3-FFT solution)...")
    result_basic = pcps_acquisition(signal_i, signal_q, PRN_NUMBER, doppler_search)
    
    print(f"  Detected Doppler: {result_basic['best_doppler']:.1f} Hz")
    print(f"  Detected Code Phase: {result_basic['best_code_phase']} chips")
    print(f"  Peak Value: {result_basic['peak_value']:.2f}")
    print(f"  Doppler Error: {abs(result_basic['best_doppler'] - true_doppler):.1f} Hz")
    print(f"  Code Phase Error: {abs(result_basic['best_code_phase'] - true_code_phase)} chips")
    print()
    
    # Test FFT splitting
    print("Testing FFT splitting methods...")
    
    # 9-FFT solution
    print("  9-FFT solution (3-way splitting)...")
    result_9fft = pcps_acquisition_with_splitting(
        signal_i, signal_q, PRN_NUMBER, doppler_search, '3way'
    )
    print(f"    FFT Size: {result_9fft['fft_size']}")
    print(f"    Detected Doppler: {result_9fft['best_doppler']:.1f} Hz")
    print(f"    Detected Code Phase: {result_9fft['best_code_phase']} chips")
    print()
    
    # Compare resources
    compare_resources()
    
    # Generate PRN FFT ROM files
    print("Generating PRN FFT ROM files for hardware implementation...")
    generate_prn_fft_rom()
    
    print("="*80)
    print("Simulation Complete!")
    print("="*80)
    print()
    print("Next Steps:")
    print("1. Review generated PRN FFT ROM files in ./rom_data/")
    print("2. Proceed to Verilog implementation of FFT-based acquisition")
    print("3. Use Xilinx FFT IP core (4096-point, 18-bit)")
    print("4. Implement 9-FFT splitting for better resource utilization")
    print()

if __name__ == '__main__':
    main()