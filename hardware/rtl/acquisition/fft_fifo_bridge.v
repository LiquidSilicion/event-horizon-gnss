module fft_fifo_bridge #(
    parameter FIFO_DEPTH = 8192
)(
    // Write side (100 MHz domain)
    input  wire        wr_clk,           // 100 MHz
    input  wire        wr_rst_n,
    input  wire signed [17:0] i_in,
    input  wire signed [17:0] q_in,
    input  wire        sample_valid,
    input  wire        last_sample,      // pulses on 4000th sample
    
    // Read side (200 MHz domain)
    input  wire        rd_clk,           // 200 MHz
    input  wire        rd_rst_n,
    output reg  signed [17:0] i_out,
    output reg  signed [17:0] q_out,
    output reg         data_valid,
    output reg         last_out,         // forwarded TLAST
    
    // Status
    output wire        fifo_full,
    output wire        fifo_empty
);

    // ==========================================
    // Pack data for FIFO write (64-bit)
    // ==========================================
    wire [63:0] fifo_din;
    assign fifo_din = {28'b0, q_in[17:0], i_in[17:0]};
    
    // ==========================================
    // AXI4-Stream FIFO Instance
    // ==========================================
    wire [63:0] fifo_dout;
    wire        wr_en, rd_en, tlast_out;
    
    fifo_fft_bridge u_fifo (
        .wr_clk(wr_clk),
        .wr_rst(~wr_rst_n),
        .wr_en(wr_en),
        .wr_data(fifo_din),
        .wr_ack(),
        .full(fifo_full),
        
        .rd_clk(rd_clk),
        .rd_rst(~rd_rst_n),
        .rd_en(rd_en),
        .rd_data(fifo_dout),
        .valid(data_valid),
        .empty(fifo_empty),
        
        // TLAST handling
        .wr_data_count(),
        .rd_data_count()
    );
    
    // Write control
    assign wr_en = sample_valid && !fifo_full;
    
    // Read control (always read when data available)
    assign rd_en = data_valid && !fifo_empty;
    
    // ==========================================
    // Unpack data on read side (200 MHz)
    // ==========================================
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            i_out <= 0;
            q_out <= 0;
        end else if (rd_en) begin
            i_out <= fifo_dout[17:0];
            q_out <= fifo_dout[35:18];
        end
    end

endmodule