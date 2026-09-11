`timescale 1ns / 1ps

module result_reporter (
    input  wire clk,
    input  wire rst_n,
    input  wire acq_done,
    input  wire [4:0]  best_prn,
    input  wire [47:0] best_doppler,
    input  wire [11:0] best_code_phase,
    input  wire [7:0]  best_frac,
    input  wire [31:0] peak_mag,
    output reg uart_tx_start,
    output reg [7:0] uart_tx_data,
    input  wire uart_tx_busy
);
    
    localparam [3:0] IDLE       = 4'd0,
                     SEND_PRN   = 4'd1,
                     SEND_DOP   = 4'd2,
                     SEND_CODE  = 4'd3,
                     SEND_FRAC  = 4'd4, // Fixed sequential numbering
                     SEND_MAG   = 4'd5,
                     SEND_NL    = 4'd6;
    
    reg [3:0]  state;
    reg [3:0]  char_idx;
    reg [47:0] doppler_shift;
    reg [11:0] code_phase_shift; // Added to fix input wire shifting bug
    reg [7:0]  frac_shift;       // Added to send full 8-bit frac
    reg [31:0] mag_shift;
    reg [3:0]  hex_digit;
    
    function [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            if (hex < 10)
                hex_to_ascii = 8'h30 + hex;  // '0' to '9'
            else
                hex_to_ascii = 8'h41 + (hex - 10);  // 'A' to 'F'
        end
    endfunction
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            uart_tx_start    <= 1'b0;
            uart_tx_data     <= 8'h00;
            char_idx         <= 4'd0;
            doppler_shift    <= 48'd0;
            code_phase_shift <= 12'd0;
            frac_shift       <= 8'd0;
            mag_shift        <= 32'd0;
            hex_digit        <= 4'd0;
        end else begin
            uart_tx_start <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (acq_done) begin
                        state            <= SEND_PRN;
                        char_idx         <= 4'd0;
                        doppler_shift    <= best_doppler;
                        code_phase_shift <= best_code_phase;
                        frac_shift       <= best_frac;
                        mag_shift        <= peak_mag;
                    end
                end
                
                SEND_PRN: begin
                    if (!uart_tx_busy) begin
                        uart_tx_data  <= hex_to_ascii(best_prn); // PRN is 5 bits, fits in 1 hex char
                        uart_tx_start <= 1'b1;
                        state         <= SEND_DOP;
                        char_idx      <= 4'd0;
                    end
                end
                
                SEND_DOP: begin
                    if (!uart_tx_busy) begin
                        if (char_idx < 12) begin
                            hex_digit      <= doppler_shift[47:44];
                            uart_tx_data   <= hex_to_ascii(hex_digit);
                            uart_tx_start  <= 1'b1;
                            doppler_shift  <= {doppler_shift[43:0], 4'b0000};
                            char_idx       <= char_idx + 1'b1;
                        end else begin
                            state    <= SEND_CODE;
                            char_idx <= 4'd0;
                        end
                    end
                end
                
                SEND_CODE: begin
                    if (!uart_tx_busy) begin
                        if (char_idx < 3) begin
                            hex_digit        <= code_phase_shift[11:8];
                            uart_tx_data     <= hex_to_ascii(hex_digit);
                            uart_tx_start    <= 1'b1;
                            code_phase_shift <= {code_phase_shift[7:0], 4'b0000};
                            char_idx         <= char_idx + 1'b1;
                        end else begin
                            state    <= SEND_FRAC;
                            char_idx <= 4'd0;
                        end
                    end
                end
                
                SEND_FRAC: begin
                    if (!uart_tx_busy) begin
                        if (char_idx < 2) begin // Send 2 hex chars for 8-bit frac
                            hex_digit    <= frac_shift[7:4];
                            uart_tx_data <= hex_to_ascii(hex_digit);
                            uart_tx_start<= 1'b1;
                            frac_shift   <= {frac_shift[3:0], 4'b0000};
                            char_idx     <= char_idx + 1'b1;
                        end else begin
                            state    <= SEND_MAG;
                            char_idx <= 4'd0;
                        end
                    end
                end
                
                SEND_MAG: begin
                    if (!uart_tx_busy) begin
                        if (char_idx < 8) begin
                            hex_digit   <= mag_shift[31:28];
                            uart_tx_data<= hex_to_ascii(hex_digit);
                            uart_tx_start<= 1'b1;
                            mag_shift   <= {mag_shift[27:0], 4'b0000};
                            char_idx    <= char_idx + 1'b1;
                        end else begin
                            state    <= SEND_NL;
                            char_idx <= 4'd0;
                        end
                    end
                end
                
                SEND_NL: begin
                    if (!uart_tx_busy) begin
                        if (char_idx == 0) begin
                            uart_tx_data  <= 8'h0D;  // Carriage Return
                            uart_tx_start <= 1'b1;
                            char_idx      <= 4'd1;
                        end else if (char_idx == 1) begin
                            uart_tx_data  <= 8'h0A;  // Line Feed
                            uart_tx_start <= 1'b1;
                            state         <= IDLE;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule