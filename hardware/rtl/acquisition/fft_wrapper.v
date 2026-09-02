`timescale 1ns / 1ps

module fft_wrapper #(
    parameter FFT_SIZE = 4096,
    parameter DATA_WIDTH = 18
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    output reg done,
    input wire signed [DATA_WIDTH-1:0] i_in,
    input wire signed [DATA_WIDTH-1:0] q_in,
    input wire in_valid,
    output wire in_ready,
    output reg signed [DATA_WIDTH-1:0] i_out,
    output reg signed [DATA_WIDTH-1:0] q_out,
    output reg [11:0] out_index,
    output reg out_valid,
    input wire out_ready,
    input wire inverse
);

    wire [7:0] config_tdata = {4'd12, 3'b000, inverse};
    
    reg config_valid_reg;
    wire config_tvalid = config_valid_reg;
    wire config_tready;
    
    always @(posedge clk) begin
        if (!rst_n) config_valid_reg <= 1'b0;
        else if (start) config_valid_reg <= 1'b1;
        else if (config_tready) config_valid_reg <= 1'b0;
    end

    wire [47:0] s_axis_data_tdata = { {6'b0, i_in}, {6'b0, q_in} }; 
    wire s_axis_data_tvalid;
    wire s_axis_data_tready;
    wire s_axis_data_tlast;
    
    wire [47:0] m_axis_data_tdata;
    wire m_axis_data_tvalid;
    wire m_axis_data_tready;
    wire m_axis_data_tlast;
    
    assign in_ready = s_axis_data_tready;

    fft_acq_4096_18b u_fft (
        .aclk(clk),
        .aclken(1'b1),
        .aresetn(rst_n),
        .s_axis_config_tdata(config_tdata),
        .s_axis_config_tvalid(config_tvalid),
        .s_axis_config_tready(config_tready),
        .s_axis_data_tdata(s_axis_data_tdata),
        .s_axis_data_tvalid(s_axis_data_tvalid),
        .s_axis_data_tready(s_axis_data_tready),
        .s_axis_data_tlast(s_axis_data_tlast),
        .m_axis_data_tdata(m_axis_data_tdata),
        .m_axis_data_tuser(),
        .m_axis_data_tvalid(m_axis_data_tvalid),
        .m_axis_data_tready(m_axis_data_tready),
        .m_axis_data_tlast(m_axis_data_tlast),
        .m_axis_status_tdata(),
        .m_axis_status_tvalid(),
        .m_axis_status_tready(1'b1),
        .event_frame_started(),
        .event_tlast_unexpected(),
        .event_tlast_missing(),
        .event_status_channel_halt(),
        .event_data_in_channel_halt(),
        .event_data_out_channel_halt()
    );
    
    localparam IDLE = 3'd0;
    localparam LOAD = 3'd1;
    localparam UNLOAD = 3'd2;
    
    reg [2:0] state;
    reg [11:0] sample_count;
    reg [11:0] out_count;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            out_valid <= 0;
            i_out <= 0;
            q_out <= 0;
            out_index <= 0;
            sample_count <= 0;
            out_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    out_valid <= 0;
                    sample_count <= 0;
                    out_count <= 0;
                    if (start) state <= LOAD;
                end
                
                LOAD: begin
                    if (in_valid && s_axis_data_tready) begin
                        sample_count <= sample_count + 1;
                        if (sample_count == FFT_SIZE - 1) begin
                            state <= UNLOAD;
                            $display("[%0t] ✅ FFT_WRAPPER: Transitioning to UNLOAD", $time);
                        end
                    end
                end
                
                UNLOAD: begin
                    // ✅ FIXED: Only accept data when out_ready is high AND we haven't output all samples yet
                    if (m_axis_data_tvalid && out_ready && out_count < FFT_SIZE) begin
                        i_out <= m_axis_data_tdata[41:24]; 
                        q_out <= m_axis_data_tdata[17:0];              
                        out_index <= out_count;
                        
                        out_count <= out_count + 1;
                        out_valid <= 1;
                        
                        // ✅ FIXED: Transition back to IDLE after outputting all samples
                        if (out_count == FFT_SIZE - 1) begin
                            state <= IDLE;
                            done <= 1;
                            out_valid <= 0;
                            $display("[%0t] ✅ FFT_WRAPPER: Completed output, returning to IDLE", $time);
                        end
                    end else begin
                        out_valid <= 0;
                    end
                end
            endcase
        end
    end
    
    assign s_axis_data_tvalid = (state == LOAD) && in_valid;
    assign s_axis_data_tlast  = (state == LOAD) && in_valid && (sample_count == FFT_SIZE - 1);
    
    // ✅ FIXED: Only assert m_axis_data_tready when we're in UNLOAD state and haven't finished
    assign m_axis_data_tready = (state == UNLOAD) && out_ready && (out_count < FFT_SIZE);

endmodule