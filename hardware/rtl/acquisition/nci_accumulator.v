`timescale 1ns / 1ps

module nci_accumulator #(
    parameter FFT_SIZE     = 4096,
    parameter DATA_WIDTH   = 18,
    parameter MAG_WIDTH    = 32,
    parameter NCI_FRAMES   = 20
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    input  wire                    start,
    output reg                     nci_done,
    
    input  wire                    fft_out_valid,
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    input  wire                    fft_tlast,
    
    output wire [MAG_WIDTH-1:0]    mag_out,
    input  wire [11:0]             read_addr,
    output reg                     mag_valid
);

    // Accumulator memory (4096 x 32-bit = 4 BRAM36K)
    reg [MAG_WIDTH-1:0] accum_mem [0:FFT_SIZE-1];
    
    // Counters
    reg [11:0] sample_cnt;
    reg [4:0]  frame_cnt;
    reg        accumulating;
    reg        clearing;           // Sequential clear in progress
    reg [11:0] clear_addr;         // Address being cleared
    
    // Magnitude computation with safe scaling
    // 18-bit * 18-bit = 36-bit
    // Shift right by 8 to prevent overflow over 20 frames
    // Max per-frame: (2^17)^2 * 2 = 2^35
    // After 20 frames: 20 * 2^35 = 2^39.3 (fits in 32 bits after >>>8)
    wire signed [2*DATA_WIDTH-1:0] i_squared = i_in * i_in;
    wire signed [2*DATA_WIDTH-1:0] q_squared = q_in * q_in;
    wire [MAG_WIDTH-1:0] magnitude = (i_squared + q_squared) >>> 8;
    
    // Parallel read interface
    assign mag_out = accum_mem[read_addr];
    
    // Main state machine
    always @(posedge clk) begin
        if (!rst_n) begin
            sample_cnt   <= 12'd0;
            frame_cnt    <= 5'd0;
            accumulating <= 1'b0;
            clearing     <= 1'b0;
            clear_addr   <= 12'd0;
            nci_done     <= 1'b0;
            mag_valid    <= 1'b0;
        end else begin
            nci_done  <= 1'b0;
            mag_valid <= 1'b0;
            
            // Priority 1: Sequential memory clear
            if (clearing) begin
                accum_mem[clear_addr] <= 32'd0;
                if (clear_addr == FFT_SIZE - 1) begin
                    clearing <= 1'b0;
                end else begin
                    clear_addr <= clear_addr + 1;
                end
            end
            
            // Priority 2: Start new accumulation
            else if (start) begin
                clearing     <= 1'b1;
                clear_addr   <= 12'd0;
                sample_cnt   <= 12'd0;
                frame_cnt    <= 5'd0;
                accumulating <= 1'b1;
            end
            
            // Priority 3: Accumulate incoming samples
            else if (accumulating && fft_out_valid) begin
                // Accumulate magnitude
                accum_mem[sample_cnt] <= accum_mem[sample_cnt] + magnitude;
                mag_valid <= 1'b1;
                
                // Check for frame boundary
                if (fft_tlast) begin
                    sample_cnt <= 12'd0;
                    
                    if (frame_cnt == NCI_FRAMES - 1) begin
                        // All frames accumulated - done!
                        accumulating <= 1'b0;
                        nci_done     <= 1'b1;
                        frame_cnt    <= 5'd0;
                    end else begin
                        frame_cnt <= frame_cnt + 1;
                    end
                end else begin
                    sample_cnt <= sample_cnt + 1;
                end
            end
        end
    end

endmodule