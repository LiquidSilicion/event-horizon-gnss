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
    
    parameter DOPPLER_STEP_HZ = 1000;
    parameter NUM_DOPPLER_BINS = 11;
    parameter NCI_FRAMES = 3;
    
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
    wire [31:0] peak_magnitude;

    reg  ctrl_start;
    wire [PHASE_BITS-1:0] best_doppler_word;

    parameter EXP_PRN = 5'd1; 

    acquisition_engine #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .PHASE_BITS(PHASE_BITS),
        .IDX_WIDTH(IDX_WIDTH),
        .NUM_DOPPLER_BINS(NUM_DOPPLER_BINS),
        .DOPPLER_STEP_HZ(DOPPLER_STEP_HZ),
        .NCI_FRAMES(NCI_FRAMES)
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
        .prn_sel(EXP_PRN),
        .best_doppler_word(best_doppler_word),
        .best_code_phase(best_code_phase),
        .peak_magnitude(peak_magnitude)
    );

    initial begin
        clk_100 = 0;
        forever #(CLK_100_PERIOD/2) clk_100 = ~clk_100;
    end

    initial begin
        clk_200 = 0;
        forever #(CLK_200_PERIOD/2) clk_200 = ~clk_200;
    end

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
                4'd8: $display("[%0t] 🔍 [DUT] NCI_SCAN", $time);
                4'd7: $display("[%0t] 🔍 [DUT] DONE", $time);
            endcase
            prev_state_debug_200 <= uut.state;
        end
    end

    reg [3:0] prev_ctrl_state;
    always @(posedge clk_200) begin
        // ✅ FIX: Point to the internal controller instance
        if (uut.u_doppler_ctrl.state !== prev_ctrl_state) begin
            $display("[%0t] 🎛️ [CTRL] State -> %0d | Bin: %0d | Freq Word: %h", 
                     $time, uut.u_doppler_ctrl.state, uut.u_doppler_ctrl.doppler_bin, uut.u_doppler_ctrl.carrier_freq_word);
            prev_ctrl_state <= uut.u_doppler_ctrl.state;
        end
    end

    initial begin
        stim_valid = 0;
        stim_i = 0;
        stim_q = 0;
        
        wait(rst_n == 1);
        #100;
        
        forever begin
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
            
            wait (uut.state !== 4'd1);
        end
    end

    initial begin
        rst_n = 0;
        ctrl_start = 0;
        prev_state_debug_200 = 4'd0;
        prev_ctrl_state = 4'd0;

        #(CLK_100_PERIOD * 10);
        rst_n = 1;
        #50000;
        
        $display("\n======================================================");
        $display("STARTING AUTONOMOUS 2D DOPPLER SEARCH WITH %0d ms NCI", NCI_FRAMES);
        $display("Bins: %0d, Step: %0d Hz", NUM_DOPPLER_BINS, DOPPLER_STEP_HZ);
        $display("======================================================");

        @(posedge clk_200);
        ctrl_start = 1;
        @(posedge clk_200);
        ctrl_start = 0;
        
        wait (done == 1);
        #(CLK_200_PERIOD * 10);

        $display("\n======================================================");
        $display("🏁 2D SEARCH COMPLETE");
        $display("======================================================");
        $display("Best Doppler Word: %h", best_doppler_word);
        $display("Best Code Phase:   %0d chips", best_code_phase);
        $display("Global Peak Mag:   %0d (after %0dms NCI)", peak_magnitude, NCI_FRAMES);
        $display("======================================================");

        if (peak_magnitude > 0) begin
            $display("✅ TEST PASSED: 2D Acquisition Successful!");
        end else begin
            $display("❌ TEST FAILED: No signal found.");
        end

        $finish;
    end

endmodule