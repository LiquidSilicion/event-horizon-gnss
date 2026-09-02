`timescale 1ns / 1ps

module acquisition_engine #(
    parameter FFT_SIZE    = 4096,
    parameter DATA_WIDTH  = 18,
    parameter PHASE_BITS  = 48,
    parameter IDX_WIDTH   = 12
)(
    input  wire                     clk_100,
    input  wire                     clk_200,
    input  wire                     rst_n,
    input  wire                     start,
    output reg                      done,
    output reg                      busy,
    input  wire signed [15:0]       i_sample,
    input  wire signed [15:0]       q_sample,
    input  wire                     sample_valid,
    input  wire [4:0]               prn_sel,
    input  wire signed [PHASE_BITS-1:0] carrier_freq_word,
    output reg [IDX_WIDTH-1:0]      best_code_phase,
    output reg [31:0]               peak_magnitude
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

    fft_fifo_bridge #(
        .FIFO_DEPTH(8192)
    ) u_fifo (
        .wr_clk(clk_100),
        .wr_rst_n(rst_n),
        .i_in(i_ext),
        .q_in(q_ext),
        .sample_valid(sample_valid),
        .last_sample(1'b0),
        .rd_clk(clk_200),
        .rd_rst_n(rst_n),
        .rd_enable(fifo_rd_enable),
        .i_out(fifo_i_out),
        .q_out(fifo_q_out),
        .data_valid(fifo_data_valid),
        .last_out(fifo_last_out),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty)
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
    
    nco_rom u_nco_rom (
        .clk(clk_200),
        .addr(carrier_idx),
        .cos_out(cos_val),
        .sin_out(sin_val)
    );

    wire signed [DATA_WIDTH-1:0] rom_fft_i;
    wire signed [DATA_WIDTH-1:0] rom_fft_q;

    code_fft_rom #(
        .FFT_SIZE(4096),
        .DATA_WIDTH(18)
    ) u_code_fft_rom (
        .clk(clk_200),
        .prn_sel(prn_sel),
        .bin_idx(rom_cnt),
        .fft_i_out(rom_fft_i),
        .fft_q_out(rom_fft_q)
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

    fft_wrapper #(
        .FFT_SIZE(FFT_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_fft (
        .clk(clk_200),
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
        .out_index(fft_out_index),
        .out_valid(fft_out_valid),
        .out_ready(1'b1)
    );

    wire signed [DATA_WIDTH-1:0] mult_i_out;
    wire signed [DATA_WIDTH-1:0] mult_q_out;
    wire                         mult_valid;
    reg                          mult_enable;

    complex_multiplier #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mult (
        .clk(clk_200),
        .rst_n(rst_n),
        .enable(mult_enable),
        .a_i(fft_i_out),
        .a_q(fft_q_out),
        .b_i(rom_fft_i),
        .b_q(rom_fft_q),
        .result_i(mult_i_out),
        .result_q(mult_q_out),
        .valid(mult_valid)
    );

    wire                     pd_done;
    wire [IDX_WIDTH-1:0]     pd_best_idx;
    wire [31:0]              pd_peak_mag;
    reg                      pd_start;

    peak_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .FFT_SIZE(FFT_SIZE),
        .IDX_WIDTH(IDX_WIDTH)
    ) u_peak_detector (
        .clk(clk_200),
        .rst_n(rst_n),
        .start(pd_start),
        .data_valid(fft_out_valid),
        .i_in(fft_i_out),
        .q_in(fft_q_out),
        .max_magnitude(pd_peak_mag),
        .max_idx(pd_best_idx),
        .done(pd_done)
    );

    reg [3:0] state;
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_WAIT_FIFO   = 4'd1;
    localparam [3:0] ST_WIPEOFF     = 4'd2;
    localparam [3:0] ST_LOAD_FWD    = 4'd3;
    localparam [3:0] ST_STREAM_MULT = 4'd4;
    localparam [3:0] ST_LOAD_INV    = 4'd5;
    localparam [3:0] ST_WAIT_INV    = 4'd6;
    localparam [3:0] ST_DONE        = 4'd7;

    always @(posedge clk_200) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            done <= 1'b0;
            busy <= 1'b0;
            carrier_phase <= 0;
            sample_cnt <= 0;
            rom_cnt <= 0;
            fft_start <= 1'b0;
            fft_inverse <= 1'b0;
            fft_in_valid <= 1'b0;
            mult_enable <= 1'b0;
            pd_start <= 1'b0;
            best_code_phase <= 0;
            peak_magnitude <= 0;
            fifo_rd_enable <= 1'b0;
            load_fwd_wait <= 1'b0;
            load_inv_wait <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    carrier_phase <= 0;
                    sample_cnt <= 0;
                    rom_cnt <= 0;
                    fifo_rd_enable <= 1'b0;
                    if (start) begin
                        state <= ST_WAIT_FIFO;
                        busy <= 1'b1;
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
                    // ✅ FIX: Keep multiplier enabled continuously to allow the pipeline to flush
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
                                pd_start <= 1'b1;
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
                    pd_start <= 1'b0;
                    if (pd_done) begin
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    best_code_phase <= pd_best_idx;
                    peak_magnitude <= pd_peak_mag;
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule