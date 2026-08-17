## Architecture

The system utilizes a hybrid processing model to optimize resource utilization:

*   **Programmable Logic (FPGA):** Handles high-throughput, highly parallel Digital Signal Processing (DSP). This includes raw sample ingestion via AXI-DMA, Digital Down-Conversion (DDC), and the massive parallel computations required for Signal Acquisition and Tracking (carrier/code NCOs and correlators).
*   **Processing System (ARM CPU):** Handles low-throughput, sequential tasks. Once the FPGA has tracked the signals and integrated the symbols, the ARM processor takes over to perform telemetry decoding, ephemeris parsing, and the final Position, Velocity, and Time (PVT) navigation solution.

## Key Features

*   **Custom FPGA IP Cores:** Verilog/VHDL/HLS implementations of baseband acquisition and tracking loops.
*   **Zero-Copy Data Transfer:** Utilizes AXI-DMA and AXI-Stream interfaces to move raw I/Q samples directly from the RF front-end into the FPGA fabric, bypassing CPU bottlenecks.
*   **gnss-sdr Integration:** Custom C++ GNU Radio blocks designed to interface seamlessly with the upstream `gnss-sdr` configuration files.
*   **Memory-Mapped Control:** AXI-Lite interfaces allow the ARM CPU to dynamically configure FPGA parameters (e.g., Doppler bins, code phases) in real-time.

## Directory Structure

event-horizon-gnss/
├── .github/                        # GitHub Actions for CI/CD (optional)
│   └── workflows/                  # YAML files for automated builds/linting
│
├── docs/                           # Project documentation
│   ├── architecture/               # Block diagrams, AXI interconnect maps
│   ├── registers/                  # AXI-Lite register maps for the FPGA IP cores
│   └── images/                     # Images used in this README
│
├── hardware/                       # FPGA Programmable Logic (PL)
│   ├── rtl/                        # Raw Verilog/VHDL source code
│   │   ├── acquisition/            # Acquisition IP (FFT, massive correlators)
│   │   ├── tracking/               # Tracking IP (NCOs, PLL, DLL loops)
│   │   ├── dma/                    # AXI DMA wrappers and signal source logic
│   │   └── top/                    # Top-level module and block design wrappers
│   ├── ip/                         # Pre-packaged or third-party IP cores
│   ├── constraints/                # XDC/SDC timing and pin constraint files
│   ├── sim/                        # Testbenches and simulation scripts (ModelSim/Vivado Sim)
│   └── scripts/                    # Vivado/Quartus Tcl scripts for hardware generation
│
├── software/                       # ARM Processing System (PS) & Linux
│   ├── device-tree/                # Device Tree Overlays (DTOs) for PL-PS interface
│   ├── drivers/                    # UIO drivers, DMA control libraries (C/C++)
│   ├── petalinux/                  # PetaLinux/Yocto configs (if building custom Linux)
│   └── gnss-sdr-blocks/            # C++ GNU Radio Out-of-Tree (OOT) modules
│       ├── gr-eventhorizon/        # The actual C++ GNU Radio wrapper blocks
│       └── cmake/                  # CMake configs for building the OOT module
│
├── scripts/                        # Global build and automation scripts
│   ├── build_hw.sh                 # Master script to build the FPGA bitstream
│   ├── build_sw.sh                 # Master script to build the software/DTB
│   └── deploy.sh                   # Script to push bitstream/software to the target board
│
├── data/                           # Test vectors and sample data
│   ├── iq_samples/                 # Small recorded RF captures for testing
│   └── golden_files/               # Expected outputs for RTL testbenches
│
├── .gitignore                      # Ignore build artifacts, .xpr, .log, etc.
├── LICENSE                         # GPL v3 (to match gnss-sdr)
└── README.md                       # Project description
