# generate_lut.py
with open("reciprocal_lut.mem", "w") as f:
    for i in range(256):
        if i == 0:
            val = 0xFFFF  # Safe fallback for invalid/flat peaks
        else:
            # Store (1.0 / (2.0 * i)) * 65536, capped at 16 bits
            val = int(round((1.0 / (2.0 * i)) * 65536))
            if val > 0xFFFF: 
                val = 0xFFFF
        
        # Write as 4-digit hexadecimal
        f.write(f"{val:04X}\n")

print("Generated reciprocal_lut.mem successfully!")