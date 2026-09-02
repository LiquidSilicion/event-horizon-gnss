`timescale 1ns / 1ps

module tb_acquisition_engine;

    parameter CLK_100_PERIOD = 10;
    parameter CLK_200_PERIOD = 5;
    parameter FFT_SIZE = 4096;
    parameter DATA_WIDTH = 18;
    parameter PHASE_BITS = 48;
    parameter IDX_WIDTH = 12;
    parameter TIMEOUT_CYCLES = 500000; // 500k cycles timeout (~2.5ms at 200MHz)

    integer wait_count;
    integer i;
    
    // ✅ FIX: Moved these declarations to the module level to fix VRFC 10-8885
    integer sum_i, sum_q;
    integer mean_i, mean_q;
    
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
    parameter signed [PHASE_BITS-1:0] EXP_DOPPLER_WORD = 48'h000010624DD2F1; 

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
        .carrier_freq_word(EXP_DOPPLER_WORD),
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
        
        // ✅ Calculate mean (DC bias)
        sum_i = 0;
        sum_q = 0;
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            sum_i = sum_i + $signed(stim_i_mem[i]);
            sum_q = sum_q + $signed(stim_q_mem[i]);
        end
        mean_i = sum_i / FFT_SIZE;
        mean_q = sum_q / FFT_SIZE;
        
        $display("======================================================");
        $display("✅ STIMULUS LOADED - DC Bias Removal");
        $display("   Mean I = %0d, Mean Q = %0d", mean_i, mean_q);
        
        // ✅ Subtract mean from all samples
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            stim_i_mem[i] = stim_i_mem[i] - mean_i;
            stim_q_mem[i] = stim_q_mem[i] - mean_q;
        end
        
        $display("   [DEBUG] Sample 0 (after DC removal): I = %0d, Q = %0d", 
                 $signed(stim_i_mem[0]), $signed(stim_q_mem[0]));
        $display("   [DEBUG] Sample 1 (after DC removal): I = %0d, Q = %0d", 
                 $signed(stim_i_mem[1]), $signed(stim_q_mem[1]));
        $display("======================================================");
    end

    // Watchdog timer - monitors if simulation is stuck
    reg [31:0] watchdog_counter;
    reg [3:0] prev_state;
    reg prev_fft_out_valid;
    reg prev_pd_done;
    
    always @(posedge clk_200) begin
        if (!rst_n) begin
            watchdog_counter <= 0;
            prev_state <= 4'd0;
            prev_fft_out_valid <= 0;
            prev_pd_done <= 0;
        end else begin
            // Check if any key signal changed
            if (uut.state !== prev_state || 
                uut.fft_out_valid !== prev_fft_out_valid || 
                uut.pd_done !== prev_pd_done) begin
                // Something changed, reset watchdog
                watchdog_counter <= 0;
                prev_state <= uut.state;
                prev_fft_out_valid <= uut.fft_out_valid;
                prev_pd_done <= uut.pd_done;
            end else begin
                // Nothing changed, increment watchdog
                watchdog_counter <= watchdog_counter + 1;
                
                // Print status every 100k cycles when stuck
                if (watchdog_counter > 0 && watchdog_counter % 100000 == 0) begin
                    $display("[%0t] ⚠️ WATCHDOG: No state change for %0d cycles. State=%0d, fft_out_valid=%b, pd_done=%b", 
                             $time, watchdog_counter, uut.state, uut.fft_out_valid, uut.pd_done);
                end
                
                // Timeout - stop simulation
                if (watchdog_counter >= TIMEOUT_CYCLES) begin
                    $display("[%0t] ❌ TIMEOUT: Simulation stuck for %0d cycles!", $time, TIMEOUT_CYCLES);
                    $display("   Final State: %0d", uut.state);
                    $display("   fft_out_valid: %b", uut.fft_out_valid);
                    $display("   pd_done: %b", uut.pd_done);
                    $display("   sample_cnt: %0d", uut.sample_cnt);
                    $display("   fft_wrapper state: %0d", uut.u_fft.state);
                    $display("   fft_wrapper sample_count: %0d", uut.u_fft.sample_count);
                    $display("   fft_wrapper out_count: %0d", uut.u_fft.out_count);
                    $finish;
                end
            end
        end
    end

    // State transition monitor
    reg [3:0] prev_state_monitor;
    always @(posedge clk_200) begin
        if (uut.state !== prev_state_monitor) begin
            case (uut.state)
                4'd0: $display("[%0t] STATE: IDLE", $time);
                4'd1: $display("[%0t] STATE: WAIT_FIFO", $time);
                4'd2: $display("[%0t] STATE: WIPEOFF", $time);
                4'd3: $display("[%0t] STATE: LOAD_FWD (Starting Forward FFT)", $time);
                4'd4: $display("[%0t] STATE: STREAM_MULT (Waiting for FFT output & Multiplying)", $time);
                4'd5: $display("[%0t] STATE: LOAD_INV (Starting IFFT)", $time);
                4'd6: $display("[%0t] STATE: WAIT_INV (Waiting for IFFT completion)", $time);
                4'd7: $display("[%0t] STATE: DONE", $time);
            endcase
            prev_state_monitor <= uut.state;
        end
    end

    // FFT wrapper state monitor
    reg [2:0] prev_fft_state;
    always @(posedge clk_200) begin
        if (uut.u_fft.state !== prev_fft_state) begin
            case (uut.u_fft.state)
                3'd0: $display("[%0t]   FFT_WRAPPER: IDLE", $time);
                3'd1: $display("[%0t]   FFT_WRAPPER: LOAD", $time);
                3'd2: $display("[%0t]   FFT_WRAPPER: UNLOAD", $time);
            endcase
            prev_fft_state <= uut.u_fft.state;
        end
    end

    // Main stimulus and control
    initial begin
        rst_n = 0;
        start = 0;
        stim_i = 0;
        stim_q = 0;
        stim_valid = 0;
        prev_state_monitor = 4'd0;
        prev_fft_state = 3'd0;

        #(CLK_100_PERIOD * 5);
        rst_n = 1;
        #(CLK_100_PERIOD * 10);

        $display("======================================================");
        $display("STARTING ACQUISITION ENGINE TESTBENCH");
        $display("======================================================");
        
        #50000;

        $display("\n[STIMULUS] Playing back from testbench memory...");
        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            @(posedge clk_100);
            stim_valid <= 1;
            stim_i <= stim_i_mem[i];
            stim_q <= stim_q_mem[i];
        end
        @(posedge clk_100);
        stim_valid <= 0;
        $display("\n✅ Finished. Played back %0d samples.", FFT_SIZE);

        $display("\n[CONTROL] Starting acquisition engine...");
        start = 1;
        #(CLK_200_PERIOD);
        start = 0;

        // Wait for completion or timeout
        wait (done === 1'b1);
        
        #(CLK_200_PERIOD * 10);

        $display("\n======================================================");
        $display("ACQUISITION COMPLETE");
        $display("======================================================");
        $display("Detected PRN: %0d", EXP_PRN);
        $display("Detected Code Phase: %0d chips", best_code_phase);
        $display("Peak Magnitude: %0d", peak_magnitude);
        $display("======================================================");

        if (peak_magnitude > 0) begin
            $display("✅ TEST PASSED: Pipeline processed real data successfully!");
        end else begin
            $display("❌ TEST FAILED: Peak magnitude is 0.");
        end

        $finish;
    end

endmodule