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

    reg [IDX_WIDTH-1:0] sample_count;
    reg armed;
    
    // ✅ FIXED: Use explicit signed arithmetic and safe bit extraction
    wire signed [35:0] i_sq = $signed(i_in) * $signed(i_in);
    wire signed [35:0] q_sq = $signed(q_in) * $signed(q_in);
    wire signed [35:0] mag_sum = i_sq + q_sq;
    
    // ✅ Extract upper 32 bits (equivalent to >>> 4 but safer)
    wire [31:0] mag = mag_sum[35:4];

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_count <= 0;
            max_magnitude <= 0;
            max_idx <= 0;
            done <= 1'b0;
            armed <= 1'b0;
        end else begin
            case ({armed, done})
                2'b00: begin
                    if (start) begin
                        armed <= 1'b1;
                        sample_count <= 0;
                        max_magnitude <= 0;
                        max_idx <= 0;
                    end
                end
                
                2'b10: begin
                    if (data_valid) begin
                        // ✅ Debug to verify magnitude calculation
                        if (sample_count < 10) begin
                            $display("[%0t] PEAK DET: count=%0d, i_in=%0d, q_in=%0d, mag=%0d, max_mag=%0d", 
                                     $time, sample_count, i_in, q_in, mag, max_magnitude);
                        end
                        
                        if (mag > max_magnitude) begin
                            max_magnitude <= mag;
                            max_idx <= sample_count;
                        end
                        
                        if (sample_count == FFT_SIZE - 1) begin
                            done <= 1'b1;
                        end else begin
                            sample_count <= sample_count + 1;
                        end
                    end
                end
                
                2'b11: begin
                    if (start) begin
                        armed <= 1'b1;
                        done <= 1'b0;
                        sample_count <= 0;
                        max_magnitude <= 0;
                        max_idx <= 0;
                    end
                end
                
                default: begin
                    armed <= 1'b0;
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule