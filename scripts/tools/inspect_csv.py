#!/usr/bin/env python3
"""Inspect the golden reference CSV file"""
import csv
import os
import numpy as np  # FIXED: Added this import

csv_file = "data/golden_files/golden_ref_data.csv"

if not os.path.exists(csv_file):
    print(f"❌ File not found: {csv_file}")
    print("Run: python3 scripts/tools/golden_reference_model.py first")
    exit(1)

print(f"📄 Inspecting: {csv_file}\n")

with open(csv_file, "r") as f:
    reader = csv.DictReader(f)
    rows = list(reader)

print(f"✓ Total epochs: {len(rows)}")
print(f"✓ Columns: {', '.join(rows[0].keys())}\n")

print("=" * 100)
print("FIRST 10 EPOCHS:")
print("=" * 100)
print(f"{'Epoch':<8} {'I_E':<10} {'Q_E':<10} {'I_P':<10} {'Q_P':<10} {'I_L':<10} {'Q_L':<10} {'Code Start':<12} {'Code End':<12}")
print("-" * 100)

for i, row in enumerate(rows[:10]):
    print(f"{row['epoch_ms']:<8} {row['I_E']:<10} {row['Q_E']:<10} "
          f"{row['I_P']:<10} {row['Q_P']:<10} {row['I_L']:<10} {row['Q_L']:<10} "
          f"{float(row['coff_chips_start']):<12.3f} {float(row['coff_chips_end']):<12.3f}")

print("\n" + "=" * 100)
print("LAST 5 EPOCHS:")
print("=" * 100)
print(f"{'Epoch':<8} {'I_E':<10} {'Q_E':<10} {'I_P':<10} {'Q_P':<10} {'I_L':<10} {'Q_L':<10} {'Code Start':<12} {'Code End':<12}")
print("-" * 100)

for row in rows[-5:]:
    print(f"{row['epoch_ms']:<8} {row['I_E']:<10} {row['Q_E']:<10} "
          f"{row['I_P']:<10} {row['Q_P']:<10} {row['I_L']:<10} {row['Q_L']:<10} "
          f"{float(row['coff_chips_start']):<12.3f} {float(row['coff_chips_end']):<12.3f}")

# Statistics
print("\n" + "=" * 100)
print("STATISTICS:")
print("=" * 100)

i_p_values = [int(row['I_P']) for row in rows]
q_p_values = [int(row['Q_P']) for row in rows]

print(f"I_P: min={min(i_p_values):7d}, max={max(i_p_values):7d}, "
      f"avg={sum(i_p_values)/len(i_p_values):7.1f}")
print(f"Q_P: min={min(q_p_values):7d}, max={max(q_p_values):7d}, "
      f"avg={sum(q_p_values)/len(q_p_values):7.1f}")

# Check code phase advancement
code_start = [float(row['coff_chips_start']) for row in rows]
code_end = [float(row['coff_chips_end']) for row in rows]
code_advance = [code_end[i] - code_start[i] for i in range(len(rows))]

print(f"\nCode phase advancement per epoch: {np.mean(code_advance):.3f} chips "
      f"(expected: 1023.0)")

print(f"\n✓ File inspection complete!")