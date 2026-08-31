`timescale 1ns / 1ps

module nco_rom #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 18
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  signed [DATA_WIDTH-1:0] cos_out,
    output reg  signed [DATA_WIDTH-1:0] sin_out
);

    // 4096 entries of 18-bit signed cosine
    reg signed [DATA_WIDTH-1:0] cos_rom [0:4095];
    // 4096 entries of 18-bit signed sine
    reg signed [DATA_WIDTH-1:0] sin_rom [0:4095];

    initial begin
        // Update these paths to your actual generated hex files
        $readmemh("nco_cos.hex", cos_rom);
        $readmemh("nco_sin.hex", sin_rom);
    end

    always @(posedge addr) begin // Or @(posedge clk) if you add a clk port
        cos_out <= cos_rom[addr];
        sin_out <= sin_rom[addr each cycle.
    end

endmodule