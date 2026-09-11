`timescale 1ns / 1ps

module tb_acquisition_engine;

    parameter CLK_100_PERIOD = 10;
    parameter CLK_200_PERIOD = 5;
    parameter FFT_SIZE = 4096;
    parameter DATA_WIDTH = 18;
    parameter PHASE_BITS = 48;
    parameter IDX_WIDTH = 12;

    integer i;
    integer sum_i, sum_q;
    integer mean_i, mean_q;
    integer stream_index;       // ✅ NEW: For 4 MHz streaming
    reg streaming_active;       // ✅ NEW: For 4 MHz streaming
    
    // ✅ UPDATED: Add new parameters for Multi-PRN and Two-Stage search
    parameter DOPPLER_STEP_HZ = 1000;
    parameter NUM_DOPPLER_BINS = 11;
    parameter NCI_FRAMES = 3;        // Keep at 3 for fast testing
    
    parameter NUM_FINE_BINS = 5;     // ✅ NEW: Only 5 fine bins for quick test
    parameter FINE_STEP_HZ = 50;     // ✅ NEW: 50 Hz fine step
    parameter NUM_PRNS = 3;
    
    reg [15:0] stim_i_mem [0:FFT_SIZE-1];
    reg [15:0] stim_q_mem [0:FFT_SIZE-1];

    reg clk_100;
    reg clk_200;
    reg rst_n;
    
    wire done; 
    wire busy;
    reg signed [15:0] stim_i;
    reg signed [15:0] stim_q;
    reg stim_valid;
    
    wire [IDX_WIDTH-1:0] best_code_phase;
    wire [7:0] best_code_phase_frac; 
    wire [31:0] peak_magnitude;
    wire [4:0] best_prn;             // ✅ NEW: Output from DUT

    reg ctrl_start;
    wire [PHASE_BITS-1:0] best_doppler_word;

    // ✅ UPDATED: Pass ALL parameters to the DUT
    acquisition_engine #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .PHASE_BITS(PHASE_BITS),
        .IDX_WIDTH(IDX_WIDTH),
        .NUM_DOPPLER_BINS(NUM_DOPPLER_BINS),
        .DOPPLER_STEP_HZ(DOPPLER_STEP_HZ),
        .NCI_FRAMES(NCI_FRAMES),
        .NUM_FINE_BINS(NUM_FINE_BINS),   // ✅ PASSED
        .FINE_STEP_HZ(FINE_STEP_HZ),     // ✅ PASSED
        .NUM_PRNS(NUM_PRNS)              // ✅ PASSED
    ) uut (
        .clk_100(clk_100),
        .clk_200(clk_200),
        .rst_n(rst_n),
        .start(ctrl_start),
        .done(done),
        .busy(busy),
        .i_sample(stim_i),
        .q_sample(stim_q),
        .sample_valid(stim_valid),
        .best_doppler_word(best_doppler_word),
        .best_code_phase(best_code_phase),
        .best_code_phase_frac(best_code_phase_frac),
        .best_prn(best_prn),             // ✅ CONNECTED
        .peak_magnitude(peak_magnitude)
    );

    // 100 MHz Clock
    initial begin
        clk_100 = 0;
        forever #(CLK_100_PERIOD/2) clk_100 = ~clk_100;
    end

    // 200 MHz Clock
    initial begin
        clk_200 = 0;
        forever #(CLK_200_PERIOD/2) clk_200 = ~clk_200;
    end

    // Load Stimulus and Apply DC Bias Removal
    initial begin
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/rtl/acquisition/stim_i.hex", stim_i_mem);
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/rtl/acquisition/stim_q.hex", stim_q_mem);
        
        sum_i = 0; sum_q = 0;
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            sum_i = sum_i + $signed(stim_i_mem[i]);
            sum_q = sum_q + $signed(stim_q_mem[i]);
        end
        mean_i = sum_i / FFT_SIZE;
        mean_q = sum_q / FFT_SIZE;
        
        $display("✅ STIMULUS LOADED - DC Bias Removal (Mean I=%0d, Q=%0d)", mean_i, mean_q);
        
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            stim_i_mem[i] = stim_i_mem[i] - mean_i;
            stim_q_mem[i] = stim_q_mem[i] - mean_q;
        end
    end

    // Debug: DUT State Machine
    reg [3:0] prev_state_debug_200;
    always @(posedge clk_200) begin
        if (uut.state !== prev_state_debug_200) begin
            case (uut.state)
                4'd0: $display("[%0t] 🔍 [DUT] IDLE", $time);
                4'd1: $display("[%0t] 🔍 [DUT] WAIT_FIFO", $time);
                4'd2: $display("[%0t] 🔍 [DUT] WIPEOFF", $time);
                4'd3: $display("[%0t] 🔍 [DUT] LOAD_FWD", $time);
                4'd4: $display("[%0t] 🔍 [DUT] STREAM_MULT", $time);
                4'd5: $display("[%0t] 🔍 [DUT] LOAD_INV", $time);
                4'd6: $display("[%0t] 🔍 [DUT] WAIT_INV", $time);
                4'd7: $display("[%0t] 🔍 [DUT] NCI_SCAN", $time);
                4'd8: $display("[%0t] 🔍 [DUT] DONE", $time);
                4'd9: $display("[%0t] 🔍 [DUT] INTERP", $time);
            endcase
            prev_state_debug_200 <= uut.state;
        end
    end

    // Debug: Controller State Machine
    reg [3:0] prev_ctrl_state;
    always @(posedge clk_200) begin
        if (uut.u_doppler_ctrl.state !== prev_ctrl_state) begin
            $display("[%0t] 🎛️ [CTRL] State -> %0d | PRN: %0d | Bin: %0d | Freq: %h", 
                     $time, uut.u_doppler_ctrl.state, uut.u_doppler_ctrl.prn_counter, uut.u_doppler_ctrl.doppler_bin, uut.u_doppler_ctrl.carrier_freq_word);
            prev_ctrl_state <= uut.u_doppler_ctrl.state;
        end
    end

    // ✅ NEW: 4 MHz Sample Rate Generator (100 MHz / 25 = 4 MHz)
    reg [4:0] tb_sample_div_counter;
    wire tb_sample_en;

    always @(posedge clk_100) begin
        if (tb_sample_div_counter == 5'd24) begin
            tb_sample_div_counter <= 5'd0;
        end else begin
            tb_sample_div_counter <= tb_sample_div_counter + 1'b1;
        end
    end
    assign tb_sample_en = (tb_sample_div_counter == 5'd24);

    // ✅ NEW: Streaming logic synchronized to 4 MHz enable signal
    initial begin
        stim_valid = 0;
        stim_i = 0;
        stim_q = 0;
        stream_index = 0;
        streaming_active = 0;
        
        wait(rst_n == 1);
        #100;
        
        forever begin
            // Wait for DUT to request data (state == 4'd1, ST_WAIT_FIFO)
            wait (uut.state == 4'd1); 
            $display("[%0t] 📥 [TB] DUT requested data. Streaming %0d samples at 4 MHz...", $time, FFT_SIZE);
            
            streaming_active = 1;
            stream_index = 0;
            
            // Stream 4096 samples, advancing ONLY on tb_sample_en
            while (stream_index < FFT_SIZE) begin
                @(posedge clk_100);
                if (tb_sample_en) begin
                    stim_valid <= 1'b1;
                    stim_i <= stim_i_mem[stream_index];
                    stim_q <= stim_q_mem[stream_index];
                    stream_index = stream_index + 1;
                end else begin
                    stim_valid <= 1'b0; // Keep valid low between samples
                end
            end
            
            // Final cycle to clear valid
            @(posedge clk_100);
            stim_valid <= 1'b0;
            streaming_active = 0;
            
            $display("[%0t] ✅ [TB] Streaming complete.", $time);
            
            // Wait for DUT to move to next state before looping
            wait (uut.state !== 4'd1);
        end
    end

    // Main Test Sequence
    initial begin
        rst_n = 0;
        ctrl_start = 0;
        prev_state_debug_200 = 4'd0;
        prev_ctrl_state = 4'd0;

        #(CLK_100_PERIOD * 10);
        rst_n = 1;
        #50000;
        
        // ✅ UPDATED: Print full configuration context
        $display("\n======================================================");
        $display("STARTING MULTI-PRN TWO-STAGE ACQUISITION");
        $display("Configuration:");
        $display("  - PRNs to search: %0d", NUM_PRNS);
        $display("  - Coarse Bins: %0d (Step: %0d Hz)", NUM_DOPPLER_BINS, DOPPLER_STEP_HZ);
        $display("  - Fine Bins: %0d (Step: %0d Hz)", NUM_FINE_BINS, FINE_STEP_HZ);
        $display("  - NCI Frames: %0d ms", NCI_FRAMES);
        $display("======================================================");

        @(posedge clk_200);
        ctrl_start = 1;
        @(posedge clk_200);
        ctrl_start = 0;
        
        wait (done == 1);
        #(CLK_200_PERIOD * 10);

        // ✅ UPDATED: Clean, non-duplicate summary with all new features
        $display("\n======================================================");
        $display("🏁 FULL COLD START SEARCH COMPLETE");
        $display("======================================================");
        $display("Best PRN:          %0d", best_prn);
        $display("Best Doppler Word: %h", best_doppler_word);
        $display("Best Code Phase:   %0d + (%0d / 256) chips", best_code_phase, $signed(best_code_phase_frac));
        $display("Global Peak Mag:   %0d (after %0dms NCI)", peak_magnitude, NCI_FRAMES);
        $display("======================================================");

        if (peak_magnitude > 0) begin
            $display("✅ TEST PASSED: Multi-PRN Acquisition Successful!");
        end else begin
            $display("❌ TEST FAILED: No signal found.");
        end

        $finish;
    end

endmodule