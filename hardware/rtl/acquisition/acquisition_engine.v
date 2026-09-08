`timescale 1ns / 1ps

module acquisition_engine #(
    parameter FFT_SIZE = 4096,
    parameter DATA_WIDTH = 18,
    parameter PHASE_BITS = 48,
    parameter IDX_WIDTH = 12,
    parameter NUM_DOPPLER_BINS = 11,
    parameter DOPPLER_STEP_HZ = 1000,
    parameter NCI_FRAMES = 20
)(
    input  wire clk_100,
    input  wire clk_200,
    input  wire rst_n,
    
    input  wire start,           
    output wire done,            
    output wire busy,            
    
    input  wire signed [15:0] i_sample,
    input  wire signed [15:0] q_sample,
    input  wire sample_valid,
    
    input  wire [4:0] prn_sel,
    
    output wire [PHASE_BITS-1:0] best_doppler_word,
    output wire [IDX_WIDTH-1:0] best_code_phase,
    output wire [7:0] best_code_phase_frac,  // ✅ Fractional chip offset
    output wire [31:0] peak_magnitude
    output wire [4:0] best_prn,  // ✅ NEW: Which satellite was found
);

    reg load_fwd_wait;
    reg load_inv_wait;

    wire signed [17:0] fifo_i_out;
    wire signed [17:0] fifo_q_out;
    wire               fifo_data_valid;
    wire               fifo_last_out;
    wire               fifo_full;
    wire               fifo_empty;
    reg                fifo_rd_enable;

    wire signed [17:0] i_ext = {{2{i_sample[15]}}, i_sample};
    wire signed [17:0] q_ext = {{2{q_sample[15]}}, q_sample};

    wire [PHASE_BITS-1:0] carrier_freq_word;
    wire                  acq_start;
    reg                   acq_done;
    reg [IDX_WIDTH-1:0]   acq_code_phase;
    reg [31:0]            acq_peak_mag;
    wire                  fft_tlast;

    // ✅ Interpolation Tracking Registers
    reg [31:0] prev_bin_mag;   // Tracks magnitude of bin k-1
    reg [31:0] last_bin_mag;   // Tracks magnitude of bin 4095 (for wrap-around)
    reg [31:0] mag_minus_1;    // Final magnitude for interpolator
    reg [31:0] mag_plus_1;     // Final magnitude for interpolator
    
    reg [4:0] nci_count;
    reg       acq_start_latched;
    reg       interp_start;    // Trigger parabolic interpolator

    // =========================================================================
    // Local State Machine
    // =========================================================================
    reg [3:0] state;
    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_WAIT_FIFO    = 4'd1;
    localparam [3:0] ST_WIPEOFF      = 4'd2;
    localparam [3:0] ST_LOAD_FWD     = 4'd3;
    localparam [3:0] ST_STREAM_MULT  = 4'd4;
    localparam [3:0] ST_LOAD_INV     = 4'd5;
    localparam [3:0] ST_WAIT_INV     = 4'd6;
    localparam [3:0] ST_NCI_SCAN     = 4'd7;
    localparam [3:0] ST_DONE         = 4'd8;
    localparam [3:0] ST_INTERP       = 4'd9;
    localparam [3:0] ST_FETCH_PLUS_1 = 4'd10;

    doppler_search_controller #(
        .FFT_SIZE(FFT_SIZE),
        .PHASE_BITS(PHASE_BITS),
        .NUM_COARSE_BINS(NUM_DOPPLER_BINS),  // ✅ RENAMED parameter
        .COARSE_STEP_HZ(DOPPLER_STEP_HZ),    // ✅ RENAMED parameter
        .NUM_FINE_BINS(21),                   // ✅ NEW parameter
        .FINE_STEP_HZ(50),                    // ✅ NEW parameter
        .NUM_PRNS(32)                         // ✅ NEW parameter
    ) u_doppler_ctrl (
        .clk(clk_200), 
        .rst_n(rst_n), 
        .start(start), 
        .done(done), 
        .busy(busy),
        .carrier_freq_word(carrier_freq_word), 
        .acq_start(acq_start),
        .acq_done(acq_done), 
        .acq_code_phase(acq_code_phase), 
        .acq_peak_mag(acq_peak_mag),
        .prn_sel_out(prn_sel),                // ✅ NEW: Controller drives PRN selection
        .best_doppler_word(best_doppler_word), 
        .best_code_phase(best_code_phase),
        .best_peak_mag(peak_magnitude),
        .best_prn(best_prn)                   // ✅ NEW
    );

    fft_fifo_bridge #(.FIFO_DEPTH(8192)) u_fifo (
        .wr_clk(clk_100), .wr_rst_n(rst_n), .i_in(i_ext), .q_in(q_ext),
        .sample_valid(sample_valid), .last_sample(1'b0), .rd_clk(clk_200),
        .rd_rst_n(rst_n), .rd_enable(fifo_rd_enable), .i_out(fifo_i_out),
        .q_out(fifo_q_out), .data_valid(fifo_data_valid), .last_out(fifo_last_out),
        .fifo_full(fifo_full), .fifo_empty(fifo_empty)
    );

    reg signed [DATA_WIDTH-1:0] i_buf [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] q_buf [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mult_i_buf [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mult_q_buf [0:FFT_SIZE-1];

    reg [IDX_WIDTH-1:0] sample_cnt;
    reg [IDX_WIDTH-1:0] rom_cnt;
    reg [PHASE_BITS-1:0] carrier_phase;
    
    wire [11:0] carrier_idx = carrier_phase[PHASE_BITS-1 -: 12];
    wire signed [DATA_WIDTH-1:0] cos_val;
    wire signed [DATA_WIDTH-1:0] sin_val;
    
    nco_rom u_nco_rom (.clk(clk_200), .addr(carrier_idx), .cos_out(cos_val), .sin_out(sin_val));

    wire signed [DATA_WIDTH-1:0] rom_fft_i;
    wire signed [DATA_WIDTH-1:0] rom_fft_q;

    code_fft_rom #(.FFT_SIZE(4096), .DATA_WIDTH(18)) u_code_fft_rom (
        .clk(clk_200), .prn_sel(prn_sel), .bin_idx(rom_cnt),
        .fft_i_out(rom_fft_i), .fft_q_out(rom_fft_q)
    );

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

    fft_wrapper #(.FFT_SIZE(FFT_SIZE), .DATA_WIDTH(DATA_WIDTH)) u_fft (
        .clk(clk_200), .rst_n(rst_n), .start(fft_start), .done(fft_done), .inverse(fft_inverse),
        .i_in(fft_i_in), .q_in(fft_q_in), .in_valid(fft_in_valid), .in_ready(fft_in_ready),
        .i_out(fft_i_out), .q_out(fft_q_out), .out_index(fft_out_index),
        .out_valid(fft_out_valid), .out_tlast(fft_tlast), .out_ready(1'b1)
    );

    wire signed [DATA_WIDTH-1:0] mult_i_out;
    wire signed [DATA_WIDTH-1:0] mult_q_out;
    wire                         mult_valid;
    reg                          mult_enable;

    complex_multiplier #(.DATA_WIDTH(DATA_WIDTH)) u_mult (
        .clk(clk_200), .rst_n(rst_n), .enable(mult_enable),
        .a_i(fft_i_out), .a_q(fft_q_out), .b_i(rom_fft_i), .b_q(rom_fft_q),
        .result_i(mult_i_out), .result_q(mult_q_out), .valid(mult_valid)
    );

    // =========================================================================
    // NCI Accumulator
    // =========================================================================
    wire [31:0] nci_mag_out;
    reg  [11:0] nci_read_addr;
    wire        nci_clear_done;
    
    wire nci_accumulate_enable = fft_out_valid & fft_inverse;

    nci_accumulator #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_nci (
        .clk(clk_200),
        .rst_n(rst_n),
        .clear(acq_start),
        .clear_done(nci_clear_done),
        .fft_out_valid(nci_accumulate_enable),
        .i_in(fft_i_out),
        .q_in(fft_q_out),
        .mag_out(nci_mag_out),
        .read_addr(nci_read_addr)
    );

    // =========================================================================
    // Parabolic Interpolator for Sub-Chip Resolution
    // =========================================================================
    wire [7:0] frac_offset;
    wire interp_done;

    parabolic_interpolator u_interp (
        .clk(clk_200),
        .rst_n(rst_n),
        .start(interp_start),
        .mag_minus_1(mag_minus_1),
        .mag_0(acq_peak_mag),
        .mag_plus_1(mag_plus_1),
        .frac_offset(frac_offset),
        .done(interp_done)
    );

    assign best_code_phase_frac = frac_offset;

    always @(posedge clk_200) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            acq_start_latched <= 1'b0;
            acq_done <= 1'b0;
            acq_code_phase <= 0;
            acq_peak_mag <= 0;
            prev_bin_mag <= 0;      // ✅ Added to reset
            last_bin_mag <= 0;      // ✅ Added to reset
            mag_minus_1 <= 0;       // ✅ Added to reset
            mag_plus_1 <= 0;        // ✅ Added to reset
            interp_start <= 1'b0;
            carrier_phase <= 0;
            sample_cnt <= 0;
            rom_cnt <= 0;
            fft_start <= 1'b0;
            fft_inverse <= 1'b0;
            fft_in_valid <= 1'b0;
            mult_enable <= 1'b0;
            fifo_rd_enable <= 1'b0;
            load_fwd_wait <= 1'b0;
            load_inv_wait <= 1'b0;
            nci_count <= 0;
            nci_read_addr <= 0;
        end else begin
            acq_done <= 1'b0;
            interp_start <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    if (acq_start) acq_start_latched <= 1'b1;
                    if (acq_start_latched) begin
                        if (nci_clear_done) begin
                            state <= ST_WAIT_FIFO;
                            nci_count <= 0;
                            acq_start_latched <= 1'b0;
                        end
                    end
                end

                ST_WAIT_FIFO: begin
                    fifo_rd_enable <= 1'b0;
                    if (!fifo_empty) begin
                        state <= ST_WIPEOFF;
                        sample_cnt <= 0;
                        fifo_rd_enable <= 1'b1;
                    end
                end

                ST_WIPEOFF: begin
                    fifo_rd_enable <= 1'b1;
                    if (fifo_data_valid) begin
                        i_buf[sample_cnt] <= (($signed(fifo_i_out) * $signed(cos_val)) + 
                                              ($signed(fifo_q_out) * $signed(sin_val))) >>> 17;
                        q_buf[sample_cnt] <= (($signed(fifo_q_out) * $signed(cos_val)) - 
                                              ($signed(fifo_i_out) * $signed(sin_val))) >>> 17;
                        carrier_phase <= carrier_phase + carrier_freq_word;
                        if (sample_cnt == FFT_SIZE - 1) begin
                            state <= ST_LOAD_FWD;
                            sample_cnt <= 0;
                            fifo_rd_enable <= 1'b0;
                        end else begin
                            sample_cnt <= sample_cnt + 1;
                        end
                    end
                end

                ST_LOAD_FWD: begin
                    fft_inverse <= 1'b0;
                    if (!load_fwd_wait) begin
                        fft_start <= 1'b1;
                        fft_in_valid <= 1'b0;
                        load_fwd_wait <= 1'b1;
                    end else begin
                        fft_start <= 1'b0;
                        fft_in_valid <= 1'b1;
                        fft_i_in <= i_buf[sample_cnt];
                        fft_q_in <= q_buf[sample_cnt];
                        if (fft_in_ready) begin
                            if (sample_cnt == FFT_SIZE - 1) begin
                                state <= ST_STREAM_MULT;
                                sample_cnt <= 0;
                                load_fwd_wait <= 1'b0;
                            end else begin
                                sample_cnt <= sample_cnt + 1;
                            end
                        end
                    end
                end

                ST_STREAM_MULT: begin
                    fft_in_valid <= 1'b0;
                    mult_enable <= 1'b1;
                    if (mult_valid) begin
                        mult_i_buf[sample_cnt] <= mult_i_out;
                        mult_q_buf[sample_cnt] <= mult_q_out;
                        if (sample_cnt == FFT_SIZE - 1) begin
                            state <= ST_LOAD_INV;
                            sample_cnt <= 0;
                            rom_cnt <= 0;
                        end else begin
                            sample_cnt <= sample_cnt + 1;
                        end
                    end
                end

                ST_LOAD_INV: begin
                    fft_inverse <= 1'b1;
                    if (!load_inv_wait) begin
                        fft_start <= 1'b1;
                        fft_in_valid <= 1'b0;
                        load_inv_wait <= 1'b1;
                    end else begin
                        fft_start <= 1'b0;
                        fft_in_valid <= 1'b1;
                        fft_i_in <= mult_i_buf[sample_cnt];
                        fft_q_in <= mult_q_buf[sample_cnt];
                        if (fft_in_ready) begin
                            if (sample_cnt == FFT_SIZE - 1) begin
                                state <= ST_WAIT_INV;
                                sample_cnt <= 0;
                                load_inv_wait <= 1'b0;
                            end else begin
                                sample_cnt <= sample_cnt + 1;
                            end
                        end
                    end
                end

                ST_WAIT_INV: begin
                    fft_in_valid <= 1'b0;
                    if (fft_done) begin
                        if (nci_count == NCI_FRAMES - 1) begin
                            state <= ST_NCI_SCAN;
                            nci_read_addr <= 0;
                            acq_peak_mag <= 0;
                            acq_code_phase <= 0;
                        end else begin
                            nci_count <= nci_count + 1;
                            state <= ST_WAIT_FIFO;
                        end
                    end
                end
                
                ST_NCI_SCAN: begin
                    // 1. Track the magnitude of the PREVIOUS bin scanned
                    prev_bin_mag <= nci_mag_out;
                    
                    // Save the very last bin (4095) for circular wrap-around
                    if (nci_read_addr == FFT_SIZE - 1) begin
                        last_bin_mag <= nci_mag_out;
                    end

                    // 2. Peak Detection
                    if (nci_mag_out > acq_peak_mag) begin
                        acq_peak_mag <= nci_mag_out;
                        acq_code_phase <= nci_read_addr;
                        // At this exact moment, prev_bin_mag holds the magnitude of bin k-1!
                        mag_minus_1 <= prev_bin_mag; 
                    end
                    
                    // 3. End of Scan Logic
                    if (nci_read_addr == FFT_SIZE - 1) begin
                        // Scan complete. Now we need to fetch mag(k+1) from BRAM.
                        if (acq_code_phase == FFT_SIZE - 1)
                            nci_read_addr <= 0;      // Wrap around to bin 0
                        else
                            nci_read_addr <= acq_code_phase + 1;
                            
                        state <= ST_FETCH_PLUS_1;    // Go fetch k+1
                    end else begin
                        nci_read_addr <= nci_read_addr + 1;
                    end
                end

                ST_FETCH_PLUS_1: begin
                    // The BRAM output nci_mag_out is now mag(k+1)
                    mag_plus_1 <= nci_mag_out;
                    
                    // Edge case fix: if peak was at bin 0, mag_minus_1 should be bin 4095
                    if (acq_code_phase == 0) begin
                        mag_minus_1 <= last_bin_mag;
                    end
                    
                    state <= ST_INTERP; // Ready to interpolate!
                end

                ST_INTERP: begin
                    interp_start <= 1'b1;  // Trigger interpolator
                    if (interp_done) begin
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    acq_done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule