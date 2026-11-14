`timescale 1ns / 1ps
`default_nettype none

module tb_phy_tx_gbx;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer DATA_W = 64;
    localparam integer CTRL_W = DATA_W / 8;
    localparam integer HDR_W = 2;
    localparam integer MAX_BLOCKS = 64;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [DATA_W-1:0] xgmii_txd = '0;
    logic [CTRL_W-1:0] xgmii_txc = '0;
    logic xgmii_tx_valid = 1'b0;
    logic tx_gbx_sync = 1'b0;
    logic serdes_tx_gbx_req_sync = 1'b0;
    logic serdes_tx_gbx_req_stall = 1'b0;

    logic [DATA_W-1:0] serdes_tx_data;
    logic serdes_tx_data_valid;
    logic [HDR_W-1:0] serdes_tx_hdr;
    logic serdes_tx_hdr_valid;
    logic tx_gbx_req_sync;
    logic tx_gbx_req_stall;
    logic serdes_tx_gbx_sync;

    logic [DATA_W-1:0] expected_data [0:MAX_BLOCKS-1];
    integer write_count = 0;
    integer read_count = 0;
    logic delayed_sync = 1'b0;
    logic [31:0] prng = 32'hC001D00D;

    always #3.2ns clk = !clk;

    taxi_eth_phy_10g #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .HDR_W(HDR_W),
        .TX_GBX_IF_EN(1'b1),
        .RX_GBX_IF_EN(1'b0),
        .SCRAMBLER_DISABLE(1'b1),
        .TX_SERDES_PIPELINE(0)
    )
    dut (
        .rx_clk(clk),
        .rx_rst(rst),
        .tx_clk(clk),
        .tx_rst(rst),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_tx_valid(xgmii_tx_valid),
        .xgmii_rxd(),
        .xgmii_rxc(),
        .xgmii_rx_valid(),
        .tx_gbx_req_sync(tx_gbx_req_sync),
        .tx_gbx_req_stall(tx_gbx_req_stall),
        .tx_gbx_sync(tx_gbx_sync),
        .rx_gbx_sync(),
        .serdes_tx_data(serdes_tx_data),
        .serdes_tx_data_valid(serdes_tx_data_valid),
        .serdes_tx_hdr(serdes_tx_hdr),
        .serdes_tx_hdr_valid(serdes_tx_hdr_valid),
        .serdes_tx_gbx_req_sync(serdes_tx_gbx_req_sync),
        .serdes_tx_gbx_req_stall(serdes_tx_gbx_req_stall),
        .serdes_tx_gbx_sync(serdes_tx_gbx_sync),
        .serdes_rx_data('0),
        .serdes_rx_data_valid(1'b0),
        .serdes_rx_hdr('0),
        .serdes_rx_hdr_valid(1'b0),
        .serdes_rx_gbx_sync(1'b0),
        .serdes_rx_bitslip(),
        .serdes_rx_reset_req(),
        .tx_bad_block(),
        .rx_error_count(),
        .rx_bad_block(),
        .rx_sequence_error(),
        .rx_block_lock(),
        .rx_high_ber(),
        .rx_status(),
        .cfg_tx_prbs31_enable(1'b0),
        .cfg_rx_prbs31_enable(1'b0)
    );

    task automatic drive_cycle(
        input logic valid,
        input logic [DATA_W-1:0] data,
        input logic sync,
        input logic req_sync,
        input logic req_stall
    );
        @(negedge clk);
        xgmii_tx_valid = valid;
        xgmii_txd = data;
        xgmii_txc = '0;
        tx_gbx_sync = sync;
        serdes_tx_gbx_req_sync = req_sync;
        serdes_tx_gbx_req_stall = req_stall;

        if (valid) begin
            expected_data[write_count] = data;
            write_count = write_count + 1;
        end

        @(posedge clk);
        #1ps;

        if (tx_gbx_req_sync !== req_sync || tx_gbx_req_stall !== req_stall) begin
            $fatal(1, "M07: gearbox request/stall signals were not propagated");
        end

        if (serdes_tx_gbx_sync !== delayed_sync) begin
            $fatal(1, "M07: gearbox sync marker was not aligned with the TX pipeline");
        end
        delayed_sync = sync;

        if (serdes_tx_data_valid !== serdes_tx_hdr_valid) begin
            $fatal(1, "M07: SERDES data and header valid signals were misaligned");
        end

        if (serdes_tx_data_valid) begin
            if (read_count >= write_count) begin
                $fatal(1, "T06: encoder emitted a block without a valid XGMII input");
            end
            if (serdes_tx_hdr !== 2'b10 || serdes_tx_data !== expected_data[read_count]) begin
                $fatal(1,
                    "T06: block %0d mismatch: got %b:%h expected 10:%h",
                    read_count, serdes_tx_hdr, serdes_tx_data, expected_data[read_count]);
            end
            read_count = read_count + 1;
        end
    endtask

    initial begin
        $display("============================================================");
        $display("TEST: TX GEARBOX AND VALID GATING (T06, M07)");
        $display("============================================================");
        $display("");

        repeat (5) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        rst = 1'b0;

        for (integer cycle = 0; cycle < 4; cycle = cycle + 1) begin
            @(negedge clk);
            xgmii_tx_valid = 1'b0;
            xgmii_txd = '0;
            xgmii_txc = '0;
            tx_gbx_sync = 1'b0;
            serdes_tx_gbx_req_sync = 1'b0;
            serdes_tx_gbx_req_stall = 1'b0;
            @(posedge clk);
            #1ps;
        end
        if (serdes_tx_data_valid !== 1'b0) begin
            $fatal(1, "T06: output remained valid after invalid-input pipeline flush");
        end
        delayed_sync = 1'b0;

        for (integer cycle = 0; cycle < 40; cycle = cycle + 1) begin
            prng = prng ^ (prng << 13);
            prng = prng ^ (prng >> 17);
            prng = prng ^ (prng << 5);
            drive_cycle(
                (cycle % 4) != 1,
                {prng, prng ^ (32'h9E3779B9 + cycle)},
                (cycle % 9) == 3,
                (cycle % 7) == 2,
                (cycle % 11) == 5
            );
        end

        repeat (4) begin
            drive_cycle(1'b0, '0, 1'b0, 1'b0, 1'b0);
        end

        if (read_count != write_count || write_count < 20) begin
            $fatal(1, "T06: valid block count mismatch (input=%0d output=%0d)",
                write_count, read_count);
        end

        $display("Input Cycles        : %0d", 40);
        $display("Valid Input Blocks  : %0d", write_count);
        $display("Output Blocks       : %0d", read_count);
        $display("Invalid Cycles      : %0d", 10);
        $display("");
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "TX gearbox testbench timeout");
    end

endmodule

`default_nettype wire
