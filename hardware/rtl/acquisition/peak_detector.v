`timescale 1ns / 1ps

module peak_detector #(
    parameter DATA_WIDTH   = 18,
    parameter FFT_SIZE     = 4096,
    parameter IDX_WIDTH    = 12,          // log2(4096)
    parameter SHIFT_AMOUNT = 16           // Match your magnitude_square module
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,              // Pulse high to reset and start search
    input  wire                         data_valid,         // High when new I/Q pair is available
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    
    output reg  [31:0]                  max_magnitude,
    output reg  [IDX_WIDTH-1:0]         max_idx,
    output reg                          done
);

    // =========================================================================
    // 1. Compute Magnitude Squared using SAFE bit-slicing 
    // (Avoids >> shift warnings and guarantees exact bit extraction)
    // =========================================================================
    wire signed [2*DATA_WIDTH-1:0] i_sq = i_in * i_in;
    wire signed [2*DATA_WIDTH-1:0] q_sq = q_in * q_in;
    wire [2*DATA_WIDTH-1:0] mag_sum = i_sq + q_sq;
    
    // Extract bits [SHIFT_AMOUNT + 31 : SHIFT_AMOUNT]
    // For DATA_WIDTH=18 and SHIFT=16, this is [47:16]
    wire [31:0] magnitude = mag_sum[SHIFT_AMOUNT + 31 : SHIFT_AMOUNT];

    // =========================================================================
    // 2. Peak Detection State Machine
    // =========================================================================
    reg [IDX_WIDTH-1:0] current_idx;
    reg [31:0] current_max_mag;
    reg [IDX_WIDTH-1:0] current_max_idx;
    reg searching;

    always @(posedge clk) begin
        if (!rst_n) begin
            done <= 0;
            searching <= 0;
            current_idx <= 0;
            current_max_mag <= 0;
            max_magnitude <= 0;
            max_idx <= 0;
        end else if (start) begin
            // Reset and start a new search
            done <= 0;
            searching <= 1;
            current_idx <= 0;
            current_max_mag <= 0;
            current_max_idx <= 0;
        end else if (searching) begin
            if (data_valid) begin
                // Update peak if current magnitude is strictly higher
                if (magnitude > current_max_mag) begin
                    current_max_mag <= magnitude;
                    current_max_idx <= current_idx;
                end
                
                // Check if we've processed all FFT bins
                if (current_idx == FFT_SIZE - 1) begin
                    searching <= 0;
                    done <= 1;
                    max_magnitude <= current_max_mag;
                    max_idx <= current_max_idx;
                end else begin
                    current_idx <= current_idx + 1;
                end
            end
        end else begin
            done <= 0;
        end
    end

endmodule