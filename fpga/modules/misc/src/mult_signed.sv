/*******************************************************************************
#
#   FILENAME: mult_signed.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 31 Dec 2019
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   31 Dec 2019    Greg Taylor
#       Initial version
#
#******************************************************************************/
`timescale 1ns / 1ps
`default_nettype none

module mult_signed #(
    parameter DATA_WIDTHA = 0,
    parameter DATA_WIDTHB = 0,
    parameter OUTPUT_DELAY = 2 // 2 or more (DSP48 has a min latency of 2 cycles)
) (
    input wire clk,
    input wire signed [DATA_WIDTHA-1:0] a,
    input wire signed [DATA_WIDTHB-1:0] b,
    output logic signed [DATA_WIDTHA+DATA_WIDTHB-1:0] result
);
    logic [DATA_WIDTHA-1:0] a_r0;
    logic [DATA_WIDTHB-1:0] b_r0;
    logic [DATA_WIDTHA+DATA_WIDTHB-1:0] result_p0 [OUTPUT_DELAY-1];

    integer i;
    always_ff @(posedge clk) begin
        a_r0 <= a;
        b_r0 <= b;
        result_p0[0] <= a_r0*b_r0;

        for (i = 0; i < OUTPUT_DELAY-2; i++)
            result_p0[i+1] <= result_p0[i];
    end

//    genvar i;
//    generate
//    for (i = 0; i < OUTPUT_DELAY-2; i++)
//        always_ff @(posedge clk)
//            result_p0[i+1] <= result_p0[i];
//    endgenerate

    always_comb result = result_p0[OUTPUT_DELAY-2];

endmodule
`default_nettype wire