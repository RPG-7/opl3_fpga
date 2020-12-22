/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: calc_phase_inc.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 13 Oct 2014
#
#   DESCRIPTION:
#   Prepare the phase increment for the NCO (calc multiplier and vibrato)
#
#   CHANGE HISTORY:
#   13 Oct 2014    Greg Taylor
#       Initial version
#
#   Copyright (C) 2014 Greg Taylor <gtaylor@sonic.net>
#
#   This file is part of OPL3 FPGA.
#
#   OPL3 FPGA is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   OPL3 FPGA is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public License
#   along with OPL3 FPGA.  If not, see <http://www.gnu.org/licenses/>.
#
#   Original Java Code:
#   Copyright (C) 2008 Robson Cozendey <robson@cozendey.com>
#
#   Original C++ Code:
#   Copyright (C) 2012  Steffen Ohrendorf <steffen.ohrendorf@gmx.de>
#
#   Some code based on forum posts in:
#   http://forums.submarine.org.uk/phpBB/viewforum.php?f=9,
#   Copyright (C) 2010-2013 by carbon14 and opl3
#
#******************************************************************************/
`timescale 1ns / 1ps
`default_nettype none  // disable implicit net type declarations

import opl3_pkg::*;

module calc_phase_inc (
    input wire clk,
    input wire sample_clk_en,
    input wire [BANK_NUM_WIDTH-1:0] bank_num,
    input wire [OP_NUM_WIDTH-1:0] op_num,
    input wire [REG_FNUM_WIDTH-1:0] fnum,
    input wire [REG_MULT_WIDTH-1:0] mult,
    input wire [REG_BLOCK_WIDTH-1:0] block,
    input wire vib,
    input wire dvb,
    input wire [ENV_WIDTH-1:0] env,
    output logic signed [PHASE_ACC_WIDTH-1:0] phase_inc = 0
);
    logic signed [PHASE_ACC_WIDTH-1:0] pre_mult = 0;
    logic signed [PHASE_ACC_WIDTH-1:0] pre_mult_p0 = 0;
    logic signed [PHASE_ACC_WIDTH-1:0] post_mult = 0;
    logic signed [PHASE_ACC_WIDTH-1:0] mult3;
    logic signed [PHASE_ACC_WIDTH-1:0] mult5;
    logic signed [PHASE_ACC_WIDTH-1:0] mult6;
    logic signed [PHASE_ACC_WIDTH-1:0] mult7;
    logic signed [PHASE_ACC_WIDTH-1:0] mult9;
    logic signed [PHASE_ACC_WIDTH-1:0] mult10;
    logic signed [PHASE_ACC_WIDTH-1:0] mult12;
    logic signed [PHASE_ACC_WIDTH-1:0] mult15;

    wire signed [REG_FNUM_WIDTH-1:0] vib_val;

    /*
     * Match delay of DSP multiplier
     */
    always_ff @(posedge clk) begin
        pre_mult_p0 = fnum << block;
        pre_mult <= pre_mult_p0;
    end

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult3_inst (
        .clk,
        .a(fnum << block),
        .b(3),
        .result(mult3)
    );

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult5_inst (
        .clk,
        .a(fnum << block),
        .b(5),
        .result(mult5)
    );

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult6_inst (
        .clk,
        .a(fnum << block),
        .b(6),
        .result(mult6)
    );

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult7_inst (
        .clk,
        .a(fnum << block),
        .b(7),
        .result(mult7)
    );

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult9_inst (
        .clk,
        .a(fnum << block),
        .b(9),
        .result(mult9)
    );

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult10_inst (
        .clk,
        .a(fnum << block),
        .b(10),
        .result(mult10)
    );

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult12_inst (
        .clk,
        .a(fnum << block),
        .b(12),
        .result(mult12)
    );

    mult_signed #(
        .DATA_WIDTHA(PHASE_ACC_WIDTH),
        .DATA_WIDTHB(4),
        .OUTPUT_DELAY(2)
    ) mult15_inst (
        .clk,
        .a(fnum << block),
        .b(15),
        .result(mult15)
    );

    always_ff @(posedge clk)
        unique case (mult)
        'h0: post_mult <= pre_mult >> 1;
        'h1: post_mult <= pre_mult;
        'h2: post_mult <= pre_mult << 1;
        'h3: post_mult <= mult3;
        'h4: post_mult <= pre_mult << 2;
        'h5: post_mult <= mult5;
        'h6: post_mult <= mult6;
        'h7: post_mult <= mult7;
        'h8: post_mult <= pre_mult << 3;
        'h9: post_mult <= mult9;
        'hA: post_mult <= mult10;
        'hB: post_mult <= mult10;
        'hC: post_mult <= mult12;
        'hD: post_mult <= mult12;
        'hE: post_mult <= mult15;
        'hF: post_mult <= mult15;
        endcase

    always_comb
        if (vib)
            phase_inc = post_mult + vib_val;
        else
            phase_inc = post_mult;

    /*
     * Calculate vib_val
     */
    vibrato vibrato (
        .*
    );
endmodule
`default_nettype wire  // re-enable implicit net type declarations