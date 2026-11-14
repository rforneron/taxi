`timescale 1ns / 1ps
`default_nettype none

module tb_phy_prbs_loopback;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer DATA_W = 64;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cfg_tx_prbs31_enable = 1'b0;
    logic cfg_rx_prbs31_enable = 1'b0;

    logic [DATA_W-1:0] serdes_tx_data;
    logic serdes_tx_data_valid;
    logic [1:0] serdes_tx_hdr;
    logic serdes_tx_hdr_valid;
    logic [6:0] rx_error_count;

    always #3.2ns clk = !clk;

    taxi_eth_phy_10g #(
        .DATA_W(DATA_W),
        .CTRL_W(DATA_W/8),
        .HDR_W(2),
        .SCRAMBLER_DISABLE(1'b1),
        .PRBS31_EN(1'b1),
        .TX_SERDES_PIPELINE(0),
        .RX_SERDES_PIPELINE(0),
        .COUNT_125US(16)
    )
    dut (
        .rx_clk(clk),
        .rx_rst(rst),
        .tx_clk(clk),
        .tx_rst(rst),
        .xgmii_txd({8{8'h07}}),
        .xgmii_txc(8'hFF),
        .xgmii_tx_valid(1'b1),
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
        .serdes_rx_data(serdes_tx_data),
        .serdes_rx_data_valid(serdes_tx_data_valid),
        .serdes_rx_hdr(serdes_tx_hdr),
        .serdes_rx_hdr_valid(serdes_tx_hdr_valid),
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
        repeat (5) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        rst = 1'b0;
        cfg_tx_prbs31_enable = 1'b1;

        // Let the first registered TX PRBS block reach the RX input before
        // enabling the checker, so both sides begin at the same sequence phase.
        @(posedge clk);
        #1ps;
        @(negedge clk);
        cfg_rx_prbs31_enable = 1'b1;

        for (integer cycle = 0; cycle < 100; cycle = cycle + 1) begin
            @(posedge clk);
            #1ps;
            if (cycle >= 6 && rx_error_count !== 7'd0) begin
                $fatal(1, "M05: integrated TX-to-RX PRBS loopback reported %0d errors",
                    rx_error_count);
            end
        end

        if (!serdes_tx_data_valid || !serdes_tx_hdr_valid) begin
            $fatal(1, "M05: PRBS loopback ended with invalid SERDES output");
        end

        $display("PASS M05: integrated TX PRBS31 stream is accepted by the RX checker");
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "Integrated PRBS loopback testbench timeout");
    end

endmodule

`default_nettype wire
