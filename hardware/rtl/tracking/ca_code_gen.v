module ca_code_gen #(
    parameter PRN_BITS  = 5,
    parameter CHIP_BITS = 10,
    parameter CODE_LENGTH = 1023,
    // FIX: Calculate exact ROM size: 32 * 1023 = 32736
    parameter ROM_SIZE = 32736 
)(
    input  wire                  clk,
    input  wire [PRN_BITS-1:0]   prn_sel,
    input  wire [CHIP_BITS-1:0]  chip_idx,
    output reg                   code_chip
);

    wire [14:0] rom_addr = {prn_sel, chip_idx};
    
    // FIX: Use ROM_SIZE instead of a fixed large number
    reg [0:0] code_rom [0:ROM_SIZE-1];
    
    //Loctaion of the hex file needs to be configured accordingly
    initial begin
        $readmemh("ca_code_all_prns.hex", code_rom);
    end
    
    always @(posedge clk) begin
        code_chip <= code_rom[rom_addr][0];
    end
endmodule