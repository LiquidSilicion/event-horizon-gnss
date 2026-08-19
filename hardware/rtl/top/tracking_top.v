`timescale 1ns / 1ps

module tracking_top (
    input wire clk_100mhz,      // 100 MHz system clock
    input wire rst_n,           // Active-low reset
    input wire signed [15:0] i_sample, // Raw I sample from ADC/DMA
    input wire signed [15:0] q_sample, // Raw Q sample from ADC/DMA
    input wire sample_valid,    // High when samples are valid
    
    // Configuration Inputs (Hardcoded or from switches for now)
    input wire [47:0] carrier_freq_word,
    input wire [31:0] code_freq_word,
    input wire [31:0] init_code_phase,
    input wire [4:0]  prn_sel,
    input wire        channel_en,
    
    // Output Measurements (To be read by ILA or simple ARM GPIO)
    output wire signed [31:0] I_E_out, Q_E_out,
    output wire signed [31:0] I_P_out, Q_P_out,
    output wire signed [31:0] I_L_out, Q_L_out,
    output wire               dump_valid_out
);

    tracking_channel #(
        .CH_ID(0),
        .SAMPLE_BITS(16),
        .ACCUM_BITS(32),
        .SAMPLES_PER_MS(4000) // Assuming 4MHz sample rate for now
    ) u_tracking_ch (
        .clk(clk_100mhz),
        .rst_n(rst_n),
        .enable(sample_valid),
        .carrier_freq_word(carrier_freq_word),
        .code_freq_word(code_freq_word),
        .init_code_phase(init_code_phase),
        .prn_sel(prn_sel),
        .channel_en(channel_en),
        .i_in(i_sample),
        .q_in(q_sample),
        .I_E(I_E_out), .Q_E(Q_E_out),
        .I_P(I_P_out), .Q_P(Q_P_out),
        .I_L(I_L_out), .Q_L(Q_L_out),
        .dump_valid(dump_valid_out),
        .carrier_phase()
    );

endmodule