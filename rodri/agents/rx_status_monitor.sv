`timescale 1ns / 1ps

module rx_status_monitor (
    input  logic        clk,
    input  logic        rst,
    input  logic [6:0]  rx_error_count,
    input  logic        rx_bad_block,
    input  logic        rx_sequence_error,
    input  logic        rx_block_lock,
    input  logic        rx_high_ber,
    input  logic        rx_status,
    input  logic        serdes_rx_bitslip,
    input  logic        serdes_rx_reset_req,
    output logic [31:0] lock_acquire_count,
    output logic [31:0] lock_loss_count,
    output logic [31:0] bitslip_count,
    output logic [31:0] bad_block_count,
    output logic [31:0] sequence_error_count,
    output logic [31:0] high_ber_assert_count,
    output logic [31:0] rx_status_up_count,
    output logic [31:0] rx_status_down_count,
    output logic [31:0] reset_request_count,
    output logic [31:0] rx_error_count_change_count
);

    logic rx_block_lock_prev;
    logic serdes_rx_bitslip_prev;
    logic rx_high_ber_prev;
    logic rx_status_prev;
    logic [6:0] rx_error_count_prev;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_block_lock_prev <= 1'b0;
            serdes_rx_bitslip_prev <= 1'b0;
            rx_high_ber_prev <= 1'b0;
            rx_status_prev <= 1'b0;
            rx_error_count_prev <= '0;

            lock_acquire_count <= '0;
            lock_loss_count <= '0;
            bitslip_count <= '0;
            bad_block_count <= '0;
            sequence_error_count <= '0;
            high_ber_assert_count <= '0;
            rx_status_up_count <= '0;
            rx_status_down_count <= '0;
            reset_request_count <= '0;
            rx_error_count_change_count <= '0;
        end else begin
            if (rx_block_lock && !rx_block_lock_prev) begin
                lock_acquire_count <= lock_acquire_count + 1'b1;
            end

            if (!rx_block_lock && rx_block_lock_prev) begin
                lock_loss_count <= lock_loss_count + 1'b1;
            end

            if (serdes_rx_bitslip && !serdes_rx_bitslip_prev) begin
                bitslip_count <= bitslip_count + 1'b1;
            end

            if (rx_bad_block) begin
                bad_block_count <= bad_block_count + 1'b1;
            end

            if (rx_sequence_error) begin
                sequence_error_count <= sequence_error_count + 1'b1;
            end

            if (rx_high_ber && !rx_high_ber_prev) begin
                high_ber_assert_count <= high_ber_assert_count + 1'b1;
            end

            if (rx_status && !rx_status_prev) begin
                rx_status_up_count <= rx_status_up_count + 1'b1;
            end

            if (!rx_status && rx_status_prev) begin
                rx_status_down_count <= rx_status_down_count + 1'b1;
            end

            if (serdes_rx_reset_req) begin
                reset_request_count <= reset_request_count + 1'b1;
            end

            if (rx_error_count != rx_error_count_prev) begin
                rx_error_count_change_count <= rx_error_count_change_count + 1'b1;
            end

            rx_block_lock_prev <= rx_block_lock;
            serdes_rx_bitslip_prev <= serdes_rx_bitslip;
            rx_high_ber_prev <= rx_high_ber;
            rx_status_prev <= rx_status;
            rx_error_count_prev <= rx_error_count;
        end
    end

endmodule
