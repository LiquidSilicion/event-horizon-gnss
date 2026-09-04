`timescale 1ns / 1ps

module nci_accumulator #(
    parameter FFT_SIZE     = 4096,
    parameter DATA_WIDTH   = 18,
    parameter MAG_WIDTH    = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    input  wire                    clear,          // Pulse to clear memory
    input  wire                    fft_out_valid,
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    
    output wire [MAG_WIDTH-1:0]    mag_out,
    input  wire [11:0]             read_addr
);

    reg [MAG_WIDTH-1:0] accum_mem [0:FFT_SIZE-1];
    reg [11:0] sample_cnt;
    reg clearing;
    reg [11:0] clear_addr;
    
    // 18-bit * 18-bit = 36-bit. Shift right by 8 to prevent overflow over 20 frames.
    wire signed [2*DATA_WIDTH-1:0] i_sq = i_in * i_in;
    wire signed [2*DATA_WIDTH-1:0] q_sq = q_in * q_in;
    wire [MAG_WIDTH-1:0] magnitude = (i_sq + q_sq) >>> 8;
    
    assign mag_out = accum_mem[read_addr];
    
    always @(posedge clk) begin
        if (!rst_n) begin
            sample_cnt <= 0;
            clearing <= 0;
            clear_addr <= 0;
        end else begin
            if (clear) begin
                clearing <= 1'b1;
                clear_addr <= 0;
                sample_cnt <= 0;
            end else if (clearing) begin
                accum_mem[clear_addr] <= 0;
                if (clear_addr == FFT_SIZE - 1) clearing <= 0;
                else clear_addr <= clear_addr + 1;
            end else if (fft_out_valid) begin
                accum_mem[sample_cnt] <= accum_mem[sample_cnt] + magnitude;
                if (sample_cnt == FFT_SIZE - 1) sample_cnt <= 0;
                else sample_cnt <= sample_cnt + 1;
            end
        end
    end
endmodule