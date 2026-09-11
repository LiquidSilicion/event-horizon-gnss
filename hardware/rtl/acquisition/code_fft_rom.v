`timescale 1ns / 1ps

module code_fft_rom #(
    parameter FFT_SIZE = 4096,
    parameter DATA_WIDTH = 18
)(
    input  wire                    clk,
    input  wire [4:0]              prn_sel,
    input  wire [$clog2(FFT_SIZE)-1:0] bin_idx,
    output reg signed [DATA_WIDTH-1:0] fft_i_out,
    output reg signed [DATA_WIDTH-1:0] fft_q_out
);

    // CRITICAL FIX: Hardcoded to 16 PRNs to save BRAM. 
    // 16 * 4096 = 65,536 entries. 
    // 65,536 * 18 bits * 2 (I & Q) = ~2.3 Mbits = ~64 BRAM36s (well under the 140 limit!)
    (* rom_style = "block" *) reg signed [DATA_WIDTH-1:0] fft_i_rom [0:65535];
    (* rom_style = "block" *) reg signed [DATA_WIDTH-1:0] fft_q_rom [0:65535];
    
    // Load the ROM files at initialization
    initial begin
        $readmemh("all_prns_fft_i.hex", fft_i_rom);
        $readmemh("all_prns_fft_q.hex", fft_q_rom);
    end
    
    // Calculate the ROM address based on PRN and bin index
    // Note: prn_sel must be 0 to 15 for this to work correctly!
    wire [15:0] rom_addr = (prn_sel * FFT_SIZE) + bin_idx;
    
    // Synchronous read (1 clock cycle latency)
    always @(posedge clk) begin
        fft_i_out <= fft_i_rom[rom_addr];
        fft_q_out <= fft_q_rom[rom_addr];
    end

endmodule