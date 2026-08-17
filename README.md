<p align="center">
  <img src="https://readme-typing-svg.demolab.com?font=Orbitron&weight=900&size=40&duration=3000&pause=1000&color=FF4500&center=true&vCenter=true&width=800&lines=EVENT+HORIZON+GNSS" alt="Event Horizon GNSS" />
</p>
---

<p align="center">
  <strong>A hybrid SoC-FPGA/ARM GNSS receiver — brute-forcing the thermal noise floor<br>to pull dead signals back to life.</strong>
</p>

<p align="center">
  <em>“Pulling navigation out of the void.”</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="license">
  <img src="https://img.shields.io/badge/core-Verilog_%C2%B7_ C%2B%2B-lightgrey.svg" alt="core">
  <img src="https://img.shields.io/badge/platforms-Zynq_%7C_ZynqMP-blue.svg" alt="platforms">
  <img src="https://img.shields.io/badge/GNSS-GPS_%C2%B7_Galileo_%C2%B7_BeiDou_%C2%B7_GLONASS-green.svg" alt="gnss">
  <img src="https://img.shields.io/badge/channels-12%2B_parallel-green.svg" alt="channels">
  <img src="https://img.shields.io/badge/lineage-gnss--sdr-orange.svg" alt="lineage">
</p>

---

A Global Navigation Satellite System (GNSS) signal arrives at the Earth's surface at roughly **-130 to -160 dBm**. It is infinitely weaker than the ambient thermal noise floor of the room you are sitting in. To a standard receiver, these signals are indistinguishable from the chaotic, radioactive hiss of the universe. They are, for all intents and purposes, dead.

**Event Horizon GNSS** takes raw I/Q samples — or a live front-end — and runs the **most computationally violent** parts of the receiver chain in hardware:

```
ingest (AXI-DMA) → acquire → track → decode nav message → solve PVT
```

…every millisecond, for every visible satellite at once. Built as a heavily accelerated, custom-hardware fork/wrapper of [`gnss-sdr`](https://github.com/gnss-sdr/gnss-sdr), it implements **Acquisition, Carrier Tracking, and Code Tracking** as deterministic, massively parallel IP cores inside the FPGA's programmable logic fabric. From one stream of raw samples it computes a fix with **two cooperating processors**:

| Processor | Stage | Implementation | Per-epoch output |
|-----------|-------|----------------|------------------|
| **FPGA** — *the Singularity* | Acquisition & tracking | Verilog / VHDL / HLS IP cores | `symbols.bin` |
| **ARM** — *the Observer* | Telemetry & PVT | C++ · gnss-sdr on Linux | `pvt.txt` |

**The Singularity** doesn't "calculate" the signal. Raw I/Q samples are blasted into the FPGA via **AXI-DMA**, where custom IP cores act as a silicon crucible: millions of parallel correlators crush the search space — thousands of Doppler bins and code phases — simultaneously, applying so much parallel gravity that the signal has no choice but to collapse out of the noise floor and reveal itself.

**The Observer** safely watches the aftermath. Once the FPGA has tracked the satellites and extracted the 50-bps telemetry, the data rate drops from millions of samples per second to a trickle; the ARM core runs the Kalman filters, decodes the ephemeris, and solves the space-time geometry (PVT) to tell you exactly where you are in the universe.

## Why This Exists

Software-defined radios are elegant, but software is bound by the sequential limitations of a CPU. True GNSS processing requires bending millions of samples per millisecond. **Event Horizon GNSS** bridges the gap between theoretical software algorithms and the terrifying, raw, unyielding speed of hardware logic gates.

---

> **Welcome to the edge of the noise floor.**