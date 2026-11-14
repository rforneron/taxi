`timescale 1ns / 1ps
`default_nettype none

module tb_phy_prbs31;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer DATA_W = 64;
    localparam integer CTRL_W = DATA_W / 8;
    localparam integer HDR_W = 2;
    localparam integer WORD_W = DATA_W + HDR_W;
    localparam logic [30:0] PRBS31_SEED = 31'h7fffffff;

    logic clk = 1'b0;
    logic tx_rst = 1'b1;
    logic rx_rst = 1'b1;
    logic tx_reference_rst = 1'b1;
    logic rx_reference_rst = 1'b1;

    logic [DATA_W-1:0] xgmii_txd = {8{8'h07}};
    logic [CTRL_W-1:0] xgmii_txc = '1;
    logic xgmii_tx_valid = 1'b1;
    logic cfg_tx_prbs31_enable = 1'b0;
    logic cfg_rx_prbs31_enable = 1'b0;

    logic [DATA_W-1:0] serdes_tx_data;
    logic serdes_tx_data_valid;
    logic [HDR_W-1:0] serdes_tx_hdr;
    logic serdes_tx_hdr_valid;

    logic [WORD_W-1:0] tx_reference_word;
    logic [WORD_W-1:0] rx_reference_word;
    logic tx_reference_advance = 1'b0;
    logic rx_reference_advance = 1'b0;
    logic rx_inject_error = 1'b0;
    logic [WORD_W-1:0] rx_error_mask = '0;
    logic [WORD_W-1:0] rx_word_to_dut;

    logic [DATA_W-1:0] serdes_rx_data;
    logic serdes_rx_data_valid = 1'b1;
    logic [HDR_W-1:0] serdes_rx_hdr;
    logic serdes_rx_hdr_valid = 1'b1;

    logic [6:0] rx_error_count;
    logic [6:0] error_count_seen;
    logic [WORD_W-1:0] expected_tx_word;

    always #3.2ns clk = !clk;

    prbs31_agent #(
        .WORD_W(WORD_W),
        .SEED(PRBS31_SEED)
    )
    tx_prbs_reference_inst (
        .clk(clk),
        .rst(tx_reference_rst),
        .advance(tx_reference_advance),
        .prbs_word(tx_reference_word)
    );

    prbs31_agent #(
        .WORD_W(WORD_W),
        .SEED(PRBS31_SEED)
    )
    rx_prbs_reference_inst (
        .clk(clk),
        .rst(rx_reference_rst),
        .advance(rx_reference_advance),
        .prbs_word(rx_reference_word)
    );

    assign rx_word_to_dut = rx_reference_word ^ (rx_inject_error ? rx_error_mask : '0);
    assign serdes_rx_hdr = rx_word_to_dut[HDR_W-1:0];
    assign serdes_rx_data = rx_word_to_dut[WORD_W-1:HDR_W];

    taxi_eth_phy_10g #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .HDR_W(HDR_W),
        .TX_GBX_IF_EN(1'b0),
        .RX_GBX_IF_EN(1'b0),
        .SCRAMBLER_DISABLE(1'b1),
        .PRBS31_EN(1'b1),
        .TX_SERDES_PIPELINE(0),
        .RX_SERDES_PIPELINE(0),
        .COUNT_125US(16)
    )
    dut (
        .rx_clk(clk),
        .rx_rst(rx_rst),
        .tx_clk(clk),
        .tx_rst(tx_rst),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_tx_valid(xgmii_tx_valid),
        .xgmii_rxd(),
        .xgmii_rxc(),
        .xgmii_rx_valid(),
        .tx_gbx_req_sync(),
        .tx_gbx_req_stall(),
        .tx_gbx_sync(1'b0),
        .rx_gbx_sync(),
        .serdes_tx_data(serdes_tx_data),
        .serdes_tx_data_valid(serdes_tx_data_valid),
        .serdes_tx_hdr(serdes_tx_hdr),
        .serdes_tx_hdr_valid(serdes_tx_hdr_valid),
        .serdes_tx_gbx_req_sync(1'b0),
        .serdes_tx_gbx_req_stall(1'b0),
        .serdes_tx_gbx_sync(),
        .serdes_rx_data(serdes_rx_data),
        .serdes_rx_data_valid(serdes_rx_data_valid),
        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid),
        .serdes_rx_gbx_sync(1'b0),
        .serdes_rx_bitslip(),
        .serdes_rx_reset_req(),
        .tx_bad_block(),
        .rx_error_count(rx_error_count),
        .rx_bad_block(),
        .rx_sequence_error(),
        .rx_block_lock(),
        .rx_high_ber(),
        .rx_status(),
        .cfg_tx_prbs31_enable(cfg_tx_prbs31_enable),
        .cfg_rx_prbs31_enable(cfg_rx_prbs31_enable)
    );

    initial begin
        $display("============================================================");
        $display("TEST: PRBS31 TX/RX AND PHASE CONTROL (P01-P04)");
        $display("============================================================");
        $display("");

        rx_error_mask[HDR_W+5] = 1'b1;

        repeat (5) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        tx_rst = 1'b0;
        rx_rst = 1'b0;
        tx_reference_rst = 1'b0;
        rx_reference_rst = 1'b0;

        // P01: compare each TX PRBS word against an independent serial reference.
        @(negedge clk);
        cfg_tx_prbs31_enable = 1'b1;
        tx_reference_advance = 1'b1;
        for (integer i = 0; i < 40; i = i + 1) begin
            expected_tx_word = tx_reference_word;
            @(posedge clk);
            #1ps;
            if (!serdes_tx_data_valid || !serdes_tx_hdr_valid) begin
                $fatal(1, "P01: TX PRBS output was not valid at word %0d", i);
            end
            if ({serdes_tx_data, serdes_tx_hdr} !== expected_tx_word) begin
                $fatal(1,
                    "P01: PRBS mismatch at word %0d: got %h expected %h",
                    i, {serdes_tx_data, serdes_tx_hdr}, expected_tx_word);
            end
        end
        @(negedge clk);
        cfg_tx_prbs31_enable = 1'b0;
        tx_reference_advance = 1'b0;

        // P02: feed a known sequence to the RX checker and require zero errors.
        @(negedge clk);
        cfg_rx_prbs31_enable = 1'b1;
        rx_reference_advance = 1'b1;
        for (integer i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            #1ps;
            if (i >= 4 && rx_error_count !== 7'd0) begin
                $fatal(1, "P02: RX PRBS checker reported errors on a clean sequence: %0d",
                    rx_error_count);
            end
        end
        // P03: inject one reproducible data-bit error and observe the checker.
        error_count_seen = '0;
        @(negedge clk);
        rx_inject_error = 1'b1;
        @(posedge clk);
        #1ps;
        @(negedge clk);
        rx_inject_error = 1'b0;
        repeat (6) begin
            @(posedge clk);
            #1ps;
            if (rx_error_count > error_count_seen) begin
                error_count_seen = rx_error_count;
            end
        end
        if (error_count_seen == 0) begin
            $fatal(1, "P03: RX PRBS checker did not detect the injected bit error");
        end
        // P04: disabling PRBS freezes its reference phase; reset while disabled
        // must not corrupt the held phase, and clean checking resumes on re-enable.
        @(negedge clk);
        cfg_tx_prbs31_enable = 1'b0;
        cfg_rx_prbs31_enable = 1'b0;
        tx_reference_advance = 1'b0;
        rx_reference_advance = 1'b0;
        rx_inject_error = 1'b0;
        repeat (4) begin
            @(posedge clk);
            #1ps;
        end
        if (serdes_tx_hdr !== 2'b01 || serdes_tx_data[7:0] !== 8'h1E) begin
            $fatal(1, "P04: disabling PRBS did not return TX to the encoded data path");
        end
        if (rx_error_count !== 7'd0) begin
            $fatal(1, "P04: disabled RX PRBS checker did not clear its error count");
        end

        @(negedge clk);
        tx_rst = 1'b1;
        rx_rst = 1'b1;
        repeat (3) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        tx_rst = 1'b0;
        rx_rst = 1'b0;
        cfg_tx_prbs31_enable = 1'b1;
        cfg_rx_prbs31_enable = 1'b1;
        tx_reference_advance = 1'b1;
        rx_reference_advance = 1'b1;

        for (integer i = 0; i < 12; i = i + 1) begin
            expected_tx_word = tx_reference_word;
            @(posedge clk);
            #1ps;
            if ({serdes_tx_data, serdes_tx_hdr} !== expected_tx_word) begin
                $fatal(1, "P04: TX PRBS phase changed across disabled reset at word %0d", i);
            end
            if (i >= 5 && rx_error_count !== 7'd0) begin
                $fatal(1, "P04: RX PRBS checker did not resume cleanly after reset");
            end
        end

        $display("TX PRBS Words Checked : %0d", 40);
        $display("RX Clean Words Checked: %0d", 40);
        $display("Injected Error Count  : %0d", error_count_seen);
        $display("Phase Resume Words    : %0d", 12);
        $display("RX Error Count        : %0d", rx_error_count);
        $display("");
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "PRBS31 testbench timeout");
    end

endmodule

`default_nettype wire
