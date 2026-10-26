`timescale 1ns / 1ps

module xgmii_tx_driver #(
    parameter integer DATA_W = 64,
    parameter integer CTRL_W = DATA_W / 8
) (
    input  logic              clk,
    output logic [DATA_W-1:0] xgmii_txd,
    output logic [CTRL_W-1:0] xgmii_txc,
    output logic              xgmii_tx_valid
);

    timeunit 1ns;
    timeprecision 1ps;

    initial begin
        xgmii_txd = '0;
        xgmii_txc = '1;
        xgmii_tx_valid = 1'b1;
    end

    task automatic send_word(
        input logic [DATA_W-1:0] data,
        input logic [CTRL_W-1:0] control
    );
        @(negedge clk);
        xgmii_txd = data;
        xgmii_txc = control;
        xgmii_tx_valid = 1'b1;
        @(posedge clk);
        #1ps;
    endtask

    task automatic send_idle_words(input integer unsigned count);
        repeat (count) begin
            send_word({CTRL_W{8'h07}}, '1);
        end
    endtask

endmodule
