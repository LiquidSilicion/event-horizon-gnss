`timescale 1ns / 1ps
//============================================================================
// AXI4-Lite Wrapper for N Tracking Channels
//
// Register map (per channel, stride = 0x100 bytes):
//   +0x00: carrier_freq_word[31:0]   (W)
//   +0x04: carrier_freq_word[47:32]  (W)
//   +0x08: code_freq_word            (W)
//   +0x0C: init_code_phase           (W)
//   +0x10: prn_sel [4:0] | channel_en [8]  (W)
//   +0x20: I_E  (R)
//   +0x24: Q_E  (R)
//   +0x28: I_P  (R)
//   +0x2C: Q_P  (R)
//   +0x30: I_L  (R)
//   +0x34: Q_L  (R)
//   +0x38: dump_valid [0], epoch_count [31:16]  (R)
//============================================================================

module axi_scalar_tracker #(
    parameter C_S_AXI_ADDR_WIDTH = 32,
    parameter C_S_AXI_DATA_WIDTH = 32
)(
    // Global Clock
    input wire  aclk,
    input wire  aresetn,

    // AXI4-Lite Slave Interface
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire                          S_AXI_AWVALID,
    output reg                           S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                          S_AXI_WVALID,
    output reg                           S_AXI_WREADY,
    output reg [1:0]                     S_AXI_BRESP,
    output reg                           S_AXI_BVALID,
    input  wire                          S_AXI_BREADY,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire                          S_AXI_ARVALID,
    output reg                           S_AXI_ARREADY,
    output reg [C_S_AXI_DATA_WIDTH-1:0]  S_AXI_RDATA,
    output reg [1:0]                     S_AXI_RRESP,
    output reg                           S_AXI_RVALID,
    input  wire                          S_AXI_RREADY,

    // RF Sample Input (From DMA/ADC)
    input wire signed [15:0] i_sample,
    input wire signed [15:0] q_sample,
    input wire               sample_valid
);

    // ==========================================
    // Internal Configuration Registers
    // ==========================================
    reg [31:0] carr_freq_lo = 0;
    reg [15:0] carr_freq_hi = 0;
    reg [31:0] code_freq    = 0;
    reg [31:0] init_code    = 0;
    reg [4:0]  prn_sel      = 0;
    reg        channel_en   = 0;

    wire [47:0] carrier_freq_word = {carr_freq_hi, carr_freq_lo};

    // ==========================================
    // DUT Instantiation (The Verified Datapath)
    // ==========================================
    wire signed [31:0] I_E, Q_E, I_P, Q_P, I_L, Q_L;
    wire dump_valid;
    reg [15:0] epoch_count = 0;

    tracking_channel #(
        .CH_ID(0),
        .SAMPLE_BITS(16),
        .ACCUM_BITS(32),
        .SAMPLES_PER_MS(4000) 
    ) u_tracking_ch (
        .clk(aclk),
        .rst_n(aresetn),
        .enable(sample_valid),
        .carrier_freq_word(carrier_freq_word),
        .code_freq_word(code_freq),
        .init_code_phase(init_code),
        .prn_sel(prn_sel),
        .channel_en(channel_en),
        .i_in(i_sample),
        .q_in(q_sample),
        .I_E(I_E), .Q_E(Q_E),
        .I_P(I_P), .Q_P(Q_P),
        .I_L(I_L), .Q_L(Q_L),
        .dump_valid(dump_valid),
        .carrier_phase()
    );

    // Epoch counter
    always @(posedge aclk) begin
        if (!aresetn) epoch_count <= 0;
        else if (dump_valid) epoch_count <= epoch_count + 1;
    end

    // ==========================================
    // AXI4-Lite Write Address & Data Handshake
    // ==========================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            S_AXI_AWREADY <= 0;
            S_AXI_WREADY  <= 0;
            S_AXI_BVALID  <= 0;
            S_AXI_BRESP   <= 2'b00; // OKAY
        end else begin
            // Acknowledge Address and Data
            if (S_AXI_AWVALID && S_AXI_WVALID && !S_AXI_AWREADY && !S_AXI_WREADY) begin
                // Execute Write
                case (S_AXI_AWADDR[7:0])
                    8'h00: carr_freq_lo <= S_AXI_WDATA;
                    8'h04: carr_freq_hi <= S_AXI_WDATA[15:0];
                    8'h08: code_freq    <= S_AXI_WDATA;
                    8'h0C: init_code    <= S_AXI_WDATA;
                    8'h10: begin
                        prn_sel    <= S_AXI_WDATA[4:0];
                        channel_en <= S_AXI_WDATA[8];
                    end
                endcase
                S_AXI_AWREADY <= 1;
                S_AXI_WREADY  <= 1;
                S_AXI_BVALID  <= 1;
            end else begin
                S_AXI_AWREADY <= 0;
                S_AXI_WREADY  <= 0;
                if (S_AXI_BREADY && S_AXI_BVALID) begin
                    S_AXI_BVALID <= 0;
                end
            end
        end
    end

    // ==========================================
    // AXI4-Lite Read Address & Data Handshake
    // ==========================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            S_AXI_ARREADY <= 0;
            S_AXI_RVALID  <= 0;
            S_AXI_RRESP   <= 2'b00; // OKAY
            S_AXI_RDATA   <= 0;
        end else begin
            if (S_AXI_ARVALID && !S_AXI_ARREADY) begin
                // Execute Read
                case (S_AXI_ARADDR[7:0])
                    8'h20: S_AXI_RDATA <= I_P;
                    8'h24: S_AXI_RDATA <= Q_P;
                    8'h28: S_AXI_RDATA <= {epoch_count, 15'b0, dump_valid};
                    default: S_AXI_RDATA <= 32'hDEADBEEF;
                endcase
                S_AXI_ARREADY <= 1;
                S_AXI_RVALID  <= 1;
            end else begin
                S_AXI_ARREADY <= 0;
                if (S_AXI_RREADY && S_AXI_RVALID) begin
                    S_AXI_RVALID <= 0;
                    S_AXI_ARREADY <= 0;
                end
            end
        end
    end

endmodule