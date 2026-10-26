`timescale 1ns / 1ps

module tb_eth_phy_10g_data;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer DATA_W = 64;
    localparam integer CTRL_W = DATA_W / 8;
    localparam integer HDR_W = 2;
    localparam integer MAX_SAMPLES = 512;
    localparam integer FRAME_WORDS = 5;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic use_internal_loopback = 1'b1;

    logic [DATA_W-1:0] xgmii_txd;
    logic [CTRL_W-1:0] xgmii_txc;
    logic xgmii_tx_valid;
    logic [DATA_W-1:0] xgmii_rxd;
    logic [CTRL_W-1:0] xgmii_rxc;
    logic xgmii_rx_valid;

    logic [DATA_W-1:0] serdes_tx_data;
    logic serdes_tx_data_valid;
    logic [HDR_W-1:0] serdes_tx_hdr;
    logic serdes_tx_hdr_valid;
    logic [DATA_W-1:0] manual_serdes_rx_data;
    logic manual_serdes_rx_data_valid;
    logic [HDR_W-1:0] manual_serdes_rx_hdr;
    logic manual_serdes_rx_hdr_valid;
    logic [DATA_W-1:0] serdes_rx_data;
    logic serdes_rx_data_valid;
    logic [HDR_W-1:0] serdes_rx_hdr;
    logic serdes_rx_hdr_valid;

    logic [DATA_W-1:0] captured_serdes_data [0:MAX_SAMPLES-1];
    logic [HDR_W-1:0] captured_serdes_hdr [0:MAX_SAMPLES-1];
    logic [DATA_W-1:0] captured_xgmii_data [0:MAX_SAMPLES-1];
    logic [CTRL_W-1:0] captured_xgmii_control [0:MAX_SAMPLES-1];
    logic captured_bad_block [0:MAX_SAMPLES-1];
    logic captured_sequence_error [0:MAX_SAMPLES-1];
    integer unsigned serdes_sample_count;
    integer unsigned xgmii_sample_count;
    logic serdes_capture_overflow;
    logic xgmii_capture_overflow;

    logic clear_serdes_capture = 1'b0;
    logic enable_serdes_capture = 1'b0;
    logic clear_xgmii_capture = 1'b0;
    logic enable_xgmii_capture = 1'b0;

    logic tx_bad_block;
    logic [6:0] rx_error_count;
    logic rx_bad_block;
    logic rx_sequence_error;
    logic rx_block_lock;
    logic rx_high_ber;
    logic rx_status;
    logic serdes_rx_bitslip;
    logic serdes_rx_reset_req;
    logic tx_gbx_req_sync;
    logic tx_gbx_req_stall;
    logic rx_gbx_sync;
    logic serdes_tx_gbx_sync;

    logic [DATA_W-1:0] expected_frame_data [0:FRAME_WORDS-1];
    logic [CTRL_W-1:0] expected_frame_control [0:FRAME_WORDS-1];

    integer start_sample;
    integer candidate_sample;
    integer frame_word;
    integer data_header_count;
    integer control_header_count;

    always #3.2ns clk = !clk;

    assign serdes_rx_data = use_internal_loopback
        ? serdes_tx_data : manual_serdes_rx_data;
    assign serdes_rx_data_valid = use_internal_loopback
        ? serdes_tx_data_valid : manual_serdes_rx_data_valid;
    assign serdes_rx_hdr = use_internal_loopback
        ? serdes_tx_hdr : manual_serdes_rx_hdr;
    assign serdes_rx_hdr_valid = use_internal_loopback
        ? serdes_tx_hdr_valid : manual_serdes_rx_hdr_valid;

    xgmii_tx_driver #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W)
    )
    xgmii_tx_driver_inst (
        .clk(clk),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_tx_valid(xgmii_tx_valid)
    );

    serdes_rx_data_driver #(
        .DATA_W(DATA_W),
        .HDR_W(HDR_W)
    )
    serdes_rx_data_driver_inst (
        .clk(clk),
        .serdes_rx_data(manual_serdes_rx_data),
        .serdes_rx_data_valid(manual_serdes_rx_data_valid),
        .serdes_rx_hdr(manual_serdes_rx_hdr),
        .serdes_rx_hdr_valid(manual_serdes_rx_hdr_valid)
    );

    taxi_eth_phy_10g #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .HDR_W(HDR_W),
        .TX_GBX_IF_EN(1'b0),
        .RX_GBX_IF_EN(1'b0),
        .BIT_REVERSE(1'b0),
        .SCRAMBLER_DISABLE(1'b0),
        .PRBS31_EN(1'b0),
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
        .xgmii_tx_valid(xgmii_tx_valid),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_rx_valid(xgmii_rx_valid),
        .tx_gbx_req_sync(tx_gbx_req_sync),
        .tx_gbx_req_stall(tx_gbx_req_stall),
        .tx_gbx_sync(1'b0),
        .rx_gbx_sync(rx_gbx_sync),
        .serdes_tx_data(serdes_tx_data),
        .serdes_tx_data_valid(serdes_tx_data_valid),
        .serdes_tx_hdr(serdes_tx_hdr),
        .serdes_tx_hdr_valid(serdes_tx_hdr_valid),
        .serdes_tx_gbx_req_sync(1'b0),
        .serdes_tx_gbx_req_stall(1'b0),
        .serdes_tx_gbx_sync(serdes_tx_gbx_sync),
        .serdes_rx_data(serdes_rx_data),
        .serdes_rx_data_valid(serdes_rx_data_valid),
        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid),
        .serdes_rx_gbx_sync(1'b0),
        .serdes_rx_bitslip(serdes_rx_bitslip),
        .serdes_rx_reset_req(serdes_rx_reset_req),
        .tx_bad_block(tx_bad_block),
        .rx_error_count(rx_error_count),
        .rx_bad_block(rx_bad_block),
        .rx_sequence_error(rx_sequence_error),
        .rx_block_lock(rx_block_lock),
        .rx_high_ber(rx_high_ber),
        .rx_status(rx_status),
        .cfg_tx_prbs31_enable(1'b0),
        .cfg_rx_prbs31_enable(1'b0)
    );

    serdes_tx_monitor #(
        .DATA_W(DATA_W),
        .HDR_W(HDR_W),
        .MAX_SAMPLES(MAX_SAMPLES)
    )
    serdes_tx_monitor_inst (
        .clk(clk),
        .capture_enable(enable_serdes_capture),
        .clear(clear_serdes_capture),
        .serdes_tx_data(serdes_tx_data),
        .serdes_tx_data_valid(serdes_tx_data_valid),
        .serdes_tx_hdr(serdes_tx_hdr),
        .serdes_tx_hdr_valid(serdes_tx_hdr_valid),
        .sample_count(serdes_sample_count),
        .overflow(serdes_capture_overflow),
        .sample_data(captured_serdes_data),
        .sample_hdr(captured_serdes_hdr)
    );

    xgmii_rx_monitor #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .MAX_SAMPLES(MAX_SAMPLES)
    )
    xgmii_rx_monitor_inst (
        .clk(clk),
        .capture_enable(enable_xgmii_capture),
        .clear(clear_xgmii_capture),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_rx_valid(xgmii_rx_valid),
        .rx_bad_block(rx_bad_block),
        .rx_sequence_error(rx_sequence_error),
        .sample_count(xgmii_sample_count),
        .overflow(xgmii_capture_overflow),
        .sample_data(captured_xgmii_data),
        .sample_control(captured_xgmii_control),
        .sample_bad_block(captured_bad_block),
        .sample_sequence_error(captured_sequence_error)
    );

    task automatic reset_rx_path;
        @(negedge clk);
        rst = 1'b1;
        repeat (3) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        rst = 1'b0;
    endtask

    task automatic configure_expected_frame;
        expected_frame_data[0] = 64'hD5555555555555FB;
        expected_frame_control[0] = 8'h01;

        expected_frame_data[1] = 64'h0706050403020100;
        expected_frame_data[2] = 64'h1716151413121110;
        expected_frame_data[3] = 64'h2726252423222120;
        expected_frame_control[1] = 8'h00;
        expected_frame_control[2] = 8'h00;
        expected_frame_control[3] = 8'h00;

        expected_frame_data[4] = 64'h07070707070707FD;
        expected_frame_control[4] = 8'hFF;
    endtask

    task automatic send_test_frame;
        for (integer word_index = 0; word_index < FRAME_WORDS; word_index = word_index + 1) begin
            xgmii_tx_driver_inst.send_word(
                expected_frame_data[word_index],
                expected_frame_control[word_index]
            );
        end
    endtask

    task automatic check_received_frame(input string test_name);
        start_sample = -1;

        for (integer sample_index = 0;
                sample_index < xgmii_sample_count;
                sample_index = sample_index + 1) begin
            if (captured_xgmii_control[sample_index][0] &&
                    captured_xgmii_data[sample_index][7:0] == 8'hFB) begin
                start_sample = sample_index;
                break;
            end
        end

        if (start_sample < 0) begin
            $fatal(1, "%s: no XGMII start character was received", test_name);
        end

        for (integer word_index = 0; word_index < FRAME_WORDS; word_index = word_index + 1) begin
            candidate_sample = start_sample + word_index;
            if (candidate_sample >= xgmii_sample_count) begin
                $fatal(1, "%s: frame ended before word %0d was captured",
                    test_name, word_index);
            end

            if (captured_xgmii_data[candidate_sample] !== expected_frame_data[word_index] ||
                    captured_xgmii_control[candidate_sample] !== expected_frame_control[word_index]) begin
                $fatal(1,
                    "%s: mismatch at frame word %0d: data %016h ctrl %02h, expected %016h ctrl %02h",
                    test_name,
                    word_index,
                    captured_xgmii_data[candidate_sample],
                    captured_xgmii_control[candidate_sample],
                    expected_frame_data[word_index],
                    expected_frame_control[word_index]
                );
            end

            if (captured_bad_block[candidate_sample] ||
                    captured_sequence_error[candidate_sample]) begin
                $fatal(1,
                    "%s: RX reported an error during frame word %0d (bad_block=%b sequence_error=%b)",
                    test_name,
                    word_index,
                    captured_bad_block[candidate_sample],
                    captured_sequence_error[candidate_sample]
                );
            end
        end
    endtask

    task automatic replay_captured_serdes_stream;
        for (integer sample_index = 0;
                sample_index < serdes_sample_count;
                sample_index = sample_index + 1) begin
            serdes_rx_data_driver_inst.send_block(
                captured_serdes_data[sample_index],
                captured_serdes_hdr[sample_index],
                1'b1,
                1'b1
            );
        end

        serdes_rx_data_driver_inst.idle_cycles(10);
    endtask

    initial begin
        configure_expected_frame();
        clear_serdes_capture = 1'b1;
        clear_xgmii_capture = 1'b1;

        repeat (4) begin
            @(posedge clk);
            #1ps;
        end

        @(negedge clk);
        rst = 1'b0;
        clear_serdes_capture = 1'b0;
        clear_xgmii_capture = 1'b0;

        // TX phase: capture a standards-shaped idle, start, data, and terminate stream.
        enable_serdes_capture = 1'b1;
        xgmii_tx_driver_inst.send_idle_words(80);
        send_test_frame();
        xgmii_tx_driver_inst.send_idle_words(24);
        enable_serdes_capture = 1'b0;

        repeat (8) begin
            @(posedge clk);
            #1ps;
        end

        if (serdes_sample_count < 100) begin
            $fatal(1, "SERDES monitor captured too few blocks: %0d", serdes_sample_count);
        end
        if (serdes_capture_overflow) begin
            $fatal(1, "SERDES monitor sample buffer overflowed");
        end

        data_header_count = 0;
        control_header_count = 0;
        for (integer sample_index = 0;
                sample_index < serdes_sample_count;
                sample_index = sample_index + 1) begin
            case (captured_serdes_hdr[sample_index])
                2'b10: data_header_count = data_header_count + 1;
                2'b01: control_header_count = control_header_count + 1;
                default: $fatal(1, "TX produced invalid 64b/66b sync header %b",
                    captured_serdes_hdr[sample_index]);
            endcase
        end

        if (data_header_count < 3 || control_header_count < 2) begin
            $fatal(1, "TX did not produce both data and control blocks");
        end

        if (tx_bad_block) begin
            $fatal(1, "TX reported a bad block for a legal XGMII frame");
        end

        $display("PASS: TX driver and SERDES monitor captured %0d blocks (%0d data, %0d control)",
            serdes_sample_count, data_header_count, control_header_count);

        // RX phase: reset the receiver, then replay the captured SERDES stream.
        use_internal_loopback = 1'b0;
        enable_xgmii_capture = 1'b0;
        clear_xgmii_capture = 1'b1;
        @(posedge clk);
        #1ps;
        clear_xgmii_capture = 1'b0;
        reset_rx_path();
        enable_xgmii_capture = 1'b1;
        replay_captured_serdes_stream();

        repeat (8) begin
            @(posedge clk);
            #1ps;
        end

        check_received_frame("RX replay");
        if (xgmii_capture_overflow) begin
            $fatal(1, "XGMII RX monitor sample buffer overflowed during replay");
        end
        $display("PASS: SERDES driver and XGMII monitor verified RX replay");

        // Integration phase: route the top's SERDES TX directly into its RX.
        // Keep the link active so the self-synchronous scrambler can settle.
        enable_xgmii_capture = 1'b0;
        use_internal_loopback = 1'b1;

        xgmii_tx_driver_inst.send_idle_words(80);
        while (!rx_block_lock) begin
            @(posedge clk);
            #1ps;
        end

        // Close any partial frame left by the preceding RX replay before checking.
        xgmii_tx_driver_inst.send_word(64'h07070707070707FD, 8'hFF);
        xgmii_tx_driver_inst.send_idle_words(8);

        clear_xgmii_capture = 1'b1;
        @(posedge clk);
        #1ps;
        clear_xgmii_capture = 1'b0;
        enable_xgmii_capture = 1'b1;

        send_test_frame();
        xgmii_tx_driver_inst.send_idle_words(16);

        repeat (8) begin
            @(posedge clk);
            #1ps;
        end

        check_received_frame("top loopback");
        if (xgmii_capture_overflow) begin
            $fatal(1, "XGMII RX monitor sample buffer overflowed during loopback");
        end
        if (rx_bad_block || rx_sequence_error || tx_bad_block) begin
            $fatal(1, "Top reported a block or sequence error in the loopback test");
        end

        $display("PASS: taxi_eth_phy_10g top TX-to-RX loopback");
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "Testbench timed out");
    end

endmodule
