`timescale 1ns / 1ps

module doppler_search_controller #(
    parameter FFT_SIZE = 4096,
    parameter PHASE_BITS = 48,
    parameter NUM_DOPPLER_BINS = 11,
    parameter DOPPLER_STEP_HZ = 1000
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    input  wire                     start,              // Start the entire 2D search
    output reg                      done,               // Search complete
    output reg                      busy,               // Search in progress
    
    output reg  [PHASE_BITS-1:0]    carrier_freq_word,  // Doppler frequency to test
    output reg                      acq_start,          // Pulse to start acquisition for THIS bin
    input  wire                     acq_done,           // Acquisition complete for this bin
    input  wire [11:0]              acq_code_phase,     // Code phase result for this bin
    input  wire [31:0]              acq_peak_mag,       // Peak magnitude result for this bin
    
    output reg  [PHASE_BITS-1:0]    best_doppler_word,  // Best Doppler frequency
    output reg  [11:0]              best_code_phase,    // Best code phase
    output reg  [31:0]              best_peak_mag       // Best peak magnitude
);

    localparam [3:0] 
        ST_IDLE          = 4'd0,
        ST_CALC_DOPPLER  = 4'd1,  
        ST_START_ACQ     = 4'd2,  
        ST_WAIT_ACQ      = 4'd3,  
        ST_COMPARE       = 4'd4,  
        ST_NEXT_BIN      = 4'd5,  
        ST_DONE          = 4'd6;

    reg [3:0] state;
    reg [4:0] doppler_bin;
    
    // Calculate the frequency word for the current bin
    wire signed [5:0] bin_offset = $signed(doppler_bin) - (NUM_DOPPLER_BINS / 2);
    wire [47:0] calculated_word = bin_offset * 48'h00000053E2D623; // 1000 Hz step @ 200 MHz

    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            done            <= 1'b0;
            busy            <= 1'b0;
            acq_start       <= 1'b0;
            doppler_bin     <= 5'd0;
            carrier_freq_word <= 48'd0;
            best_peak_mag   <= 32'd0;
            best_code_phase <= 12'd0;
            best_doppler_word <= 48'd0;
        end else begin
            // Default: deassert pulse
            acq_start <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        doppler_bin <= 5'd0;
                        best_peak_mag   <= 32'd0;
                        best_code_phase <= 12'd0;
                        best_doppler_word <= 48'd0;
                        state <= ST_CALC_DOPPLER;
                    end
                end
                
                ST_CALC_DOPPLER: begin
                    carrier_freq_word <= calculated_word;
                    acq_start <= 1'b1; // ✅ FIX: Pulse acq_start for EVERY bin to clear NCI
                    state <= ST_START_ACQ;
                end
                
                ST_START_ACQ: begin
                    acq_start <= 1'b0; // ✅ FIX: Deassert after 1 cycle
                    state <= ST_WAIT_ACQ;
                end
                
                ST_WAIT_ACQ: begin
                    if (acq_done) begin
                        state <= ST_COMPARE;
                    end
                end
                
                ST_COMPARE: begin
                    // Compare this bin's result with the global best
                    if (acq_peak_mag > best_peak_mag) begin
                        best_peak_mag   <= acq_peak_mag;
                        best_code_phase <= acq_code_phase;
                        best_doppler_word <= carrier_freq_word;
                    end
                    state <= ST_NEXT_BIN;
                end
                
                ST_NEXT_BIN: begin
                    if (doppler_bin < NUM_DOPPLER_BINS - 1) begin
                        doppler_bin <= doppler_bin + 1;
                        state <= ST_CALC_DOPPLER; // ✅ Loop back and pulse acq_start again
                    end else begin
                        state <= ST_DONE;
                    end
                end
                
                ST_DONE: begin
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