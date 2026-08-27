`timescale 1ns / 1ps
//============================================================================
// Synthetic GPS L1 Signal Generator
//============================================================================
module gps_signal_gen #(
    parameter SAMPLE_RATE = 4000000,
    parameter PRN_SEL     = 1,
    parameter CODE_PHASE_INIT = 0
)(
    input  wire              clk,
    input  wire              rst_n,
    output wire              sample_valid,
    output reg signed [15:0] i_out,
    output reg signed [15:0] q_out
);

    // 1. Generate 4 MHz sample_valid pulse from 100 MHz clock
    reg [4:0] clk_div = 0;
    always @(posedge clk) begin
        if (!rst_n) clk_div <= 0;
        else if (clk_div == 24) clk_div <= 0;
        else clk_div <= clk_div + 1;
    end
    assign sample_valid = (clk_div == 24);

    // 2. CRITICAL FIX: Use the exact same Code NCO and CA Code Gen as the receiver!
    wire [31:0] gen_code_phase;
    wire [9:0]  gen_chip_idx;
    wire        gen_ca_chip;
    
    code_nco #(
        .PHASE_BITS(32),
        .CHIP_BITS(10)
    ) u_gen_code_nco (
        .clk(clk),
        .rst_n(rst_n),
        .enable(sample_valid),
        .code_freq_word(32'h4178D4FD), // 1.023 MHz @ 4 MHz sample rate
        .init_phase(32'd0),
        .load(1'b0),
        .code_phase(gen_code_phase),
        .chip_idx(gen_chip_idx)
    );
    
    ca_code_gen u_gen_ca_code (
        .clk(clk),
        .prn_sel(PRN_SEL),
        .chip_idx(gen_chip_idx),
        .code_chip(gen_ca_chip)
    );

    // 3. Carrier NCO (1 kHz Doppler @ 4 MHz sample rate)
    localparam [47:0] CARR_FREQ_WORD = 48'h000010624DD2F1;
    
    reg [47:0] carrier_phase = 0;
    wire [11:0] rom_idx = carrier_phase[47:36];
    
    reg signed [17:0] sin_val, cos_val;
    reg signed [17:0] sin_table [0:4095];
    reg signed [17:0] cos_table [0:4095];
    
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            sin_table[i] = $rtoi($sin(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
            cos_table[i] = $rtoi($cos(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            carrier_phase <= 0;
            sin_val <= 0;
            cos_val <= 0;
            i_out <= 0;
            q_out <= 0;
        end else if (sample_valid) begin
            carrier_phase <= carrier_phase + CARR_FREQ_WORD;
            sin_val <= sin_table[rom_idx];
            cos_val <= cos_table[rom_idx];
            
            // BPSK Modulation: chip=1 -> +1, chip=0 -> -1
            if (gen_ca_chip) begin
                i_out <= cos_val >>> 1;
                q_out <= sin_val >>> 1;
            end else begin
                i_out <= -(cos_val >>> 1);
                q_out <= -(sin_val >>> 1);
            end
        end
    end
endmodule