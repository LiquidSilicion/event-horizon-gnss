`timescale 1ns / 1ps
//============================================================================
// AXI4-Lite Wrapper for N Tracking Channels
//
// Register map (per channel, stride = 0x100 bytes):
//   +0x00: carrier_freq_word[31:0]   (W)
//   +0x04: carrier_freq_word[47:32]  (W)
//   +0x08: code_freq_word            (W)
//   +0x0C: init_code_phase           (W)
//   +0x10: prn_sel [4:0] | channel_en [8]  (W)
//   +0x20: I_E  (R)
//   +0x24: Q_E  (R)
//   +0x28: I_P  (R)
//   +0x2C: Q_P  (R)
//   +0x30: I_L  (R)
//   +0x34: Q_L  (R)
//   +0x38: dump_valid [0], epoch_count [31:16]  (R)
//============================================================================

module axi_scalar_tracker #(
    parameter N_CHANNELS  = 4,
    parameter SAMPLE_BITS = 16,
    parameter ACCUM_BITS  = 32,
    parameter PHASE_BITS  = 48,
    parameter CODE_BITS   = 32
)(
    input  wire                          aclk,
    input  wire                          aresetn,
    
    // AXI4-Lite slave interface (simplified — use Vivado IP Integrator)
    // ... (standard AXI signals)
    
    // RF sample input (shared across channels)
    input  wire signed [SAMPLE_BITS-1:0] i_in,
    input  wire signed [SAMPLE_BITS-1:0] q_in,
    input  wire                          sample_valid
);

    // Per-channel registers
    reg [PHASE_BITS-1:0] carr_freq [0:N_CHANNELS-1];
    reg [CODE_BITS-1:0]  code_freq [0:N_CHANNELS-1];
    reg [CODE_BITS-1:0]  init_code [0:N_CHANNELS-1];
    reg [4:0]            prn_sel   [0:N_CHANNELS-1];
    reg                  ch_en     [0:N_CHANNELS-1];
    
    // Latched I&D dumps
    reg signed [ACCUM_BITS-1:0] I_E_lat [0:N_CHANNELS-1];
    reg signed [ACCUM_BITS-1:0] Q_E_lat [0:N_CHANNELS-1];
    reg signed [ACCUM_BITS-1:0] I_P_lat [0:N_CHANNELS-1];
    reg signed [ACCUM_BITS-1:0] Q_P_lat [0:N_CHANNELS-1];
    reg signed [ACCUM_BITS-1:0] I_L_lat [0:N_CHANNELS-1];
    reg signed [ACCUM_BITS-1:0] Q_L_lat [0:N_CHANNELS-1];
    reg                         dump_v    [0:N_CHANNELS-1];
    reg [15:0]                  epoch_cnt [0:N_CHANNELS-1];
    
    // Instantiate N tracking channels
    genvar ch;
    generate
        for (ch = 0; ch < N_CHANNELS; ch = ch + 1) begin : gen_ch
            wire signed [ACCUM_BITS-1:0] I_E_out, Q_E_out, I_P_out, Q_P_out, I_L_out, Q_L_out;
            wire dump_valid_out;
            
            tracking_channel #(
                .CH_ID(ch),
                .SAMPLE_BITS(SAMPLE_BITS),
                .ACCUM_BITS(ACCUM_BITS),
                .PHASE_BITS(PHASE_BITS),
                .CODE_BITS(CODE_BITS)
            ) u_ch (
                .clk(aclk), .rst_n(aresetn), .enable(sample_valid),
                .carrier_freq_word(carr_freq[ch]),
                .code_freq_word(code_freq[ch]),
                .init_code_phase(init_code[ch]),
                .prn_sel(prn_sel[ch]),
                .channel_en(ch_en[ch]),
                .i_in(i_in), .q_in(q_in),
                .I_E(I_E_out), .Q_E(Q_E_out),
                .I_P(I_P_out), .Q_P(Q_P_out),
                .I_L(I_L_out), .Q_L(Q_L_out),
                .dump_valid(dump_valid_out),
                .carrier_phase()
            );
            
            // Latch dumps when valid
            always @(posedge aclk) begin
                if (!aresetn) begin
                    dump_v[ch] <= 0;
                    epoch_cnt[ch] <= 0;
                end else if (dump_valid_out) begin
                    I_E_lat[ch] <= I_E_out;
                    Q_E_lat[ch] <= Q_E_out;
                    I_P_lat[ch] <= I_P_out;
                    Q_P_lat[ch] <= Q_P_out;
                    I_L_lat[ch] <= I_L_out;
                    Q_L_lat[ch] <= Q_L_out;
                    dump_v[ch] <= 1'b1;
                    epoch_cnt[ch] <= epoch_cnt[ch] + 1;
                end else begin
                    dump_v[ch] <= 1'b0;
                end
            end
        end
    endgenerate
    
    // AXI read/write logic would go here
    // Use Vivado IP Integrator to generate this automatically

endmodule