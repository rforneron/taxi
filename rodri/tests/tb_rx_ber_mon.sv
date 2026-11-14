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

    task automatic apply_reset;
        @(negedge clk);
        rst = 1'b1;
        repeat (3) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        rst = 1'b0;
    endtask

    initial begin
        repeat (5) begin
            @(posedge clk);
            #1ps;
        end

        @(negedge clk);
        rst = 1'b0;

        // An invalid value without a valid header must not affect the monitor.
        header_driver_inst.send_header(2'b00, 1'b0);
        if (rx_high_ber !== 1'b0) begin
            $fatal(1, "M01: invalid header with valid low changed BER status");
        end

        apply_reset();

        // M01: verify the implemented threshold at 15/16 invalid headers.
        for (integer i = 0; i < 15; i = i + 1) begin
            header_driver_inst.send_header(2'b00, 1'b1);
        end

        if (rx_high_ber !== 1'b0) begin
            $fatal(1, "M01: High BER asserted before 16 invalid headers");
        end

        header_driver_inst.send_header(2'b11, 1'b1);

        if (rx_high_ber !== 1'b1) begin
            $fatal(1, "M01: High BER did not assert on the 16th invalid header");
        end

        // M02: the first boundary closes the window containing the errors.
        // The following fully clean window allows High BER to deassert.
        repeat (COUNT_125US-15) begin
            header_driver_inst.send_header(2'b01, 1'b1);
        end
        if (rx_high_ber !== 1'b1) begin
            $fatal(1, "M02: High BER cleared before the error window closed");
        end

        repeat (COUNT_125US+1) begin
            header_driver_inst.send_header(2'b10, 1'b1);
        end
        if (rx_high_ber !== 1'b0) begin
            $fatal(1, "M02: High BER did not clear after a clean window");
        end

        $display("PASS M01: 15/16 invalid-header threshold and valid gating");
        $display("PASS M02: High BER clears after a clean window");

        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "BER monitor testbench timeout");
    end

endmodule
