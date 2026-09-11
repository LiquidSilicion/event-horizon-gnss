`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output reg        tx_busy
);
    
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;
    
    localparam [2:0] IDLE      = 3'd0,
                     START_BIT = 3'd1,
                     DATA_BIT  = 3'd2,
                     STOP_BIT  = 3'd3;
    
    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_data_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx        <= 1'b1;
            tx_busy    <= 1'b0;
            clk_cnt    <= 16'd0;
            bit_idx    <= 3'd0;
            tx_data_reg <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    tx     <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_data_reg <= tx_data;
                        state     <= START_BIT;
                        tx_busy <= 1'b1;
                        clk_cnt    <= 16'd0;
                    end
                end
                
                START_BIT: begin
                    tx <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt  <= 16'd0;
                        bit_idx  <= 3'd0;
                        state    <= DATA_BIT;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                DATA_BIT: begin
                    tx <= tx_data_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt  <= 16'd0;
                        if (bit_idx == 7) begin
                            state <= STOP_BIT;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                STOP_BIT: begin
                    tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state    <= IDLE;
                        tx_busy <= 1'b0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule