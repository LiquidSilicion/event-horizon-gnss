`timescale 1ns / 1ps

module stimulus_generator #(
    parameter FFT_SIZE = 4096,
    parameter DATA_WIDTH = 16,
    parameter FILE_I = "stim_i.hex",
    parameter FILE_Q = "stim_q.hex"
)(
    input  wire                     clk,          // 100 MHz system clock
    input  wire                     rst_n,
    input  wire                     enable,       // High when acquisition is active
    input  wire                     sample_en,    // ✅ NEW: 4 MHz pulse (1 out of every 25 cycles)
    output reg                      sample_valid,
    output reg signed [DATA_WIDTH-1:0] sample_i,
    output reg signed [DATA_WIDTH-1:0] sample_q
);

    // Memory to hold the stimulus data
    reg signed [DATA_WIDTH-1:0] mem_i [0:FFT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] mem_q [0:FFT_SIZE-1];
    
    reg [11:0] addr;
    reg        running;

    // Load hex files into memory at startup
    initial begin
        $readmemh(FILE_I, mem_i);
        $readmemh(FILE_Q, mem_q);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr          <= 12'd0;
            running       <= 1'b0;
            sample_valid  <= 1'b0;
            sample_i      <= 16'd0;
            sample_q      <= 16'd0;
        end else begin
            // Start streaming when enabled and not already running
            if (enable && !running) begin
                running <= 1'b1;
                addr    <= 12'd0;
            end
            
            if (running) begin
                // ✅ Only output a sample when the 4 MHz enable pulse fires
                if (sample_en) begin
                    sample_valid <= 1'b1;
                    sample_i     <= mem_i[addr];
                    sample_q     <= mem_q[addr];
                    
                    if (addr == FFT_SIZE - 1) begin
                        running <= 1'b0; // Stop after 4096 samples
                    end else begin
                        addr <= addr + 1'b1;
                    end
                end else begin
                    sample_valid <= 1'b0;
                end
            end else begin
                sample_valid <= 1'b0;
            end
        end
    end

endmodule