`timescale 1ns / 1ps

module complex_multiplier #(
    parameter DATA_WIDTH = 18
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    input  wire signed [DATA_WIDTH-1:0] a_i,
    input  wire signed [DATA_WIDTH-1:0] a_q,
    input  wire signed [DATA_WIDTH-1:0] b_i,
    input  wire signed [DATA_WIDTH-1:0] b_q,
    output reg  signed [DATA_WIDTH-1:0] result_i,
    output reg  signed [DATA_WIDTH-1:0] result_q,
    output reg                      valid
);

    reg signed [2*DATA_WIDTH-1:0] k1, k2, k3;

    always @(posedge clk) begin
        if (!rst_n) begin
            k1 <= 0; k2 <= 0; k3 <= 0;
            result_i <= 0; result_q <= 0;
            valid <= 1'b0;
        end else begin
            valid <= enable;
            if (enable) begin
                k1 <= a_i * (b_i + b_q);
                k2 <= b_i * (a_q - a_i);
                k3 <= b_q * (a_i + a_q);
                
                result_i <= k1 - k3;
                result_q <= k1 + k2;
            end
        end
    end
endmodule