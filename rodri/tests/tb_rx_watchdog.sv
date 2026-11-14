`timescale 1ns / 1ps

module tb_rx_watchdog;

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer COUNT_125US = 16;

    logic clk = 0;
    logic rst = 1;

    logic [1:0] serdes_rx_hdr;
    logic serdes_rx_hdr_valid;

    logic rx_bad_block;
    logic rx_sequence_error;
    logic rx_block_lock;
    logic rx_high_ber;

    logic serdes_rx_reset_req;
    logic rx_status;

    always #3.2ns clk = ~clk;

    // =====================================================
    // Header Driver
    // =====================================================

    serdes_rx_header_driver
    header_driver_inst (
        .clk(clk),
        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid)
    );

    // =====================================================
    // DUT
    // =====================================================

    taxi_eth_phy_10g_rx_watchdog #(
        .COUNT_125US(COUNT_125US)
    )
    dut (
        .clk(clk),
        .rst(rst),

        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid),

        .serdes_rx_reset_req(serdes_rx_reset_req),

        .rx_bad_block(rx_bad_block),
        .rx_sequence_error(rx_sequence_error),
        .rx_block_lock(rx_block_lock),
        .rx_high_ber(rx_high_ber),

        .rx_status(rx_status)
    );

    // =====================================================
    // Stimulus
    // =====================================================

    initial begin

        rx_bad_block      = 0;
        rx_sequence_error = 0;
        rx_high_ber       = 0;
        rx_block_lock     = 0;

        repeat (5) begin
            @(posedge clk);
        end

        rst = 0;

        // -------------------------------------------------
        // STEP 1
        // No lock => status must remain low
        // -------------------------------------------------

        repeat (100) begin
            header_driver_inst.send_header(2'b01, 1'b1);
        end

        if (rx_status !== 1'b0) begin
            $fatal(1,
                "rx_status asserted without block lock");
        end

        // -------------------------------------------------
        // STEP 2
        // Acquire lock
        // -------------------------------------------------

        rx_block_lock = 1'b1;

        // Send many valid control headers
        // enough to overflow status_count_reg
        repeat (300) begin
            header_driver_inst.send_header(2'b01, 1'b1);
        end

        // Wait several watchdog windows
        repeat (400) begin
            @(posedge clk);
        end

        if (rx_status !== 1'b1) begin
            $fatal(1,
                "rx_status never asserted");
        end
        $display("PASS M03: watchdog asserts healthy status after consecutive good windows");

        // M04: loss of lock clears status; persistent bad windows request a reset.
        @(negedge clk);
        rx_block_lock = 1'b0;
        @(posedge clk);
        #1ps;
        if (rx_status !== 1'b0) begin
            $fatal(1, "M04: RX status did not clear when block lock was lost");
        end

        @(negedge clk);
        rx_block_lock = 1'b1;
        serdes_rx_hdr = 2'b10;
        serdes_rx_hdr_valid = 1'b1;

        begin
            logic reset_request_seen;
            reset_request_seen = 1'b0;
            for (integer cycle = 0; cycle < 20*(COUNT_125US+1); cycle = cycle + 1) begin
                @(posedge clk);
                #1ps;
                if (serdes_rx_reset_req) begin
                    reset_request_seen = 1'b1;
                end
            end
            if (!reset_request_seen) begin
                $fatal(1, "M04: persistent unhealthy windows did not request an RX reset");
            end
        end
        $display("PASS M04: unhealthy windows clear status and request an RX reset");

        // -------------------------------------------------
        // REPORT
        // -------------------------------------------------

        $display("");
        $display("============================================================");
        $display("TEST: RX WATCHDOG");
        $display("============================================================");
        $display("");

        $display("Block Lock         : %0b", rx_block_lock);
        $display("RX Status          : %0b", rx_status);
        $display("Reset Request      : %0b", serdes_rx_reset_req);

        $display("");

        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
        $display("");

        $finish;

    end

    initial begin
        #100us;
        $fatal(1, "Timeout");
    end

endmodule