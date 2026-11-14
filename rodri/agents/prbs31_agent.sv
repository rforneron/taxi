`timescale 1ns / 1ps
`default_nettype none

module prbs31_agent #(
    parameter integer WORD_W = 66,
    parameter logic [30:0] SEED = 31'h7fffffff
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  advance,
    output logic [WORD_W-1:0]     prbs_word
);

    timeunit 1ns;
    timeprecision 1ps;

    logic [30:0] state_reg = SEED;
    logic [30:0] state_next;
    logic feedback;

    always_comb begin
        state_next = state_reg;
        prbs_word = '0;

        for (integer i = 0; i < WORD_W; i = i + 1) begin
            feedback = state_next[30] ^ state_next[27];
            prbs_word[i] = ~feedback;
            state_next = state_next << 1;
            state_next[0] = feedback;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg <= SEED;
        end else if (advance) begin
            state_reg <= state_next;
        end
    end

    initial begin
        if (WORD_W < 1) begin
            $fatal(1, "WORD_W must be positive");
        end
        if (SEED == '0) begin
            $fatal(1, "PRBS31 seed must be nonzero");
        end
    end

endmodule

`default_nettype wire
