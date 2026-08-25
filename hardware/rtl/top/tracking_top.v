`timescale 1ns / 1ps

module tracking_top (
    input wire clk_100mhz,
    input wire rst_n,
    output wire led_dump_valid,
    output wire led_tracking_ok
);

    // ==========================================
    // Hardcoded Configuration
    // ==========================================
    wire [47:0] carrier_freq_word = 48'h00000000D6A0;
    wire [31:0] code_freq_word    = 32'h410624DD;
    wire [31:0] init_code_phase   = 32'd1466933248;
    wire [4:0]  prn_sel           = 5'd1;
    wire        channel_en        = 1'b1;

    // ==========================================
    // Internal Wires for DEBUG PROBES
    // ==========================================
    wire signed [31:0] I_E_int;
    wire signed [31:0] Q_E_int;
    wire signed [31:0] I_P_int;
    wire signed [31:0] Q_P_int;
    wire signed [31:0] I_L_int;
    wire signed [31:0] Q_L_int;
    wire dump_valid_int;
    wire [47:0] carrier_phase_int;

    // ==========================================
    // TEST STIMULUS GENERATOR
    // ==========================================
 reg [31:0] stim_cnt = 0;
    always @(posedge clk_100mhz) begin
        if (!rst_n)
            stim_cnt <= 0;
        else
            stim_cnt <= stim_cnt + 1;
    end
    
    wire signed [15:0] i_sample = stim_cnt[15:0];
    wire signed [15:0] q_sample = stim_cnt[31:16];
    wire sample_valid = 1'b1;

    // ==========================================
    // DUT Instantiation
    // ==========================================
    tracking_channel #(
        .CH_ID(0),
        .SAMPLE_BITS(16),
        .ACCUM_BITS(32),
        .SAMPLES_PER_MS(4000) 
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
        .I_E(I_E_int), .Q_E(Q_E_int),
        .I_P(I_P_int), .Q_P(Q_P_int),
        .I_L(I_L_int), .Q_L(Q_L_int),
        .dump_valid(dump_valid_int),
        .carrier_phase(carrier_phase_int)
    );


    // ==========================================
    // Physical Pin Mapping (unchanged)
    // ==========================================
    assign led_dump_valid = dump_valid_int;
    assign led_tracking_ok = ~I_P_int[31] & I_P_int[30]; 

endmodule