`timescale 1ns / 1ps
`default_nettype none

module tb_phy_configs;

    timeunit 1ns;
    timeprecision 1ps;

    logic done_32 = 1'b0;
    logic done_64 = 1'b0;
    logic done_reverse = 1'b0;

    phy_loopback_config_case #(
        .DATA_W(32),
        .BIT_REVERSE(1'b0)
    )
    width_32_case (
        .done(done_32)
    );

    phy_loopback_config_case #(
        .DATA_W(64),
        .BIT_REVERSE(1'b0)
    )
    width_64_case (
        .done(done_64)
    );

    phy_loopback_config_case #(
        .DATA_W(64),
        .BIT_REVERSE(1'b1)
    )
    bit_reverse_case (
        .done(done_reverse)
    );

    initial begin
        $display("============================================================");
        $display("TEST: PHY WIDTH AND BIT REVERSE (R06, M06)");
        $display("============================================================");
        $display("");

        wait (done_32 && done_64);
        wait (done_reverse);
        $display("DATA_W Configurations : 32, 64");
        $display("Bit Reverse           : Enabled");
        $display("Scrambler             : Enabled");
        $display("Loopback Result       : Passed");
        $display("");
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "PHY configuration testbench timeout");
    end

endmodule

module phy_loopback_config_case #(
    parameter integer DATA_W = 64,
    parameter logic BIT_REVERSE = 1'b0
) (
    output logic done
);

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer CTRL_W = DATA_W / 8;
    localparam integer SEGMENTS = 64 / DATA_W;
    localparam integer FRAME_WORDS = 5;
    localparam integer EXPECTED_SAMPLES = FRAME_WORDS * SEGMENTS;
    localparam integer MAX_SAMPLES = 1024;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [DATA_W-1:0] xgmii_txd = '0;
    logic [CTRL_W-1:0] xgmii_txc = '0;
    logic [DATA_W-1:0] xgmii_rxd;
    logic [CTRL_W-1:0] xgmii_rxc;
    logic xgmii_rx_valid;
    logic [DATA_W-1:0] serdes_tx_data;
    logic serdes_tx_data_valid;
    logic [1:0] serdes_tx_hdr;
    logic serdes_tx_hdr_valid;
    logic tx_bad_block;
    logic rx_bad_block;
    logic rx_sequence_error;
    logic rx_block_lock;

    logic capture_enable = 1'b0;
    logic [DATA_W-1:0] captured_data [0:MAX_SAMPLES-1];
    logic [CTRL_W-1:0] captured_control [0:MAX_SAMPLES-1];
    integer capture_count = 0;
    integer start_index;
    integer sample_index;

    logic [63:0] frame_data [0:FRAME_WORDS-1];
    logic [7:0] frame_control [0:FRAME_WORDS-1];

    always #3.2ns clk = !clk;

    taxi_eth_phy_10g #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .HDR_W(2),
        .TX_GBX_IF_EN(1'b0),
        .RX_GBX_IF_EN(1'b0),
        .BIT_REVERSE(BIT_REVERSE),
        .SCRAMBLER_DISABLE(1'b0),
        .TX_SERDES_PIPELINE(2),
        .RX_SERDES_PIPELINE(2),
        .COUNT_125US(16)
    )
    dut (
        .rx_clk(clk),
        .rx_rst(rst),
        .tx_clk(clk),
        .tx_rst(rst),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_tx_valid(1'b1),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_rx_valid(xgmii_rx_valid),
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
        .tx_bad_block(tx_bad_block),
        .rx_error_count(),
        .rx_bad_block(rx_bad_block),
        .rx_sequence_error(rx_sequence_error),
        .rx_block_lock(rx_block_lock),
        .rx_high_ber(),
        .rx_status(),
        .cfg_tx_prbs31_enable(1'b0),
        .cfg_rx_prbs31_enable(1'b0)
    );

    always @(posedge clk) begin
        #1ps;
        if (capture_enable && xgmii_rx_valid) begin
            if (capture_count >= MAX_SAMPLES) begin
                $fatal(1, "Configuration loopback capture overflowed");
            end
            captured_data[capture_count] = xgmii_rxd;
            captured_control[capture_count] = xgmii_rxc;
            capture_count = capture_count + 1;
        end
    end

    task automatic send_idle_cycles(input integer count);
        repeat (count) begin
            @(negedge clk);
            xgmii_txd = {CTRL_W{8'h07}};
            xgmii_txc = '1;
            @(posedge clk);
            #2ps;
        end
    endtask

    task automatic send_frame;
        for (integer word_index = 0; word_index < FRAME_WORDS; word_index = word_index + 1) begin
            for (integer segment = 0; segment < SEGMENTS; segment = segment + 1) begin
                @(negedge clk);
                xgmii_txd = frame_data[word_index][segment*DATA_W +: DATA_W];
                xgmii_txc = frame_control[word_index][segment*CTRL_W +: CTRL_W];
                @(posedge clk);
                #2ps;
            end
        end
    endtask

    initial begin
        done = 1'b0;
        frame_data[0] = 64'hD5555555555555FB;
        frame_data[1] = 64'h0706050403020100;
        frame_data[2] = 64'h1716151413121110;
        frame_data[3] = 64'h2726252423222120;
        frame_data[4] = 64'h07070707070707FD;
        frame_control[0] = 8'h01;
        frame_control[1] = 8'h00;
        frame_control[2] = 8'h00;
        frame_control[3] = 8'h00;
        frame_control[4] = 8'hFF;

        repeat (5) begin
            @(posedge clk);
            #2ps;
        end
        @(negedge clk);
        rst = 1'b0;
        send_idle_cycles(160);
        for (integer timeout = 0; timeout < 32 && !rx_block_lock; timeout = timeout + 1) begin
            send_idle_cycles(1);
        end
        if (!rx_block_lock) begin
            $fatal(1, "DATA_W=%0d BIT_REVERSE=%0b: RX failed to acquire block lock",
                DATA_W, BIT_REVERSE);
        end

        capture_count = 0;
        capture_enable = 1'b1;
        send_frame();
        send_idle_cycles(20);
        capture_enable = 1'b0;

        start_index = -1;
        for (integer i = 0; i < capture_count; i = i + 1) begin
            if (captured_control[i][0] && captured_data[i][7:0] == 8'hFB) begin
                start_index = i;
                break;
            end
        end
        if (start_index < 0) begin
            $fatal(1, "DATA_W=%0d BIT_REVERSE=%0b: frame start was not received",
                DATA_W, BIT_REVERSE);
        end

        for (integer word_index = 0; word_index < FRAME_WORDS; word_index = word_index + 1) begin
            for (integer segment = 0; segment < SEGMENTS; segment = segment + 1) begin
                sample_index = start_index + word_index*SEGMENTS + segment;
                if (sample_index >= capture_count ||
                        captured_data[sample_index] !==
                            frame_data[word_index][segment*DATA_W +: DATA_W] ||
                        captured_control[sample_index] !==
                            frame_control[word_index][segment*CTRL_W +: CTRL_W]) begin
                    $fatal(1,
                        "DATA_W=%0d BIT_REVERSE=%0b: mismatch at frame word %0d segment %0d",
                        DATA_W, BIT_REVERSE, word_index, segment);
                end

                if (rx_bad_block || rx_sequence_error || tx_bad_block) begin
                    $fatal(1,
                        "DATA_W=%0d BIT_REVERSE=%0b: unexpected block/sequence error",
                        DATA_W, BIT_REVERSE);
                end
            end
        end

        done = 1'b1;
    end

endmodule

`default_nettype wire
