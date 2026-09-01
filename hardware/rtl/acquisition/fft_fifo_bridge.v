`timescale 1ns / 1ps

module fft_fifo_bridge #(
    parameter FIFO_DEPTH = 8192
)(
    input  wire        wr_clk,           
    input  wire        wr_rst_n,         
    input  wire signed [17:0] i_in,
    input  wire signed [17:0] q_in,
    input  wire        sample_valid,
    input  wire        last_sample,      
    
    input  wire        rd_clk,           
    input  wire        rd_rst_n,
    output reg  signed [17:0] i_out,
    output reg  signed [17:0] q_out,
    output reg         data_valid,
    output reg         last_out,         
    
    output wire        fifo_full,
    output wire        fifo_empty
);

    wire [63:0] fifo_din;
    assign fifo_din = {28'b0, q_in[17:0], i_in[17:0]};
    
    wire [63:0] fifo_dout;
    wire        fifo_valid;
    wire        ip_full;
    wire        ip_empty;
    
    assign fifo_full  = ip_full;
    assign fifo_empty = ip_empty;

    // ============================================================
    // THE FIX: rd_en is driven by ~empty, NOT by fifo_valid
    // This breaks the deadlock. We read whenever FIFO has data.
    // ============================================================
    wire rd_enable = ~ip_empty;

    fifo_fft_bridge u_fifo (
      .rst(~wr_rst_n),          
      .wr_clk(wr_clk),          
      .rd_clk(rd_clk),          
      .din(fifo_din),           
      .wr_en(sample_valid),     
      .rd_en(rd_enable),        // FIXED: Read when FIFO has data
      .dout(fifo_dout),         
      .full(ip_full),           
      .empty(ip_empty),         
      .valid(fifo_valid)        // FIFO tells us when dout is valid
    );

    // Capture data when FIFO says it's valid
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            i_out      <= 18'sd0;
            q_out      <= 18'sd0;
            data_valid <= 1'b0;
            last_out   <= 1'b0;
        end else begin
            // Register fifo_valid to align with captured data
            data_valid <= fifo_valid;
            
            if (fifo_valid) begin
                i_out    <= fifo_dout[17:0];
                q_out    <= fifo_dout[35:18];
                last_out <= last_sample;
            end
        end
    end

endmodule