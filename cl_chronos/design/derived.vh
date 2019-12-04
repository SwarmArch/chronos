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


   // Derived parameters.
   // ---------------------------------------------------------------------------------//
   parameter CACHE_TAG_WIDTH = ADDR_BITS - CACHE_BYTE_WIDTH - CACHE_INDEX_WIDTH; //18
                                    
   parameter LOG_CQ_TS_BANKS = LOG_CQ_SLICE_SIZE - LOG_GVT_PERIOD;

   parameter L2_BANKS = (1<<LOG_L2_BANKS);
   `ifdef USE_PIPELINED_TEMPLATE 
      parameter L2_PORTS = 4; // rw, ro, splitter, coal
   `else 
      parameter L2_PORTS = N_CORES + 3; // splitter, coal, undo_log
   `endif
   

   parameter UNDO_LOG_THREADS = UNORDERED ? 1 : 4;

   parameter UNDO_LOG_ADDR_WIDTH = 32;
   parameter UNDO_LOG_DATA_WIDTH = 32;


   // derived parameters
   parameter C_N_TILES = (2**$clog2(N_TILES));
   parameter LOG_N_TILES = (N_TILES == 1) ? 1 : $clog2(N_TILES);
   parameter TQ_WIDTH = (TS_WIDTH + TASK_TYPE_WIDTH + OBJECT_WIDTH + ARG_WIDTH + 4);
   // TQ_WIDTH cannot be larger than cache line. TODO:Add assert
   
   parameter CACHE_LOG_WAYS = (CACHE_NUM_WAYS == 1) ? 1 : $clog2(CACHE_NUM_WAYS);
   
   parameter TASK_ENQ_DATA_WIDTH = (TQ_WIDTH + 1 + LOG_TSB_SIZE + LOG_N_TILES);
   parameter TASK_RESP_DATA_WIDTH = (LOG_TSB_SIZE + 1 + EPOCH_WIDTH + LOG_TQ_SIZE);
   parameter ABORT_CHILD_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH + LOG_N_TILES + LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK + 1);
   parameter ABORT_RESP_DATA_WIDTH = (LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK +1);
   parameter CUT_TIES_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH);


`ifndef USE_PIPELINED_TEMPLATE
   // dummy values to prevent compiler errors
   parameter RW_WIDTH = 32;
   parameter LOG_N_SUB_TYPES = 1;
   parameter DATA_WIDTH = 32;
   parameter RW_BASE_ADDR = 0;

   `define RW_WORKER sssp_rw
   `define RO_WORKER sssp_ro
`endif

   parameter LOG_RW_WIDTH = $clog2(RW_WIDTH)-3;
   parameter N_SUB_TYPES = 2**LOG_N_SUB_TYPES;
