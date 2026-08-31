`timescale 1ns / 1ps

module fft_wrapper #(
    parameter FFT_SIZE = 4096,
    parameter DATA_WIDTH = 18
)(
    input wire clk,
    input wire rst_n,
    
    // Control
    input wire start,              // Pulse high for 1 cycle to configure and start
    output reg done,               // Pulses high when the last output sample is transferred
    
    // Input Data (from ADC or signal generator)
    input wire signed [DATA_WIDTH-1:0] i_in,
    input wire signed [DATA_WIDTH-1:0] q_in,
    input wire in_valid,           // High when input data is valid
    output wire in_ready,          // Driven by FFT IP: High when it can accept data
    
    // Output Data (FFT result)
    output reg signed [DATA_WIDTH-1:0] i_out,
    output reg signed [DATA_WIDTH-1:0] q_out,
    output reg out_valid,          // High when output data is valid
    input wire out_ready,          // High when downstream can accept data
    
    // Configuration
    input wire inverse             // 0 = Forward FFT, 1 = Inverse FFT
);

    // Internal AXI4-Stream signals
    wire [15:0] config_tdata = {15'b0, inverse};
    wire config_tvalid = start;
    wire config_tready;
    
    // Xilinx FFT expects {Imaginary, Real} or {Real, Imaginary} depending on config. 
    // We'll use {q_in, i_in} as a placeholder. Verify this in your IP config.
    wire [2*DATA_WIDTH-1:0] s_axis_data_tdata = {q_in, i_in}; 
    wire s_axis_data_tvalid;
    wire s_axis_data_tready;
    wire s_axis_data_tlast;
    
    wire [2*DATA_WIDTH-1:0] m_axis_data_tdata;
    wire m_axis_data_tvalid;
    wire m_axis_data_tready = out_ready;
    wire m_axis_data_tlast;
    
    // The FFT IP drives s_axis_data_tready. We expose this as in_ready.
    assign in_ready = s_axis_data_tready;

    // =========================================================================
    // FFT IP Instantiation
    // IMPORTANT: Replace 'fft_acq_4096_18b' with the EXACT name of the 
    // Xilinx FFT IP you generated in the Vivado IP Catalog!
    // =========================================================================
    fft_acq_4096_18b u_fft (
        .aclk(clk),
        .aresetn(rst_n),
        
        // Configuration interface
        .s_axis_config_tdata(config_tdata),
        .s_axis_config_tvalid(config_tvalid),
        .s_axis_config_tready(config_tready),
        
        // Data input interface
        .s_axis_data_tdata(s_axis_data_tdata),
        .s_axis_data_tvalid(s_axis_data_tvalid),
        .s_axis_data_tready(s_axis_data_tready),
        .s_axis_data_tlast(s_axis_data_tlast),
        
        // Data output interface
        .m_axis_data_tdata(m_axis_data_tdata),
        .m_axis_data_tvalid(m_axis_data_tvalid),
        .m_axis_data_tready(m_axis_data_tready),
        .m_axis_data_tlast(m_axis_data_tlast),
        
        // Event ports (optional, can be left unconnected)
        .event_frame_started(),
        .event_tlast_unexpected(),
        .event_tlast_missing(),
        .event_status_channel_halt(),
        .event_data_in_channel_halt(),
        .event_data_out_channel_halt()
    );
    
    // =========================================================================
    // State machine to manage the AXI4-Stream flow
    // =========================================================================
    localparam IDLE = 3'd0;
    localparam LOAD = 3'd1;
    localparam UNLOAD = 3'd2;
    
    reg [2:0] state;
    reg [11:0] sample_count;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            out_valid <= 0;
            i_out <= 0;
            q_out <= 0;
            sample_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    out_valid <= 0;
                    sample_count <= 0;
                    if (start) begin
                        state <= LOAD;
                    end
                end
                
                LOAD: begin
                    if (in_valid && s_axis_data_tready) begin
                        sample_count <= sample_count + 1;
                        if (sample_count == FFT_SIZE - 1) begin
                            state <= UNLOAD;
                        end
                    end
                end
                
                UNLOAD: begin
                    if (m_axis_data_tvalid && out_ready) begin
                        // Capture the output data. 
                        // NOTE: Verify the order in your FFT IP config. 
                        // It is usually {Real, Imag} for Natural Order, but check the docs.
                        i_out <= m_axis_data_tdata[2*DATA_WIDTH-1 : DATA_WIDTH]; // Real
                        q_out <= m_axis_data_tdata[DATA_WIDTH-1:0];              // Imag
                        
                        sample_count <= sample_count + 1;
                        out_valid <= 1;
                        
                        // Check if this is the last output sample
                        if (m_axis_data_tlast || sample_count == FFT_SIZE - 1) begin
                            state <= IDLE;
                            done <= 1;
                            out_valid <= 0;
                        end
                    end else begin
                        out_valid <= 0;
                    end
                end
            endcase
        end
    end
    
    // Combinational assignments for control signals
    assign s_axis_data_tvalid = (state == LOAD) && in_valid;
    assign s_axis_data_tlast  = (state == LOAD) && in_valid && (sample_count == FFT_SIZE - 1);

endmodule