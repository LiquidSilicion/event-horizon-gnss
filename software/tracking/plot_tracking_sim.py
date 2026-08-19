#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv('tracking_sim_log.csv')

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8))

ax1.plot(df['epoch_ms'], df['freq_error_hz'], 'b-', linewidth=2)
ax1.set_ylabel('Frequency Error (Hz)')
ax1.set_title('PLL Convergence')
ax1.grid(True)
ax1.axhline(y=0, color='r', linestyle='--')

ax2.plot(df['epoch_ms'], df['I_P'], 'g-', linewidth=1, alpha=0.7, label='I_P')
ax2.plot(df['epoch_ms'], df['Q_P'], 'r-', linewidth=1, alpha=0.7, label='Q_P')
ax2.set_xlabel('Time (ms)')
ax2.set_ylabel('Correlator Output')
ax2.set_title('Prompt Correlator Outputs')
ax2.legend()
ax2.grid(True)

plt.tight_layout()
plt.savefig('tracking_sim_results.png', dpi=150)
print("✓ Plot saved to: tracking_sim_results.png")
plt.show()