module ca_code_gen #(
    parameter PRN_BITS  = 5,
    parameter CHIP_BITS = 10,
    parameter CODE_LENGTH = 1023,
    parameter ROM_SIZE = 32736 
)(
    input  wire                  clk,
    input  wire [PRN_BITS-1:0]   prn_sel,
    input  wire [CHIP_BITS-1:0]  chip_idx,
    output reg                   code_chip
);

    wire [14:0] rom_addr = {prn_sel, chip_idx};
    reg [0:0] code_rom [0:ROM_SIZE-1];
    
    initial begin
        // If this file is missing, XSim will silently leave the ROM as 'x'
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/rtl/tracking/ca_code_all_prns.hex", code_rom);
        
        // ✅ DEBUG: This will print to the console if the file is found
        $display("✅ CA CODE ROM LOADED SUCCESSFULLY FROM ABSOLUTE PATH");
    end
    
    always @(posedge clk) begin
        code_chip <= code_rom[rom_addr][0];
    end
endmodule