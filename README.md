# Event Horizon GNSS

### *Pulling Navigation Out of the Void*

---

A Global Navigation Satellite System (GNSS) signal arrives at the Earth's surface at roughly **-130 to -160 dBm**. It is infinitely weaker than the ambient thermal noise floor of the room you are sitting in. To a standard receiver, these signals are indistinguishable from the chaotic, radioactive hiss of the universe. They are, for all intents and purposes, dead.

**Event Horizon GNSS** is a hybrid SoC-FPGA/ARM architecture designed to brute-force the thermal noise floor and pull those dead signals back to life.

Built as a heavily accelerated, custom-hardware fork/wrapper of the [`gnss-sdr`](https://github.com/gnss-sdr/gnss-sdr) project, this repository implements the most computationally violent parts of the signal chain—**Acquisition, Carrier Tracking, and Code Tracking**—as deterministic, massively parallel IP cores inside the FPGA's programmable logic fabric.

---

## The Architecture: The Singularity and The Observer

This system treats the SoC FPGA (like a Xilinx Zynq) not just as a chip, but as a physics engine:

### The Singularity (FPGA Programmable Logic)

Raw I/Q samples are blasted into the FPGA via **AXI-DMA**. Here, custom Verilog/VHDL/HLS IP cores act as a silicon crucible. Millions of parallel correlators crush the search space—thousands of Doppler bins and code phases—simultaneously. The FPGA doesn't "calculate" the signal; it applies so much parallel gravity that the signal has no choice but to collapse out of the noise floor and reveal itself.

### The Observer (ARM Processing System)

Once the FPGA has tracked the satellites and extracted the 50-bps telemetry, the data rate drops from millions of samples per second to a trickle. The ARM core safely observes the extracted data, running the Kalman filters, decoding the ephemeris, and solving the space-time geometry (PVT) to tell you exactly where you are in the universe.

---

## Why This Exists

Software-defined radios are elegant, but software is bound by the sequential limitations of a CPU. True GNSS processing requires bending millions of samples per millisecond. **Event Horizon GNSS** bridges the gap between theoretical software algorithms and the terrifying, raw, unyielding speed of hardware logic gates.

---

> **Welcome to the edge of the noise floor.**
