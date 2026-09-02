`timescale 1ns / 1ps

module peak_detector #(
    parameter DATA_WIDTH = 18,
    parameter FFT_SIZE   = 4096,
    parameter IDX_WIDTH  = 12
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire                     data_valid,
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    output reg  [31:0]              max_magnitude,
    output reg  [IDX_WIDTH-1:0]     max_idx,
    output reg                      done
);

    reg [IDX_WIDTH-1:0] current_idx;
    reg                 searching;

    // 18-bit signed * 18-bit signed = 36 bits.
    // 36 bits + 36 bits = 37 bits maximum.
    wire [36:0] mag_sq = ($signed(i_in) * $signed(i_in)) + ($signed(q_in) * $signed(q_in));
    
    // We only need 32 bits for the output magnitude. 
    // Taking the lower 32 bits is safe and prevents any out-of-bounds warnings.
    wire [31:0] mag_out = mag_sq[31:0]; 

    always @(posedge clk) begin
        if (!rst_n) begin
            current_idx   <= 0;
            searching     <= 1'b0;
            max_magnitude <= 0;
            max_idx       <= 0;
            done          <= 1'b0;
        end else if (start) begin
            // Reset for a new search
            current_idx   <= 0;
            searching     <= 1'b1;
            max_magnitude <= 0;
            max_idx       <= 0;
            done          <= 1'b0;
        end else if (searching) begin
            if (data_valid) begin
                // Update peak if current magnitude is strictly greater
                if (mag_out > max_magnitude) begin
                    max_magnitude <= mag_out;
                    max_idx       <= current_idx;
                end
                
                current_idx <= current_idx + 1;
                
                // Check if we have processed all FFT_SIZE bins
                if (current_idx == FFT_SIZE - 1) begin
                    searching <= 1'b0;
                    done      <= 1'b1;
                end
            end
        end else begin
            done <= 1'b0;
        end
    end

endmodule