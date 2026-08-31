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

    // ==========================================
    // Peak Detection Magnitude Calculation Wires
    // ==========================================
    // 18-bit * 18-bit = 36-bit. We use $unsigned to ensure the square is treated as positive.
    wire [35:0] i_sq = $unsigned(fft_i_out) * $unsigned(fft_i_out);
    wire [35:0] q_sq = $unsigned(fft_q_out) * $unsigned(fft_q_out);
    
    // 36-bit + 36-bit = 37-bit max
    wire [36:0] mag_sum = i_sq + q_sq;
    
    // Shift right by 16 bits to scale down, and zero-extend to 32 bits for comparison
    wire [31:0] magnitude = {11'b0, mag_sum[36:16]}; 
    
    // Initialize sine/cosine tables
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            sin_table[i] = $rtoi($sin(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
            cos_table[i] = $rtoi($cos(i * 2.0 * 3.14159265 / 4096.0) * 131071.0);
        end
    end

    initial begin
        // Load the combined master files
        // Use absolute paths if XSim complains about file not found, 
        // just like you did for ca_code_all_prns.hex
        $readmemh("all_prns_fft_i.hex", prn_fft_i);
        $readmemh("all_prns_fft_q.hex", prn_fft_q);
        
        $display("✅ ALL PRN FFT ROMS LOADED SUCCESSFULLY FROM MASTER FILES");
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
                    // Find peak magnitude using the pre-calculated wire
                    if (fft_out_valid) begin
                        if (magnitude > current_peak) begin
                            current_peak <= magnitude;
                            current_peak_idx <= fft_out_index;
                        end
                        
                        fft_counter <= fft_counter + 1;
                        
                        // Check if we have processed all FFT bins for this Doppler hypothesis
                        if (fft_counter == FFT_SIZE - 1) begin
                            state <= NEXT_DOPPLER;
                            
                            // Update global peak if this Doppler bin had the highest peak
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

    //============================================================================
    // 1. WIRE DECLARATIONS (Connect these to your Xilinx FFT IP outputs)
    //============================================================================
    wire ifft_source_valid;          // Maps to FFT IP: m_axis_data_tvalid
    wire ifft_source_tlast;          // Maps to FFT IP: m_axis_data_tlast (Crucial for frame sync!)
    wire signed [17:0] ifft_source_real; // Maps to FFT IP: m_axis_data_tdata[17:0]
    wire signed [17:0] ifft_source_imag; // Maps to FFT IP: m_axis_data_tdata[35:18]

    // Note: Adjust the bit slicing [35:18] and [17:0] based on your specific 
    // Xilinx FFT IP configuration (e.g., if it outputs {imag, real} or {real, imag}).

    //============================================================================
    // 2. MAGNITUDE CALCULATOR INSTANTIATION
    //============================================================================
    wire [31:0] current_magnitude;

    magnitude_squared #(
        .DATA_WIDTH(18),      // Assuming 18-bit signed input from IFFT
        .SHIFT_AMOUNT(16)     // Shift right by 16 to prevent overflow and scale
    ) u_mag_calc (
        .clk(clk),
        .rst_n(rst_n),
        .i_in(ifft_source_real),   
        .q_in(ifft_source_imag),   
        .mag_out(current_magnitude)
    );

    //============================================================================
    // 3. IMPROVED PEAK DETECTOR LOGIC
    //============================================================================
    reg [31:0] max_mag;
    reg [11:0] best_code_phase; 
    reg [11:0] current_bin_idx;

    // Control signal: Assert this for 1 clock cycle when starting a NEW Doppler bin search
    // This ensures we find the peak *for the current Doppler hypothesis*, not globally across all time.
    wire reset_peak_detector; 

    always @(posedge clk) begin
        if (!rst_n) begin
            max_mag <= 32'd0;
            best_code_phase <= 12'd0;
            current_bin_idx <= 12'd0;
        end 
        else if (reset_peak_detector) begin
            // Reset for the new Doppler bin search
            max_mag <= 32'd0;
            best_code_phase <= 12'd0;
            current_bin_idx <= 12'd0;
        end
        else if (ifft_source_valid) begin 
            
            // 1. Update peak if current magnitude is strictly higher
            if (current_magnitude > max_mag) begin
                max_mag <= current_magnitude;
                best_code_phase <= current_bin_idx;
            end
            
            // 2. Increment bin index (wraps at 4096 for a 4096-point FFT)
            if (current_bin_idx == 12'd4095) begin
                current_bin_idx <= 12'd0;
            end else begin
                current_bin_idx <= current_bin_idx + 12'd1;
            end
        end
    end

    //============================================================================
    // 4. (OPTIONAL BUT RECOMMENDED) CAPTURE RESULT ON FRAME END
    //============================================================================
    // When the FFT outputs the last sample of the frame, we know the search for 
    // this Doppler bin is complete. We can latch the results here.
    reg [31:0] final_max_mag;
    reg [11:0] final_best_code_phase;
    reg search_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            final_max_mag <= 32'd0;
            final_best_code_phase <= 12'd0;
            search_done <= 1'b0;
        end
        else if (ifft_source_valid && ifft_source_tlast) begin
            final_max_mag <= max_mag;
            final_best_code_phase <= best_code_phase;
            search_done <= 1'b1; // Tell the state machine this Doppler bin is done
        end
        else begin
            search_done <= 1'b0;
        end
    end

endmodule