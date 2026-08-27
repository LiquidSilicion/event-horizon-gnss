`timescale 1ns / 1ps

module tb_tracking_top;

    reg clk_100mhz;
    reg rst_n;

    wire led_dump_valid;
    wire led_tracking_ok;

    tracking_top uut (
        .clk_100mhz(clk_100mhz),
        .rst_n(rst_n),
        .led_dump_valid(led_dump_valid),
        .led_tracking_ok(led_tracking_ok)
    );

    // 1. Clock Generation (100 MHz = 10 ns period)
    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // 2. Stimulus & Reset Sequence
    initial begin
        // Start in reset (Active-High for the top module, which inverts it internally)
        rst_n = 0;
        
        // Print initial state
        $monitor("TIME=%0t ns | rst_n=%b | stim_cnt=%0d | I_P=%0d | dump_valid=%b", 
                 $time, rst_n, uut.stim_cnt, uut.I_P_int, uut.dump_valid_int);

        // Hold reset for 100 ns (10 clock cycles)
        #100;
        
        // Release reset
        rst_n = 1;

        // Run long enough to see multiple 1ms epochs (40 µs each)
        // 4000 samples @ 100MHz = 40,000 ns. Let's run for 150,000 ns.
        #150000;
        
        $display("Simulation Finished.");
        $finish;
    end

endmodule