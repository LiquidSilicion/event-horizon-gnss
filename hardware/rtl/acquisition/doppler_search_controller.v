module doppler_search_controller #(
    parameter FFT_SIZE = 4096,
    parameter PHASE_BITS = 48,
    parameter NUM_DOPPLER_BINS = 11,
    parameter DOPPLER_STEP_HZ = 1000
)(
    input  wire clk,
    input  wire rst_n,
    
    // Control Interface
    input wire start, // Start the 2D search
    output reg done, // Search complete
    output reg busy, // Search in progress
    
    // Acquisition Engine Interface
    output reg [PHASE_BITS-1:0]  carrier_freq_word,  // Doppler frequency to test
    output reg acq_start, // Pulse to start acquisition
    input wire acq_done, // Acquisition complete signal
    input wire [11:0] acq_code_phase, // Code phase result
    input wire [31:0] acq_peak_mag, // Peak magnitude result
    
    // Output Results
    output reg [PHASE_BITS-1:0] best_doppler_word,  // Best Doppler frequency
    output reg [11:0] best_code_phase,    // Best code phase
    output reg [31:0] best_peak_mag       // Best peak magnitude
);  
    // State definitions
    localparam [3:0] 
        ST_IDLE          = 4'd0,
        ST_CALC_DOPPLER  = 4'd1,  // Calculate NCO word for current bin
        ST_START_ACQ     = 4'd2,  // Pulse acq_start
        ST_WAIT_ACQ      = 4'd3,  // Wait for acq_done
        ST_COMPARE       = 4'd4,  // Compare with global best
        ST_NEXT_BIN      = 4'd5,  // Increment bin counter
        ST_DONE          = 4'd6;

    reg [3:0] state;
    reg [4:0] doppler_bin;        // 0 to NUM_DOPPLER_BINS-1
    
    // 1000 Hz step at 200 MHz clock = (1000 / 200,000,000) * 2^48 = 1,407,374,883,553 = 48'h00000053E2D623
    // We cast doppler_bin to signed so (0 - 5) correctly becomes -5 in 2's complement.
    wire signed [5:0] bin_offset = $signed(doppler_bin) - (NUM_DOPPLER_BINS / 2);
    wire [47:0] calculated_word = bin_offset * 48'h00000053E2D623;

    always @(posedge clk) begin
        if(!rst_n) begin
            state <= ST_IDLE;
            done <= 1'b0;
            busy <= 1'b0;
            doppler_bin <= 5'd0;
            carrier_freq_word <= 48'd0;
            acq_start <= 1'b0;
            best_code_phase <= 12'd0;
            best_peak_mag <= 32'd0;
            best_doppler_word <= 48'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    acq_start <= 1'b0;
                    // TODO: Wait for start, initialize counters
                    if(start) begin
                        busy <=1'b1;
                        doppler_bin <= 5'd0;
                        best_peak_mag <= 32'd0;
                        best_code_phase <= 12'd0;
                        best_doppler_word <= 48'd0;
                        state <= ST_CALC_DOPPLER;
                    end
                end
                
                ST_CALC_DOPPLER: begin
                    // TODO: Calculate carrier_freq_word for current doppler_bin
                    // Transition to ST_START_ACQ
                    carrier_freq_word <= calculated_word;
                    state <= ST_START_ACQ;
                end
                
                ST_START_ACQ: begin
                    // TODO: Assert acq_start for 1-5 cycles
                    // Transition to ST_WAIT_ACQ
                    acq_start <= 1'b1;
                    state <= ST_WAIT_ACQ;
                end
                
                ST_WAIT_ACQ: begin
                    // TODO: Wait until acq_done == 1
                    // Transition to ST_COMPARE
                    acq_start <= 1'b0;
                    if(acq_done) begin
                        state <= ST_COMPARE;
                    end
                end
                
                ST_COMPARE: begin
                    // TODO: Compare acq_peak_mag with best_peak_mag
                    // Update best_* registers if needed
                    // Transition to ST_NEXT_BIN
                    if(acq_peak_mag > best_peak_mag) begin
                        best_peak_mag <= acq_peak_mag;
                        best_code_phase <= acq_code_phase;
                        best_doppler_word <= carrier_freq_word;
                    end
                    state <= ST_NEXT_BIN;
                end
                
                ST_NEXT_BIN: begin
                    // TODO: Increment doppler_bin
                    // If doppler_bin < NUM_DOPPLER_BINS, go to ST_CALC_DOPPLER
                    // Else go to ST_DONE
                    if(doppler_bin < NUM_DOPPLER_BINS -1) begin
                        doppler_bin <= doppler_bin+1;
                        state <= ST_CALC_DOPPLER;
                    end else begin
                        state <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    // TODO: Assert done, transition to ST_IDLE
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule