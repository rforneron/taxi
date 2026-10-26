`timescale 1ns / 1ps

module serdes_rx_header_driver (
    input  logic       clk,
    output logic [1:0] serdes_rx_hdr,
    output logic       serdes_rx_hdr_valid
);

    timeunit 1ns;
    timeprecision 1ps;

    initial begin
        serdes_rx_hdr = 2'b00;
        serdes_rx_hdr_valid = 1'b0;
    end

    task automatic send_header(
        input logic [1:0] header,
        input logic       header_valid
    );
        @(negedge clk);
        serdes_rx_hdr = header;
        serdes_rx_hdr_valid = header_valid;
        @(posedge clk);
        #1ps;
    endtask

    task automatic idle_cycles(input integer unsigned cycle_count);
        @(negedge clk);
        serdes_rx_hdr_valid = 1'b0;

        repeat (cycle_count) begin
            @(posedge clk);
            #1ps;
        end
    endtask

endmodule
