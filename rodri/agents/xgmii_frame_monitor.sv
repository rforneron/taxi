`timescale 1ns / 1ps
`default_nettype none

module xgmii_frame_monitor #(
    parameter integer DATA_W = 64,
    parameter integer CTRL_W = DATA_W / 8,
    parameter integer MAX_FRAME_BYTES = 2048
) (
    input logic clk,
    input logic rst,
    input logic capture_enable,
    input logic [DATA_W-1:0] xgmii_txd,
    input logic [CTRL_W-1:0] xgmii_txc,
    input logic xgmii_tx_valid,
    output logic [MAX_FRAME_BYTES*8-1:0] frame_data,
    output integer unsigned frame_len,
    output logic preamble_valid,
    output logic sfd_valid,
    output logic frame_done
);

    timeunit 1ns;
    timeprecision 1ps;

    logic capturing;
    integer unsigned preamble_count;

    always @(posedge clk) begin
        if (rst || !capture_enable) begin
            frame_data = '0;
            frame_len = 0;
            preamble_valid = 1'b1;
            sfd_valid = 1'b0;
            frame_done = 1'b0;
            capturing = 1'b0;
            preamble_count = 0;
        end else if (!frame_done && xgmii_tx_valid === 1'b1) begin
            for (integer lane = 0; lane < CTRL_W && !frame_done; lane = lane + 1) begin
                logic [7:0] data_byte;
                data_byte = xgmii_txd[lane*8 +: 8];

                if (!capturing) begin
                    if (xgmii_txc[lane] && data_byte == 8'hfb) begin
                        capturing = 1'b1;
                    end
                end else if (xgmii_txc[lane] && data_byte == 8'hfd) begin
                    frame_done = 1'b1;
                end else if (xgmii_txc[lane]) begin
                    $fatal(1, "XGMII monitor: unexpected control character %02x inside frame", data_byte);
                end else if (preamble_count < 6) begin
                    if (data_byte != 8'h55) begin
                        preamble_valid = 1'b0;
                    end
                    preamble_count = preamble_count + 1;
                end else if (preamble_count == 6) begin
                    sfd_valid = (data_byte == 8'hd5);
                    preamble_count = preamble_count + 1;
                end else begin
                    if (frame_len >= MAX_FRAME_BYTES) begin
                        $fatal(1, "XGMII monitor: captured frame exceeds configured capacity");
                    end
                    frame_data[frame_len*8 +: 8] = data_byte;
                    frame_len = frame_len + 1;
                end
            end
        end
    end

endmodule

`default_nettype wire
