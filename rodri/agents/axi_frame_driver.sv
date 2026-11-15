`timescale 1ns / 1ps
`default_nettype none

module axi_frame_driver #(
    parameter integer DATA_W = 64,
    parameter integer KEEP_W = DATA_W / 8,
    parameter integer TAG_W = 16,
    parameter integer MAX_FRAME_BYTES = 2048
) (
    input logic clk,
    input logic rst,
    taxi_axis_if.src axis
);

    timeunit 1ns;
    timeprecision 1ps;

    initial begin
        axis.tdata = '0;
        axis.tkeep = '0;
        axis.tstrb = '0;
        axis.tid = '0;
        axis.tdest = '0;
        axis.tuser = '0;
        axis.tlast = 1'b0;
        axis.tvalid = 1'b0;
    end

    task automatic send_frame(
        input logic [MAX_FRAME_BYTES*8-1:0] frame_data,
        input integer unsigned frame_len,
        input logic [TAG_W-1:0] frame_tag
    );
        integer unsigned offset;
        integer unsigned bytes_this_beat;

        if (frame_len == 0 || frame_len > MAX_FRAME_BYTES) begin
            $fatal(1, "AXI frame driver: invalid frame length %0d", frame_len);
        end

        offset = 0;
        while (offset < frame_len) begin
            @(negedge clk);
            if (rst !== 1'b0) begin
                $fatal(1, "AXI frame driver: reset asserted while sending a frame");
            end

            axis.tdata = '0;
            axis.tkeep = '0;
            axis.tstrb = '0;
            axis.tid = frame_tag;
            axis.tdest = '0;
            axis.tuser = '0;
            axis.tlast = 1'b0;
            axis.tvalid = 1'b1;

            bytes_this_beat = frame_len - offset;
            if (bytes_this_beat > KEEP_W) begin
                bytes_this_beat = KEEP_W;
            end

            for (integer lane = 0; lane < bytes_this_beat; lane = lane + 1) begin
                axis.tdata[lane*8 +: 8] = frame_data[(offset+lane)*8 +: 8];
                axis.tkeep[lane] = 1'b1;
                axis.tstrb[lane] = 1'b1;
            end
            axis.tlast = (offset + bytes_this_beat) == frame_len;

            do begin
                @(posedge clk);
            end while (axis.tready !== 1'b1);

            offset = offset + bytes_this_beat;
        end

        @(negedge clk);
        axis.tdata = '0;
        axis.tkeep = '0;
        axis.tstrb = '0;
        axis.tlast = 1'b0;
        axis.tvalid = 1'b0;
    endtask

endmodule

`default_nettype wire
