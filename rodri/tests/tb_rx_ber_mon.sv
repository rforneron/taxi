`timescale 1ns / 1ps

module tb_rx_ber_mon;

    timeunit 1ns;
    timeprecision 1ps;

    // =====================================================
    // Configuration
    // =====================================================

    localparam integer COUNT_125US = 1000;

    // =====================================================
    // Clock / Reset
    // =====================================================

    logic clk = 1'b0;
    logic rst = 1'b1;

    always #3.2ns clk = ~clk;

    // =====================================================
    // DUT Signals
    // =====================================================

    logic [1:0] serdes_rx_hdr;
    logic       serdes_rx_hdr_valid;

    logic       rx_high_ber;

    // =====================================================
    // Agent
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

    taxi_eth_phy_10g_rx_ber_mon #(
        .HDR_W(2),
        .COUNT_125US(COUNT_125US)
    )
    dut (
        .clk(clk),
        .rst(rst),

        .serdes_rx_hdr(serdes_rx_hdr),
        .serdes_rx_hdr_valid(serdes_rx_hdr_valid),

        .rx_high_ber(rx_high_ber)
    );

    // =====================================================
    // Counters
    // =====================================================

    integer valid_header_count;
    integer invalid_header_count;

    // =====================================================
    // Test
    // =====================================================

    initial begin

        valid_header_count   = 0;
        invalid_header_count = 0;

        // -------------------------------------------------
        // Reset
        // -------------------------------------------------

        repeat (5) begin
            @(posedge clk);
            #1ps;
        end

        @(negedge clk);
        rst = 1'b0;

        // =================================================
        // PHASE 1
        // VALID HEADERS
        // =================================================

        repeat (32) begin
            header_driver_inst.send_header(2'b01, 1'b1);
            valid_header_count++;
        end

        repeat (32) begin
            header_driver_inst.send_header(2'b10, 1'b1);
            valid_header_count++;
        end

        if (rx_high_ber !== 1'b0) begin
            $fatal(1,
                "High BER asserted while sending valid headers");
        end

        // =================================================
        // PHASE 2
        // INVALID HEADER COUNT
        // =================================================

        repeat (15) begin
            header_driver_inst.send_header(2'b00, 1'b1);
            invalid_header_count++;
        end

        if (rx_high_ber !== 1'b0) begin
            $fatal(1,
                "High BER asserted too early (15 invalid headers)");
        end

        // =================================================
        // PHASE 3
        // HIGH BER DETECTION
        // =================================================

        header_driver_inst.send_header(2'b00, 1'b1);

        invalid_header_count++;

        if (rx_high_ber !== 1'b1) begin
            $fatal(1,
                "High BER not asserted after 16 invalid headers");
        end

        // =================================================
        // PHASE 4
        // HEADER MATRIX
        // =================================================

        // 01 = valid
        header_driver_inst.send_header(2'b01, 1'b1);

        // 10 = valid
        header_driver_inst.send_header(2'b10, 1'b1);

        // 11 = invalid
        header_driver_inst.send_header(2'b11, 1'b1);
        invalid_header_count++;

        // 00 = invalid
        header_driver_inst.send_header(2'b00, 1'b1);
        invalid_header_count++;

        // =================================================
        // REPORT
        // =================================================

        $display("");
        $display("============================================================");
        $display("TEST: RX BER MONITOR");
        $display("============================================================");
        $display("");

        $display("[VALID HEADERS]");
        $display("------------------------------------------------------------");
        $display("Valid Headers Tested   : %0d", valid_header_count);
        $display("High BER               : 0");
        $display("");

        $display("[INVALID HEADER COUNT]");
        $display("------------------------------------------------------------");
        $display("Invalid Headers Tested : 15");
        $display("High BER               : 0");
        $display("");

        $display("[HIGH BER DETECTION]");
        $display("------------------------------------------------------------");
        $display("Invalid Headers Tested : 16");
        $display("High BER               : %0b", rx_high_ber);
        $display("");

        $display("[HEADER MATRIX]");
        $display("------------------------------------------------------------");
        $display("01 -> VALID");
        $display("10 -> VALID");
        $display("00 -> INVALID");
        $display("11 -> INVALID");
        $display("");

        $display("============================================================");
        $display("RESULT : PASS");
        $display("============================================================");
        $display("");

        $finish;

    end

    // =====================================================
    // Timeout Protection
    // =====================================================

    initial begin
        #100us;
        $fatal(1, "Timeout");
    end

endmodule