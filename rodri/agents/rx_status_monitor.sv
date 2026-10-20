// ===========================================================
//                    AGENTE RX STATUS MONITOR
// ===========================================================
//
//  Objetivo:
// Monitorear el estado operativo del receptor 10GBASE-R.
//
// Se;ales monitoreadas:
// - rx_error_count
// - rx_bad_block
// - rx_sequence_error
// - rx_block_lock
// - rx_high_ber
// - rx_status
//
//  Version 1: No probada todavia
// ===========================================================
// -----------------------------------------------------------


module rx_status_monitor (
    input logic         clk,
    input logic         rst,

    input logic [6:0]   rx_error_count,
    input logic         rx_bad_block,
    input logic         rx_sequence_error,
    input logic         rx_block_lock,
    input logic         rx_high_ber,
    input logic         rx_status
);

    // -------------------------------------------------------
    // Estado anterior
    // -------------------------------------------------------

    logic rx_block_lock_prev;
    logic rx_high_ber_prev;
    logic rx_status_prev;

    // -------------------------------------------------------
    // Inicializacion
    // -------------------------------------------------------

    initial begin
        rx_block_lock_prev = 1'b0;
        rx_high_ber_prev   = 1'b0;
        rx_status_prev     = 1'b0;
    end

    // -------------------------------------------------------
    // Monitor principal
    // -------------------------------------------------------

    always_ff @(posedge clk) begin

        if (rst) begin

            rx_block_lock_prev <= 1'b0;
            rx_high_ber_prev   <= 1'b0;
            rx_status_prev     <= 1'b0;

        end
        else begin

            //-------------------------------------------------
            // Block Lock
            //-------------------------------------------------

            if (rx_block_lock && !rx_block_lock_prev) begin
                $display("[%0t] RX_MONITOR: Block Lock ACQUIRED",
                    $time);
            end

            if (!rx_block_lock && rx_block_lock_prev) begin
                $display("[%0t] RX_MONITOR: Block Lock LOST",
                    $time);
            end

            //-------------------------------------------------
            // High BER
            //-------------------------------------------------

            if (rx_high_ber && !rx_high_ber_prev) begin
                $display("[%0t] RX_MONITOR: HIGH BER DETECTED",
                    $time);
            end

            if (!rx_high_ber && rx_high_ber_prev) begin
                $display("[%0t] RX_MONITOR: HIGH BER CLEARED",
                    $time);
            end

            //-------------------------------------------------
            // RX Status
            //-------------------------------------------------

            if (rx_status && !rx_status_prev) begin
                $display("[%0t] RX_MONITOR: RX STATUS UP",
                    $time);
            end

            if (!rx_status && rx_status_prev) begin
                $display("[%0t] RX_MONITOR: RX STATUS DOWN",
                    $time);
            end

            //-------------------------------------------------
            // Errores
            //-------------------------------------------------

            if (rx_bad_block) begin
                $display("[%0t] RX_MONITOR: Bad Block",
                    $time);
            end

            if (rx_sequence_error) begin
                $display("[%0t] RX_MONITOR: Sequence Error",
                    $time);
            end

            //-------------------------------------------------
            // Actualización de estado
            //-------------------------------------------------

            rx_block_lock_prev <= rx_block_lock;
            rx_high_ber_prev   <= rx_high_ber;
            rx_status_prev     <= rx_status;

        end

    end

endmodule