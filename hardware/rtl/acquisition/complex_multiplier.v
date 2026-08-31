`timescale 1ns / 1ps
//============================================================================
// Complex Multiplier: (a + jb) × (c + jd) = (ac - bd) + j(ad + bc)
// Uses 3-multiplier optimization with continuous streaming (enable/valid)
//============================================================================
module complex_multiplier #(
    parameter DATA_WIDTH = 18
)(
    input wire clk,
    input wire rst_n,
    input wire enable,               // Keep high to stream data continuously
    input wire signed [DATA_WIDTH-1:0] a_i,
    input wire signed [DATA_WIDTH-1:0] a_q,
    input wire signed [DATA_WIDTH-1:0] b_i,
    input wire signed [DATA_WIDTH-1:0] b_q,
    output reg signed [DATA_WIDTH-1:0] result_i,
    output reg signed [DATA_WIDTH-1:0] result_q,
    output reg valid
);

    // 3-multiplier optimization
    wire signed [2*DATA_WIDTH-1:0] k1 = (a_i + a_q) * b_i;
    wire signed [2*DATA_WIDTH-1:0] k2 = a_i * (b_q - b_i);
    wire signed [2*DATA_WIDTH-1:0] k3 = a_q * (b_i + b_q);
    
    reg signed [2*DATA_WIDTH-1:0] k1_reg, k2_reg, k3_reg;
    reg valid_pipe;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            k1_reg <= 0; k2_reg <= 0; k3_reg <= 0;
            valid <= 0; valid_pipe <= 0;
        end else begin
            if (enable) begin
                k1_reg <= k1;
                k2_reg <= k2;
                k3_reg <= k3;
                valid_pipe <= 1;
            end else begin
                valid_pipe <= 0;
            end
            
            if (valid_pipe) begin
                // Result: (k1 - k3) + j(k1 + k2)
                // Shift right by (DATA_WIDTH - 1) to scale back to original fixed-point range
                result_i <= (k1_reg - k3_reg) >>> (DATA_WIDTH - 1);
                result_q <= (k1_reg + k2_reg) >>> (DATA_WIDTH - 1);
                valid <= 1;
            end else begin
                valid <= 0;
            end
        end
    end
endmodule