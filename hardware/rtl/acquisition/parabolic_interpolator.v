`timescale 1ns / 1ps

module parabolic_interpolator #(
    parameter MAG_WIDTH = 32,
    parameter FRAC_BITS = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    
    input  wire [MAG_WIDTH-1:0] mag_minus_1,
    input  wire [MAG_WIDTH-1:0] mag_0,
    input  wire [MAG_WIDTH-1:0] mag_plus_1,
    
    output reg  signed [FRAC_BITS-1:0] frac_offset,
    output reg  done
);

    reg [1:0] state;
    localparam IDLE  = 2'd0;
    localparam CALC  = 2'd1;
    localparam DONE  = 2'd2;

    // 1. Calculate Numerator and Denominator
    // N = (mag_minus_1 - mag_plus_1) << FRAC_BITS
    wire signed [MAG_WIDTH+FRAC_BITS:0] num = ($signed(mag_minus_1) - $signed(mag_plus_1)) <<< FRAC_BITS;
    
    // D = 2 * (mag_minus_1 - 2*mag_0 + mag_plus_1)
    // For a valid peak, D is always negative. We take its absolute value for LUT indexing.
    wire signed [MAG_WIDTH+2:0] den_signed = ($signed(mag_minus_1) + $signed(mag_plus_1)) - ($signed(mag_0) <<< 1);
    wire [MAG_WIDTH+2:0] den_abs = den_signed < 0 ? -den_signed : den_signed;

    // 2. Normalize den_abs to 8 bits (find MSB) to preserve the N/D ratio
    reg [7:0] lut_addr;
    reg signed [MAG_WIDTH+FRAC_BITS:0] num_shifted;
    
    always @(*) begin
        lut_addr = 8'd128; 
        num_shifted = num;
        
        // Priority encoder to find MSB of den_abs (from bit MAG_WIDTH+2 down to 7)
        // For MAG_WIDTH=32, MAG_WIDTH+2 = 34.
        if      (den_abs[34]) begin lut_addr = den_abs[34:27]; num_shifted = num >>> 27; end
        else if (den_abs[33]) begin lut_addr = den_abs[33:26]; num_shifted = num >>> 26; end
        else if (den_abs[32]) begin lut_addr = den_abs[32:25]; num_shifted = num >>> 25; end
        else if (den_abs[31]) begin lut_addr = den_abs[31:24]; num_shifted = num >>> 24; end
        else if (den_abs[30]) begin lut_addr = den_abs[30:23]; num_shifted = num >>> 23; end
        else if (den_abs[29]) begin lut_addr = den_abs[29:22]; num_shifted = num >>> 22; end
        else if (den_abs[28]) begin lut_addr = den_abs[28:21]; num_shifted = num >>> 21; end
        else if (den_abs[27]) begin lut_addr = den_abs[27:20]; num_shifted = num >>> 20; end
        else if (den_abs[26]) begin lut_addr = den_abs[26:19]; num_shifted = num >>> 19; end
        else if (den_abs[25]) begin lut_addr = den_abs[25:18]; num_shifted = num >>> 18; end
        else if (den_abs[24]) begin lut_addr = den_abs[24:17]; num_shifted = num >>> 17; end
        else if (den_abs[23]) begin lut_addr = den_abs[23:16]; num_shifted = num >>> 16; end
        else if (den_abs[22]) begin lut_addr = den_abs[22:15]; num_shifted = num >>> 15; end
        else if (den_abs[21]) begin lut_addr = den_abs[21:14]; num_shifted = num >>> 14; end
        else if (den_abs[20]) begin lut_addr = den_abs[20:13]; num_shifted = num >>> 13; end
        else if (den_abs[19]) begin lut_addr = den_abs[19:12]; num_shifted = num >>> 12; end
        else if (den_abs[18]) begin lut_addr = den_abs[18:11]; num_shifted = num >>> 11; end
        else if (den_abs[17]) begin lut_addr = den_abs[17:10]; num_shifted = num >>> 10; end
        else if (den_abs[16]) begin lut_addr = den_abs[16:9];  num_shifted = num >>> 9;  end
        else if (den_abs[15]) begin lut_addr = den_abs[15:8];  num_shifted = num >>> 8;  end
        else if (den_abs[14]) begin lut_addr = den_abs[14:7];  num_shifted = num >>> 7;  end
        else if (den_abs[13]) begin lut_addr = den_abs[13:6];  num_shifted = num >>> 6;  end
        else if (den_abs[12]) begin lut_addr = den_abs[12:5];  num_shifted = num >>> 5;  end
        else if (den_abs[11]) begin lut_addr = den_abs[11:4];  num_shifted = num >>> 4;  end
        else if (den_abs[10]) begin lut_addr = den_abs[10:3];  num_shifted = num >>> 3;  end
        else if (den_abs[9])  begin lut_addr = den_abs[9:2];   num_shifted = num >>> 2;  end
        else if (den_abs[8])  begin lut_addr = den_abs[8:1];   num_shifted = num >>> 1;  end
        else if (den_abs[7])  begin lut_addr = den_abs[7:0];   num_shifted = num;        end
        else                  begin lut_addr = 8'd128;         num_shifted = num;        end
    end

    // 3. Reciprocal LUT (128 entries, 16 bits each)
    // Stores: round((1.0 / (2.0 * i)) * 65536) for i = 128 to 255
    reg [15:0] lut_mem [127:0];
    initial begin
        $readmemh("reciprocal_lut.mem", lut_mem);
    end

    wire [15:0] lut_out = lut_mem[lut_addr - 8'd128];

    // 4. DSP Multiplication
    // num_shifted has FRAC_BITS fractional bits.
    // lut_out has 16 fractional bits.
    // Product has FRAC_BITS + 16 fractional bits.
    // We want FRAC_BITS fractional bits in the output, so we extract bits [FRAC_BITS+15 : 16]
    wire signed [MAG_WIDTH+FRAC_BITS+15:0] mult_result = num_shifted * $signed({1'b0, lut_out});
    wire signed [FRAC_BITS-1:0] frac_raw = mult_result[FRAC_BITS+15 : 16];

    // 5. State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frac_offset <= 0;
            done        <= 1'b0;
            state       <= IDLE;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= CALC;
                    end
                end
                CALC: begin
                    // Multiplication is combinational, so it's ready in the same cycle
                    frac_offset <= frac_raw;
                    state <= DONE;
                end
                DONE: begin
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule