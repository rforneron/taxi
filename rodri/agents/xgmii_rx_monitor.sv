`timescale 1ns / 1ps

module xgmii_rx_monitor #(
    parameter integer DATA_W = 64,
    parameter integer CTRL_W = DATA_W / 8,
    parameter integer MAX_SAMPLES = 512
) (
    input logic clk,
    input logic capture_enable,
    input logic clear,
    input logic [DATA_W-1:0] xgmii_rxd,
    input logic [CTRL_W-1:0] xgmii_rxc,
    input logic xgmii_rx_valid,
    input logic rx_bad_block,
    input logic rx_sequence_error,
    output integer unsigned sample_count,
    output logic overflow,
    output logic [DATA_W-1:0] sample_data [0:MAX_SAMPLES-1],
    output logic [CTRL_W-1:0] sample_control [0:MAX_SAMPLES-1],
    output logic sample_bad_block [0:MAX_SAMPLES-1],
    output logic sample_sequence_error [0:MAX_SAMPLES-1]
);

    always_ff @(posedge clk) begin
        if (clear) begin
            sample_count <= 0;
            overflow <= 1'b0;
        end else if (capture_enable && xgmii_rx_valid) begin
            if (sample_count < MAX_SAMPLES) begin
                sample_data[sample_count] <= xgmii_rxd;
                sample_control[sample_count] <= xgmii_rxc;
                sample_bad_block[sample_count] <= rx_bad_block;
                sample_sequence_error[sample_count] <= rx_sequence_error;
                sample_count <= sample_count + 1;
            end else begin
                overflow <= 1'b1;
            end
        end
    end

endmodule
