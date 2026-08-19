`timescale 1ns / 1ps

module tb_tracking_channel;

    // Parameters
    parameter FS = 4_000_000;
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter SAMPLES_PER_MS = 4000;
    
    // Signals
    reg clk, rst_n;
    reg signed [15:0] i_in, q_in;
    reg sample_valid;
    
    reg [47:0] carrier_freq_word;
    reg [31:0] code_freq_word;
    reg [31:0] init_code_phase;
    reg [4:0]  prn_sel;
    reg        channel_en;
    
    wire signed [31:0] I_E, Q_E, I_P, Q_P, I_L, Q_L;
    wire dump_valid;
    
    // DUT Instantiation
    tracking_channel #(
        .CH_ID(0),
        .SAMPLE_BITS(16),
        .ACCUM_BITS(32),
        .SAMPLES_PER_MS(SAMPLES_PER_MS)
    ) dut (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .carrier_freq_word(carrier_freq_word),
        .code_freq_word(code_freq_word),
        .init_code_phase(init_code_phase),
        .prn_sel(prn_sel),
        .channel_en(channel_en),
        .i_in(i_in), .q_in(q_in),
        .I_E(I_E), .Q_E(Q_E),
        .I_P(I_P), .Q_P(Q_P),
        .I_L(I_L), .Q_L(Q_L),
        .dump_valid(dump_valid),
        .carrier_phase()
    );
    
    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Testbench Variables (Module Level for Verilog-2001)
    integer epoch;
    integer sample_cnt;
    
    // Stimulus Generators (Integer NCOs)
    reg [47:0] stim_carr_phase;
    reg [31:0] stim_code_phase;
    reg        stim_code_chip;
    reg signed [15:0] stim_i, stim_q;
    reg [1:0]  carr_quad; // Moved to module level
    
    // Constants for Stimulus
    // Real Doppler: 1250 Hz. Phase Inc = (1250 / 4e6) * 2^48
    parameter STIM_CARR_INC = 48'h00000000D5E5; 
    // Code Rate: 1.023 MHz. Phase Inc = (1.023e6 / 4e6) * 2^32
    parameter STIM_CODE_INC = 32'h410624DD; 
    
    // Simple PRN 1 Code Lookup (Alternating for TB verification)
    function reg get_prn1_chip;
        input [9:0] idx;
        begin
            if (idx[0]) get_prn1_chip = 1;
            else get_prn1_chip = -1;
        end
    endfunction
    
    initial begin
        rst_n = 0;
        sample_valid = 0;
        channel_en = 1;
        prn_sel = 1;
        
        // Set DUT NCOs to Local Doppler (1255 Hz)
        carrier_freq_word = 48'h00000000D6A0; 
        code_freq_word = 32'h410624DD;
        init_code_phase = 347 << 22; 
        
        #100;
        rst_n = 1;
        
        // Run for 10 epochs
        for (epoch = 0; epoch < 10; epoch = epoch + 1) begin
            // Reset stimulus phases
            stim_carr_phase = 0;
            stim_code_phase = 347 << 22; 
            
            for (sample_cnt = 0; sample_cnt < SAMPLES_PER_MS; sample_cnt = sample_cnt + 1) begin
                // 1. Generate Code Chip
                stim_code_chip = get_prn1_chip(stim_code_phase[31:22]);
                
                // 2. Generate Carrier (Quadrant-based Sine/Cosine Approximation)
                // Uses top 2 bits of phase to determine quadrant
                carr_quad = stim_carr_phase[47:46];
                
                // Approximate sin/cos values (scaled to 16-bit signed)
                // 0.707 * 32767 ≈ 23170
                if (carr_quad == 2'b00 || carr_quad == 2'b11) begin
                    stim_q = 23170; // Sin positive
                end else begin
                    stim_q = -23170; // Sin negative
                end
                
                if (carr_quad == 2'b00 || carr_quad == 2'b01) begin
                    stim_i = 23170; // Cos positive
                end else begin
                    stim_i = -23170; // Cos negative
                end
                
                // 3. Mix Code and Carrier
                i_in = stim_i * stim_code_chip;
                q_in = stim_q * stim_code_chip;
                
                // Advance Stimulus Phases
                stim_carr_phase = stim_carr_phase + STIM_CARR_INC;
                stim_code_phase = stim_code_phase + STIM_CODE_INC;
                
                sample_valid = 1;
                @(posedge clk);
                sample_valid = 0;
                @(posedge clk);
            end
            
            wait (dump_valid);
            @(posedge clk);
            
            // Verification: If locked, I_P should be large and positive
            if (I_P > 1000000) begin
                $display("Epoch %0d: PASS (I_P=%0d)", epoch, I_P);
            end else begin
                $display("Epoch %0d: FAIL (I_P=%0d)", epoch, I_P);
            end
        end
        
        $finish;
    end

endmodule