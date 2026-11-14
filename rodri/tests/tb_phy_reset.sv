`timescale 1ns / 1ps
`default_nettype none

module tb_phy_reset;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer DATA_W = 64;
    localparam integer CTRL_W = DATA_W / 8;

    logic tx_clk = 1'b0;
    logic rx_clk = 1'b0;
    logic tx_rst = 1'b1;
    logic rx_rst = 1'b1;

    logic [DATA_W-1:0] xgmii_txd = {8{8'h07}};
    logic [CTRL_W-1:0] xgmii_txc = '1;
    logic xgmii_tx_valid = 1'b1;

    logic [DATA_W-1:0] serdes_tx_data;
    logic serdes_tx_data_valid;
    logic [1:0] serdes_tx_hdr;
    logic serdes_tx_hdr_valid;

    logic [DATA_W-1:0] serdes_rx_data = '0;
    logic serdes_rx_data_valid = 1'b1;
    logic [1:0] serdes_rx_hdr = 2'b10;
    logic serdes_rx_hdr_valid = 1'b1;

    logic tx_bad_block;
    logic rx_block_lock;

    integer tx_valid_samples = 0;
    integer tx_valid_samples_before_rx_reset;

    always #3.2ns tx_clk = !tx_clk;
    always #3.55ns rx_clk = !rx_clk;

    always @(posedge tx_clk) begin
        if (!tx_rst && serdes_tx_data_valid && serdes_tx_hdr_valid) begin
            tx_valid_samples = tx_valid_samples + 1;
        end
    end

    taxi_eth_phy_10g #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .HDR_W(2),
        .TX_GBX_IF_EN(1'b0),
        .RX_GBX_IF_EN(1'b0),
        .SCRAMBLER_DISABLE(1'b1),
        .PRBS31_EN(1'b0),
        .TX_SERDES_PIPELINE(0),
        .RX_SERDES_PIPELINE(0),
        .COUNT_125US(16)
    )
    dut (
        .rx_clk(rx_clk),
        .rx_rst(rx_rst),
        .tx_clk(tx_clk),
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
        .tx_bad_block(tx_bad_block),
        .rx_error_count(),
        .rx_bad_block(),
        .rx_sequence_error(),
        .rx_block_lock(rx_block_lock),
        .rx_high_ber(),
        .rx_status(),
        .cfg_tx_prbs31_enable(1'b0),
        .cfg_rx_prbs31_enable(1'b0)
    );

    task automatic send_idle_word;
        @(negedge tx_clk);
        xgmii_txd = {8{8'h07}};
        xgmii_txc = '1;
        xgmii_tx_valid = 1'b1;
        @(posedge tx_clk);
        #1ps;
    endtask

    initial begin
        $display("============================================================");
        $display("TEST: PHY RESET (T01)");
        $display("============================================================");
        $display("");

        repeat (5) begin
            @(posedge tx_clk);
            #1ps;
        end

        @(negedge tx_clk);
        tx_rst = 1'b0;
        @(negedge rx_clk);
        rx_rst = 1'b0;

        repeat (70) @(posedge rx_clk);
        #1ps;
        if (rx_block_lock !== 1'b1) begin
            $fatal(1, "T01: RX failed to acquire lock with valid SERDES headers");
        end

        @(negedge tx_clk);
        tx_rst = 1'b1;
        repeat (12) begin
            @(posedge rx_clk);
            #1ps;
        end
        if (rx_block_lock !== 1'b1) begin
            $fatal(1, "T01: TX reset disturbed the independently clocked RX lock");
        end

        @(negedge tx_clk);
        tx_rst = 1'b0;

        tx_valid_samples_before_rx_reset = tx_valid_samples;
        @(negedge rx_clk);
        rx_rst = 1'b1;
        repeat (20) begin
            send_idle_word();
            if (!serdes_tx_data_valid || !serdes_tx_hdr_valid || tx_bad_block) begin
                $fatal(1, "T01: RX reset disturbed valid TX operation");
            end
        end

        if (tx_valid_samples - tx_valid_samples_before_rx_reset < 20) begin
            $fatal(1, "T01: TX did not continue while RX was held in reset");
        end
        if (rx_block_lock !== 1'b0) begin
            $fatal(1, "T01: RX block lock did not clear during RX reset");
        end

        @(negedge rx_clk);
        rx_rst = 1'b0;
        repeat (70) @(posedge rx_clk);
        #1ps;
        if (rx_block_lock !== 1'b1) begin
            $fatal(1, "T01: RX did not reacquire lock after reset release");
        end

        $display("TX Valid Samples    : %0d", tx_valid_samples);
        $display("RX Block Lock       : %0b", rx_block_lock);
        $display("TX Bad Block        : %0b", tx_bad_block);
        $display("");
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "T01: timeout");
    end

endmodule

`default_nettype wire
