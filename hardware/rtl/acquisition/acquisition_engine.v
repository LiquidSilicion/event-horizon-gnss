`timescale 1ns / 1ps
//============================================================================
// FFT-Based Acquisition Engine (PCPS Algorithm)
//============================================================================
module acquisition_engine #(
    parameter FFT_SIZE = 4096,
    parameter DATA_WIDTH = 18,
    parameter PHASE_BITS = 48,
    parameter DOPPLER_MIN = -10000,
    parameter DOPPLER_MAX = 10000,
    parameter DOPPLER_STEP = 500,
    parameter SAMPLE_RATE = 4000000
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    output reg done,
    output reg [4:0] detected_prn,
    output reg signed [15:0] detected_doppler,
    output reg [11:0] detected_code_phase,
    output reg [31:0] peak_magnitude,
    input wire signed [15:0] i_sample,
    input wire signed [15:0] q_sample,
    input wire sample_valid,
    output reg busy
);

    localparam [3:0] IDLE = 0, LOAD_SAMPLES = 1, CARRIER_WIPEOFF = 2,
                     FFT_FWD_START = 3, FFT_FWD_FEED = 4, WAIT_FWD = 5,
                     MULTIPLY = 6, FFT_INV_START = 7, FFT_INV_FEED = 8, WAIT_INV = 9,
                     PEAK_DETECT = 10, NEXT_DOPPLER = 11, NEXT_PRN = 12, DONE_STATE = 13;
    
    reg [3:0] state;
    
    // Buffers
    reg signed [DATA_WIDTH-1:0] i_buffer [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] q_buffer [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] fft_i_mem [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] fft_q_mem [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mult_i_mem [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mult_q_mem [0:FFT_SIZE-1];
    
    reg [11:0] sample_counter, fft_counter;
    
    // NCO
    reg [PHASE_BITS-1:0] carrier_phase;
    wire [11:0] carrier_idx = carrier_phase[PHASE_BITS-1 -: 12];
    reg signed [DATA_WIDTH-1:0] sin_table [0:4095];
    reg signed [DATA_WIDTH-1:0] cos_table [0:4095];
    reg signed [PHASE_BITS-1:0] carrier_freq_word;
    
    // FFT Interface
    reg fft_start, fft_inverse;
    reg signed [DATA_WIDTH-1:0] fft_i_in, fft_q_in;
    reg fft_in_valid;
    wire signed [DATA_WIDTH-1:0] fft_i_out, fft_q_out;
    wire fft_out_valid;
    wire [11:0] fft_out_index;
    wire fft_done, fft_in_ready;
    
    // Multiplier Interface
    reg mult_enable;
    reg signed [DATA_WIDTH-1:0] mult_a_i, mult_a_q, mult_b_i, mult_b_q;
    wire signed [DATA_WIDTH-1:0] mult_result_i, mult_result_q;
    wire mult_valid;
    
    // PRN FFT BRAM
    (* rom_style = "block" *) reg signed [DATA_WIDTH-1:0] prn_fft_i [0:32*FFT_SIZE-1];
    (* rom_style = "block" *) reg signed [DATA_WIDTH-1:0] prn_fft_q [0:32*FFT_SIZE-1];
    
    // Search & Peak Detection
    reg [4:0] prn_counter;
    reg signed [15:0] doppler_counter;
    reg [31:0] current_peak, global_peak;
    reg [11:0] current_peak_idx, global_peak_idx;
    reg [4:0] global_peak_prn;
    reg signed [15:0] global_peak_doppler;

    // Magnitude Calculation (I^2 + Q^2)
    wire [35:0] i_sq = $unsigned(fft_i_out) * $unsigned(fft_i_out);
    wire [35:0] q_sq = $unsigned(fft_q_out) * $unsigned(fft_q_out);
    wire [36:0] mag_sum = i_sq + q_sq;
    wire [31:0] magnitude = {11'b0, mag_sum[36:16]}; 
    
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            sin_table[i] = $rtoi($sin(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
            cos_table[i] = $rtoi($cos(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
        end
        $readmemh("all_prns_fft_i.hex", prn_fft_i);
        $readmemh("all_prns_fft_q.hex", prn_fft_q);
        $display("✅ ALL PRN FFT ROMS LOADED SUCCESSFULLY");
    end
    
    fft_wrapper #(.FFT_SIZE(FFT_SIZE), .DATA_WIDTH(DATA_WIDTH)) u_fft (
        .clk(clk), .rst_n(rst_n), .start(fft_start), .done(fft_done),
        .i_in(fft_i_in), .q_in(fft_q_in), .in_valid(fft_in_valid), .in_ready(fft_in_ready),
        .i_out(fft_i_out), .q_out(fft_q_out), .out_index(fft_out_index),
        .out_valid(fft_out_valid), .out_ready(1'b1), .inverse(fft_inverse)
    );
    
    complex_multiplier #(.DATA_WIDTH(DATA_WIDTH)) u_mult (
        .clk(clk), .rst_n(rst_n), .enable(mult_enable),
        .a_i(mult_a_i), .a_q(mult_a_q), .b_i(mult_b_i), .b_q(mult_b_q),
        .result_i(mult_result_i), .result_q(mult_result_q), .valid(mult_valid)
    );
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE; done <= 0; busy <= 0;
            prn_counter <= 1; doppler_counter <= DOPPLER_MIN;
            global_peak <= 0; fft_start <= 0; fft_in_valid <= 0; mult_enable <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0; busy <= 0;
                    if (start) begin
                        state <= LOAD_SAMPLES; busy <= 1;
                        sample_counter <= 0; prn_counter <= 1; doppler_counter <= DOPPLER_MIN;
                        global_peak <= 0;
                    end
                end
                
                LOAD_SAMPLES: begin
                    if (sample_valid) begin
                        i_buffer[sample_counter] <= i_sample;
                        q_buffer[sample_counter] <= q_sample;
                        sample_counter <= sample_counter + 1;
                        if (sample_counter == FFT_SIZE - 1) begin
                            state <= CARRIER_WIPEOFF;
                            sample_counter <= 0; carrier_phase <= 0;
                            carrier_freq_word <= (doppler_counter * 48'h000010624DD2F1) / SAMPLE_RATE; // 2^48
                        end
                    end
                end
                
                CARRIER_WIPEOFF: begin
                    carrier_phase <= carrier_phase + carrier_freq_word;
                    i_buffer[sample_counter] <= (i_buffer[sample_counter] * cos_table[carrier_idx] + q_buffer[sample_counter] * sin_table[carrier_idx]) >>> 17;
                    q_buffer[sample_counter] <= (q_buffer[sample_counter] * cos_table[carrier_idx] - i_buffer[sample_counter] * sin_table[carrier_idx]) >>> 17;
                    sample_counter <= sample_counter + 1;
                    if (sample_counter == FFT_SIZE - 1) begin
                        state <= FFT_FWD_START;
                        sample_counter <= 0; fft_counter <= 0;
                    end
                end
                
                FFT_FWD_START: begin
                    fft_start <= 1; fft_inverse <= 0;
                    state <= FFT_FWD_FEED;
                end
                
                FFT_FWD_FEED: begin
                    fft_start <= 0;
                    fft_i_in <= i_buffer[sample_counter];
                    fft_q_in <= q_buffer[sample_counter];
                    fft_in_valid <= 1;
                    sample_counter <= sample_counter + 1;
                    if (sample_counter == FFT_SIZE) state <= WAIT_FWD;
                end
                
                WAIT_FWD: begin
                    fft_in_valid <= 0;
                    if (fft_out_valid) begin
                        fft_i_mem[fft_counter] <= fft_i_out;
                        fft_q_mem[fft_counter] <= fft_q_out;
                        fft_counter <= fft_counter + 1;
                        if (fft_counter == FFT_SIZE) begin
                            state <= MULTIPLY;
                            fft_counter <= 0;
                        end
                    end
                end
                
                MULTIPLY: begin
                    mult_enable <= 1;
                    mult_a_i <= fft_i_mem[fft_counter];
                    mult_a_q <= fft_q_mem[fft_counter];
                    mult_b_i <= prn_fft_i[(prn_counter-1)*FFT_SIZE + fft_counter];
                    mult_b_q <= -prn_fft_q[(prn_counter-1)*FFT_SIZE + fft_counter]; // Conjugate
                    
                    if (mult_valid) begin
                        mult_i_mem[fft_counter] <= mult_result_i;
                        mult_q_mem[fft_counter] <= mult_result_q;
                        fft_counter <= fft_counter + 1;
                        if (fft_counter == FFT_SIZE) begin
                            state <= FFT_INV_START;
                            fft_counter <= 0; mult_enable <= 0;
                        end
                    end
                end
                
                FFT_INV_START: begin
                    fft_start <= 1; fft_inverse <= 1;
                    state <= FFT_INV_FEED;
                end
                
                FFT_INV_FEED: begin
                    fft_start <= 0;
                    fft_i_in <= mult_i_mem[sample_counter];
                    fft_q_in <= mult_q_mem[sample_counter];
                    fft_in_valid <= 1;
                    sample_counter <= sample_counter + 1;
                    if (sample_counter == FFT_SIZE) state <= WAIT_INV;
                end
                
                WAIT_INV: begin
                    fft_in_valid <= 0;
                    if (fft_out_valid) begin
                        // Peak detection happens on the fly during IFFT output
                        if (magnitude > current_peak) begin
                            current_peak <= magnitude;
                            current_peak_idx <= fft_out_index;
                        end
                        fft_counter <= fft_counter + 1;
                        if (fft_counter == FFT_SIZE) state <= NEXT_DOPPLER;
                    end
                end
                
                NEXT_DOPPLER: begin
                    if (current_peak > global_peak) begin
                        global_peak <= current_peak;
                        global_peak_idx <= current_peak_idx;
                        global_peak_prn <= prn_counter;
                        global_peak_doppler <= doppler_counter;
                    end
                    current_peak <= 0; fft_counter <= 0;
                    
                    doppler_counter <= doppler_counter + DOPPLER_STEP;
                    if (doppler_counter >= DOPPLER_MAX) begin
                        state <= NEXT_PRN;
                        doppler_counter <= DOPPLER_MIN;
                    end else begin
                        state <= LOAD_SAMPLES;
                        sample_counter <= 0;
                    end
                end
                
                NEXT_PRN: begin
                    prn_counter <= prn_counter + 1;
                    if (prn_counter > 32) begin
                        state <= DONE_STATE;
                    end else begin
                        state <= LOAD_SAMPLES;
                        sample_counter <= 0;
                        doppler_counter <= DOPPLER_MIN;
                    end
                end
                
                DONE_STATE: begin
                    done <= 1; busy <= 0;
                    detected_prn <= global_peak_prn;
                    detected_doppler <= global_peak_doppler;
                    detected_code_phase <= global_peak_idx;
                    peak_magnitude <= global_peak;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule