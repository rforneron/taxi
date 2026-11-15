`timescale 1ns / 1ps

package mac_frame_pkg;

    parameter integer MAX_FRAME_BYTES = 2048;

    function automatic logic [31:0] ethernet_crc32(
        input logic [MAX_FRAME_BYTES*8-1:0] frame_data,
        input integer unsigned frame_len
    );
        logic [31:0] crc;
        logic [7:0] data_byte;

        crc = 32'hffff_ffff;
        for (integer byte_index = 0; byte_index < frame_len; byte_index = byte_index + 1) begin
            data_byte = frame_data[byte_index*8 +: 8];
            crc = crc ^ {24'd0, data_byte};
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (crc[0]) begin
                    crc = (crc >> 1) ^ 32'hedb8_8320;
                end else begin
                    crc = crc >> 1;
                end
            end
        end

        return ~crc;
    endfunction

endpackage
