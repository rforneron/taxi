`timescale 1ns / 1ps
`default_nettype none

module tb_phy_rx_extended;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer DATA_W = 64;
    localparam integer PIPELINE = 3;
    localparam integer HDR_W = 2;
    localparam integer SAMPLES = 32;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [DATA_W-1:0] serdes_rx_data = '0;
    logic serdes_rx_data_valid = 1'b0;
    logic [HDR_W-1:0] serdes_rx_hdr = '0;
    logic serdes_rx_hdr_valid = 1'b0;
    logic serdes_rx_gbx_sync = 1'b0;

    logic [DATA_W-1:0] encoded_rx_data;
    logic encoded_rx_data_valid;
    logic [HDR_W-1:0] encoded_rx_hdr;
    logic encoded_rx_hdr_valid;
    logic rx_gbx_sync;

    logic [DATA_W-1:0] expected_data [0:SAMPLES-1];
    logic expected_data_valid [0:SAMPLES-1];
    logic [HDR_W-1:0] expected_hdr [0:SAMPLES-1];
    logic expected_hdr_valid [0:SAMPLES-1];
    logic expected_gbx_sync [0:SAMPLES-1];

    logic [DATA_W-1:0] decoder_data = '0;
    logic decoder_data_valid = 1'b1;
    logic [HDR_W-1:0] decoder_hdr = '0;
    logic decoder_hdr_valid = 1'b1;
    logic [DATA_W-1:0] xgmii_rxd;
    logic [DATA_W/8-1:0] xgmii_rxc;
    logic xgmii_rx_valid;
    logic rx_bad_block;
    logic rx_sequence_error;
    integer unsigned cycle;

    always #3.2ns clk = !clk;

    taxi_eth_phy_10g_rx_if #(
        .DATA_W(DATA_W),
        .HDR_W(HDR_W),
        .GBX_IF_EN(1'b1),
        .SCRAMBLER_DISABLE(1'b1),
        .PRBS31_EN(1'b0),
        .SERDES_PIPELINE(PIPELINE)
    )
    rx_if_dut (
        .clk(clk),
        .rst(rst),
        .encoded_rx_data(encoded_rx_data),
        .encoded_rx_data_valid(encoded_rx_data_valid),
        .encoded_rx_hdr(encoded_rx_hdr),
        .encoded_rx_hdr_valid(encoded_rx_hdr_valid),
        .rx_gbx_sync(rx_gbx_sync),
        .serdes_rx_data(serdes_rx_data),
        .serdes_rx_data_valid(serdes_rx_data_valid),
        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid),
        .serdes_rx_gbx_sync(serdes_rx_gbx_sync),
        .serdes_rx_bitslip(),
        .serdes_rx_reset_req(),
        .rx_bad_block(1'b0),
        .rx_sequence_error(1'b0),
        .rx_error_count(),
        .rx_block_lock(),
        .rx_high_ber(),
        .rx_status(),
        .cfg_rx_prbs31_enable(1'b0)
    );

    taxi_xgmii_baser_dec #(
        .DATA_W(DATA_W),
        .CTRL_W(DATA_W/8),
        .HDR_W(HDR_W)
    )
    decoder_dut (
        .clk(clk),
        .rst(rst),
        .encoded_rx_data(decoder_data),
        .encoded_rx_data_valid(decoder_data_valid),
        .encoded_rx_hdr(decoder_hdr),
        .encoded_rx_hdr_valid(decoder_hdr_valid),
        .rx_gbx_sync_in(1'b0),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_rx_valid(xgmii_rx_valid),
        .rx_gbx_sync_out(),
        .rx_os(),
        .rx_os_sig(),
        .rx_os_valid(),
        .rx_os_match(),
        .rx_idle_match(),
        .rx_bad_block(rx_bad_block),
        .rx_sequence_error(rx_sequence_error)
    );

    task automatic drive_rx_sample(
        input integer sample_index,
        input logic [DATA_W-1:0] data,
        input logic data_valid,
        input logic [HDR_W-1:0] hdr,
        input logic hdr_valid,
        input logic gbx_sync
    );
        integer expected_index;

        @(negedge clk);
        serdes_rx_data = data;
        serdes_rx_data_valid = data_valid;
        serdes_rx_hdr = hdr;
        serdes_rx_hdr_valid = hdr_valid;
        serdes_rx_gbx_sync = gbx_sync;

        expected_data[sample_index] = data;
        expected_data_valid[sample_index] = data_valid;
        expected_hdr[sample_index] = hdr;
        expected_hdr_valid[sample_index] = hdr_valid;
        expected_gbx_sync[sample_index] = gbx_sync;

        @(posedge clk);
        #1ps;

        expected_index = sample_index - PIPELINE;
        if (expected_index >= 0) begin
            if (encoded_rx_data !== expected_data[expected_index] ||
                    encoded_rx_hdr !== expected_hdr[expected_index] ||
                    encoded_rx_data_valid !== expected_data_valid[expected_index] ||
                    encoded_rx_hdr_valid !== expected_hdr_valid[expected_index] ||
                    rx_gbx_sync !== expected_gbx_sync[expected_index]) begin
                $fatal(1,
                    "R04: RX pipeline mismatch at sample %0d (source %0d)",
                    sample_index, expected_index);
            end
        end
    endtask

    task automatic send_decoder_block(
        input logic [DATA_W-1:0] data,
        input logic [HDR_W-1:0] hdr
    );
        @(negedge clk);
        decoder_data = data;
        decoder_hdr = hdr;
        @(posedge clk);
        #1ps;
    endtask

    initial begin
        $display("============================================================");
        $display("TEST: RX PIPELINE AND INVALID BLOCKS (R04-R05)");
        $display("============================================================");
        $display("");

        repeat (5) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < SAMPLES; cycle = cycle + 1) begin
            drive_rx_sample(
                cycle,
                64'hA500000000000000 ^ (64'h0102040810204081 * cycle),
                (cycle % 4) != 1,
                cycle[0] ? 2'b10 : 2'b01,
                (cycle % 3) != 2,
                (cycle % 7) == 4
            );
        end
        // R05: reject both an illegal block type and an illegal control code.
        send_decoder_block(64'h0000000000000002, 2'b01);
        if (rx_bad_block !== 1'b1) begin
            $fatal(1, "R05: decoder did not flag an illegal 64b/66b block type");
        end

        send_decoder_block(64'h0000000000007F1E, 2'b01);
        if (rx_bad_block !== 1'b1 || xgmii_rxd[7:0] !== 8'hFE ||
                xgmii_rxc[0] !== 1'b1) begin
            $fatal(1, "R05: decoder did not flag an illegal control code");
        end
        $display("Pipeline Depth       : %0d cycles", PIPELINE);
        $display("Pipeline Samples     : %0d", SAMPLES);
        $display("Invalid Blocks Tested: %0d", 2);
        $display("RX Bad Block         : %0b", rx_bad_block);
        $display("");
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "Extended RX testbench timeout");
    end

endmodule

`default_nettype wire
