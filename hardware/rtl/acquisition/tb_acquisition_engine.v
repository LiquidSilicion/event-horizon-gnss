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
    
    // 2D Search Variables
    reg signed [PHASE_BITS-1:0] current_doppler_word;
    integer doppler_bin;
    integer doppler_hz;
    real doppler_real;
    real clk_real;
    real word_real;
    
    integer best_doppler_bin;
    integer best_doppler_hz;
    reg [31:0] global_best_mag;
    reg [IDX_WIDTH-1:0] global_best_code_phase;
    
    // Search Grid Configuration
    parameter DOPPLER_STEP_HZ = 1000;
    parameter NUM_DOPPLER_BINS = 11;
    
    // Timeout counter
    integer timeout_count;
    parameter MAX_WAIT_CYCLES = 500000;
    
    reg [15:0] stim_i_mem [0:FFT_SIZE-1];
    reg [15:0] stim_q_mem [0:FFT_SIZE-1];

    reg clk_100;
    reg clk_200;
    reg rst_n;
    reg start;
    wire done;
    wire busy;
    
    reg signed [15:0] stim_i;
    reg signed [15:0] stim_q;
    reg stim_valid;
    
    wire [IDX_WIDTH-1:0] best_code_phase;
    wire [31:0] peak_magnitude;

    parameter EXP_PRN = 5'd1; 

    acquisition_engine #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .PHASE_BITS(PHASE_BITS),
        .IDX_WIDTH(IDX_WIDTH)
    ) uut (
        .clk_100(clk_100),
        .clk_200(clk_200),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .busy(busy),
        .i_sample(stim_i),
        .q_sample(stim_q),
        .sample_valid(stim_valid),
        .prn_sel(EXP_PRN),
        .carrier_freq_word(current_doppler_word),
        .best_code_phase(best_code_phase),
        .peak_magnitude(peak_magnitude)
    );

    // Clock generation
    initial begin
        clk_100 = 0;
        forever #(CLK_100_PERIOD/2) clk_100 = ~clk_100;
    end

    initial begin
        clk_200 = 0;
        forever #(CLK_200_PERIOD/2) clk_200 = ~clk_200;
    end

    // Load stimulus and remove DC bias
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

    // ✅ COMPREHENSIVE STATE MACHINE DEBUG
    reg [3:0] prev_state_debug;
    reg [3:0] prev_state_debug_200;
    
    // Monitor on clk_100 domain
    always @(posedge clk_100) begin
        if (uut.state !== prev_state_debug) begin
            $display("[%0t] 🔍 [STATE_100] State changed: %0d -> %0d", $time, prev_state_debug, uut.state);
            prev_state_debug <= uut.state;
        end
    end
    
    // Monitor on clk_200 domain
    always @(posedge clk_200) begin
        if (uut.state !== prev_state_debug_200) begin
            case (uut.state)
                4'd0: $display("[%0t] 🔍 [STATE_200] IDLE", $time);
                4'd1: $display("[%0t] 🔍 [STATE_200] WAIT_FIFO", $time);
                4'd2: $display("[%0t] 🔍 [STATE_200] WIPEOFF", $time);
                4'd3: $display("[%0t] 🔍 [STATE_200] LOAD_FWD", $time);
                4'd4: $display("[%0t] 🔍 [STATE_200] STREAM_MULT", $time);
                4'd5: $display("[%0t] 🔍 [STATE_200] LOAD_INV", $time);
                4'd6: $display("[%0t] 🔍 [STATE_200] WAIT_INV", $time);
                4'd7: $display("[%0t] 🔍 [STATE_200] DONE", $time);
            endcase
            prev_state_debug_200 <= uut.state;
        end
        
        // Monitor key internal signals
        if (uut.state == 4'd0 && start) begin
            $display("[%0t] ⚠️ [DEBUG] START asserted while in IDLE! busy=%b, done=%b", $time, busy, done);
        end
    end

    // Monitor start signal
    reg prev_start;
    always @(posedge clk_200) begin
        if (start !== prev_start) begin
            $display("[%0t] 📍 [START] start signal: %b -> %b", $time, prev_start, start);
            prev_start <= start;
        end
    end

    // Main stimulus and 2D Search Loop
    initial begin
        rst_n = 0;
        start = 0;
        stim_i = 0;
        stim_q = 0;
        stim_valid = 0;
        current_doppler_word = 0;
        prev_state_debug = 4'd0;
        prev_state_debug_200 = 4'd0;
        prev_start = 0;
        
        global_best_mag = 0;
        best_doppler_bin = 0;
        best_doppler_hz = 0;

        $display("[%0t] 🔄 [RESET] Asserting reset...", $time);
        #(CLK_100_PERIOD * 10);
        rst_n = 1;
        $display("[%0t] ✅ [RESET] Reset released. Waiting for stabilization...", $time);
        #50000;
        
        $display("[%0t] 🔍 [CHECK] Current state after reset: %0d, busy=%b, done=%b", $time, uut.state, busy, done);

        $display("\n======================================================");
        $display("STARTING 2D DOPPLER SEARCH (%0d Bins, %0d Hz Step)", NUM_DOPPLER_BINS, DOPPLER_STEP_HZ);
        $display("======================================================");

        // THE 2D SEARCH LOOP
        for (doppler_bin = 0; doppler_bin < NUM_DOPPLER_BINS; doppler_bin = doppler_bin + 1) begin
            
            doppler_hz = (doppler_bin - (NUM_DOPPLER_BINS/2)) * DOPPLER_STEP_HZ;
            doppler_real = doppler_hz;
            clk_real = 200000000.0;
            word_real = (doppler_real / clk_real) * 281474976710656.0;
            current_doppler_word = $rtoi(word_real);
            
            $display("\n--- Testing Doppler Bin %0d (%0d Hz) | Word: %h ---", doppler_bin, doppler_hz, current_doppler_word);
            
            // ✅ ENSURE WE'RE IN IDLE BEFORE STARTING
            $display("[%0t] 🔍 [CHECK] Waiting for IDLE state...", $time);
            wait (uut.state == 4'd0);
            $display("[%0t] ✅ [CHECK] Confirmed in IDLE state. busy=%b, done=%b", $time, busy, done);
            
            // 1. Feed 4096 samples into the FIFO
            $display("[%0t] 📥 [DEBUG] Starting stimulus playback...", $time);
            for (i = 0; i < FFT_SIZE; i = i + 1) begin
                @(posedge clk_100);
                stim_valid <= 1;
                stim_i <= stim_i_mem[i];
                stim_q <= stim_q_mem[i];
            end
            @(posedge clk_100);
            stim_valid <= 0;
            $display("[%0t] ✅ [DEBUG] Stimulus playback complete.", $time);
            
            // 2. Wait for CDC FIFO to settle
            $display("[%0t] ⏳ [DEBUG] Waiting 5000ns for FIFO to settle...", $time);
            #5000; 
            $display("[%0t] ✅ [DEBUG] FIFO settle complete.", $time);
            
            // 3. ✅ IMPROVED START PULSE - Hold for multiple cycles
            $display("[%0t] 🚀 [DEBUG] Asserting start signal...", $time);
            @(posedge clk_200);
            start = 1;
            $display("[%0t] 📍 [DEBUG] start = 1", $time);
            repeat(5) @(posedge clk_200); // Hold for 5 clock cycles
            start = 0;
            $display("[%0t] 📍 [DEBUG] start = 0", $time);
            $display("[%0t] ✅ [DEBUG] Start pulse complete.", $time);
            
            // 4. Wait for done with timeout
            $display("[%0t] ⏳ [DEBUG] Waiting for acquisition to complete...", $time);
            timeout_count = 0;
            while (done !== 1'b1 && timeout_count < MAX_WAIT_CYCLES) begin
                @(posedge clk_200);
                timeout_count = timeout_count + 1;
                
                if (timeout_count % 100000 == 0) begin
                    $display("[%0t] ⏳ [DEBUG] Still waiting... %0d cycles. State=%0d, busy=%b, done=%b, fifo_empty=%b", 
                             $time, timeout_count, uut.state, busy, done, uut.fifo_empty);
                end
            end
            
            if (timeout_count >= MAX_WAIT_CYCLES) begin
                $display("[%0t] ❌ [TIMEOUT] Acquisition did not complete!", $time);
                $display("   State: %0d, busy: %b, done: %b", uut.state, busy, done);
                $display("   fifo_empty: %b, fifo_full: %b", uut.fifo_empty, uut.fifo_full);
                $display("   sample_cnt: %0d", uut.sample_cnt);
                $display("   Stopping simulation...");
                $finish;
            end
            
            $display("[%0t] ✅ [DEBUG] Acquisition complete! done=%b", $time, done);
            #(CLK_200_PERIOD * 10);
            
            $display("   📊 Result: Code Phase = %0d, Peak Mag = %0d", best_code_phase, peak_magnitude);
            
            if (peak_magnitude > global_best_mag) begin
                global_best_mag = peak_magnitude;
                global_best_code_phase = best_code_phase;
                best_doppler_bin = doppler_bin;
                best_doppler_hz = doppler_hz;
                $display("   🏆 *** NEW GLOBAL PEAK FOUND! ***");
            end
            
            // 6. Reset DUT for next bin
            if (doppler_bin < NUM_DOPPLER_BINS - 1) begin
                $display("[%0t] 🔄 [DEBUG] Resetting DUT for next Doppler bin...", $time);
                rst_n = 0;
                #100;
                rst_n = 1;
                $display("[%0t] ✅ [DEBUG] Reset complete. Waiting for stabilization...", $time);
                #10000;
            end
        end

        // Final Results
        $display("\n======================================================");
        $display("🏁 2D SEARCH COMPLETE");
        $display("======================================================");
        $display("Best Doppler: %0d Hz (Bin %0d)", best_doppler_hz, best_doppler_bin);
        $display("Best Code Phase: %0d chips", global_best_code_phase);
        $display("Global Peak Magnitude: %0d", global_best_mag);
        $display("======================================================");

        if (global_best_mag > 0) begin
            $display("✅ TEST PASSED: 2D Acquisition Successful!");
        end else begin
            $display("❌ TEST FAILED: No signal found.");
        end

        $finish;
    end

endmodule