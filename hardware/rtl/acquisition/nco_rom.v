`timescale 1ns / 1ps

module nco_rom #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 18
)(
    input  wire                     clk,
    input  wire [ADDR_WIDTH-1:0]    addr,
    output reg  signed [DATA_WIDTH-1:0] cos_out,
    output reg  signed [DATA_WIDTH-1:0] sin_out
);

    (* ram_style = "block" *)
    reg signed [DATA_WIDTH-1:0] cos_rom [0:4095];
    
    (* ram_style = "block" *)
    reg signed [DATA_WIDTH-1:0] sin_rom [0:4095];

    initial begin
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/rtl/acquisition/nco_cos.hex", cos_rom);
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/rtl/acquisition/nco_sin.hex", sin_rom);
        $display("======================================================");
        $display("✅ NCO ROMS LOADED SUCCESSFULLY");
        $display("   [DEBUG] NCO Addr 0 (0 deg):    cos = %0d (0x%h), sin = %0d (0x%h)", cos_rom[0], cos_rom[0], sin_rom[0], sin_rom[0]);
        $display("   [DEBUG] NCO Addr 1024 (90 deg):  cos = %0d (0x%h), sin = %0d (0x%h)", cos_rom[1024], cos_rom[1024], sin_rom[1024], sin_rom[1024]);
        $display("======================================================");
    end

    always @(posedge clk) begin
        cos_out <= cos_rom[addr];
        sin_out <= sin_rom[addr];
    end
endmodule