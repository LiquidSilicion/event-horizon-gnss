# Fixed-Point Precision Analysis for Scalar Tracking Engine

## Overview
This document defines the numerical precision requirements for the Event Horizon GNSS scalar tracking engine to support centimeter-level RTK accuracy, as mandated by the "Architecting Centimeter-Accuracy" framework.

## Carrier Phase NCO: 48-Bit Accumulator
-   **Requirement:** Resolve carrier phase to < 1 cm at L1 frequency (λ ≈ 19.0 cm).
-   **Resolution Calculation:** 
    -   48-bit accumulator provides $2^{-48}$ cycles per LSB.
    -   Phase resolution = $19.0 \text{ cm} \times 2^{-48} \approx 6.7 \times 10^{-14} \text{ cm}$.
-   **Justification:** While 32 bits ($\approx 4.4 \times 10^{-9}$ cm) is theoretically sufficient for static cm-level accuracy, 48 bits prevents phase truncation error accumulation over long tracking periods in high-dynamics environments (e.g., UAVs at 200 Hz update rates). This aligns with the framework's emphasis on robustness in dynamic platforms.

## Code Phase NCO: 32-Bit Accumulator
-   **Requirement:** Track code delay with sufficient resolution for pseudorange smoothing.
-   **Resolution Calculation:**
    -   32-bit accumulator provides $2^{-32}$ chips per LSB.
    -   Code resolution = $(293 \text{ m/chip}) \times 2^{-32} \approx 6.8 \times 10^{-5} \text{ mm}$.
-   **Justification:** 32 bits provides sub-millimeter code phase resolution, which is more than adequate for DLL tracking and carrier-smoothing algorithms. Using >32 bits would waste DSP/LUT resources without improving RTK fix quality.

## Correlator Accumulators: 32-Bit Signed
-   **Requirement:** Prevent overflow during 1 ms coherent integration.
-   **Dynamic Range Check:**
    -   Max input amplitude: $2^{15}-1 = 32767$ (16-bit signed).
    -   Samples per epoch: 4000 (at 4 MHz).
    -   Max accumulation: $32767 \times 4000 \approx 1.31 \times 10^8$.
    -   32-bit signed max: $2^{31}-1 \approx 2.15 \times 10^9$.
-   **Justification:** 32-bit accumulators provide ~16x headroom above max expected signal, preventing saturation even under strong signal conditions or extended integration.

## Sample Width: 16-Bit Signed I/Q
-   **Justification:** Balances ADC dynamic range (typical for AD9361) with FPGA DSP efficiency. 16-bit samples map directly to Xilinx DSP48 multipliers, enabling II=1 pipelined correlation without resource waste.

## Conclusion
The selected bit-widths (48/32/32/16) represent the optimal Pareto point for cm-level RTK accuracy on Zynq-7000 class FPGAs, satisfying the framework's DSE mandate for minimal precision that meets accuracy targets.