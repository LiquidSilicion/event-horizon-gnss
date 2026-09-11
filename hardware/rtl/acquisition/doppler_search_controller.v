`timescale 1ns / 1ps

module doppler_search_controller #(
    parameter FFT_SIZE = 4096,
    parameter PHASE_BITS = 48,
    parameter NUM_COARSE_BINS = 11,
    parameter COARSE_STEP_HZ = 1000,
    parameter NUM_FINE_BINS = 21,
    parameter FINE_STEP_HZ = 50,
    parameter NUM_PRNS = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    input  wire                     start,
    output reg                      done,
    output reg                      busy,
    
    // Outputs to acquisition engine
    output reg  [PHASE_BITS-1:0]    carrier_freq_word,
    output reg                      acq_start,
    input  wire                     acq_done,
    input  wire [11:0]              acq_code_phase,
    input  wire [31:0]              acq_peak_mag,
    
    // PRN selection output
    output reg  [4:0]               prn_sel_out,
    
    // Final results
    output reg  [PHASE_BITS-1:0]    best_doppler_word,
    output reg  [11:0]              best_code_phase,
    output reg  [31:0]              best_peak_mag,
    output reg  [4:0]               best_prn
);

    // Frequency step words (Based on 200 MHz clock)
    localparam [PHASE_BITS-1:0] COARSE_STEP_WORD = 48'h000053E2D623;
    localparam [PHASE_BITS-1:0] FINE_STEP_WORD   = 48'h00000431B820;

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
    reg [4:0] prn_counter;
    reg       search_stage;  // 0 = coarse, 1 = fine
    
    // Save coarse search results for fine search centering
    reg [PHASE_BITS-1:0] coarse_best_freq;
    reg [11:0]           coarse_best_code_phase;
    reg [31:0]           coarse_best_mag;
    
    // Global best across all PRNs
    reg [PHASE_BITS-1:0] global_best_freq;
    reg [11:0]           global_best_code_phase;
    reg [31:0]           global_best_mag;
    reg [4:0]            global_best_prn;
    
    // Current bin's frequency word calculation
    wire signed [5:0] coarse_offset = $signed(doppler_bin) - (NUM_COARSE_BINS / 2);
    wire [PHASE_BITS-1:0] coarse_word = coarse_offset * COARSE_STEP_WORD;
    
    wire signed [5:0] fine_offset = $signed(doppler_bin) - (NUM_FINE_BINS / 2);
    wire [PHASE_BITS-1:0] fine_word = coarse_best_freq + (fine_offset * FINE_STEP_WORD);

    always @(posedge clk) begin
        if (!rst_n) begin
            state                <= ST_IDLE;
            done                 <= 1'b0;
            busy                 <= 1'b0;
            acq_start            <= 1'b0;
            doppler_bin          <= 5'd0;
            prn_counter          <= 5'd1;       // ✅ CORRECT: Start at 1
            search_stage         <= 1'b0;
            carrier_freq_word    <= 48'd0;
            prn_sel_out          <= 5'd1;       // ✅ CORRECT: Start at 1
            coarse_best_freq     <= 48'd0;
            coarse_best_code_phase <= 12'd0;
            coarse_best_mag      <= 32'd0;
            global_best_freq     <= 48'd0;
            global_best_code_phase <= 12'd0;
            global_best_mag      <= 32'd0;
            global_best_prn      <= 5'd0;
            best_doppler_word    <= 48'd0;
            best_code_phase      <= 12'd0;
            best_peak_mag        <= 32'd0;
            best_prn             <= 5'd0;
        end else begin
            acq_start <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    done  <= 1'b0;
                    busy  <= 1'b0;
                    if (start) begin
                        busy                 <= 1'b1;
                        prn_counter          <= 5'd1;       // Start counting at PRN 1
                        search_stage         <= 1'b0;
                        doppler_bin          <= 5'd0;
                        global_best_mag      <= 32'd0;
                        global_best_freq     <= 48'd0;
                        global_best_code_phase <= 12'd0;
                        global_best_prn      <= 5'd0;
                        prn_sel_out          <= 5'd0;       // ROM address for PRN 1 is 0
                        state                <= ST_CALC_DOPPLER;
                    end
                end
                
                ST_CALC_DOPPLER: begin
                    if (search_stage == 1'b0)
                        carrier_freq_word <= coarse_word;
                    else
                        carrier_freq_word <= fine_word;
                    
                    acq_start <= 1'b1;
                    state <= ST_START_ACQ;
                end
                
                ST_START_ACQ: begin
                    acq_start <= 1'b0;
                    state <= ST_WAIT_ACQ;
                end
                
                ST_WAIT_ACQ: begin
                    if (acq_done) begin
                        state <= ST_COMPARE;
                    end
                end
                
                ST_COMPARE: begin
                    if (search_stage == 1'b0) begin
                        if (acq_peak_mag > coarse_best_mag) begin
                            coarse_best_mag        <= acq_peak_mag;
                            coarse_best_freq       <= carrier_freq_word;
                            coarse_best_code_phase <= acq_code_phase;
                        end
                    end else begin
                        if (acq_peak_mag > global_best_mag) begin
                            global_best_mag        <= acq_peak_mag;
                            global_best_freq       <= carrier_freq_word;
                            global_best_code_phase <= acq_code_phase;
                            global_best_prn        <= prn_counter; // ✅ CORRECT: Stores 1 to NUM_PRNS
                        end
                    end
                    state <= ST_NEXT_BIN;
                end
                
                ST_NEXT_BIN: begin
                    if (search_stage == 1'b0) begin
                        if (doppler_bin < NUM_COARSE_BINS - 1) begin
                            doppler_bin <= doppler_bin + 1;
                            state <= ST_CALC_DOPPLER;
                        end else begin
                            search_stage <= 1'b1;
                            doppler_bin  <= 5'd0;
                            state <= ST_CALC_DOPPLER;
                        end
                    end else begin
                        if (doppler_bin < NUM_FINE_BINS - 1) begin
                            doppler_bin <= doppler_bin + 1;
                            state <= ST_CALC_DOPPLER;
                        end else begin
                            // Check against NUM_PRNS (e.g., < 16)
                            if (prn_counter < NUM_PRNS) begin 
                                prn_counter  <= prn_counter + 1;
                                prn_sel_out  <= prn_counter;  // ROM address becomes 1, 2, ... 15
                                search_stage <= 1'b0;
                                doppler_bin  <= 5'd0;
                                coarse_best_mag <= 32'd0;
                                state <= ST_CALC_DOPPLER;
                            end else begin
                                state <= ST_DONE;
                            end
                        end
                    end
                end
                
                ST_DONE: begin
                    done            <= 1'b1;
                    busy            <= 1'b0;
                    best_doppler_word <= global_best_freq;
                    best_code_phase <= global_best_code_phase;
                    best_peak_mag   <= global_best_mag;
                    best_prn        <= global_best_prn;
                    state <= ST_IDLE;
                end
                
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule