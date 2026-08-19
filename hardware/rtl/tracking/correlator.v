`timescale 1ns / 1ps
//============================================================================
// Correlator: Early/Prompt/Late Integrate-and-Dump
//
// Python equivalent (from compute_idump):
//   I_E += i_wiped * code_e
//   Q_E += q_wiped * code_e
//   ... (6 accumulators)
//
// Hardware: 6 DSP48-based MAC units, accumulate for 4000 samples (1 ms @ 4 MHz)
//           Output: 32-bit signed I/Q for E/P/L
//============================================================================

module correlator #(
    parameter SAMPLE_BITS    = 16,
    parameter ACCUM_BITS     = 32,
    parameter SAMPLES_PER_MS = 4000,   // 4 MHz * 1 ms
    parameter EARLY_OFFSET   = -512,   // -0.5 chips (10-bit fractional)
    parameter LATE_OFFSET    =  512    // +0.5 chips
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          enable,
    
    // Wiped-off I/Q input (from carrier mixer)
    input  wire signed [SAMPLE_BITS-1:0] i_wiped,
    input  wire signed [SAMPLE_BITS-1:0] q_wiped,
    
    // Code chips at E/P/L positions (from code gen)
    input  wire                          code_e,
    input  wire                          code_p,
    input  wire                          code_l,
    
    // 1 ms epoch boundary (from code NCO rollover or sample counter)
    input  wire                          epoch_tick,
    
    // I&D dump outputs
    output reg signed [ACCUM_BITS-1:0] I_E, Q_E,
    output reg signed [ACCUM_BITS-1:0] I_P, Q_P,
    output reg signed [ACCUM_BITS-1:0] I_L, Q_L,
    output reg                         dump_valid
);

    // Convert code chip (0/1) to signed value (-1/+1)
    wire signed [2:0] ce_s = code_e ? 3'sd1 : -3'sd1;
    wire signed [2:0] cp_s = code_p ? 3'sd1 : -3'sd1;
    wire signed [2:0] cl_s = code_l ? 3'sd1 : -3'sd1;
    
    // 6 accumulators
    reg signed [ACCUM_BITS-1:0] acc_IE, acc_QE;
    reg signed [ACCUM_BITS-1:0] acc_IP, acc_QP;
    reg signed [ACCUM_BITS-1:0] acc_IL, acc_QL;
    
    // Sample counter (0 to 3999)
    reg [$clog2(SAMPLES_PER_MS)-1:0] sample_cnt;
    
    // Multiply-accumulate (DSP48)
    wire signed [SAMPLE_BITS+2:0] prod_IE = i_wiped * ce_s;
    wire signed [SAMPLE_BITS+2:0] prod_QE = q_wiped * ce_s;
    wire signed [SAMPLE_BITS+2:0] prod_IP = i_wiped * cp_s;
    wire signed [SAMPLE_BITS+2:0] prod_QP = q_wiped * cp_s;
    wire signed [SAMPLE_BITS+2:0] prod_IL = i_wiped * cl_s;
    wire signed [SAMPLE_BITS+2:0] prod_QL = q_wiped * cl_s;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            acc_IE <= 0; acc_QE <= 0;
            acc_IP <= 0; acc_QP <= 0;
            acc_IL <= 0; acc_QL <= 0;
            sample_cnt <= 0;
            dump_valid <= 0;
            I_E <= 0; Q_E <= 0;
            I_P <= 0; Q_P <= 0;
            I_L <= 0; Q_L <= 0;
        end else if (enable) begin
            dump_valid <= 0;
            
            if (epoch_tick || sample_cnt == SAMPLES_PER_MS - 1) begin
                // End of 1 ms: latch outputs, reset accumulators
                I_E <= acc_IE + prod_IE;
                Q_E <= acc_QE + prod_QE;
                I_P <= acc_IP + prod_IP;
                Q_P <= acc_QP + prod_QP;
                I_L <= acc_IL + prod_IL;
                Q_L <= acc_QL + prod_QL;
                dump_valid <= 1;
                
                acc_IE <= 0; acc_QE <= 0;
                acc_IP <= 0; acc_QP <= 0;
                acc_IL <= 0; acc_QL <= 0;
                sample_cnt <= 0;
            end else begin
                // Accumulate
                acc_IE <= acc_IE + prod_IE;
                acc_QE <= acc_QE + prod_QE;
                acc_IP <= acc_IP + prod_IP;
                acc_QP <= acc_QP + prod_QP;
                acc_IL <= acc_IL + prod_IL;
                acc_QL <= acc_QL + prod_QL;
                sample_cnt <= sample_cnt + 1;
            end
        end
    end

endmodule