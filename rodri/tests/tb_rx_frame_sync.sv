`timescale 1ns / 1ps

module tb_rx_frame_sync;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer VALID_HEADERS_TO_LOCK = 64;
    localparam integer INVALID_HEADERS_TO_UNLOCK = 16;

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [1:0] serdes_rx_hdr;
    logic serdes_rx_hdr_valid;
    logic serdes_rx_bitslip;
    logic rx_block_lock;

    logic [6:0] rx_error_count = '0;
    logic rx_bad_block = 1'b0;
    logic rx_sequence_error = 1'b0;
    logic rx_high_ber = 1'b0;
    logic rx_status = 1'b0;
    logic serdes_rx_reset_req = 1'b0;

    logic [31:0] lock_acquire_count;
    logic [31:0] lock_loss_count;
    logic [31:0] bitslip_count;
    logic [31:0] bad_block_count;
    logic [31:0] sequence_error_count;
    logic [31:0] high_ber_assert_count;
    logic [31:0] rx_status_up_count;
    logic [31:0] rx_status_down_count;
    logic [31:0] reset_request_count;
    logic [31:0] rx_error_count_change_count;

    always #3.2ns clk = !clk;

    serdes_rx_header_driver serdes_rx_header_driver_inst (
        .clk(clk),
        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid)
    );

    taxi_eth_phy_10g_rx_frame_sync #(
        .HDR_W(2),
        .BITSLIP_HIGH_CYCLES(1),
        .BITSLIP_LOW_CYCLES(7)
    )
    dut (
        .clk(clk),
        .rst(rst),
        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid),
        .serdes_rx_bitslip(serdes_rx_bitslip),
        .rx_block_lock(rx_block_lock)
    );

    rx_status_monitor rx_status_monitor_inst (
        .clk(clk),
        .rst(rst),
        .rx_error_count(rx_error_count),
        .rx_bad_block(rx_bad_block),
        .rx_sequence_error(rx_sequence_error),
        .rx_block_lock(rx_block_lock),
        .rx_high_ber(rx_high_ber),
        .rx_status(rx_status),
        .serdes_rx_bitslip(serdes_rx_bitslip),
        .serdes_rx_reset_req(serdes_rx_reset_req),
        .lock_acquire_count(lock_acquire_count),
        .lock_loss_count(lock_loss_count),
        .bitslip_count(bitslip_count),
        .bad_block_count(bad_block_count),
        .sequence_error_count(sequence_error_count),
        .high_ber_assert_count(high_ber_assert_count),
        .rx_status_up_count(rx_status_up_count),
        .rx_status_down_count(rx_status_down_count),
        .reset_request_count(reset_request_count),
        .rx_error_count_change_count(rx_error_count_change_count)
    );

    initial begin
        repeat (3) begin
            @(posedge clk);
            #1ps;
        end

        @(negedge clk);
        rst = 1'b0;

        if (rx_block_lock !== 1'b0) begin
            $fatal(1, "Block lock must be low after reset");
        end

        // An invalid header without valid asserted must not affect lock.
        serdes_rx_header_driver_inst.send_header(2'b00, 1'b0);
        if (rx_block_lock !== 1'b0) begin
            $fatal(1, "An invalid header without valid asserted changed lock");
        end

        // The receiver acquires lock on the 64th valid sync header.
        for (integer i = 0; i < VALID_HEADERS_TO_LOCK-1; i = i + 1) begin
            serdes_rx_header_driver_inst.send_header(i[0] ? 2'b10 : 2'b01, 1'b1);
        end

        if (rx_block_lock !== 1'b0) begin
            $fatal(1, "Block lock asserted before 64 valid headers");
        end

        serdes_rx_header_driver_inst.send_header(2'b10, 1'b1);
        if (rx_block_lock !== 1'b1) begin
            $fatal(1, "Block lock did not assert on the 64th valid header");
        end

        // Sixteen consecutive invalid headers cause lock loss and bitslip.
        for (integer i = 0; i < INVALID_HEADERS_TO_UNLOCK; i = i + 1) begin
            serdes_rx_header_driver_inst.send_header(2'b00, 1'b1);
        end

        if (rx_block_lock !== 1'b0) begin
            $fatal(1, "Block lock did not drop after 16 invalid headers");
        end

        if (serdes_rx_bitslip !== 1'b1) begin
            $fatal(1, "Bitslip did not assert after block lock was lost");
        end

        // Stop presenting headers while the bitslip request runs.
        serdes_rx_header_driver_inst.idle_cycles(2);
        if (lock_acquire_count != 1 || lock_loss_count != 1 || bitslip_count != 1) begin
            $fatal(1, "Status monitor did not record the lock loss and bitslip events");
        end

        serdes_rx_header_driver_inst.idle_cycles(20);
        if (serdes_rx_bitslip !== 1'b0) begin
            $fatal(1, "Bitslip did not deassert after its configured interval");
        end

        // A fresh run of valid headers reacquires lock.
        for (integer i = 0; i < VALID_HEADERS_TO_LOCK; i = i + 1) begin
            serdes_rx_header_driver_inst.send_header(i[0] ? 2'b10 : 2'b01, 1'b1);
        end

        serdes_rx_header_driver_inst.idle_cycles(1);
        if (rx_block_lock !== 1'b1 || lock_acquire_count != 2) begin
            $fatal(1, "Receiver did not reacquire block lock");
        end

        $display("PASS: RX frame sync acquisition, loss, bitslip, and recovery");
        $finish;
    end

endmodule
