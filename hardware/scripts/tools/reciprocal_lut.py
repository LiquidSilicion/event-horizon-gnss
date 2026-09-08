# generate_lut.py
with open("reciprocal_lut.mem", "w") as f:
    for i in range(128, 256):
        # Calculate reciprocal scaled by 65536 (2^16)
        val = int(round((1.0 / (2.0 * i)) * 65536))
        # Write as 4-digit hexadecimal
        f.write(f"{val:04X}\n")

print("✅ Generated 128-entry reciprocal_lut.mem successfully!")