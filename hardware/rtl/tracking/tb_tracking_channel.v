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
    
    function [47:0] doppler_to_freq_word;
        input real doppler_hz;
        begin
            doppler_to_freq_word = $rtoi((doppler_hz / FS) * (2.0**48));
        end
    endfunction
    
    function [31:0] code_rate_to_freq_word;
        input integer dummy;
        begin
            code_rate_to_freq_word = $rtoi((1_023_000.0 / FS) * (2.0**32));
        end
    endfunction

    integer fd_if, fd_truth;
    reg [31:0] raw_buffer; 
    reg [31:0] truth_I_E, truth_Q_E, truth_I_P, truth_Q_P, truth_I_L, truth_Q_L;
    
    reg [31:0] epoch;
    reg [31:0] err_I_P, err_Q_P;
    reg [31:0] max_err = 0;
    reg [31:0] count; 

    initial begin
        rst_n = 0;
        sample_valid = 0;
        channel_en = 1;
        prn_sel = 1;
        
        carrier_freq_word = doppler_to_freq_word(1255.0);
        code_freq_word = code_rate_to_freq_word(0);
        init_code_phase = 347 << 22; 
        
        // ABSOLUTE PATHS
        fd_if = $fopen("/home/johan/Documents/fpga/event_horizon/event-horizon-gnss/hardware/scripts/tools/data/iq_samples/synthetic_gps_l1ca.bin", "rb");
        fd_truth = $fopen("/home/johan/Documents/fpga/event_horizon/event-horizon-gnss/hardware/scripts/tools/data/golden_files/golden_ref_data.bin", "rb");
        
        if (fd_if == 0 || fd_truth == 0) begin
            $display("ERROR: Cannot open input files. Check paths!");
            $finish;
        end
        
        #100;
        rst_n = 1;
        
        for (epoch = 0; epoch < 100; epoch = epoch + 1) begin
            // Read 6 Big-Endian integers from truth file
            count = $fread(truth_I_E, fd_truth);
            count = $fread(truth_Q_E, fd_truth);
            count = $fread(truth_I_P, fd_truth);
            count = $fread(truth_Q_P, fd_truth);
            count = $fread(truth_I_L, fd_truth);
            count = $fread(truth_Q_L, fd_truth);
            
            // Process 4000 samples (1 ms)
            repeat (SAMPLES_PER_MS) begin
                // Read 4 bytes (2 samples) from IF file
                count = $fread(raw_buffer, fd_if);
                
                // Handle Little-Endian 16-bit pairs in a Big-Endian read
                // Memory: [I_low, I_high, Q_low, Q_high]
                // Verilog $fread into 32-bit reg: [I_low, I_high, Q_low, Q_high] mapped to [31:0]
                i_in = {raw_buffer[23:16], raw_buffer[31:24]};
                q_in = {raw_buffer[7:0],   raw_buffer[15:8]};
                
                sample_valid = 1;
                @(posedge clk);
                sample_valid = 0;
                @(posedge clk);
            end
            
            wait (dump_valid);
            @(posedge clk);
            
            // Calculate errors
            err_I_P = I_P - truth_I_P;
            err_Q_P = Q_P - truth_Q_P;
            
            // Absolute value logic for 32-bit signed
            if (err_I_P[31]) err_I_P = -err_I_P;
            if (err_Q_P[31]) err_Q_P = -err_Q_P;
            
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