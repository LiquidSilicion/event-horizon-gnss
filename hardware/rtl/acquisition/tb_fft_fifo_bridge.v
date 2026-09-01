`timescale 1ns / 1ps

module tb_fft_fifo_bridge;

    parameter WR_CLK_PERIOD = 10;
    parameter RD_CLK_PERIOD = 5;
    parameter NUM_SAMPLES = 10;

    integer i;
    integer read_count;
    integer wait_count;

    reg wr_clk;
    reg wr_rst_n;
    reg signed [17:0] i_in;
    reg signed [17:0] q_in;
    reg sample_valid;
    reg last_sample;
    
    reg rd_clk;
    reg rd_rst_n;
    
    wire signed [17:0] i_out;
    wire signed [17:0] q_out;
    wire data_valid;
    wire last_out;
    wire fifo_full;
    wire fifo_empty;

    fft_fifo_bridge #(
        .FIFO_DEPTH(8192)
    ) uut (
        .wr_clk(wr_clk),
        .wr_rst_n(wr_rst_n),
        .i_in(i_in),
        .q_in(q_in),
        .sample_valid(sample_valid),
        .last_sample(last_sample),
        .rd_clk(rd_clk),
        .rd_rst_n(rd_rst_n),
        .i_out(i_out),
        .q_out(q_out),
        .data_valid(data_valid),
        .last_out(last_out),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty)
    );

    initial begin
        wr_clk = 0;
        forever #(WR_CLK_PERIOD/2) wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 0;
        forever #(RD_CLK_PERIOD/2) rd_clk = ~rd_clk;
    end

    // ============================================================
    // BACKGROUND PROCESS: Count ALL data_valid pulses continuously
    // ============================================================
    initial begin
        read_count = 0;
        forever begin
            @(posedge rd_clk);
            if (data_valid) begin
                $display("  [READ %0d] I=%0d, Q=%0d, Last=%b", 
                         read_count, i_out, q_out, last_out);
                read_count = read_count + 1;
            end
        end
    end

    // Main stimulus
    initial begin
        wr_rst_n = 0;
        rd_rst_n = 0;
        i_in = 0;
        q_in = 0;
        sample_valid = 0;
        last_sample = 0;

        $display("======================================================");
        $display("STARTING FIFO CDC TESTBENCH");
        $display("======================================================");

        #(WR_CLK_PERIOD * 5);
        wr_rst_n = 1;
        rd_rst_n = 1;

        $display("\n[WAIT] Waiting for FIFO to become ready...");
        wait_count = 0;
        while (fifo_full !== 1'b0 && wait_count < 500) begin
            @(posedge wr_clk);
            wait_count = wait_count + 1;
        end
        
        if (wait_count >= 500) begin
            $display("[ERROR] FIFO never became ready!");
            $finish;
        end
        
        $display("[OK] FIFO ready after %0d cycles.", wait_count);
        repeat (10) @(posedge rd_clk);

        // PHASE 1: WRITE
        $display("\n======================================================");
        $display("PHASE 1: WRITING %0d SAMPLES", NUM_SAMPLES);
        $display("======================================================");
        
        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
            @(posedge wr_clk);
            
            while (fifo_full !== 1'b0) begin
                @(posedge wr_clk);
            end
            
            i_in <= i * 100;
            q_in <= (i * 200) + 50;
            sample_valid <= 1;
            
            if (i == NUM_SAMPLES - 1) begin
                last_sample <= 1;
            end else begin
                last_sample <= 0;
            end
            
            $display("  [WRITE %0d] I=%0d, Q=%0d | Full=%b, Empty=%b", 
                     i, i_in, q_in, fifo_full, fifo_empty);
        end
        
        @(posedge wr_clk);
        sample_valid <= 0;
        last_sample <= 0;

        $display("\n[STATUS] Write Complete. Waiting for all reads to complete...");
        // Wait long enough for all CDC + reads to finish
        repeat (500) @(posedge rd_clk);

        // FINAL SUMMARY
        $display("\n======================================================");
        $display("TEST SUMMARY");
        $display("======================================================");
        $display("  Written: %0d  |  Read: %0d", NUM_SAMPLES, read_count);
        
        if (read_count == NUM_SAMPLES) begin
            $display("  ✅ PASS - All samples crossed successfully!");
        end else begin
            $display("  ❌ FAIL - Sample mismatch!");
        end
        $display("======================================================\n");
        
        $finish;
    end

endmodule