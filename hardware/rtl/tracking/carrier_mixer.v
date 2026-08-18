`timescale 1ns / 1ps

// Complex mixer: performs carrier wipe-off
// i_out = i_in * cos + q_in * sin
// q_out = q_in * cos - i_in * sin
// Uses DSP48 slices for the 4 multiplies + 2 adds.

module carrier_mixer #(
    parameter SAMPLE_BITS = 16,
    parameter SINCOS_BITS = 18,
    parameter OUTPUT_BITS = 18
)(
    input wire clk,
    input wire rst_n,
    input wire signed [SAMPLE_BITS-1:0] i_in,
    input wire signed [SAMPLE_BITS-1:0] q_in,
    input wire signed [SINCOS_BITS-1:0] cos_val,
    input wire signed [SINCOS_BITS-1:0] sin_val,
    output reg  signed [OUTPUT_BITS-1:0] i_out,
    output reg  signed [OUTPUT_BITS-1:0] q_out
);

    // 4 multiplies (use DSP48)
    wire signed [SAMPLE_BITS+SINCOS_BITS-1:0] i_cos = i_in * cos_val;
    wire signed [SAMPLE_BITS+SINCOS_BITS-1:0] q_sin = q_in * sin_val;
    wire signed [SAMPLE_BITS+SINCOS_BITS-1:0] q_cos = q_in * cos_val;
    wire signed [SAMPLE_BITS+SINCOS_BITS-1:0] i_sin = i_in * sin_val;
    
    // Sum and truncate to OUTPUT_BITS (take middle bits)
    // i_out = i_cos + q_sin
    // q_out = q_cos - i_sin
    wire signed [SAMPLE_BITS+SINCOS_BITS-1:0] i_sum = i_cos + q_sin;
    wire signed [SAMPLE_BITS+SINCOS_BITS-1:0] q_sum = q_cos - i_sin;
    
    // Scale down by 2^(SINCOS_BITS-1) = 2^17 to normalize
    // (since cos/sin are scaled to 2^17)
    localparam SHIFT = SINCOS_BITS - 1;  // 17
    
    always @(posedge clk) begin
        if (!rst_n) begin
            i_out <= 0;
            q_out <= 0;
        end else begin
            // Arithmetic right shift with rounding
            i_out <= (i_sum + (1 << (SHIFT-1))) >>> SHIFT;
            q_out <= (q_sum + (1 << (SHIFT-1))) >>> SHIFT;
        end
    end

endmodule