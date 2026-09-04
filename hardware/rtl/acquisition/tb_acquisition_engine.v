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
    
    // Search Grid Configuration
    parameter DOPPLER_STEP_HZ = 1000;
    parameter NUM_DOPPLER_BINS = 11;
    
    reg [15:0] stim_i_mem [0:FFT_SIZE-1];
    reg [15:0] stim_q_mem [0:FFT_SIZE-1];

    reg clk_100;
    reg clk_200;
    reg rst_n;
    
    // DUT signals
    wire done; 
    wire busy;
    reg signed [15:0] stim_i;
    reg signed [15:0] stim_q;
    reg stim_valid;
    wire [IDX_WIDTH-1:0] best_code_phase;
    wire [31:0] peak_magnitude;

    // Controller signals
    reg  ctrl_start;
    wire ctrl_done;
    wire ctrl_busy;
    wire [PHASE_BITS-1:0] carrier_freq_word;
    wire acq_start;
    wire [PHASE_BITS-1:0] best_doppler_word;
    wire [IDX_WIDTH-1:0] ctrl_best_code_phase;
    wire [31:0] ctrl_best_peak_mag;

    parameter EXP_PRN = 5'd1; 

    // 1. Instantiate Acquisition Engine (The Hardware Accelerator)
    acquisition_engine #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .PHASE_BITS(PHASE_BITS),
        .IDX_WIDTH(IDX_WIDTH)
    ) uut (
        .clk_100(clk_100),
        .clk_200(clk_200),
        .rst_n(rst_n),
        .start(acq_start),             // Driven by Controller
        .done(done),
        .busy(busy),
        .i_sample(stim_i),
        .q_sample(stim_q),
        .sample_valid(stim_valid),
        .prn_sel(EXP_PRN),
        .carrier_freq_word(carrier_freq_word), // Driven by Controller
        .best_code_phase(best_code_phase),
        .peak_magnitude(peak_magnitude)
    );

    // 2. Instantiate Doppler Search Controller (The Baseband Processor)
    doppler_search_controller #(
        .FFT_SIZE(FFT_SIZE),
        .PHASE_BITS(PHASE_BITS),
        .NUM_DOPPLER_BINS(NUM_DOPPLER_BINS),
        .DOPPLER_STEP_HZ(DOPPLER_STEP_HZ)
    ) u_ctrl (
        .clk(clk_200),
        .rst_n(rst_n),
        .start(ctrl_start),
        .done(ctrl_done),
        .busy(ctrl_busy),
        .carrier_freq_word(carrier_freq_word),
        .acq_start(acq_start),
        .acq_done(done),               // Fed by Acquisition Engine
        .acq_code_phase(best_code_phase),
        .acq_peak_mag(peak_magnitude),
        .best_doppler_word(best_doppler_word),
        .best_code_phase(ctrl_best_code_phase),
        .best_peak_mag(ctrl_best_peak_mag)
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

    // State Machine Debug Monitor
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
                4'd7: $display("[%0t] 🔍 [DUT] DONE", $time);
            endcase
            prev_state_debug_200 <= uut.state;
        end
    end

    // Controller State Monitor
    reg [3:0] prev_ctrl_state;
    always @(posedge clk_200) begin
        if (u_ctrl.state !== prev_ctrl_state) begin
            $display("[%0t] 🎛️ [CTRL] State -> %0d | Bin: %0d | Freq Word: %h", 
                     $time, u_ctrl.state, u_ctrl.doppler_bin, u_ctrl.carrier_freq_word);
            prev_ctrl_state <= u_ctrl.state;
        end
    end

    // =======================================================================
    // AUTONOMOUS FIFO DATA FEEDER (Acts as the RF Front-End / ADC)
    // =======================================================================
    initial begin
        stim_valid = 0;
        stim_i = 0;
        stim_q = 0;
        
        wait(rst_n == 1);
        #100;
        
        forever begin
            // Wait until DUT enters WAIT_FIFO state (it needs data)
            wait (uut.state == 4'd1); 
            $display("[%0t] 📥 [TB] DUT requested data. Streaming %0d samples...", $time, FFT_SIZE);
            
            for (i = 0; i < FFT_SIZE; i = i + 1) begin
                @(posedge clk_100);
                stim_valid <= 1;
                stim_i <= stim_i_mem[i];
                stim_q <= stim_q_mem[i];
            end
            @(posedge clk_100);
            stim_valid <= 0;
            $display("[%0t] ✅ [TB] Streaming complete.", $time);
            
            // Wait until DUT leaves WAIT_FIFO to avoid re-triggering immediately
            wait (uut.state !== 4'd1);
        end
    end

    // =======================================================================
    // MAIN TEST SEQUENCE
    // =======================================================================
    initial begin
        rst_n = 0;
        ctrl_start = 0;
        prev_state_debug_200 = 4'd0;
        prev_ctrl_state = 4'd0;

        $display("[%0t] 🔄 [RESET] Asserting reset...", $time);
        #(CLK_100_PERIOD * 10);
        rst_n = 1;
        $display("[%0t] ✅ [RESET] Reset released.", $time);
        #50000;
        
        $display("\n======================================================");
        $display("STARTING AUTONOMOUS 2D DOPPLER SEARCH");
        $display("Bins: %0d, Step: %0d Hz", NUM_DOPPLER_BINS, DOPPLER_STEP_HZ);
        $display("======================================================");

        // Pulse start to the controller
        @(posedge clk_200);
        ctrl_start = 1;
        @(posedge clk_200);
        ctrl_start = 0;
        
        // Wait for the entire 2D search to complete autonomously
        wait (ctrl_done == 1);
        #(CLK_200_PERIOD * 10);

        // Final Results
        $display("\n======================================================");
        $display("🏁 2D SEARCH COMPLETE");
        $display("======================================================");
        $display("Best Doppler Word: %h", best_doppler_word);
        $display("Best Code Phase:   %0d chips", ctrl_best_code_phase);
        $display("Global Peak Mag:   %0d", ctrl_best_peak_mag);
        $display("======================================================");

        if (ctrl_best_peak_mag > 0) begin
            $display("✅ TEST PASSED: 2D Acquisition Successful!");
        end else begin
            $display("❌ TEST FAILED: No signal found.");
        end

        $finish;
    end

endmodule