/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: phase_generator.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 13 Oct 2014
#
#   DESCRIPTION:
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
`default_nettype none // disable implicit net type declarations

import opl3_pkg::*;

module phase_generator (
    input wire clk,
    input wire sample_clk_en,
    input wire is_new,
    input wire [BANK_NUM_WIDTH-1:0] bank_num,
    input wire [OP_NUM_WIDTH-1:0] op_num,
    input wire [PHASE_ACC_WIDTH-1:0] phase_inc,
    input wire [REG_WS_WIDTH-1:0] ws,
    input wire [ENV_WIDTH-1:0] env,
    input wire key_on_pulse,
    input wire [OP_OUT_WIDTH-1:0] modulation,
    input operator_t op_type,
    output logic signed [OP_OUT_WIDTH-1:0] out = 0
);
    localparam LOG_SIN_OUT_WIDTH = 12;
    localparam EXP_IN_WIDTH = 8;
    localparam EXP_OUT_WIDTH = 10;
    localparam LOG_SIN_PLUS_GAIN_WIDTH = 13;
    localparam PIPELINE_DELAY = 2;

    typedef struct packed {
        logic [PHASE_ACC_WIDTH-1:0] phase_acc;
        logic [PHASE_ACC_WIDTH-1:0] final_phase;
    } logic_reduction_saved_values_t;

    logic [PIPELINE_DELAY-1:0] sample_clk_en_delayed = 0;
    logic [PHASE_ACC_WIDTH-1:0] phase_acc = 0;
    logic [PHASE_ACC_WIDTH-1:0] final_phase = 0;
    logic [PHASE_ACC_WIDTH-1:0] rhythm_phase;

    logic is_odd_period [NUM_BANKS][NUM_OPERATORS_PER_BANK] = '{ default: '0 };
    logic phase_acc_msb_pos_edge_pulse [NUM_BANKS][NUM_OPERATORS_PER_BANK];
    wire [LOG_SIN_OUT_WIDTH-1:0] log_sin_out;
    logic [LOG_SIN_PLUS_GAIN_WIDTH-1:0] log_sin_plus_gain = 0;
    wire [EXP_OUT_WIDTH-1:0] exp_out;
    logic [OP_OUT_WIDTH-1:0] tmp_out0;
    logic signed [OP_OUT_WIDTH-1:0] tmp_out1;
    logic signed [OP_OUT_WIDTH-1:0] tmp_out2;
    logic signed [OP_OUT_WIDTH-1:0] tmp_ws2;
    logic signed [OP_OUT_WIDTH-1:0] tmp_ws4;
    logic [LOG_SIN_OUT_WIDTH-1:0] tmp_ws7;
    logic [REG_WS_WIDTH-1:0] ws_post_opl;
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
        in_values.phase_acc = phase_acc;
        in_values.final_phase = final_phase;
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

    /*
     * OPL2 only supports first 4 waveforms
     */
    always_comb ws_post_opl = ws & (is_new ? 'h7 : 'h3);

    /*
     * sample_clk_en must be delayed so the phase_inc is correct when it is added
     * to the phase accumulator (inputs must settle for this time slot)
     */
    always_ff @(posedge clk) begin
        sample_clk_en_delayed <= sample_clk_en_delayed << 1;
        sample_clk_en_delayed[0] <= sample_clk_en;
    end

    /*
     * Some rhythm instruments require further transformations to the phase.
     * Pass through phase_acc normally.
     */
    calc_rhythm_phase calc_rhythm_phase (
        .*
    );

    /*
     * Phase Accumulator. Modulation gets added to the final phase but not
     * back into the accumulator.
     */
    always_ff @(posedge clk)
        if (load_store_ram_values) begin
            phase_acc <= out_values.phase_acc;
            final_phase <= out_values.final_phase;
        end
        else if (sample_clk_en_delayed[PIPELINE_DELAY-1])
            if (key_on_pulse) begin
                phase_acc <= 0;
                final_phase <= 0;
            end
            else if (ws_post_opl == 4 || ws_post_opl == 5) begin
                // double the frequency
                phase_acc <= phase_acc + (phase_inc << 1);
                final_phase <= rhythm_phase + (phase_inc << 1)
                 + (modulation << 10);
            end
            else begin
                phase_acc <= phase_acc + phase_inc;
                final_phase <= rhythm_phase + phase_inc
                 + (modulation << 10);
            end

    always_comb tmp_ws2 = tmp_out1 < 0 ? ~tmp_out1 : tmp_out1;
    always_comb tmp_ws4 = is_odd_period[bank_num][op_num] ? tmp_out1 : 0;

    genvar i, j;
    generate
    for (i = 0; i < NUM_BANKS; i ++)
        for (j = 0; j < NUM_OPERATORS_PER_BANK; j++) begin
            edge_detector #(
                .EDGE_LEVEL(0),
                .CLK_DLY(0)
            ) phase_acc_msb_edge_detect (
                .clk,
                .clk_en(1'b1),
                .in(final_phase[19]),
                .edge_detected(phase_acc_msb_pos_edge_pulse[i][j])
            );

        always_ff @(posedge clk)
            if (phase_acc_msb_pos_edge_pulse[i][j])
                is_odd_period[i][j] <= !is_odd_period[i][j];
    end
    endgenerate

    opl3_log_sine_lut log_sine_lut_inst (
        .theta(final_phase[18] ? ~final_phase[17:10]
         : final_phase[17:10]),
        .out(log_sin_out),
    	.*
    );

    /*
     * Setting the msb effectively mutes. Mute 2nd and 3rd quadrant.
     */
    always_comb
        unique case (final_phase[19:18])
        0: tmp_ws7[11] = 0;
        1: tmp_ws7[11] = 1;
        2: tmp_ws7[11] = 1;
        3: tmp_ws7[11] = 0;
        endcase

    always_comb tmp_ws7[10:0] = final_phase[19] ?
     ~final_phase[17:10] << 3 : final_phase[17:10] << 3;

    always_comb log_sin_plus_gain = (ws_post_opl == 7 ? tmp_ws7 : log_sin_out) + (env << 3);

    opl3_exp_lut exp_lut_inst (
        .in(~log_sin_plus_gain[7:0]),
        .out(exp_out),
        .*
    );

    always_comb tmp_out0 = (2**10 + exp_out) << 1;

    always_comb
        if (final_phase[19])
            tmp_out1 = ~(tmp_out0 >> log_sin_plus_gain[LOG_SIN_PLUS_GAIN_WIDTH-1:8]);
        else
            tmp_out1 = tmp_out0 >> log_sin_plus_gain[LOG_SIN_PLUS_GAIN_WIDTH-1:8];

    /*
     * Select waveform, do proper transformations to the wave
     */
    always_comb
        unique case (ws_post_opl)
        0: tmp_out2 = tmp_out1;
        1: tmp_out2 = tmp_out1 < 0 ? 0 : tmp_out1;
        2: tmp_out2 = tmp_ws2;
        3: tmp_out2 = final_phase[PHASE_ACC_WIDTH-2] ? 0 : tmp_ws2;
        4: tmp_out2 = tmp_ws4;
        5: tmp_out2 = tmp_ws4 < 0 ? ~tmp_ws4 : tmp_ws4;
        6: tmp_out2 = tmp_out1 > 0 ? 2**(OP_OUT_WIDTH-1) - 1 : -2**(OP_OUT_WIDTH-1);
        7: tmp_out2 = tmp_out1;
        endcase

    always_ff @(posedge clk)
        unique case (op_type)
        OP_NORMAL:    out <= tmp_out2;
        OP_BASS_DRUM: out <= tmp_out2;
        default:      out <= tmp_out2 << 1;
        endcase
endmodule
`default_nettype wire  // re-enable implicit net type declarations

