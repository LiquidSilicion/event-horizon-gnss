`timescale 1ns / 1ps

module tracking_top (
    input wire clk_100mhz,
    input wire rst_n,
    output wire led_dump_valid,
    output wire led_tracking_ok
);

    // 1. Reset Polarity Fix (Active-High button -> Active-Low internal)
    wire rst_internal = ~rst_n; 

    // 2. Internal Wires for ILA
    wire signed [31:0] I_E_int, Q_E_int, I_P_int, Q_P_int, I_L_int, Q_L_int;
    wire dump_valid_int;
    wire [47:0] carrier_phase_int;
    
    // 3. GPS Signal Generator
    wire signed [15:0] i_sample;
    wire signed [15:0] q_sample;
    wire sample_valid;

    //gps_signal_gen #(
    //    .SAMPLE_RATE(4000000),
    //    .PRN_SEL(1),
    //    .CODE_PHASE_INIT(0)
    //) u_gps_gen (
    //    .clk(clk_100mhz),
    //    .rst_n(rst_internal),
    //    .sample_valid(sample_valid),
    //    .i_out(i_sample),
    //    .q_out(q_sample)
    //);

    // ==========================================
    // HARDWARE: Simple stimulus (replace gps_signal_gen)
    // The real GPS samples will come from the ADC/AXI DMA later
    // ==========================================
    reg [31:0] stim_cnt = 0;
    always @(posedge clk_100mhz) begin
        if (rst_internal)
            stim_cnt <= 0;
        else
            stim_cnt <= stim_cnt + 1;
    end

    wire signed [15:0] i_sample = stim_cnt[15:0];
    wire signed [15:0] q_sample = stim_cnt[31:16];
    wire sample_valid = 1'b1;  // Always valid for hardware test

    // 4. Tracking Channel
    tracking_channel #(
        .CH_ID(0),
        .SAMPLE_BITS(16),
        .ACCUM_BITS(32),
        .SAMPLES_PER_MS(4000) 
    ) u_tracking_ch (
        .clk(clk_100mhz),
        .rst_n(rst_internal),
        .enable(sample_valid),
        
        // ✅ CORRECTED FREQUENCY WORDS FOR 4 MHZ UPDATE RATE
        .carrier_freq_word(48'h000010624DD2F1),  // 1 kHz Doppler @ 4 MHz
        .code_freq_word(32'h4178D4FD),           // 1.023 MHz code rate @ 4 MHz
        
        .init_code_phase(32'd0),
        .prn_sel(5'd1),
        .channel_en(1'b1),
        .i_in(i_sample),
        .q_in(q_sample),
        .I_E(I_E_int), .Q_E(Q_E_int),
        .I_P(I_P_int), .Q_P(Q_P_int),
        .I_L(I_L_int), .Q_L(Q_L_int),
        .dump_valid(dump_valid_int),
        .carrier_phase(carrier_phase_int)
    );

    // ==========================================
    // Physical Pin Mapping
    // ==========================================
    //assign led_dump_valid = dump_valid_int;

    // NEW: Check if correlation is strong (I_P > 500,000)
    // This is a reasonable threshold for your signal levels
    //wire tracking_locked = (I_P_int > 32'd500000);
    //assign led_tracking_ok = tracking_locked;

    // ==========================================
    // Physical Pin Mapping & Sanity Checks
    // ==========================================
    
    // 1. LED0: Blinks rapidly every time a 1ms epoch completes
    assign led_dump_valid = dump_valid_int;

    // 2. LED1: Slow blink (~1.5 Hz) to prove the clock and reset are working
    // and the tracking channel is not stuck in reset.
    reg [25:0] blink_cnt = 0;
    always @(posedge clk_100mhz) begin
        if (rst_internal) 
            blink_cnt <= 0;
        else 
            blink_cnt <= blink_cnt + 1;
    end
    
    // TEMPORARY: Light up when the slow blink is high. 
    // (Change this back to your correlation threshold when you feed REAL GPS data!)
    assign led_tracking_ok = blink_cnt[25];


    ila_0 your_instance_name (
	.clk(clk_100mhz), // input wire clk


	.probe0(rst_n), // input wire [0:0]  probe0  
	.probe1(I_P_int), // input wire [31:0]  probe1 
	.probe2(Q_P_int), // input wire [31:0]  probe2 
	.probe3(dump_valid_int), // input wire [0:0]  probe3 
	.probe4(carrier_phase_int) // input wire [47:0]  probe4
);

endmodule