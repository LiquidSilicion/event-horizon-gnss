`timescale 1ns / 1ps
// Code phase NCO: tracks the fractional code phase in chips
// 32-bit accumulator, top bits select the chip index
module code_nco #(
    parameter PHASE_BITS = 32,
    parameter CHIP_BITS  = 10     // 1023 chips -> 10 bits
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  enable,
    input  wire [PHASE_BITS-1:0] code_freq_word,  // chips per sample (scaled)
    input  wire [PHASE_BITS-1:0] init_phase,      // Load on start
    input  wire                  load,
    output reg  [PHASE_BITS-1:0] code_phase,
    output reg  [CHIP_BITS-1:0]  chip_idx
);

    localparam CODE_LENGTH = 1023;
    // 1023 << 22 = 32'hFFC00000
    localparam WRAP_THRESHOLD = CODE_LENGTH << (PHASE_BITS - CHIP_BITS); 

    // ✅ CRITICAL FIX: Use a 33-bit variable to safely catch 32-bit overflow
    reg [PHASE_BITS:0] next_phase;

    always @(posedge clk) begin
        if (!rst_n) begin
            code_phase <= 0;
            chip_idx   <= 0;
        end else if (load) begin
            code_phase <= init_phase;
            chip_idx   <= init_phase[PHASE_BITS-1 -: CHIP_BITS];
        end else if (enable) begin
            // 1. Calculate next phase with an extra bit to catch overflow
            next_phase = code_phase + code_freq_word;
            
            // 2. If the NEW phase exceeds the 1023-chip boundary, wrap it around
            if (next_phase >= WRAP_THRESHOLD) begin
                next_phase = next_phase - WRAP_THRESHOLD;
            end
            
            // 3. Update outputs with the correctly wrapped phase
            code_phase <= next_phase[PHASE_BITS-1:0];
            chip_idx   <= next_phase[PHASE_BITS-1 -: CHIP_BITS];
        end
    end

endmodule