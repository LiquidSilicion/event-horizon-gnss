`timescale 1ns / 1ps

module magnitude_square #(
    parameter DATA_WIDTH   = 18,  // Match your IFFT output width (e.g., 18 or 32)
    parameter SHIFT_AMOUNT = 16   // Number of bits to shift right to prevent overflow
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    output reg  [31:0]              mag_out
);

    // 1. Wires for squared values (width doubles after multiplication)
    wire signed [2*DATA_WIDTH-1:0] i_squared;
    wire signed [2*DATA_WIDTH-1:0] q_squared;

    // 2. Wire for the sum
    wire [2*DATA_WIDTH-1:0] mag_sum;

    // 3. Perform the multiplications (Infers DSP48 slices in Xilinx FPGAs)
    assign i_squared = i_in * i_in;
    assign q_squared = q_in * q_in;

    // 4. Add the squares
    assign mag_sum = i_squared + q_squared;

    // 5. Scale down and assign
    always @(posedge clk) begin
        if (!rst_n) begin
            mag_out <= 32'd0;
        end else begin
            // Extract bits [SHIFT_AMOUNT + 31 : SHIFT_AMOUNT]
            // For DATA_WIDTH=18 and SHIFT=16, this is [47:16]
            mag_out <= mag_sum[SHIFT_AMOUNT + 31 : SHIFT_AMOUNT];
        end
    end

endmodule