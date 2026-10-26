`timescale 1ns / 1ps

module serdes_tx_monitor #(
    parameter integer DATA_W = 64,
    parameter integer HDR_W = 2,
    parameter integer MAX_SAMPLES = 512
) (
    input logic clk,
    input logic capture_enable,
    input logic clear,
    input logic [DATA_W-1:0] serdes_tx_data,
    input logic serdes_tx_data_valid,
    input logic [HDR_W-1:0] serdes_tx_hdr,
    input logic serdes_tx_hdr_valid,
    output integer unsigned sample_count,
    output logic overflow,
    output logic [DATA_W-1:0] sample_data [0:MAX_SAMPLES-1],
    output logic [HDR_W-1:0] sample_hdr [0:MAX_SAMPLES-1]
);

    always_ff @(posedge clk) begin
        if (clear) begin
            sample_count <= 0;
            overflow <= 1'b0;
        end else if (capture_enable && serdes_tx_data_valid && serdes_tx_hdr_valid) begin
            if (sample_count < MAX_SAMPLES) begin
                sample_data[sample_count] <= serdes_tx_data;
                sample_hdr[sample_count] <= serdes_tx_hdr;
                sample_count <= sample_count + 1;
            end else begin
                overflow <= 1'b1;
            end
        end
    end

endmodule
