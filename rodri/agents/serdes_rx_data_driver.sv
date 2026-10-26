`timescale 1ns / 1ps

module serdes_rx_data_driver #(
    parameter integer DATA_W = 64,
    parameter integer HDR_W = 2
) (
    input  logic             clk,
    output logic [DATA_W-1:0] serdes_rx_data,
    output logic             serdes_rx_data_valid,
    output logic [HDR_W-1:0] serdes_rx_hdr,
    output logic             serdes_rx_hdr_valid
);

    timeunit 1ns;
    timeprecision 1ps;

    initial begin
        serdes_rx_data = '0;
        serdes_rx_data_valid = 1'b0;
        serdes_rx_hdr = '0;
        serdes_rx_hdr_valid = 1'b0;
    end

    task automatic send_block(
        input logic [DATA_W-1:0] data,
        input logic [HDR_W-1:0] header,
        input logic             data_valid,
        input logic             header_valid
    );
        @(negedge clk);
        serdes_rx_data = data;
        serdes_rx_hdr = header;
        serdes_rx_data_valid = data_valid;
        serdes_rx_hdr_valid = header_valid;
        @(posedge clk);
        #1ps;
    endtask

    task automatic idle_cycles(input integer unsigned count);
        @(negedge clk);
        serdes_rx_data_valid = 1'b0;
        serdes_rx_hdr_valid = 1'b0;

        repeat (count) begin
            @(posedge clk);
            #1ps;
        end
    endtask

endmodule
