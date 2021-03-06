/** $lic$
 * Copyright (C) 2014-2019 by Massachusetts Institute of Technology
 *
 * This file is part of the Chronos FPGA Acceleration Framework.
 *
 * Chronos is free software; you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, version 2.
 *
 * If you use this framework in your research, we request that you reference
 * the Chronos paper ("Chronos: Efficient Speculative Parallelism for
 * Accelerators", Abeydeera and Sanchez, ASPLOS-25, March 2020), and that
 * you send us a citation of your work.
 *
 * Chronos is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */

WARNING ASTAR NON-PIPELINED VERSION IS NOT SUPPORTED
WARNING HENCE, DEFAULTING TO PIPELINED VERSION

`define USE_PIPELINED_TEMPLATE

parameter APP_NAME = "astar";
parameter APP_ID = 2;
parameter RISCV = 0;

parameter ARG_WIDTH = 64;

parameter RW_WIDTH = 32;
parameter DATA_WIDTH = 64;


parameter LOG_N_SUB_TYPES = 2;

parameter RW_BASE_ADDR = 20;
parameter OFFSET_BASE_ADDR = 12;
parameter NEIGHBOR_BASE_ADDR = 16;

`define RO_WORKER astar_ro
`define RW_WORKER astar_rw

parameter N_CORES = 0;


