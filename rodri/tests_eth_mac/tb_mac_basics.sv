`timescale 1ns / 1ps
`default_nettype none

module tb_mac_basics #(
    parameter integer DATA_W = 64
);

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer CTRL_W = DATA_W / 8;
    localparam integer KEEP_W = DATA_W / 8;
    localparam integer TAG_W = 16;
    localparam integer MAX_FRAME_BYTES = mac_frame_pkg::MAX_FRAME_BYTES;
    localparam integer MAX_RX_STREAM_BYTES = MAX_FRAME_BYTES + 32;
    localparam realtime CLK_HALF_PERIOD = DATA_W == 64 ? 3.2 : 1.6;

    logic tx_clk = 1'b0;
    logic rx_clk = 1'b0;
    logic tx_rst = 1'b1;
    logic rx_rst = 1'b1;

    taxi_axis_if #(
        .DATA_W(DATA_W),
        .USER_EN(1'b1),
        .USER_W(1),
        .ID_EN(1'b1),
        .ID_W(TAG_W)
    ) s_axis_tx();

    taxi_axis_if #(
        .DATA_W(96),
        .KEEP_W(1),
        .KEEP_EN(1'b0),
        .LAST_EN(1'b0),
        .ID_EN(1'b1),
        .ID_W(TAG_W)
    ) m_axis_tx_cpl();

    taxi_axis_if #(
        .DATA_W(DATA_W),
        .USER_EN(1'b1),
        .USER_W(1)
    ) m_axis_rx();

    taxi_axis_if #(
        .DATA_W(16),
        .KEEP_W(1),
        .KEEP_EN(1'b0),
        .LAST_EN(1'b0),
        .USER_EN(1'b1),
        .USER_W(1),
        .ID_EN(1'b1),
        .ID_W(8)
    ) m_axis_stat();

    logic [DATA_W-1:0] xgmii_rxd = {KEEP_W{8'h07}};
    logic [CTRL_W-1:0] xgmii_rxc = '1;
    logic xgmii_rx_valid = 1'b1;
    logic [DATA_W-1:0] xgmii_txd;
    logic [CTRL_W-1:0] xgmii_txc;
    logic xgmii_tx_valid;
    logic tx_capture_enable = 1'b0;
    logic [MAX_FRAME_BYTES*8-1:0] tx_capture_data;
    integer unsigned tx_capture_len;
    logic tx_preamble_valid;
    logic tx_sfd_valid;
    logic tx_capture_done;
    logic rx_capture_enable = 1'b0;
    logic [MAX_FRAME_BYTES*8-1:0] rx_capture_data = '0;
    integer unsigned rx_capture_len = 0;
    logic rx_capture_error = 1'b0;
    logic rx_capture_done = 1'b0;
    logic tx_completion_capture_enable = 1'b0;
    logic tx_completion_done = 1'b0;
    logic [TAG_W-1:0] tx_completion_tag = '0;
    logic stat_rx_err_bad_fcs;
    logic stat_rx_err_framing;
    logic stat_rx_err_preamble;

    always #(CLK_HALF_PERIOD) tx_clk = !tx_clk;
    always #(CLK_HALF_PERIOD) rx_clk = !rx_clk;

    assign m_axis_rx.tready = 1'b1;
    assign m_axis_tx_cpl.tready = 1'b1;
    assign m_axis_stat.tready = 1'b1;

    always_ff @(posedge rx_clk) begin
        integer next_len;

        if (rx_rst) begin
            rx_capture_data <= '0;
            rx_capture_len <= 0;
            rx_capture_error <= 1'b0;
            rx_capture_done <= 1'b0;
        end else if (rx_capture_enable && m_axis_rx.tvalid && m_axis_rx.tready) begin
            next_len = rx_capture_len;
            rx_capture_error <= rx_capture_error | m_axis_rx.tuser[0];
            for (integer lane = 0; lane < KEEP_W; lane = lane + 1) begin
                if (m_axis_rx.tkeep[lane] && next_len < MAX_FRAME_BYTES) begin
                    rx_capture_data[next_len*8 +: 8] <= m_axis_rx.tdata[lane*8 +: 8];
                    next_len = next_len + 1;
                end

            end
            rx_capture_len <= next_len;
            if (m_axis_rx.tlast) begin
                rx_capture_done <= 1'b1;
            end
        end
    end

    always_ff @(posedge tx_clk) begin
        if (tx_rst || !tx_completion_capture_enable) begin
            tx_completion_done <= 1'b0;
            tx_completion_tag <= '0;
        end else if (!tx_completion_done && m_axis_tx_cpl.tvalid && m_axis_tx_cpl.tready) begin
            tx_completion_done <= 1'b1;
            tx_completion_tag <= m_axis_tx_cpl.tid;
        end
    end

    /* verilator lint_off PINMISSING */
    taxi_eth_mac_10g #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .DIC_EN(1'b1),
        .PTP_TS_EN(1'b0),
        .PTP_TD_EN(1'b0),
        .PTP_TS_FMT_TOD(1'b0),
        .PTP_TS_W(96),
        .PFC_EN(1'b0),
        .PAUSE_EN(1'b0),
        .STAT_EN(1'b0)
    )
    dut (
        .rx_clk(rx_clk),
        .rx_rst(rx_rst),
        .tx_clk(tx_clk),
        .tx_rst(tx_rst),
        .s_axis_tx(s_axis_tx),
        .m_axis_tx_cpl(m_axis_tx_cpl),
        .m_axis_rx(m_axis_rx),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_rx_valid(xgmii_rx_valid),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_tx_valid(xgmii_tx_valid),
        .stat_clk(tx_clk),
        .stat_rst(tx_rst),
        .m_axis_stat(m_axis_stat),
        .cfg_tx_pad_en(1'b1),
        .cfg_tx_min_pkt_len(8'd59),
        .cfg_tx_max_pkt_len(16'd1517),
        .cfg_tx_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_max_pkt_len(16'd1517),
        .cfg_rx_enable(1'b1),
        .stat_rx_err_bad_fcs(stat_rx_err_bad_fcs),
        .stat_rx_err_framing(stat_rx_err_framing),
        .stat_rx_err_preamble(stat_rx_err_preamble)
    );
    /* verilator lint_on PINMISSING */

    axi_frame_driver #(
        .DATA_W(DATA_W),
        .KEEP_W(KEEP_W),
        .TAG_W(TAG_W),
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES)
    )
    axi_driver (
        .clk(tx_clk),
        .rst(tx_rst),
        .axis(s_axis_tx)
    );

    xgmii_frame_monitor #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES)
    )
    xgmii_monitor (
        .clk(tx_clk),
        .rst(tx_rst),
        .capture_enable(tx_capture_enable),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_tx_valid(xgmii_tx_valid),
        .frame_data(tx_capture_data),
        .frame_len(tx_capture_len),
        .preamble_valid(tx_preamble_valid),
        .sfd_valid(tx_sfd_valid),
        .frame_done(tx_capture_done)
    );

    mac_frame_scoreboard #(
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES)
    )
    scoreboard ();

    task automatic build_ethernet_frame(
        output logic [MAX_FRAME_BYTES*8-1:0] frame_data,
        input integer unsigned frame_len,
        input logic [7:0] payload_seed
    );
        frame_data = '0;
        if (frame_len < 14 || frame_len > MAX_FRAME_BYTES) begin
            $fatal(1, "Testbench: invalid Ethernet frame length %0d", frame_len);
        end

        frame_data[0*8 +: 8] = 8'h02;
        frame_data[1*8 +: 8] = 8'h00;
        frame_data[2*8 +: 8] = 8'h00;
        frame_data[3*8 +: 8] = 8'h00;
        frame_data[4*8 +: 8] = 8'h00;
        frame_data[5*8 +: 8] = 8'h01;
        frame_data[6*8 +: 8] = 8'h02;
        frame_data[7*8 +: 8] = 8'h00;
        frame_data[8*8 +: 8] = 8'h00;
        frame_data[9*8 +: 8] = 8'h00;
        frame_data[10*8 +: 8] = 8'h00;
        frame_data[11*8 +: 8] = 8'h02;
        frame_data[12*8 +: 8] = 8'h08;
        frame_data[13*8 +: 8] = 8'h00;

        for (integer byte_index = 14; byte_index < frame_len; byte_index = byte_index + 1) begin
            frame_data[byte_index*8 +: 8] = payload_seed + 8'(byte_index*13);
        end
    endtask

    task automatic reset_all;
        @(negedge tx_clk);
        tx_rst = 1'b1;
        @(negedge rx_clk);
        rx_rst = 1'b1;
        repeat (4) begin
            @(posedge tx_clk);
            @(posedge rx_clk);
        end
        @(negedge tx_clk);
        tx_rst = 1'b0;
        @(negedge rx_clk);
        rx_rst = 1'b0;
        repeat (4) begin
            @(posedge tx_clk);
            @(posedge rx_clk);
        end
    endtask

    task automatic send_rx_frame(
        input logic [MAX_FRAME_BYTES*8-1:0] frame_data,
        input integer unsigned frame_len
    );
        logic [MAX_RX_STREAM_BYTES*8-1:0] stream_data;
        logic [MAX_RX_STREAM_BYTES-1:0] stream_ctrl;
        logic [31:0] fcs;
        logic [DATA_W-1:0] word_data;
        logic [CTRL_W-1:0] word_ctrl;
        integer unsigned stream_len;

        stream_data = '0;
        stream_ctrl = '0;
        stream_len = 0;
        fcs = mac_frame_pkg::ethernet_crc32(frame_data, frame_len);

        stream_data[stream_len*8 +: 8] = 8'hfb;
        stream_ctrl[stream_len] = 1'b1;
        stream_len = stream_len + 1;
        for (integer byte_index = 0; byte_index < 6; byte_index = byte_index + 1) begin
            stream_data[stream_len*8 +: 8] = 8'h55;
            stream_len = stream_len + 1;
        end
        stream_data[stream_len*8 +: 8] = 8'hd5;
        stream_len = stream_len + 1;

        for (integer byte_index = 0; byte_index < frame_len; byte_index = byte_index + 1) begin
            stream_data[stream_len*8 +: 8] = frame_data[byte_index*8 +: 8];
            stream_len = stream_len + 1;
        end
        for (integer byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
            stream_data[stream_len*8 +: 8] = fcs[byte_index*8 +: 8];
            stream_len = stream_len + 1;
        end
        stream_data[stream_len*8 +: 8] = 8'hfd;
        stream_ctrl[stream_len] = 1'b1;
        stream_len = stream_len + 1;
        while (stream_len % CTRL_W != 0) begin
            stream_data[stream_len*8 +: 8] = 8'h07;
            stream_ctrl[stream_len] = 1'b1;
            stream_len = stream_len + 1;
        end
        repeat (4) begin
            for (integer lane = 0; lane < CTRL_W; lane = lane + 1) begin
                stream_data[stream_len*8 +: 8] = 8'h07;
                stream_ctrl[stream_len] = 1'b1;
                stream_len = stream_len + 1;
            end
        end

        for (integer offset = 0; offset < stream_len; offset = offset + CTRL_W) begin
            @(negedge rx_clk);
            word_data = '0;
            word_ctrl = '0;
            for (integer lane = 0; lane < CTRL_W; lane = lane + 1) begin
                word_data[lane*8 +: 8] = stream_data[(offset+lane)*8 +: 8];
                word_ctrl[lane] = stream_ctrl[offset+lane];
            end
            xgmii_rxd = word_data;
            xgmii_rxc = word_ctrl;
            xgmii_rx_valid = 1'b1;
            @(posedge rx_clk);
        end
    endtask

    task automatic transmit_and_check(
        input logic [MAX_FRAME_BYTES*8-1:0] frame_data,
        input integer unsigned frame_len,
        input logic [TAG_W-1:0] frame_tag
    );
        integer unsigned wait_cycles;

        @(negedge tx_clk);
        tx_capture_enable = 1'b1;
        tx_completion_capture_enable = 1'b1;
        axi_driver.send_frame(frame_data, frame_len, frame_tag);

        wait_cycles = 0;
        while (tx_capture_done !== 1'b1 && wait_cycles < 10000) begin
            @(posedge tx_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (tx_capture_done !== 1'b1) begin
            $fatal(1, "Testbench: timed out waiting for TX XGMII frame");
        end
        scoreboard.compare_tx_frame(
            frame_data,
            frame_len,
            tx_capture_data,
            tx_capture_len,
            tx_preamble_valid,
            tx_sfd_valid
        );
        wait_cycles = 0;
        while (tx_completion_done !== 1'b1 && wait_cycles < 10000) begin
            @(posedge tx_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (tx_completion_done !== 1'b1) begin
            $fatal(1, "Testbench: timed out waiting for TX completion");
        end
        scoreboard.compare_completion_tag(frame_tag, tx_completion_tag);
        @(negedge tx_clk);
        tx_capture_enable = 1'b0;
        tx_completion_capture_enable = 1'b0;
    endtask

    task automatic receive_and_check(
        input logic [MAX_FRAME_BYTES*8-1:0] expected_data,
        input integer unsigned expected_len
    );
        logic [MAX_FRAME_BYTES*8-1:0] observed_data;
        integer unsigned observed_len;
        logic frame_error;

        @(negedge rx_clk);
        rx_capture_enable = 1'b1;
        send_rx_frame(expected_data, expected_len);

        begin
            integer unsigned wait_cycles;
            wait_cycles = 0;
            while (!rx_capture_done && wait_cycles < 10000) begin
                @(posedge rx_clk);
                wait_cycles = wait_cycles + 1;
            end
        end
        if (!rx_capture_done) begin
            $display("RX statuses: fcs=%b framing=%b preamble=%b",
                stat_rx_err_bad_fcs, stat_rx_err_framing, stat_rx_err_preamble);
            $fatal(1, "Testbench: timeout waiting for RX AXI frame");
        end
        @(negedge rx_clk);
        rx_capture_enable = 1'b0;

        observed_data = rx_capture_data;
        observed_len = rx_capture_len;
        frame_error = rx_capture_error;

        scoreboard.compare_rx_frame(
            expected_data,
            expected_len,
            observed_data,
            observed_len,
            frame_error
        );
    endtask

    task automatic test_bas_01;
        logic [MAX_FRAME_BYTES*8-1:0] frame_data;
        integer unsigned frame_len;

        $display("============================================================");
        $display("TEST: MAC BAS-01 - INDEPENDENT TX/RX RESET");
        $display("============================================================");

        reset_all();
        frame_len = 60;
        build_ethernet_frame(frame_data, frame_len, 8'h21);

        @(negedge tx_clk);
        tx_rst = 1'b1;
        receive_and_check(frame_data, frame_len);
        @(negedge tx_clk);
        tx_rst = 1'b0;

        @(negedge rx_clk);
        rx_rst = 1'b1;
        transmit_and_check(frame_data, frame_len, 16'hb001);
        @(negedge rx_clk);
        rx_rst = 1'b0;

        receive_and_check(frame_data, frame_len);

        $display("Reset Isolation      : TX and RX independently exercised");
        $display("TX/RX Recovery       : PASS");
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
    endtask

    task automatic test_bas_02;
        logic [MAX_FRAME_BYTES*8-1:0] frame_data;
        integer unsigned frame_len;

        $display("============================================================");
        $display("TEST: MAC BAS-02 - TX FRAME AND COMPLETION");
        $display("============================================================");

        reset_all();
        frame_len = 60;
        build_ethernet_frame(frame_data, frame_len, 8'h42);
        transmit_and_check(frame_data, frame_len, 16'hb002);

        $display("Frame Bytes          : %0d", frame_len);
        $display("TX Preamble/SFD/FCS  : Verified");
        $display("Completion Tag       : %04x", 16'hb002);
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
    endtask

    task automatic test_bas_03;
        logic [MAX_FRAME_BYTES*8-1:0] frame_data;
        integer unsigned frame_len;

        $display("============================================================");
        $display("TEST: MAC BAS-03 - RX FRAME");
        $display("============================================================");

        reset_all();
        frame_len = 60;
        build_ethernet_frame(frame_data, frame_len, 8'h63);
        receive_and_check(frame_data, frame_len);

        $display("Frame Bytes          : %0d", frame_len);
        $display("RX Error Flag        : 0");
        $display("RX Payload           : Verified");
        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
    endtask

    initial begin
        if (DATA_W != 32 && DATA_W != 64) begin
            $fatal(1, "Testbench: unsupported DATA_W=%0d", DATA_W);
        end

        test_bas_01();
        test_bas_02();
        test_bas_03();

        $display("============================================================");
        $display("MAC BASIC TESTS COMPLETE: DATA_W=%0d", DATA_W);
        $display("RESULT : PASS");
        $display("============================================================");
        $finish;
    end

    initial begin
        #500us;
        $fatal(1, "MAC basic testbench timeout");
    end

endmodule

`default_nettype wire
