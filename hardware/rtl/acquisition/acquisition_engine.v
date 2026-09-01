`timescale 1ns / 1ps

module acquisition_engine #(
    parameter FFT_SIZE    = 4096,
    parameter DATA_WIDTH  = 18,
    parameter PHASE_BITS  = 48,
    parameter IDX_WIDTH   = 12  // log2(4096)
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control
    input  wire                     start,          // Pulse high to start acquisition for current Doppler/PRN
    output reg                      done,           // Pulse high when acquisition for this bin is complete
    
    // Inputs
    input  wire signed [15:0]       i_sample,       // Incoming I sample (will be sign-extended to 18)
    input  wire signed [15:0]       q_sample,       // Incoming Q sample
    input  wire                     sample_valid,   // High when sample is valid (e.g., 4 MHz pulse)
    input  wire [4:0]               prn_sel,        // Current PRN being searched (1-32)
    input  wire signed [PHASE_BITS-1:0] carrier_freq_word, // NCO frequency for current Doppler
    
    // Outputs
    output reg [IDX_WIDTH-1:0]      best_code_phase,
    output reg [31:0]               peak_magnitude
);

    // =========================================================================
    // 1. Local Buffers (Infer BRAM)
    // =========================================================================
    reg signed [DATA_WIDTH-1:0] i_buf [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] q_buf [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mult_i_buf [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mult_q_buf [0:FFT_SIZE-1];

    // =========================================================================
    // 2. Carrier Wipe-off (NCO)
    // =========================================================================
    reg [PHASE_BITS-1:0] carrier_phase;
    wire [11:0] carrier_idx = carrier_phase[PHASE_BITS-1 -: 12];
    
    wire signed [DATA_WIDTH-1:0] cos_val;
    wire signed [DATA_WIDTH-1:0] sin_val;
    
    // Instantiate your existing NCO ROM here
    nco_rom u_nco_rom (
        .clk(clk),
        .addr(carrier_idx),
        .cos_out(cos_val),
        .sin_out(sin_val)
    );

    // =========================================================================
    // 3. PRN FFT ROM
    // =========================================================================
    code_fft_rom #(
        .FFT_SIZE(4096),
        .DATA_WIDTH(18)
    ) u_code_fft_rom (
        .clk(clk),
        .prn_sel(current_prn),      // 1 to 32
        .bin_idx(fft_counter),      // 0 to 4095
        .fft_i_out(rom_fft_i),      // Connect to complex multiplier
        .fft_q_out(rom_fft_q)       // Connect to complex multiplier
    );

    // =========================================================================
    // 4. FFT Wrapper (Time-multiplexed for FWD and INV)
    // =========================================================================
    wire                     fft_in_ready;
    wire                     fft_out_valid;
    wire [IDX_WIDTH-1:0]     fft_out_index;
    wire                     fft_done;
    
    reg                      fft_start;
    reg                      fft_inverse;
    reg signed [DATA_WIDTH-1:0] fft_i_in;
    reg signed [DATA_WIDTH-1:0] fft_q_in;
    reg                      fft_in_valid;
    
    wire signed [DATA_WIDTH-1:0] fft_i_out;
    wire signed [DATA_WIDTH-1:0] fft_q_out;

    fft_wrapper #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_fft (
        .clk(clk),
        .rst_n(rst_n),
        .start(fft_start),
        .done(fft_done),
        .inverse(fft_inverse),
        .i_in(fft_i_in),
        .q_in(fft_q_in),
        .in_valid(fft_in_valid),
        .in_ready(fft_in_ready),
        .i_out(fft_i_out),
        .q_out(fft_q_out),
        .out_valid(fft_out_valid),
        .out_index(fft_out_index),
        .out_ready(1'b1)); // Always ready to accept output from FFT


    // =========================================================================
    // 5. Complex Multiplier
    // =========================================================================
    wire signed [DATA_WIDTH-1:0] mult_i_out;
    wire signed [DATA_WIDTH-1:0] mult_q_out;
    wire                         mult_valid;
    reg                          mult_enable;

    complex_multiplier #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .enable(mult_enable),
        .a_i(fft_i_out),
        .a_q(fft_q_out),
        .b_i(rom_i),
        .b_q(rom_q),          // Assumed to be pre-conjugated in the ROM
        .result_i(mult_i_out),
        .result_q(mult_q_out),
        .valid(mult_valid)
    );


    // =========================================================================
    // 6. Peak Detector
    // =========================================================================
    wire                     pd_done;
    wire [IDX_WIDTH-1:0]     pd_best_idx;
    wire [31:0]              pd_peak_mag;
    reg                      pd_start;

    peak_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .FFT_SIZE(FFT_SIZE),
        .IDX_WIDTH(IDX_WIDTH)
    ) u_peak_detector (
        .clk(clk),
        .rst_n(rst_n),
        .start(pd_start),
        .data_valid(fft_out_valid), // IFFT outputs stream directly into peak detector
        .i_in(fft_i_out),
        .q_in(fft_q_out),
        .max_magnitude(pd_peak_mag),
        .max_idx(pd_best_idx),
        .done(pd_done)
    );

    // =========================================================================
    // 7. Main Control State Machine
    // =========================================================================
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_WIPEOFF    = 4'd1;
    localparam [3:0] ST_LOAD_FWD   = 4'd2;
    localparam [3:0] ST_WAIT_FWD   = 4'd3;
    localparam [3:0] ST_MULT       = 4'd4;
    localparam [3:0] ST_LOAD_INV   = 4'd5;
    localparam [3:0] ST_WAIT_INV   = 4'd6;
    localparam [3:0] ST_DONE       = 4'd7;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            done <= 1'b0;
            carrier_phase <= 0;
            sample_cnt <= 0;
            fft_counter <= 0;
            fft_start <= 1'b0;
            fft_inverse <= 1'b0;
            fft_in_valid <= 1'b0;
            mult_enable <= 1'b0;
            pd_start <= 1'b0;
            best_code_phase <= 0;
            peak_magnitude <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    carrier_phase <= 0;
                    sample_cnt <= 0;
                    fft_counter <= 0;
                    if (start) begin
                        state <= ST_WIPEOFF;
                    end
                end

                ST_WIPEOFF: begin
                    if (sample_valid) begin
                        // Wipe-off: (I + jQ) * (cos - j*sin) 
                        i_buf[sample_cnt] <= (i_sample * cos_val + q_sample * sin_val) >>> 17;
                        q_buf[sample_cnt] <= (q_sample * cos_val - i_sample * sin_val) >>> 17;
                        
                        carrier_phase <= carrier_phase + carrier_freq_word;
                        sample_cnt <= sample_cnt + 1;
                        
                        if (sample_cnt == FFT_SIZE - 1) begin
                            state <= ST_LOAD_FWD;
                            sample_cnt <= 0;
                        end
                    end
                end

                ST_LOAD_FWD: begin
                    fft_inverse <= 1'b0;
                    fft_i_in <= i_buf[sample_cnt];
                    fft_q_in <= q_buf[sample_cnt];
                    fft_in_valid <= 1'b1;
                    fft_start <= (sample_cnt == 0); // 1-cycle pulse
                    
                    sample_cnt <= sample_cnt + 1;
                    if (sample_cnt == FFT_SIZE - 1) begin
                        state <= ST_WAIT_FWD;
                        fft_in_valid <= 1'b0;
                    end
                end

                ST_WAIT_FWD: begin
                    if (fft_done) begin
                        state <= ST_MULT;
                        fft_counter <= 0;
                    end
                end

                ST_MULT: begin
                    // Stream enable directly from FFT valid. Multiplier pipelines it perfectly.
                    mult_enable <= fft_out_valid;
                    
                    if (mult_valid) begin
                        mult_i_buf[fft_counter] <= mult_i_out;
                        mult_q_buf[fft_counter] <= mult_q_out;
                        fft_counter <= fft_counter + 1;
                        if (fft_counter == FFT_SIZE - 1) begin
                            state <= ST_LOAD_INV;
                            fft_counter <= 0;
                        end
                    end
                end

                ST_LOAD_INV: begin
                    fft_inverse <= 1'b1;
                    fft_i_in <= mult_i_buf[fft_counter];
                    fft_q_in <= mult_q_buf[fft_counter];
                    fft_in_valid <= 1'b1;
                    fft_start <= (fft_counter == 0);
                    
                    fft_counter <= fft_counter + 1;
                    if (fft_counter == FFT_SIZE - 1) begin
                        state <= ST_WAIT_INV;
                        fft_in_valid <= 1'b0;
                        pd_start <= 1'b1; // Reset peak detector right before IFFT stream starts
                    end
                end

                ST_WAIT_INV: begin
                    pd_start <= 1'b0; // Keep low after 1 cycle
                    if (fft_done) begin
                        // fft_done and pd_done happen on the exact same cycle (the 4096th sample)
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    best_code_phase <= pd_best_idx;
                    peak_magnitude <= pd_peak_mag;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule