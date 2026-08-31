`timescale 1ns / 1ps

module fft_ifft_wrapper #(
    parameter FFT_SIZE = 4096,          // No. of points in the FFT(e.g., 4096)
    parameter DATA_WIDTH = 18,          // Must match your IP config (e.g., 18)
    parameter CONFIG_WIDTH = 16         // Xilinx FFT config port is always 16 bits
)(
    input  wire clk,
    input  wire rst_n,
    
    // Control Signals
    input  wire start,          // Pulse high for 1 cycle to start a transform
    input  wire do_ifft,        // 0 = Forward FFT, 1 = Inverse FFT (IFFT)
    
    // AXI4-Stream Input (Data going INTO the FFT)
    input  wire [2*DATA_WIDTH-1:0] s_axis_data_tdata,   // {imaginary, real}
    input  wire s_axis_data_tvalid,
    output wire s_axis_data_tready,
    
    // AXI4-Stream Output (Data coming OUT of the FFT)
    output wire [2*DATA_WIDTH-1:0] m_axis_data_tdata,   // {imaginary, real}
    output wire m_axis_data_tvalid,
    input  wire m_axis_data_tready
);

    // Internal wires for the Xilinx IP
    wire [CONFIG_WIDTH-1:0] config_tdata;
    wire config_tvalid;
    wire config_tready;
    
    wire event_frame_started;
    wire event_tlast_unexpected;
    wire event_tlast_missing;
    wire event_status_channel_halt;
    wire event_data_in_channel_halt;
    wire event_data_out_channel_halt;

    // =========================================================
    // Configuration Logic
    // =========================================================
    // Bit 0 of config_tdata controls Forward (0) vs Inverse (1)
    // We hold this valid whenever we are actively processing a frame
    reg config_valid_reg;
    // Counter needs to count up to FFT_SIZE, so we use $clog2 to size it correctly
    reg [$clog2(FFT_SIZE)-1:0] out_count;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            config_valid_reg <= 1'b0;
            out_count <= 0;
        end else if (start) begin
            // On start, enable config and reset the output counter
            config_valid_reg <= 1'b1;
            out_count <= 0;
        end else if (m_axis_data_tvalid && m_axis_data_tready) begin
            // Count every successfully transferred output sample
            if (out_count == FFT_SIZE - 1) begin
                config_valid_reg <= 1'b0; // Last sample transferred, drop config valid
                out_count <= 0;           // Reset for next frame
            end else begin
                out_count <= out_count + 1;
            end
        end
    end
    
    // Bit 0 of config_tdata controls Forward (0) vs Inverse (1)
    assign config_tdata   = {15'b0, do_ifft}; 
    assign config_tvalid  = config_valid_reg;

    // =========================================================
    // Xilinx FFT IP Instantiation
    // IMPORTANT: Replace 'fft_4096_18b' with the EXACT name of 
    // the IP core you generated in the Vivado IP Catalog!
    // =========================================================
    fft_4096_18b u_fft_core (
        .aclk(clk),
        .aresetn(rst_n),
        
        // Configuration Interface
        .s_axis_config_tdata(config_tdata),
        .s_axis_config_tvalid(config_tvalid),
        .s_axis_config_tready(config_tready),
        
        // Data Input Interface
        .s_axis_data_tdata(s_axis_data_tdata),
        .s_axis_data_tvalid(s_axis_data_tvalid),
        .s_axis_data_tready(s_axis_data_tready),
        .s_axis_data_tlast(1'b0), // Not strictly needed for basic Burst mode
        
        // Data Output Interface
        .m_axis_data_tdata(m_axis_data_tdata),
        .m_axis_data_tvalid(m_axis_data_tvalid),
        .m_axis_data_tready(m_axis_data_tready),
        .m_axis_data_tlast(),     // Optional
        
        // Event Ports (Can be left unconnected if not debugging)
        .event_frame_started(event_frame_started),
        .event_tlast_unexpected(event_tlast_unexpected),
        .event_tlast_missing(event_tlast_missing),
        .event_status_channel_halt(event_status_channel_halt),
        .event_data_in_channel_halt(event_data_in_channel_halt),
        .event_data_out_channel_halt(event_data_out_channel_halt)
    );

endmodule