/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: envelope_generator.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 30 Oct 2014
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   30 Oct 2014    Greg Taylor
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
`default_nettype none // disable implicit net type declarations

import opl3_pkg::*;

module envelope_generator #(
    parameter SILENCE = 511
)(
    input wire clk,
    input wire sample_clk_en,
    input wire [BANK_NUM_WIDTH-1:0] bank_num,
    input wire [OP_NUM_WIDTH-1:0] op_num,
    input wire [REG_ENV_WIDTH-1:0] ar, // attack rate
    input wire [REG_ENV_WIDTH-1:0] dr, // decay rate
    input wire [REG_ENV_WIDTH-1:0] sl, // sustain level
    input wire [REG_ENV_WIDTH-1:0] rr, // release rate
    input wire [REG_TL_WIDTH-1:0] tl,  // total level
    input wire ksr,                    // key scale rate
    input wire [REG_KSL_WIDTH-1:0] ksl, // key scale level
    input wire egt,                     // envelope type
    input wire am,                      // amplitude modulation (tremolo)
    input wire dam,                     // depth of tremolo
    input wire nts,                     // keyboard split selection
    input wire [REG_FNUM_WIDTH-1:0] fnum,
    input wire [REG_MULT_WIDTH-1:0] mult,
    input wire [REG_BLOCK_WIDTH-1:0] block,
    input wire key_on_pulse,
    input wire key_off_pulse,
    output logic [ENV_WIDTH-1:0] env = SILENCE
);
    localparam KSL_ADD_WIDTH = 8;
    localparam PIPELINE_DELAY = 2;

    typedef enum {
        ATTACK,
        DECAY,
        SUSTAIN,
        RELEASE
    } state_t;

    typedef struct packed {
        state_t state;
        logic [ENV_WIDTH-1:0] env_int;
    } logic_reduction_saved_values_t;

    state_t state = RELEASE;
    state_t next_state;

    wire [KSL_ADD_WIDTH-1:0] ksl_add;
    logic [ENV_WIDTH-1:0] env_int = SILENCE;
    wire [AM_VAL_WIDTH-1:0] am_val;
    logic [REG_ENV_WIDTH-1:0] requested_rate;
    wire [ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] rate_counter_overflow;
    logic signed [ENV_WIDTH+1:0] env_tmp; // two more bits wide than env for >, < comparison
    logic [PIPELINE_DELAY-1:0] sample_clk_en_delayed = 0;
    logic bank_num_r0 = 0;
    logic op_num_r0 = 0;
    logic_reduction_saved_values_t in_values;
    logic_reduction_saved_values_t out_values;
    logic load_store_ram_values;

    always_ff @(posedge clk) begin
        bank_num_r0 <= bank_num;
        op_num_r0 <= op_num;
    end

    always_comb load_store_ram_values = op_num_r0 != op_num;

    always_comb begin
        in_values.state = state;
        in_values.env_int = env_int;
    end

    mem_simple_dual_port_distributed #(
        .DATA_WIDTH($bits(logic_reduction_saved_values_t)),
        .DEPTH(NUM_BANKS*NUM_OPERATORS_PER_BANK),
        .OUTPUT_DELAY(0)
    ) logic_reduction_ram (
        .clka(clk),
        .clkb(clk),
        .wea(load_store_ram_values),
        .reb('1),
        .addra({bank_num_r0, op_num_r0}),
        .addrb({bank_num, op_num}),
        .dia(in_values),
        .dob(out_values)
    );

    ksl_add_rom ksl_add_rom (
        .*
    );

    always_ff @(posedge clk)
        if (load_store_ram_values)
            state <= out_values.state;
        else if (key_on_pulse)
            state <= ATTACK;
        else if (key_off_pulse)
            state <= RELEASE;
        else if (sample_clk_en)
            state <= next_state;

    always_comb
        unique case (state)
        ATTACK: next_state = env_int == 0 ? DECAY : ATTACK;
        DECAY: next_state = (env_int >> 4) >= sl ? SUSTAIN : DECAY;
        SUSTAIN: next_state = !egt ? RELEASE : SUSTAIN;
        RELEASE: next_state = RELEASE;
        endcase

    always_comb
        unique case (state)
        ATTACK: requested_rate = ar;
        DECAY: requested_rate = dr;
        SUSTAIN: requested_rate = 0;
        RELEASE: requested_rate = rr;
        endcase

    /*
     * Calculate rate_counter_overflow
     */
    env_rate_counter env_rate_counter (
        .*
    );

    always_ff @(posedge clk) begin
        sample_clk_en_delayed <= sample_clk_en_delayed << 1;
        sample_clk_en_delayed[0] <= sample_clk_en;
    end

    always_ff @(posedge clk)
        if (load_store_ram_values)
            env_int <= out_values.env_int;
        else if (sample_clk_en_delayed[PIPELINE_DELAY-1])
            if (state == ATTACK && rate_counter_overflow != 0 && env_int != 0)
                env_int <= env_int - (((env_int*rate_counter_overflow) >> 3) + 1);
            else if (state == DECAY || state == RELEASE)
                if (env_int + rate_counter_overflow > SILENCE)
                    // env_int would overflow
                    env_int <= SILENCE;
                else
                    env_int <= env_int + rate_counter_overflow;

    /*
     * Calculate am_val
     */
    tremolo tremolo (
        .*
    );

    always_comb
        if (am)
            env_tmp = env_int + (tl << 2) + ksl_add + am_val;
        else
            env_tmp = env_int + (tl << 2) + ksl_add;

    always_ff @(posedge clk)
        if (env_tmp < 0)
            env <= 0;
        else if (env_tmp > SILENCE)
            env <= SILENCE;
        else
            env <= env_tmp;

endmodule
`default_nettype wire  // re-enable implicit net type declarations
