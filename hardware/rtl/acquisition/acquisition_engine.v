`timescale 1ns / 1ps
//============================================================================
// FFT-Based Acquisition Engine (PCPS Algorithm)
// Implements Parallel Code Phase Search for GPS L1 C/A signals
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
    
    // Control
    input wire start,
    output reg done,
    output reg [4:0] detected_prn,
    output reg signed [15:0] detected_doppler,
    output reg [11:0] detected_code_phase,
    output reg [31:0] peak_magnitude,
    
    // RF Sample Input (From DMA/ADC)
    input wire signed [15:0] i_sample,
    input wire signed [15:0] q_sample,
    input wire sample_valid,
    
    // Status
    output reg busy
);

    // State machine
    localparam [3:0] IDLE = 0,
                     LOAD_SAMPLES = 1,
                     CARRIER_WIPEOFF = 2,
                     FFT_INPUT = 3,
                     WAIT_FFT_INPUT = 4,
                     MULTIPLY = 5,
                     IFFT = 6,
                     WAIT_IFFT = 7,
                     PEAK_DETECT = 8,
                     NEXT_DOPPLER = 9,
                     NEXT_PRN = 10,
                     DONE_STATE = 11;
    
    reg [3:0] state;
    
    // Sample buffer (store 1ms of data)
    reg signed [DATA_WIDTH-1:0] i_buffer [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] q_buffer [0:FFT_SIZE-1];
    reg [11:0] sample_counter;
    
    // Carrier NCO for Doppler wipe-off
    reg [PHASE_BITS-1:0] carrier_phase;
    wire [11:0] carrier_idx = carrier_phase[PHASE_BITS-1 -: 12];
    
    // Sine/Cosine lookup (18-bit signed)
    reg signed [DATA_WIDTH-1:0] sin_table [0:4095];
    reg signed [DATA_WIDTH-1:0] cos_table [0:4095];
    
    // Carrier frequency word calculation
    // freq_word = (doppler / sample_rate) * 2^48
    reg signed [PHASE_BITS-1:0] carrier_freq_word;
    
    // FFT input/output
    reg signed [DATA_WIDTH-1:0] fft_i_in, fft_q_in;
    reg fft_in_valid;
    wire signed [DATA_WIDTH-1:0] fft_i_out, fft_q_out;
    wire fft_out_valid;
    wire [11:0] fft_out_index;
    
    // Complex multiplier
    reg signed [DATA_WIDTH-1:0] mult_i_in, mult_q_in;
    reg signed [DATA_WIDTH-1:0] code_fft_i, code_fft_q;
    reg mult_start;
    wire signed [DATA_WIDTH-1:0] mult_i_out, mult_q_out;
    wire mult_done;
    
    // PRN FFT BRAM
    reg signed [DATA_WIDTH-1:0] prn_fft_i [0:32*FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] prn_fft_q [0:32*FFT_SIZE-1];
    
    // Search parameters
    reg [4:0] prn_counter;
    reg signed [15:0] doppler_counter;
    reg [11:0] fft_counter;
    
    // Peak detection
    reg [31:0] current_peak;
    reg [11:0] current_peak_idx;
    reg [31:0] global_peak;
    reg [11:0] global_peak_idx;
    reg [4:0] global_peak_prn;
    reg signed [15:0] global_peak_doppler;
    
    // Initialize sine/cosine tables
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            sin_table[i] = $rtoi($sin(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
            cos_table[i] = $rtoi($cos(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
        end
    end
    
    // Load PRN FFT data from hex files
    integer prn;
    initial begin
        for (prn = 1; prn <= 32; prn = prn + 1) begin
            $readmemh($sformatf("prn%02d_fft.hex", prn), 
                      prn_fft_i[(prn-1)*FFT_SIZE : prn*FFT_SIZE-1]);
            $readmemh($sformatf("prn%02d_fft_q.hex", prn), 
                      prn_fft_q[(prn-1)*FFT_SIZE : prn*FFT_SIZE-1]);
        end
    end
    
    // FFT IP instantiation (Xilinx FFT IP)
    fft_wrapper #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_fft (
        .clk(clk),
        .rst_n(rst_n),
        .start(state == FFT_INPUT || state == IFFT),
        .inverse(state == IFFT),
        .i_in(fft_i_in),
        .q_in(fft_q_in),
        .in_valid(fft_in_valid),
        .i_out(fft_i_out),
        .q_out(fft_q_out),
        .out_valid(fft_out_valid),
        .out_index(fft_out_index),
        .done()
    );
    
    // Complex multiplier instantiation
    complex_multiplier #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mult (
        .clk(clk),
        .rst_n(rst_n),
        .start(mult_start),
        .a_i(mult_i_in),
        .a_q(mult_q_in),
        .b_i(code_fft_i),
        .b_q(code_fft_q),
        .result_i(mult_i_out),
        .result_q(mult_q_out),
        .done(mult_done)
    );
    
    // Main state machine
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
            prn_counter <= 1;
            doppler_counter <= DOPPLER_MIN;
            sample_counter <= 0;
            fft_counter <= 0;
            global_peak <= 0;
            global_peak_idx <= 0;
            global_peak_prn <= 0;
            global_peak_doppler <= 0;
            carrier_phase <= 0;
            fft_in_valid <= 0;
            mult_start <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    busy <= 0;
                    if (start) begin
                        state <= LOAD_SAMPLES;
                        busy <= 1;
                        sample_counter <= 0;
                        prn_counter <= 1;
                        doppler_counter <= DOPPLER_MIN;
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
                            sample_counter <= 0;
                            carrier_phase <= 0;
                            // Calculate carrier frequency word
                            carrier_freq_word <= (doppler_counter * 2**48) / SAMPLE_RATE;
                        end
                    end
                end
                
                CARRIER_WIPEOFF: begin
                    // Carrier wipe-off: multiply by e^(-j*2*pi*doppler*t)
                    // i_wiped = i*cos + q*sin
                    // q_wiped = q*cos - i*sin
                    carrier_phase <= carrier_phase + carrier_freq_word;
                    
                    // Store wiped-off samples back to buffer
                    i_buffer[sample_counter] <= (i_buffer[sample_counter] * cos_table[carrier_idx] + 
                                                  q_buffer[sample_counter] * sin_table[carrier_idx]) >>> 17;
                    q_buffer[sample_counter] <= (q_buffer[sample_counter] * cos_table[carrier_idx] - 
                                                  i_buffer[sample_counter] * sin_table[carrier_idx]) >>> 17;
                    
                    sample_counter <= sample_counter + 1;
                    if (sample_counter == FFT_SIZE - 1) begin
                        state <= FFT_INPUT;
                        sample_counter <= 0;
                        fft_counter <= 0;
                    end
                end
                
                FFT_INPUT: begin
                    // Feed samples to FFT
                    fft_i_in <= i_buffer[sample_counter];
                    fft_q_in <= q_buffer[sample_counter];
                    fft_in_valid <= 1;
                    sample_counter <= sample_counter + 1;
                    if (sample_counter == FFT_SIZE - 1) begin
                        state <= WAIT_FFT_INPUT;
                        fft_in_valid <= 0;
                    end
                end
                
                WAIT_FFT_INPUT: begin
                    if (fft_out_valid) begin
                        state <= MULTIPLY;
                        fft_counter <= 0;
                    end
                end
                
                MULTIPLY: begin
                    // Multiply FFT(input) with conjugate(FFT(local_code))
                    // Conjugate means: (a+jb)* = a-jb
                    mult_i_in <= fft_i_out;
                    mult_q_in <= fft_q_out;
                    code_fft_i <= prn_fft_i[(prn_counter-1)*FFT_SIZE + fft_counter];
                    code_fft_q <= -prn_fft_q[(prn_counter-1)*FFT_SIZE + fft_counter]; // Conjugate
                    mult_start <= 1;
                    
                    if (mult_done) begin
                        mult_start <= 0;
                        fft_counter <= fft_counter + 1;
                        if (fft_counter == FFT_SIZE - 1) begin
                            state <= IFFT;
                            fft_counter <= 0;
                        end
                    end
                end
                
                IFFT: begin
                    // Feed multiplied result to IFFT
                    fft_i_in <= mult_i_out;
                    fft_q_in <= mult_q_out;
                    fft_in_valid <= 1;
                    fft_counter <= fft_counter + 1;
                    if (fft_counter == FFT_SIZE - 1) begin
                        state <= WAIT_IFFT;
                        fft_in_valid <= 0;
                    end
                end
                
                WAIT_IFFT: begin
                    if (fft_out_valid) begin
                        state <= PEAK_DETECT;
                        fft_counter <= 0;
                        current_peak <= 0;
                        current_peak_idx <= 0;
                    end
                end
                
                PEAK_DETECT: begin
                    // Find peak magnitude: |I + jQ|^2 = I^2 + Q^2
                    if (fft_out_valid) begin
                        automatic logic [31:0] magnitude = (fft_i_out * fft_i_out + fft_q_out * fft_q_out) >>> 16;
                        if (magnitude > current_peak) begin
                            current_peak <= magnitude;
                            current_peak_idx <= fft_out_index;
                        end
                        fft_counter <= fft_counter + 1;
                        if (fft_counter == FFT_SIZE - 1) begin
                            state <= NEXT_DOPPLER;
                            // Update global peak if needed
                            if (current_peak > global_peak) begin
                                global_peak <= current_peak;
                                global_peak_idx <= current_peak_idx;
                                global_peak_prn <= prn_counter;
                                global_peak_doppler <= doppler_counter;
                            end
                        end
                    end
                end
                
                NEXT_DOPPLER: begin
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
                    done <= 1;
                    busy <= 0;
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