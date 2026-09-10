`timescale 1ns / 1ps

module acquisition_top (
    // System Clock (100 MHz from Zedboard oscillator)
    input  wire       clk_100,
    // Control Buttons
    input  wire       rst_n,          // Active Low Reset (e.g., BTNC)
    input  wire       start_btn,      // Active High Start (e.g., BTNU)
    
    // Status LEDs
    output wire       led_done,       // e.g., LD0
    output wire       led_busy,       // e.g., LD1
    output wire       led_found,      // e.g., LD2
    output wire [4:0] led_prn,        // e.g., LD3-LD7 (binary PRN)
    
    // UART Interface (Pmod JA Pin 1)
    output wire       uart_tx,
    input  wire       uart_rx
);

    // =========================================================================
    // 4 MHz Sample Rate Generator (100 MHz / 25 = 4 MHz)
    // =========================================================================
    reg [4:0] sample_div_counter;
    wire      sample_en;

    always @(posedge clk_100) begin
        if (sample_div_counter == 5'd24) begin
            sample_div_counter <= 5'd0;
        end else begin
            sample_div_counter <= sample_div_counter + 1'b1;
        end
    end

    // This pulse fires exactly at 4 MHz
    assign sample_en = (sample_div_counter == 5'd24);
    
    // ========================================================================
    // Button Synchronization & Debouncing (Sync to 200 MHz domain)
    // ========================================================================
    reg [2:0] start_btn_sync;
    wire start_btn_rising;
    
    always @(posedge clk_200) begin
        if (!rst_n || !clk_locked)
            start_btn_sync <= 3'b000;
        else
            start_btn_sync <= {start_btn_sync[1:0], start_btn};
    end
    
    assign start_btn_rising = start_btn_sync[1] & ~start_btn_sync[2];
    
    // ========================================================================
    // Acquisition Engine Instance
    // ========================================================================
    wire        acq_done;
    wire        acq_busy;
    wire [47:0] best_doppler_word;
    wire [11:0] best_code_phase;
    wire [7:0]  best_code_phase_frac;
    wire [4:0]  best_prn;
    wire [31:0] peak_magnitude;
    
    // Stimulus Generator (for testing without ADC)
    // Runs at the sampling clock rate (4.096 MHz)
    wire        stim_valid;
    wire signed [15:0] stim_i;
    wire signed [15:0] stim_q;
    
    stimulus_generator u_stim_gen (
        .clk         (clk_sample),
        .rst_n       (rst_n & clk_locked),
        .enable      (acq_busy),
        .sample_valid(stim_valid),
        .sample_i    (stim_i),
        .sample_q    (stim_q)
    );
    
    acquisition_engine #(
        .FFT_SIZE          (4096),
        .DATA_WIDTH        (18),
        .PHASE_BITS        (48),
        .IDX_WIDTH         (12),
        .NUM_DOPPLER_BINS  (11),
        .DOPPLER_STEP_HZ   (1000),
        .NCI_FRAMES        (20),
        .NUM_FINE_BINS     (21),
        .FINE_STEP_HZ      (50),
        .NUM_PRNS          (32)
    ) u_acq_engine (
        .clk_sample           (clk_sample), // <-- Wired to 4.096 MHz sample clock
        .clk_200              (clk_200),    // <-- Wired to 200 MHz processing clock
        .rst_n                (rst_n & clk_locked),
        .start                (start_btn_rising),
        .done                 (acq_done),
        .busy                 (acq_busy),
        .i_sample             (stim_i),
        .q_sample             (stim_q),
        .sample_valid         (stim_valid),
        .best_doppler_word    (best_doppler_word),
        .best_code_phase      (best_code_phase),
        .best_code_phase_frac (best_code_phase_frac),
        .best_prn             (best_prn),
        .peak_magnitude       (peak_magnitude)
    );
    
    // ========================================================================
    // UART Transmitter
    // ========================================================================
    wire        uart_tx_start;
    wire [7:0]  uart_tx_data;
    wire        uart_tx_busy;
    
    uart_tx #(
        .CLK_FREQ (100_000_000), // UART runs off the stable 100 MHz board clock
        .BAUD     (115200)
    ) u_uart_tx (
        .clk      (clk_100),
        .rst_n    (rst_n & clk_locked),
        .tx_data  (uart_tx_data),
        .tx_start (uart_tx_start),
        .tx       (uart_tx),
        .tx_busy  (uart_tx_busy)
    );
    
    // ========================================================================
    // Result Reporter (Converts binary to ASCII and sends via UART)
    // ========================================================================
    result_reporter u_result_reporter (
        .clk              (clk_200), 
        .rst_n            (rst_n & clk_locked),
        .acq_done         (acq_done),
        .best_prn         (best_prn),
        .best_doppler     (best_doppler_word),
        .best_code_phase  (best_code_phase),
        .best_frac        (best_code_phase_frac),
        .peak_mag         (peak_magnitude),
        .uart_tx_start    (uart_tx_start),
        .uart_tx_data     (uart_tx_data),
        .uart_tx_busy     (uart_tx_busy)
    );
    
    // ========================================================================
    // LED Control
    // ========================================================================
    assign led_done  = acq_done;
    assign led_busy  = acq_busy;
    assign led_found = acq_done & (peak_magnitude > 32'd1000000);
    assign led_prn   = best_prn[4:0];

endmodule