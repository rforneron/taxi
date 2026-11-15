`timescale 1ns / 1ps
`default_nettype none

module mac_frame_scoreboard #(
    parameter integer MAX_FRAME_BYTES = 2048
) ();

    timeunit 1ns;
    timeprecision 1ps;

    task automatic compare_tx_frame(
        input logic [MAX_FRAME_BYTES*8-1:0] expected_data,
        input integer unsigned expected_len,
        input logic [MAX_FRAME_BYTES*8-1:0] observed_data,
        input integer unsigned observed_len,
        input logic preamble_valid,
        input logic sfd_valid
    );
        logic [31:0] expected_fcs;

        if (!preamble_valid || !sfd_valid) begin
            $fatal(1, "Scoreboard: TX preamble or SFD mismatch");
        end
        if (observed_len != expected_len + 4) begin
            $fatal(1, "Scoreboard: TX frame length %0d, expected %0d including FCS",
                observed_len, expected_len + 4);
        end

        for (integer byte_index = 0; byte_index < expected_len; byte_index = byte_index + 1) begin
            if (observed_data[byte_index*8 +: 8] !== expected_data[byte_index*8 +: 8]) begin
                $fatal(1, "Scoreboard: TX payload mismatch at byte %0d", byte_index);
            end
        end

        expected_fcs = mac_frame_pkg::ethernet_crc32(expected_data, expected_len);
        for (integer byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
            if (observed_data[(expected_len+byte_index)*8 +: 8] !== expected_fcs[byte_index*8 +: 8]) begin
                $fatal(1, "Scoreboard: TX FCS mismatch at byte %0d", byte_index);
            end
        end
    endtask

    task automatic compare_rx_frame(
        input logic [MAX_FRAME_BYTES*8-1:0] expected_data,
        input integer unsigned expected_len,
        input logic [MAX_FRAME_BYTES*8-1:0] observed_data,
        input integer unsigned observed_len,
        input logic observed_error
    );
        if (observed_error !== 1'b0) begin
            $fatal(1, "Scoreboard: RX marked a valid frame as erroneous");
        end
        if (observed_len != expected_len) begin
            $fatal(1, "Scoreboard: RX frame length %0d, expected %0d",
                observed_len, expected_len);
        end

        for (integer byte_index = 0; byte_index < expected_len; byte_index = byte_index + 1) begin
            if (observed_data[byte_index*8 +: 8] !== expected_data[byte_index*8 +: 8]) begin
                $fatal(1, "Scoreboard: RX payload mismatch at byte %0d", byte_index);
            end
        end
    endtask

    task automatic compare_completion_tag(
        input logic [15:0] expected_tag,
        input logic [15:0] observed_tag
    );
        if (observed_tag !== expected_tag) begin
            $fatal(1, "Scoreboard: TX completion tag %04x, expected %04x",
                observed_tag, expected_tag);
        end
    endtask

endmodule

`default_nettype wire
