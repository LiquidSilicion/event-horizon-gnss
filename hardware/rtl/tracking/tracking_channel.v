`timescale 1ns / 1ps
//============================================================================
// Top-Level Tracking Channel: Wires carrier NCO + mixer + code NCO + correlator
//
// This is one "lane" of the scalar correlator bank.
// Instantiate N of these for N channels.
//============================================================================

module tracking_channel #(
    parameter CH_ID          = 0,
    parameter PHASE_BITS     = 48,
    parameter CODE_BITS      = 32,
    parameter SAMPLE_BITS    = 16,
    parameter ACCUM_BITS     = 32,
    parameter SAMPLES_PER_MS = 4000,
    parameter SINCOS_BITS    = 18
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    enable,
    
    // Configuration from ARM (via AXI-Lite)
    input  wire [PHASE_BITS-1:0]   carrier_freq_word,
    input  wire [CODE_BITS-1:0]    code_freq_word,
    input  wire [CODE_BITS-1:0]    init_code_phase,
    input  wire [4:0]              prn_sel,
    input  wire                    channel_en,
    
    // RF sample input
    input  wire signed [SAMPLE_BITS-1:0] i_in,
    input  wire signed [SAMPLE_BITS-1:0] q_in,
    
    // I&D dump outputs (to AXI)
    output wire signed [ACCUM_BITS-1:0] I_E, Q_E,
    output wire signed [ACCUM_BITS-1:0] I_P, Q_P,
    output wire signed [ACCUM_BITS-1:0] I_L, Q_L,
    output wire                         dump_valid,
    
    // Carrier phase output (for ARM to read)
    output wire [PHASE_BITS-1:0]   carrier_phase
);

    // ---- Carrier path ----
    wire signed [SINCOS_BITS-1:0] cos_val, sin_val;
    wire [PHASE_BITS-1:0] carr_phase;
    
    carrier_nco #(
        .PHASE_BITS(PHASE_BITS),
        .OUTPUT_BITS(SINCOS_BITS)
    ) u_carr_nco (
        .clk(clk), .rst_n(rst_n), .enable(enable && channel_en),
        .freq_word(carrier_freq_word),
        .cos_out(cos_val), .sin_out(sin_val),
        .phase(carr_phase)
    );
    
    assign carrier_phase = carr_phase;
    
    wire signed [SINCOS_BITS-1:0] i_wiped, q_wiped;
    carrier_mixer #(
        .SAMPLE_BITS(SAMPLE_BITS),
        .SINCOS_BITS(SINCOS_BITS),
        .OUTPUT_BITS(SINCOS_BITS)
    ) u_mixer (
        .clk(clk), .rst_n(rst_n),
        .i_in(i_in), .q_in(q_in),
        .cos_val(cos_val), .sin_val(sin_val),
        .i_out(i_wiped), .q_out(q_wiped)
    );
    
    // ---- Code path ----
    wire [CODE_BITS-1:0] code_phase;
    wire [9:0] chip_idx_p;
    
    code_nco #(
        .PHASE_BITS(CODE_BITS),
        .CHIP_BITS(10)
    ) u_code_nco (
        .clk(clk), .rst_n(rst_n),
        .enable(enable && channel_en),
        .code_freq_word(code_freq_word),
        .init_phase(init_code_phase),
        .load(1'b0),
        .code_phase(code_phase),
        .chip_idx(chip_idx_p)
    );
    
    // Early/Late chip indices (±0.5 chips = ±512 in 10-bit fractional)
    wire [9:0] chip_idx_e = chip_idx_p - 10'd512;
    wire [9:0] chip_idx_l = chip_idx_p + 10'd512;
    
    wire code_e, code_p, code_l;
    ca_code_gen u_code_p (.clk(clk), .prn_sel(prn_sel), .chip_idx(chip_idx_p), .code_chip(code_p));
    ca_code_gen u_code_e (.clk(clk), .prn_sel(prn_sel), .chip_idx(chip_idx_e), .code_chip(code_e));
    ca_code_gen u_code_l (.clk(clk), .prn_sel(prn_sel), .chip_idx(chip_idx_l), .code_chip(code_l));
    
    // Epoch tick: fires once per ms (when code phase wraps 1023 chips)
    // Simplified: use a sample counter (4000 samples at 4 MHz = 1 ms)
    reg [11:0] ms_cnt;
    reg epoch_tick;
    always @(posedge clk) begin
        if (!rst_n) begin
            ms_cnt <= 0;
            epoch_tick <= 0;
        end else if (enable && channel_en) begin
            epoch_tick <= 0;
            if (ms_cnt == SAMPLES_PER_MS - 1) begin
                ms_cnt <= 0;
                epoch_tick <= 1;
            end else begin
                ms_cnt <= ms_cnt + 1;
            end
        end
    end
    
    // ---- Correlator ----
    correlator #(
        .SAMPLE_BITS(SAMPLE_BITS),
        .ACCUM_BITS(ACCUM_BITS),
        .SAMPLES_PER_MS(SAMPLES_PER_MS)
    ) u_corr (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .i_wiped(i_wiped[SAMPLE_BITS-1:0]),  // Truncate to sample width
        .q_wiped(q_wiped[SAMPLE_BITS-1:0]),
        .code_e(code_e), .code_p(code_p), .code_l(code_l),
        .epoch_tick(epoch_tick),
        .I_E(I_E), .Q_E(Q_E),
        .I_P(I_P), .Q_P(Q_P),
        .I_L(I_L), .Q_L(Q_L),
        .dump_valid(dump_valid)
    );

endmodule