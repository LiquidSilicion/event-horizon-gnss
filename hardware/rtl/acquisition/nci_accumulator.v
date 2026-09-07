`timescale 1ns / 1ps

module nci_accumulator #(
    parameter FFT_SIZE = 4096,
    parameter DATA_WIDTH = 18,
    parameter MAG_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear,              // Asserted at start of each Doppler bin
    input  wire                    fft_out_valid,      // Gated with state in parent module
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    output wire [MAG_WIDTH-1:0]    mag_out,
    input  wire [11:0]             read_addr
);

    reg [MAG_WIDTH-1:0] accum_mem [0:FFT_SIZE-1];
    reg        clearing;
    reg [11:0] clear_addr;
    reg [11:0] accum_addr;

    // Compute magnitude squared: I² + Q², scaled to prevent overflow
    wire signed [2*DATA_WIDTH-1:0] i_sq = i_in * i_in;
    wire signed [2*DATA_WIDTH-1:0] q_sq = q_in * q_in;
    wire [MAG_WIDTH-1:0] magnitude = (i_sq + q_sq) >>> 8;

    // Parallel read interface
    assign mag_out = accum_mem[read_addr];

    // Sequential write interface
    always @(posedge clk) begin
        if (!rst_n) begin
            clearing   <= 1'b0;
            clear_addr <= 12'd0;
            accum_addr <= 12'd0;
        end else begin
            if (clear) begin
                // Start clearing sequence
                clearing   <= 1'b1;
                clear_addr <= 12'd0;
                accum_addr <= 12'd0;
            end else if (clearing) begin
                // Clear one address per cycle
                accum_mem[clear_addr] <= {MAG_WIDTH{1'b0}};
                if (clear_addr == FFT_SIZE - 1) begin
                    clearing <= 1'b0;
                end else begin
                    clear_addr <= clear_addr + 1;
                end
            end else if (fft_out_valid) begin
                // Accumulate magnitude squared
                accum_mem[accum_addr] <= accum_mem[accum_addr] + magnitude;
                if (accum_addr == FFT_SIZE - 1) begin
                    accum_addr <= 12'd0;
                end else begin
                    accum_addr <= accum_addr + 1;
                end
            end
        end
    end

endmodule