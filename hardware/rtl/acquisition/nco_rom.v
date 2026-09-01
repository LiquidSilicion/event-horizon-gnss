`timescale 1ns / 1ps

module nco_rom #(
    parameter ADDR_WIDTH = 12,      // log2(4096)
    parameter DATA_WIDTH = 18       // 18-bit signed output
)(
    input  wire                     clk,            // ADDED: Clock port for synchronous read
    input  wire [ADDR_WIDTH-1:0]    addr,
    output reg  signed [DATA_WIDTH-1:0] cos_out,
    output reg  signed [DATA_WIDTH-1:0] sin_out
);

    // 4096 entries of 18-bit signed cosine
    (* rom_style = "block" *) // Forces Vivado to use BRAM instead of LUTs
    reg signed [DATA_WIDTH-1:0] cos_rom [0:4095];
    
    // 4096 entries of 18-bit signed sine
    (* rom_style = "block" *)
    reg signed [DATA_WIDTH-1:0] sin_rom [0:4095];

    initial begin
        // IMPORTANT: Use ABSOLUTE paths to ensure XSim and Synthesis can find the files
        $readmemh("nco_cos.hex", cos_rom);
        $readmemh("nco_sin.hex", sin_rom);
        $display("NCO ROMS LOADED SUCCESSFULLY");
    end

    // Synchronous read (Standard pattern for BRAM inference)
    always @(posedge clk) begin
        cos_out <= cos_rom[addr];
        sin_out <= sin_rom[addr];
    end

endmodule