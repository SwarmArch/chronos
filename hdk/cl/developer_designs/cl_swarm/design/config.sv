// Amazon FPGA Hardware Development Kit
//
// Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.

`ifndef SWARM_CONFIG
`define SWARM_CONFIG

`ifdef XILINX_SIMULATOR
   `define SIMPLE_MEMORY
   `define FAST_MEM_INIT
   `define FAST_VERIFY
`endif 

package swarm; 

   parameter VERSION = 10; // increment on every change to the addr_map.

   `include "apps/sssp/config.vh"
   parameter N_TILES = 1;

   parameter TASK_UNIT_LOGGING = 0;
   parameter COMMIT_QUEUE_LOGGING = 0;
   parameter SPLITTER_LOGGING = 0;
   parameter UNDO_LOG_LOGGING = 0;
   parameter SERIALIZER_LOGGING = 0;
   parameter L2_LOGGING = 0;
   parameter CORE_LOGGING = 0;
   parameter PCI_LOGGING = 1;
   parameter CORE_STATE_STATS = 1;
   parameter SERIALIZER_STATS = 1;
   parameter TQ_STATS = 1;
   parameter CQ_STATS = 1;
   parameter CQ_CONFIG = 1;

   // how many tiles go directly into the axi xbar. has to be a power of two
   parameter XBAR_IN_TILES = 1;

   parameter NO_SPILLING = 1; 
   parameter NON_SPEC = 1;

   // both of the following should be changed together. Unfortunately cannot 
   // `define inside and if block in SV.
   parameter UNORDERED = 0;
   //`define TASK_UNIT_MODULE task_unit_unordered
   `define TASK_UNIT_MODULE task_unit

   parameter N_DDR_CTRL = 2;
   
   // has to be set for des
   parameter ALL_OCL    = 1; 

   parameter LOG_CQ_SLICE_SIZE = 7;
   parameter LOG_TQ_SIZE = 12;
   parameter TQ_STAGES = 13; 
   parameter LOG_READY_LIST_SIZE = 4;
   parameter LOG_L2_BANKS = 0;

   parameter LOG_LAST_DEQ_VT_CACHE = 9; // must be >=4, 0 to turn off

   parameter TS_WIDTH = UNORDERED ? 1 : 32;
   parameter LOCALE_WIDTH = 32;
   // ARG_WIDTH is app dependent
   parameter N_TASK_TYPES = 16;
   parameter TASK_TYPE_WIDTH = $clog2(N_TASK_TYPES);
   
   parameter EPOCH_WIDTH = 8;
   parameter LOG_TSB_SIZE = 4;
   parameter LOG_CHILDREN_PER_TASK = 3;
   parameter LOG_UNDO_LOG_ENTRIES_PER_TASK = 3;

   parameter TB_WIDTH = 32; // tiebreaker width;
   parameter LOG_GVT_PERIOD = 5; // 16 cycles
   parameter LOG_CQ_TS_BANKS = LOG_CQ_SLICE_SIZE - LOG_GVT_PERIOD;


   // Cache parameters 
   // Total Address Space Size = 16GB = 34 bits 
   parameter ADDR_BITS = 34;
   parameter CACHE_BYTE_WIDTH = 6; // 64 bytes per line
   parameter CACHE_INDEX_WIDTH = 11; // 1K lines
   parameter CACHE_NUM_WAYS = 4; 
   parameter CACHE_TAG_WIDTH = ADDR_BITS - CACHE_BYTE_WIDTH - CACHE_INDEX_WIDTH; //18
                                    
   parameter LOG_N_MSHR = 4;

   parameter L2_BANKS = (1<<LOG_L2_BANKS);
   parameter L2_PORTS = RO_STAGES + 2;
   
   // 'Core' is any module that gets tasks from CC. OCL is a special case 
   // APP_COREs have IDs {1..N_APP_CORES}
   parameter N_THREADS = 4; 

   parameter UNDO_LOG_THREADS = UNORDERED ? 1 : 4;

   parameter UNDO_LOG_ADDR_WIDTH = 32;
   parameter UNDO_LOG_DATA_WIDTH = 32;


   // derived parameters
   parameter C_N_TILES = (2**$clog2(N_TILES));
   parameter LOG_N_TILES = (N_TILES == 1) ? 1 : $clog2(N_TILES);
   parameter TQ_WIDTH = (TS_WIDTH + TASK_TYPE_WIDTH + LOCALE_WIDTH + ARG_WIDTH + 3);
   //parameter TASK_WIDTH = (TS_WIDTH + HINT_WIDTH + ARG_WIDTH);
   parameter CACHE_LOG_WAYS = (CACHE_NUM_WAYS == 1) ? 1 : $clog2(CACHE_NUM_WAYS);
   
   parameter TASK_ENQ_DATA_WIDTH = (TQ_WIDTH + 1 + LOG_TSB_SIZE + LOG_N_TILES);
   parameter TASK_RESP_DATA_WIDTH = (LOG_TSB_SIZE + 1 + EPOCH_WIDTH + LOG_TQ_SIZE);
   parameter ABORT_CHILD_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH + LOG_N_TILES + LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK + 1);
   parameter ABORT_RESP_DATA_WIDTH = (LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK +1);
   parameter CUT_TIES_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH);

  
   `include "spill_config.vh"
   `include "types.vh"
   `include "addr_map.vh"
endpackage

`endif
