`timescale 1ns / 1ps
//============================================================================
// Complex Multiplier: (a + jb) × (c + jd) = (ac - bd) + j(ad + bc)
// Uses 3-multiplier optimization
//============================================================================
module complex_multiplier #(
    parameter DATA_WIDTH = 18
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire signed [DATA_WIDTH-1:0] a_i,
    input wire signed [DATA_WIDTH-1:0] a_q,
    input wire signed [DATA_WIDTH-1:0] b_i,
    input wire signed [DATA_WIDTH-1:0] b_q,
    output reg signed [DATA_WIDTH-1:0] result_i,
    output reg signed [DATA_WIDTH-1:0] result_q,
    output reg done
);

    // 3-multiplier optimization
    wire signed [2*DATA_WIDTH-1:0] k1 = (a_i + a_q) * b_i;
    wire signed [2*DATA_WIDTH-1:0] k2 = a_i * (b_q - b_i);
    wire signed [2*DATA_WIDTH-1:0] k3 = a_q * (b_i + b_q);
    
    // Pipeline stages
    reg [2:0] pipeline_count;
    reg signed [2*DATA_WIDTH-1:0] k1_reg, k2_reg, k3_reg;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            pipeline_count <= 0;
            done <= 0;
        end else begin
            if (start) begin
                k1_reg <= k1;
                k2_reg <= k2;
                k3_reg <= k3;
                pipeline_count <= 1;
            end else if (pipeline_count > 0) begin
                pipeline_count <= pipeline_count + 1;
                if (pipeline_count == 3) begin
                    // Result: (k1 - k3) + j(k1 + k2)
                    result_i <= (k1_reg - k3_reg) >>> (DATA_WIDTH - 1);
                    result_q <= (k1_reg + k2_reg) >>> (DATA_WIDTH - 1);
                    done <= 1;
                    pipeline_count <= 0;
                end
            end else begin
                done <= 0;
            end
        end
    end

endmodule