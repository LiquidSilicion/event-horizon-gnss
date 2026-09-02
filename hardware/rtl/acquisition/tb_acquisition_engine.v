`timescale 1ns / 1ps

module tb_acquisition_engine;

    parameter CLK_100_PERIOD = 10;
    parameter CLK_200_PERIOD = 5;
    parameter FFT_SIZE = 4096;
    parameter DATA_WIDTH = 18;
    parameter PHASE_BITS = 48;
    parameter IDX_WIDTH = 12;

    integer wait_count;
    integer i;
    
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
        $display("======================================================");
        $display("✅ STIMULUS LOADED INTO TESTBENCH MEMORY");
        $display("   [DEBUG] Sample 0: I = %0d (0x%h), Q = %0d (0x%h)", stim_i_mem[0], stim_i_mem[0], stim_q_mem[0], stim_q_mem[0]);
        $display("   [DEBUG] Sample 1: I = %0d (0x%h), Q = %0d (0x%h)", stim_i_mem[1], stim_i_mem[1], stim_q_mem[1], stim_q_mem[1]);
        $display("======================================================");
    end

    integer load_fwd_count;
    initial begin load_fwd_count = 0; end
    always @(posedge clk_200) begin
        if (uut.state == 4'd3) begin
            load_fwd_count <= load_fwd_count + 1;
            if (load_fwd_count % 1000 == 0 || load_fwd_count < 10) begin
                $display("[%0t] DEBUG LOAD_FWD: sample_cnt=%0d, fft_in_valid=%b, fft_in_ready=%b", 
                         $time, uut.sample_cnt, uut.fft_in_valid, uut.fft_in_ready);
            end
            if (load_fwd_count > 10000) begin
                $display("[%0t] ⚠️ ERROR: Stuck in ST_LOAD_FWD!", $time);
                $finish;
            end
        end else begin
            load_fwd_count <= 0;
        end
    end

    integer stream_mult_count;
    initial begin stream_mult_count = 0; end
    always @(posedge clk_200) begin
        if (uut.state == 4'd4) begin
            stream_mult_count <= stream_mult_count + 1;
            if (stream_mult_count < 10 || stream_mult_count % 5000 == 0) begin
                $display("[%0t] DEBUG STREAM_MULT: sample_cnt=%0d, rom_cnt=%0d, fft_out_valid=%b, mult_valid=%b", 
                         $time, uut.sample_cnt, uut.rom_cnt, uut.fft_out_valid, uut.mult_valid);
            end
            if (stream_mult_count > 60000) begin
                $display("[%0t] ⚠️ ERROR: Stuck in ST_STREAM_MULT!", $time);
                $finish;
            end
        end else begin
            stream_mult_count <= 0;
        end
    end

    reg [3:0] prev_state;
    always @(posedge clk_200) begin
        if (uut.state !== prev_state) begin
            case (uut.state)
                4'd0: $display("[%0t] STATE: IDLE", $time);
                4'd1: $display("[%0t] STATE: WAIT_FIFO", $time);
                4'd2: $display("[%0t] STATE: WIPEOFF", $time);
                4'd3: $display("[%0t] STATE: LOAD_FWD (Starting Forward FFT)", $time);
                4'd4: $display("[%0t] STATE: STREAM_MULT (Waiting for FFT output & Multiplying)", $time);
                4'd5: $display("[%0t] STATE: LOAD_INV (Starting IFFT)", $time);
                4'd6: $display("[%0t] STATE: WAIT_INV", $time);
                4'd7: $display("[%0t] STATE: DONE", $time);
            endcase
            prev_state <= uut.state;
        end
    end

    initial begin
        rst_n = 0;
        start = 0;
        stim_i = 0;
        stim_q = 0;
        stim_valid = 0;
        prev_state = 4'd0;

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

        wait_count = 0;
        while (done !== 1 && wait_count < 5000000) begin
            @(posedge clk_200);
            wait_count = wait_count + 1;
        end
        
        if (wait_count >= 5000000) begin
            $display("\n⚠️ WARNING: Acquisition timed out!");
        end
        
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