`timescale 1ns / 1ps

// Carrier NCO: 48-bit phase accumulator + 18-bit signed sine/cosine output
// Output range: [-131071, +131071] (18-bit signed, ~full scale of 2^17)
// This matches the Python model's np.cos/sin scaled to 18-bit.


module carrier_nco #(
    parameter PHASE_BITS=48,
    parameter OUTPUT_BITS =18
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire [PHASE_BITS-1:0] freq_word,
    output reg signed [OUTPUT_BITS -1:0] cos_out,
    output reg signed [OUTPUT_BITS -1:0] sin_out,
    output reg [PHASE_BITS-1:0] phase);

// Phase accumulator
    reg [PHASE_BITS-1:0] phase_acc = 0;
    
    // Top 12 bits of phase index into the sincos ROM (4096 entries)
    wire [11:0] rom_idx = phase_acc[PHASE_BITS-1 -: 12];
    
    // Sine/cosine lookup ROM (quarter-wave symmetry would save BRAM,
    // but for clarity we use a full table here — replace with Xilinx ROM IP)
    // For synthesis, use $readmemh to load from a .coe file, or use Xilinx
    // Distributed Memory Generator IP.
    
    // Simplified: use a LUT-based approximation for simulation.
    // For real hardware, replace with a proper ROM IP.
    reg signed [OUTPUT_BITS-1:0] sin_table [0:4095];
    reg signed [OUTPUT_BITS-1:0] cos_table [0:4095];
    
    // Initialize ROM with sine/cosine values (scaled to 18-bit signed)
    // In practice, generate this with a Python script and $readmemh
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            // phase = i * 2*pi / 4096
            // sin/cos scaled to +/- 131071 (17 bits magnitude)
            sin_table[i] = $rtoi($sin(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
            cos_table[i] = $rtoi($cos(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
        end
    end
    
    // Phase accumulator + ROM read (2-cycle pipeline)
    always @(posedge clk) begin
        if (!rst_n) begin
            phase_acc <= 0;
            cos_out   <= 0;
            sin_out   <= 0;
            phase     <= 0;
        end else if (enable) begin
            phase_acc <= phase_acc + freq_word;
            cos_out   <= cos_table[rom_idx];
            sin_out   <= sin_table[rom_idx];
            phase     <= phase_acc;
        end
    end
endmodule