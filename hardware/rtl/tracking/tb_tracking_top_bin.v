`timescale 1ns / 1ps

module tb_tracking_top;

    // Testbench signals
    reg clk_100mhz;
    reg rst_n;
    reg sample_valid;
    reg signed [15:0] i_in;
    reg signed [15:0] q_in;

    // DUT outputs
    wire led_dump_valid;
    wire led_tracking_ok;

    // 1. Instantiate DUT
    tracking_top uut (
        .clk_100mhz(clk_100mhz),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .i_in(i_in),
        .q_in(q_in),
        .led_dump_valid(led_dump_valid),
        .led_tracking_ok(led_tracking_ok)
    );
    
    // 2. Load Real Data into Testbench Memory
    // Size matches 4000 samples (1 ms at 4 MHz)
    reg signed [15:0] stim_i_mem [0:3999]; 
    reg signed [15:0] stim_q_mem [0:3999];
    
    initial begin
        // Use absolute paths to guarantee Vivado finds the files
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/sim/stim_i.hex", stim_i_mem);
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/sim/stim_q.hex", stim_q_mem);
        $display("INFO: Stimulus memory loaded successfully from absolute paths.");
    end

    // 3. Clock Generation (100 MHz = 10 ns period)
    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // 4. Stimulus Driver
    integer sample_idx = 0;
    integer i;
    
    initial begin
        // Initialize all signals
        rst_n = 0;
        sample_valid = 0;
        i_in = 0;
        q_in = 0;
        sample_idx = 0;
        
        // Hold reset for 100 ns
        #100;
        rst_n = 1; // Release reset
        
        // Wait a few cycles after reset to stabilize
        repeat(5) @(posedge clk_100mhz);
        
        $display("INFO: Starting stimulus drive (4000 samples @ 4 MHz effective rate)...");
        
        // Drive 4000 samples
        // 4 MHz = 250 ns period. At 100 MHz (10 ns period), that's 25 clock cycles.
        for (i = 0; i < 4000; i = i + 1) begin
            // Wait 24 clock cycles (240 ns)
            repeat(24) @(posedge clk_100mhz);
            
            // Drive the signals on the 25th cycle
            @(posedge clk_100mhz);
            sample_valid <= 1'b1;
            i_in <= stim_i_mem[i];
            q_in <= stim_q_mem[i];
            sample_idx = i + 1;
            
            // Keep sample_valid high for exactly 1 clock cycle
            @(posedge clk_100mhz);
            sample_valid <= 1'b0;
        end
        
        $display("INFO: Stimulus complete. Letting design settle for 1 ms...");
        
        // Let the design run for 1 ms (100,000 clock cycles) to see the final I_P/Q_P accumulation
        #1000000; 
        
        $display("====================================================");
        $display("FINAL RESULTS:");
        $display("I_P = %0d", uut.I_P_int);
        $display("Q_P = %0d", uut.Q_P_int);
        $display("LED Tracking OK = %b", uut.led_tracking_ok);
        $display("====================================================");
        
        $finish;
    end

    // 5. Monitor: Print every time dump_valid pulses
    always @(posedge clk_100mhz) begin
        if (uut.dump_valid_int) begin
            $display("[%0t ns] DUMP VALID: I_P=%0d, Q_P=%0d, LED_OK=%b", 
                     $time, uut.I_P_int, uut.Q_P_int, uut.led_tracking_ok);
        end
    end

endmodule