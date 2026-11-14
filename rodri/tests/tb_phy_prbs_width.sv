`timescale 1ns / 1ps
`default_nettype none

module tb_phy_prbs_width;

    timeunit 1ns;
    timeprecision 1ps;

    logic done_32 = 1'b0;
    logic done_64 = 1'b0;

    prbs_tx_width_case #(
        .DATA_W(32)
    )
    width_32_case (
        .done(done_32)
    );

    prbs_tx_width_case #(
        .DATA_W(64)
    )
    width_64_case (
        .done(done_64)
    );

    initial begin
        wait (done_32 && done_64);
        $display("PASS P05: PRBS31 output and valid gating work at DATA_W=32 and DATA_W=64");
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "PRBS width testbench timeout");
    end

endmodule

module prbs_tx_width_case #(
    parameter integer DATA_W = 64
) (
    output logic done
);

    timeunit 1ns;
    timeprecision 1ps;

    localparam integer WORD_W = DATA_W + 2;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cfg_tx_prbs31_enable = 1'b0;
    logic [DATA_W-1:0] encoded_tx_data = '0;
    logic encoded_tx_data_valid = 1'b0;
    logic [1:0] encoded_tx_hdr = 2'b10;
    logic encoded_tx_hdr_valid = 1'b0;
    logic [DATA_W-1:0] serdes_tx_data;
    logic serdes_tx_data_valid;
    logic [1:0] serdes_tx_hdr;
    logic serdes_tx_hdr_valid;
    logic [DATA_W-1:0] continuous_data;
    logic continuous_data_valid;
    logic [1:0] continuous_hdr;
    logic continuous_hdr_valid;
    logic [WORD_W-1:0] reference_history [0:83];
    logic [WORD_W-1:0] expected_word;
    integer valid_count = 0;

    always #3.2ns clk = !clk;

    taxi_eth_phy_10g_tx_if #(
        .DATA_W(DATA_W),
        .HDR_W(2),
        .GBX_IF_EN(1'b1),
        .SCRAMBLER_DISABLE(1'b1),
        .PRBS31_EN(1'b1),
        .SERDES_PIPELINE(0)
    )
    dut (
        .clk(clk),
        .rst(rst),
        .encoded_tx_data(encoded_tx_data),
        .encoded_tx_data_valid(encoded_tx_data_valid),
        .encoded_tx_hdr(encoded_tx_hdr),
        .encoded_tx_hdr_valid(encoded_tx_hdr_valid),
        .tx_gbx_req_sync(),
        .tx_gbx_req_stall(),
        .tx_gbx_sync(1'b0),
        .serdes_tx_data(serdes_tx_data),
        .serdes_tx_data_valid(serdes_tx_data_valid),
        .serdes_tx_hdr(serdes_tx_hdr),
        .serdes_tx_hdr_valid(serdes_tx_hdr_valid),
        .serdes_tx_gbx_req_sync(1'b0),
        .serdes_tx_gbx_req_stall(1'b0),
        .serdes_tx_gbx_sync(),
        .cfg_tx_prbs31_enable(cfg_tx_prbs31_enable)
    );

    taxi_eth_phy_10g_tx_if #(
        .DATA_W(DATA_W),
        .HDR_W(2),
        .GBX_IF_EN(1'b1),
        .SCRAMBLER_DISABLE(1'b1),
        .PRBS31_EN(1'b1),
        .SERDES_PIPELINE(0)
    )
    continuous_reference_dut (
        .clk(clk),
        .rst(rst),
        .encoded_tx_data(encoded_tx_data),
        .encoded_tx_data_valid(1'b1),
        .encoded_tx_hdr(encoded_tx_hdr),
        .encoded_tx_hdr_valid(1'b1),
        .tx_gbx_req_sync(),
        .tx_gbx_req_stall(),
        .tx_gbx_sync(1'b0),
        .serdes_tx_data(continuous_data),
        .serdes_tx_data_valid(continuous_data_valid),
        .serdes_tx_hdr(continuous_hdr),
        .serdes_tx_hdr_valid(continuous_hdr_valid),
        .serdes_tx_gbx_req_sync(1'b0),
        .serdes_tx_gbx_req_stall(1'b0),
        .serdes_tx_gbx_sync(),
        .cfg_tx_prbs31_enable(cfg_tx_prbs31_enable)
    );

    task automatic drive_cycle(input logic valid, input integer cycle);
        @(negedge clk);
        encoded_tx_data = DATA_W'(cycle * 32'h10204081);
        encoded_tx_data_valid = valid;
        encoded_tx_hdr_valid = valid;
        @(posedge clk);
        #1ps;

        if (serdes_tx_data_valid !== valid || serdes_tx_hdr_valid !== valid) begin
            $fatal(1, "P05 DATA_W=%0d: SERDES valid gating mismatch at cycle %0d",
                DATA_W, cycle);
        end
        if (!continuous_data_valid || !continuous_hdr_valid) begin
            $fatal(1, "P05 DATA_W=%0d: continuous reference output was invalid", DATA_W);
        end
        reference_history[cycle] = {continuous_data, continuous_hdr};
        if (valid) begin
            if (valid_count == cycle) begin
                expected_word = reference_history[cycle];
            end else begin
                expected_word = reference_history[valid_count];
            end
            if ({serdes_tx_data, serdes_tx_hdr} !== expected_word) begin
                $fatal(1,
                    "P05 DATA_W=%0d: paused PRBS phase mismatch at cycle %0d (got %h expected %h)",
                    DATA_W, cycle, {serdes_tx_data, serdes_tx_hdr}, expected_word);
            end
            valid_count = valid_count + 1;
        end
    endtask

    initial begin
        done = 1'b0;
        repeat (4) begin
            @(posedge clk);
            #1ps;
        end
        @(negedge clk);
        rst = 1'b0;
        cfg_tx_prbs31_enable = 1'b1;

        for (integer cycle = 0; cycle < 80; cycle = cycle + 1) begin
            drive_cycle((cycle % 7) == 1 || (cycle % 7) == 2 ||
                (cycle % 11) == 0, cycle);
        end
        for (integer cycle = 80; cycle < 84; cycle = cycle + 1) begin
            drive_cycle(1'b0, cycle);
        end

        if (valid_count < 20) begin
            $fatal(1, "P05 DATA_W=%0d: insufficient valid PRBS samples", DATA_W);
        end
        done = 1'b1;
    end

endmodule

`default_nettype wire
