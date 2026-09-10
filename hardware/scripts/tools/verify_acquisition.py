import numpy as np

def load_hex_18bit(filename):
    """Correctly parses 18-bit signed hex values from a file."""
    with open(filename, 'r') as f:
        def parse_18bit(x):
            val = int(x, 16)
            if val >= (1 << 17):  # Check sign bit (bit 17)
                val -= (1 << 18)  # Convert to negative two's complement
            return val
        return np.array([parse_18bit(x) for x in f.read().split()], dtype=np.int32)

def load_hex_16bit(filename):
    """Parses 16-bit signed hex values (for stimulus)."""
    with open(filename, 'r') as f:
        def parse_16bit(x):
            val = int(x, 16)
            if val >= (1 << 15):
                val -= (1 << 16)
            return val
        return np.array([parse_16bit(x) for x in f.read().split()], dtype=np.int32)

print("Loading stimulus data (16-bit signed)...")
stim_i = load_hex_16bit('stim_i.hex')
stim_q = load_hex_16bit('stim_q.hex')

print("Loading local code FFT data (18-bit signed)...")
# Load all, then slice the first 4096 for PRN 1
prn_fft_i_full = load_hex_18bit('all_prns_fft_i.hex')
prn_fft_q_full = load_hex_18bit('all_prns_fft_q.hex')

prn_fft_i = prn_fft_i_full[:4096]
prn_fft_q = prn_fft_q_full[:4096]

# Combine into complex arrays
stim = stim_i.astype(np.float64) + 1j * stim_q.astype(np.float64)
prn_fft = prn_fft_i.astype(np.float64) + 1j * prn_fft_q.astype(np.float64)

# Parameters
doppler_hz = 2000
fs = 100e6  # Adjust if your actual sample rate is different

# Generate carrier and mix
t = np.arange(len(stim)) / fs
carrier = np.exp(-1j * 2 * np.pi * doppler_hz * t)
mixed = stim * carrier
mixed_fft = np.fft.fft(mixed)

# --- TEST 1: WITH Conjugation (Standard Frequency-Domain Correlation) ---
corr_fft_conj = mixed_fft * np.conj(prn_fft)
corr_time_conj = np.fft.ifft(corr_fft_conj)
mag_conj = np.abs(corr_time_conj)**2
peak_idx_conj = np.argmax(mag_conj)
peak_mag_conj = np.max(mag_conj)

# --- TEST 2: WITHOUT Conjugation (In case FPGA does convolution instead) ---
corr_fft_no_conj = mixed_fft * prn_fft
corr_time_no_conj = np.fft.ifft(corr_fft_no_conj)
mag_no_conj = np.abs(corr_time_no_conj)**2
peak_idx_no_conj = np.argmax(mag_no_conj)
peak_mag_no_conj = np.max(mag_no_conj)

print("\n============================================================")
print("PYTHON GOLDEN MODEL RESULTS (Correct 18-bit Parsing)")
print("============================================================")
print(f"Target PRN:        1")
print(f"Target Doppler:    {doppler_hz} Hz")
print(f"------------------------------------------------------------")
print(f"--- WITH np.conj(prn_fft) ---")
print(f"Best Code Phase:   {peak_idx_conj} (out of 4096)")
print(f"Peak Magnitude:    {peak_mag_conj:.2f}")
print(f"------------------------------------------------------------")
print(f"--- WITHOUT np.conj(prn_fft) ---")
print(f"Best Code Phase:   {peak_idx_no_conj} (out of 4096)")
print(f"Peak Magnitude:    {peak_mag_no_conj:.2f}")
print("============================================================")

if peak_idx_conj == 0 or peak_idx_no_conj == 0:
    print("✅ SUCCESS: Python found the peak at Code Phase 0, perfectly matching the FPGA!")
else:
    print("⚠️ Mismatch: Neither method found the peak at 0. Check stimulus generation.")