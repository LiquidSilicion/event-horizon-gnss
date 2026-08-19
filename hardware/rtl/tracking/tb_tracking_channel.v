`timescale 1ns / 1ps

module tb_tracking_channel;

    localparam FS = 4_000_000;
    localparam CLK_PERIOD = 10;  // 100 MHz
    localparam SAMPLES_PER_MS = 4000;
    
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
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Compute NCO frequency word from Doppler
    function [47:0] doppler_to_freq_word;
        input real doppler_hz;
        begin
            doppler_to_freq_word = $rtoi((doppler_hz / FS) * (2.0**48));
        end
    endfunction
    
    // Compute code freq word
    function [31:0] code_rate_to_freq_word;
        begin
            code_rate_to_freq_word = $rtoi((1_023_000.0 / FS) * (2.0**32));
        end
    endfunction
    
    integer fd_if, fd_truth;
    integer i_if, q_if;
    integer truth_I_E, truth_Q_E, truth_I_P, truth_Q_P, truth_I_L, truth_Q_L;
    integer epoch;
    integer err_I_P, err_Q_P;
    integer max_err = 0;
    
    initial begin
        rst_n = 0;
        sample_valid = 0;
        channel_en = 1;
        prn_sel = 1;
        
        // Local Doppler = 1255 Hz (5 Hz offset from truth)
        carrier_freq_word = doppler_to_freq_word(1255.0);
        code_freq_word = code_rate_to_freq_word();
        init_code_phase = 347 << 22;  // 347 chips (scaled to 32-bit)
        
        fd_if = $fopen("../../data/iq_samples/synthetic_gps_l1ca.bin", "rb");
        fd_truth = $fopen("../../data/golden_files/golden_ref_data.bin", "rb");
        
        if (fd_if == 0 || fd_truth == 0) begin
            $display("ERROR: Cannot open input files");
            $finish;
        end
        
        #100;
        rst_n = 1;
        
        for (epoch = 0; epoch < 100; epoch = epoch + 1) begin
            // Read truth for this epoch
            $fread(truth_I_E, fd_truth);
            $fread(truth_Q_E, fd_truth);
            $fread(truth_I_P, fd_truth);
            $fread(truth_Q_P, fd_truth);
            $fread(truth_I_L, fd_truth);
            $fread(truth_Q_L, fd_truth);
            
            // Process 4000 samples (1 ms)
            repeat (SAMPLES_PER_MS) begin
                $fread(i_if, fd_if);
                $fread(q_if, fd_if);
                i_in = i_if[15:0];
                q_in = q_if[15:0];
                sample_valid = 1;
                @(posedge clk);
                sample_valid = 0;
                @(posedge clk);
            end
            
            wait (dump_valid);
            @(posedge clk);
            
            err_I_P = I_P - truth_I_P;
            err_Q_P = Q_P - truth_Q_P;
            
            if (err_I_P < 0) err_I_P = -err_I_P;
            if (err_Q_P < 0) err_Q_P = -err_Q_P;
            
            if (err_I_P > max_err) max_err = err_I_P;
            if (err_Q_P > max_err) max_err = err_Q_P;
            
            $display("Epoch %0d: I_P=%0d truth=%0d err=%0d | Q_P=%0d truth=%0d err=%0d",
                     epoch, I_P, truth_I_P, I_P - truth_I_P,
                     Q_P, truth_Q_P, Q_P - truth_Q_P);
            
            if (err_I_P > 2 || err_Q_P > 2) begin
                $display("ERROR: Mismatch at epoch %0d!", epoch);
                $stop;
            end
        end
        
        $display("\n=== ALL 100 EPOCHS PASSED ===");
        $display("Maximum error: %0d LSB", max_err);
        $fclose(fd_if);
        $fclose(fd_truth);
        $finish;
    end

endmodule