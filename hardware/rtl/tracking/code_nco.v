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
    
    always @(posedge clk) begin
        if (!rst_n) begin
            code_phase <= 0;
            chip_idx   <= 0;
        end else if (load) begin
            code_phase <= init_phase;
            chip_idx   <= init_phase[PHASE_BITS-1 -: CHIP_BITS];
        end else if (enable) begin
            code_phase <= code_phase + code_freq_word;
            // Wrap at 1023 chips (code length)
            if (code_phase >= (CODE_LENGTH << (PHASE_BITS - CHIP_BITS)))
                code_phase <= code_phase - (CODE_LENGTH << (PHASE_BITS - CHIP_BITS));
            chip_idx <= code_phase[PHASE_BITS-1 -: CHIP_BITS];
        end
    end

endmodule