module ca_code_gen #(
    parameter PRN_BITS = 5,
    parameter CHIP_BITS = 10
)(
    input  wire                  clk,
    input  wire [PRN_BITS-1:0]   prn_sel,
    input  wire [CHIP_BITS-1:0]  chip_idx,
    output reg                   code_chip     // 1 or 0 (maps to +1/-1)
);

endmodule