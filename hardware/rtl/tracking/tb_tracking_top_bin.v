`timescale 1ns / 1ps

module tb_tracking_top;

    // ==========================================
    // Clock and Reset
    // ==========================================
    reg clk_100mhz;
    reg rst_n; // Physical pin: 1 = Reset (Pressed), 0 = Run (Released)

    // ==========================================
    // DUT Outputs
    // ==========================================
    wire led_dump_valid;
    wire led_tracking_ok;

    // ==========================================
    // Instantiate DUT
    // ==========================================
    tracking_top uut (
        .clk_100mhz(clk_100mhz),
        .rst_n(rst_n),
        .led_dump_valid(led_dump_valid),
        .led_tracking_ok(led_tracking_ok)
    );

    // ==========================================
    // Clock Generation (100 MHz = 10 ns period)
    // ==========================================
    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // ==========================================
    // Stimulus & Reset Sequence (MATCHES HARDWARE)
    // ==========================================
    initial begin
        // 1. START IN RESET (Simulate button being pressed = 1)
        rst_n = 1;
        #100;
        
        // 2. RELEASE RESET (Simulate button being released = 0)
        // This makes rst_internal = ~0 = 1, telling the design to RUN
        rst_n = 0;
        
        // 3. Run simulation for 10 ms (10 epochs)
        #10000000;
        
        $display("================================================");
        $display("[%0t ns] Simulation Complete", $time);
        $display("================================================");
        $finish;
    end

    // ==========================================
    // Monitor: Print dump_valid events
    // ==========================================
    integer dump_count = 0;
    
    always @(posedge clk_100mhz) begin
        if (uut.dump_valid_int) begin
            dump_count = dump_count + 1;
            $display("------------------------------------------------");
            $display("[%0t ns] *** DUMP VALID #%0d ***", $time, dump_count);
            $display("  I_P = %0d", uut.I_P_int);
            $display("  Q_P = %0d", uut.Q_P_int);
            $display("  I_E = %0d, Q_E = %0d", uut.I_E_int, uut.Q_E_int);
            $display("  I_L = %0d, Q_L = %0d", uut.I_L_int, uut.Q_L_int);
            $display("  Carrier Phase = 0x%012h", uut.carrier_phase_int);
            $display("  LED Tracking OK = %b", uut.led_tracking_ok);
            $display("------------------------------------------------");
        end
    end

    // ==========================================
    // Periodic Status Report (every 1 ms)
    // ==========================================
    always @(posedge clk_100mhz) begin
        if ($time > 0 && ($time % 1000000 == 0)) begin  // Every 1 ms
            $display("[%0t ns] Status: I_P=%0d, Q_P=%0d, dump_valid=%b", 
                     $time, uut.I_P_int, uut.Q_P_int, uut.dump_valid_int);
        end
    end

endmodule