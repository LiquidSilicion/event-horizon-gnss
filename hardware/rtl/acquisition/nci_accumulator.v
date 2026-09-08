`timescale 1ns / 1ps

module nci_accumulator #(
    parameter FFT_SIZE     = 4096,
    parameter DATA_WIDTH   = 18,
    parameter MAG_WIDTH    = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    input  wire                    clear,          
    output wire                    clear_done,     
    
    input  wire                    fft_out_valid,
    input  wire signed [DATA_WIDTH-1:0] i_in,
    input  wire signed [DATA_WIDTH-1:0] q_in,
    
    output wire [MAG_WIDTH-1:0]    mag_out,
    input  wire [11:0]             read_addr
);

    reg [MAG_WIDTH-1:0] accum_mem [0:FFT_SIZE-1];
    reg [11:0] sample_cnt;
    reg clearing;
    reg [11:0] clear_addr;
    
    // Explicit wires and assigns to avoid parser issues
    wire signed [2*DATA_WIDTH-1:0] i_sq;
    wire signed [2*DATA_WIDTH-1:0] q_sq;
    wire [MAG_WIDTH-1:0] magnitude;
    
    assign i_sq = $signed(i_in) * $signed(i_in);
    assign q_sq = $signed(q_in) * $signed(q_in);
    assign magnitude = (i_sq + q_sq) >>> 4;
    
    assign mag_out = accum_mem[read_addr];
    assign clear_done = ~clearing;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            sample_cnt <= 12'd0;
            clearing <= 1'b0;
            clear_addr <= 12'd0;
        end else begin
            if (clear) begin
                clearing <= 1'b1;
                clear_addr <= 12'd0;
                sample_cnt <= 12'd0;
            end else if (clearing) begin
                accum_mem[clear_addr] <= {MAG_WIDTH{1'b0}};
                if (clear_addr == FFT_SIZE - 1) begin
                    clearing <= 1'b0;
                end else begin
                    clear_addr <= clear_addr + 12'd1;
                end
            end else if (fft_out_valid) begin
                accum_mem[sample_cnt] <= accum_mem[sample_cnt] + magnitude;
                if (sample_cnt == FFT_SIZE - 1) begin
                    sample_cnt <= 12'd0;
                end else begin
                    sample_cnt <= sample_cnt + 12'd1;
                end
            end
        end
    end

endmodule