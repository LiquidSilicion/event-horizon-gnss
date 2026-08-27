`timescale 1ns / 1ps

module tb_tracking_top;

    // Inputs to the DUT
    reg clk_100mhz;
    reg rst_n;

    // Outputs from the DUT
    wire led_dump_valid;
    wire led_tracking_ok;

    // Instantiate the Unit Under Test (UUT)
    tracking_top uut (
        .clk_100mhz(clk_100mhz),
        .rst_n(rst_n),
        .led_dump_valid(led_dump_valid),
        .led_tracking_ok(led_tracking_ok)
    );

    // ==========================================
    // 1. Clock Generation (100 MHz = 10 ns period)
    // ==========================================
    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // ==========================================
    // 2. Stimulus & Reset Sequence
    // ==========================================
    initial begin
        // Start in reset (Active Low for simulation)
        rst_n = 0;

        // Hold reset for 100 ns (10 clock cycles)
        #100;

        // Release reset and let the design run
        rst_n = 1;

        // Run simulation long enough to see multiple dump_valid pulses.
        // SAMPLES_PER_MS = 4000. At 100 MHz, 4000 samples = 40,000 ns (40 µs).
        // We will run for 150 µs to see ~3-4 epochs.
        #150000;

        $display("[%0t ns] Simulation Finished.", $time);
        $finish;
    end

    // ==========================================
    // 3. Monitoring & Debug Prints
    // ==========================================
    
    // Print a summary every time dump_valid pulses
    always @(posedge clk_100mhz) begin
        if (uut.dump_valid_int) begin
            $display("--------------------------------------------------");
            $display("[%0t ns] *** DUMP VALID ***", $time);
            $display("  I_P = %0d", uut.I_P_int);
            $display("  Q_P = %0d", uut.Q_P_int);
            $display("  Carrier Phase = %0h", uut.carrier_phase_int);
            $display("--------------------------------------------------");
        end
    end

    // Optional: Print status every 10 µs to show the design is alive
    always @(posedge clk_100mhz) begin
        if ($time % 10000 == 0 && $time > 0) begin
            $display("[%0t ns] Running... I_P = %0d, Phase = %0h", 
                     $time, uut.I_P_int, uut.carrier_phase_int);
        end
    end

endmodule