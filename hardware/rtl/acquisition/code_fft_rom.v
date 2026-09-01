`timescale 1ns / 1ps
//============================================================================
// code_fft_rom.v
// Stores pre-computed complex-conjugated FFT of all 32 GPS L1 C/A PRN codes.
// Data is loaded from two master hex files (I and Q components).
// Infers Block RAM (BRAM) for efficient FPGA resource utilization.
//============================================================================
module code_fft_rom #(
    parameter FFT_SIZE   = 4096,
    parameter DATA_WIDTH = 18,
    parameter NUM_PRNS   = 32,
    parameter ADDR_WIDTH = 12    // log2(FFT_SIZE)
)(
    input  wire                        clk,
    input  wire [4:0]                  prn_sel,     // PRN number (1 to 32)
    input  wire [ADDR_WIDTH-1:0]       bin_idx,     // FFT bin index (0 to 4095)
    output reg  signed [DATA_WIDTH-1:0] fft_i_out,  // Real (I) component
    output reg  signed [DATA_WIDTH-1:0] fft_q_out   // Imaginary (Q) component
);

    // =========================================================================
    // Total ROM depth = 32 PRNs * 4096 bins = 131,072 words
    // =========================================================================
    localparam ROM_DEPTH = NUM_PRNS * FFT_SIZE;

    // =========================================================================
    // BRAM Arrays for I and Q components
    // The (* ram_style = "block" *) attribute forces Vivado to infer BRAM
    // instead of wasting thousands of LUTs on distributed RAM.
    // =========================================================================
    (* ram_style = "block" *) 
    reg signed [DATA_WIDTH-1:0] prn_fft_i [0:ROM_DEPTH-1];
    
    (* ram_style = "block" *) 
    reg signed [DATA_WIDTH-1:0] prn_fft_q [0:ROM_DEPTH-1];

    // =========================================================================
    // Flat 1D Address Calculation
    // Address = ((prn_sel - 1) * FFT_SIZE) + bin_idx
    // Using 17-bit wire to hold the result (max = 32*4096 - 1 = 131071)
    // =========================================================================
    wire [16:0] flat_addr = ((prn_sel - 5'd1) * FFT_SIZE) + bin_idx;

    // =========================================================================
    // Load ROM data from hex files at simulation/elaboration time
    // IMPORTANT: Use ABSOLUTE paths to ensure XSim and Synthesis can find them.
    // Update these paths to match your actual directory structure.
    // =========================================================================
    initial begin
        $readmemh("all_prns_fft_i.hex", prn_fft_i);
        $readmemh("all_prns_fft_q.hex", prn_fft_q);
        $display("✅ CODE FFT ROM LOADED SUCCESSFULLY FROM MASTER FILES");
        $display("   - I component: all_prns_fft_i.hex");
        $display("   - Q component: all_prns_fft_q.hex");
        $display("   - Total entries: %0d (32 PRNs x 4096 bins)", ROM_DEPTH);
    end

    // =========================================================================
    // Synchronous Read (Required for BRAM Inference)
    // The output is registered on the clock edge, which is the standard
    // pattern Vivado recognizes for inferring Block RAM with output registers.
    // =========================================================================
    always @(posedge clk) begin
        fft_i_out <= prn_fft_i[flat_addr];
        fft_q_out <= prn_fft_q[flat_addr];
    end

endmodule