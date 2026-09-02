`timescale 1ns / 1ps

module code_fft_rom #(
    parameter FFT_SIZE   = 4096,
    parameter DATA_WIDTH = 18,
    parameter NUM_PRNS   = 32,
    parameter ADDR_WIDTH = 12
)(
    input  wire                        clk,
    input  wire [4:0]                  prn_sel,
    input  wire [ADDR_WIDTH-1:0]       bin_idx,
    output reg  signed [DATA_WIDTH-1:0] fft_i_out,
    output reg  signed [DATA_WIDTH-1:0] fft_q_out
);

    localparam ROM_DEPTH = NUM_PRNS * FFT_SIZE;

    (* ram_style = "block" *) 
    reg signed [DATA_WIDTH-1:0] prn_fft_i [0:ROM_DEPTH-1];
    
    (* ram_style = "block" *) 
    reg signed [DATA_WIDTH-1:0] prn_fft_q [0:ROM_DEPTH-1];

    wire [16:0] flat_addr = ((prn_sel - 5'd1) * FFT_SIZE) + bin_idx;

    initial begin
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/rtl/acquisition/all_prns_fft_i.hex", prn_fft_i);
        $readmemh("/home/johan2/Documents/fpga/event-horizon-gnss/hardware/rtl/acquisition/all_prns_fft_q.hex", prn_fft_q);
        $display("======================================================");
        $display("✅ CODE FFT ROM LOADED SUCCESSFULLY");
        $display("   [DEBUG] PRN 1, Bin 0: I = %0d (0x%h), Q = %0d (0x%h)", prn_fft_i[0], prn_fft_i[0], prn_fft_q[0], prn_fft_q[0]);
        $display("   [DEBUG] PRN 1, Bin 1: I = %0d (0x%h), Q = %0d (0x%h)", prn_fft_i[1], prn_fft_i[1], prn_fft_q[1], prn_fft_q[1]);
        $display("======================================================");
    end

    always @(posedge clk) begin
        fft_i_out <= prn_fft_i[flat_addr];
        fft_q_out <= prn_fft_q[flat_addr];
    end
endmodule