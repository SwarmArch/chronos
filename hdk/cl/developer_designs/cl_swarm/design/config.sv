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

   `include "app_config.vh"

   // most used onfiguration options
   parameter N_TILES = 1;   // Number of tiles
   parameter N_THREADS = 32; 
   parameter LOG_CQ_SLICE_SIZE = 7; // log of Commit Queue size per tile
   parameter LOG_TQ_SIZE = 12;  // Task Queue: Task Array size
   parameter TQ_STAGES = 13;  // Task Queue: min_heap size (has to be >= array size)
   parameter LOG_READY_LIST_SIZE = 4; // Size of the ready list in locale serializer
   parameter CACHE_INDEX_WIDTH = 11; // index bits in cache
   parameter CACHE_NUM_WAYS = 4;     // number of cache ways
   parameter NON_SPEC = 0;  // Non-spec version. 
   
   //If you kno that the TQ will not overflow, set this to save some area.
   parameter NO_SPILLING = 0; 

   // Logging parameters. Used in debugging. The value of each parameter is
   // a bitmask specifying which tiles are being actively logged. 
   // eg: TASK_UNIT_LOGGING = 'hf means first four tiles' task units are being
   // logged.
   parameter TASK_UNIT_LOGGING = 1;
   parameter COMMIT_QUEUE_LOGGING = 1;
   parameter SPLITTER_LOGGING = 1;
   parameter UNDO_LOG_LOGGING = 0;
   parameter SERIALIZER_LOGGING = 1;
   parameter L2_LOGGING = 1;
   parameter CORE_LOGGING = 1; // deprecated
   parameter READ_RW_LOGGING = 1;
   parameter WRITE_RW_LOGGING = 1;
   parameter READ_ONLY_STAGE_LOGGING = 1;
   parameter PCI_LOGGING = 1;

   // Stats parameters. The value of each parameter is a bitmask specifying
   // which tiles' stats are being recorded. 
   parameter CORE_STATE_STATS = 1;
   parameter SERIALIZER_STATS = 1;
   parameter TQ_STATS = 1;
   parameter CQ_STATS = 1;

   
   // Lesser used config options. 
   
   parameter LOG_STAGE_FIFO_SIZE = 5;
   
   // Number of DDR controllers (1, 2 or 4).  If your application is not memory bound,
   // reducing the number of controllers can save area. (Each DDR controllers takes roughly
   // the same area as a tile).
   parameter N_DDR_CTRL = 1;

   // how many tiles go directly into the memory xbar. has to be a power of two
   // Increase this parameter if this xbar becomes the bottleneck.
   parameter XBAR_IN_TILES = 1;

   // Specifies whether to use a simple unordered FIFO as the task queue; 
   // The default settings uses the ordered min_heap. 
   // Set UNORDERED=1 and uncomment the second `define statement to use the FIFO
   // both of the following should be changed together. Unfortunately cannot 
   // `define inside and if block in SV.
   parameter UNORDERED = 0;
   `define TASK_UNIT_MODULE task_unit
   //`define TASK_UNIT_MODULE task_unit_nonspec
   //`define TASK_UNIT_MODULE task_unit_unordered

   
   // Turn off OCL slave unit for all tiles but the first. If there is no need
   // for the host program to communicate with all tiles set this to 0 to save area.
   // The OCL slave takes about ~2000 LUTs.
   parameter ALL_OCL    = 1; 

   parameter LOG_L2_BANKS = 1;  // Number of L2 banks (either 0 or 1)

   // The CQ contains a cache (indexed by locale) of the last dequeued timestamp
   // of each locale. This cache can be used to bypass conflict checks if the
   // currently dequeueing task has timestamp larger than the last dequeued
   // timestamp with the same locale.
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
   parameter LOG_GVT_PERIOD = 5; //32 cycles

   parameter LOG_N_MSHR = 4; // Number of MSHRs in each cache

   // Cache parameters 
   // Total Address Space Size = 16GB = 34 bits 
   parameter ADDR_BITS = 34;
   parameter CACHE_BYTE_WIDTH = 6; // 64 bytes per line
   parameter LOG_LOG_DEPTH = 14; // Size of each on-chip debugging logs
   
   parameter CQ_CONFIG = 1; // Can dynamically configure CQ sizes 

   // Derived parameters.
   // ---------------------------------------------------------------------------------//
   parameter CACHE_TAG_WIDTH = ADDR_BITS - CACHE_BYTE_WIDTH - CACHE_INDEX_WIDTH; //18
                                    
   parameter LOG_CQ_TS_BANKS = LOG_CQ_SLICE_SIZE - LOG_GVT_PERIOD;

   parameter L2_BANKS = (1<<LOG_L2_BANKS);
   parameter L2_PORTS = RISCV ? N_CORES + 3 : 4 ; // rw, ro, splitter, coal (for RV undo_log) 
   

   parameter UNDO_LOG_THREADS = UNORDERED ? 1 : 4;

   parameter UNDO_LOG_ADDR_WIDTH = 32;
   parameter UNDO_LOG_DATA_WIDTH = 32;


   // derived parameters
   parameter C_N_TILES = (2**$clog2(N_TILES));
   parameter LOG_N_TILES = (N_TILES == 1) ? 1 : $clog2(N_TILES);
   parameter TQ_WIDTH = (TS_WIDTH + TASK_TYPE_WIDTH + LOCALE_WIDTH + ARG_WIDTH + 4);
   //parameter TASK_WIDTH = (TS_WIDTH + HINT_WIDTH + ARG_WIDTH);
   parameter CACHE_LOG_WAYS = (CACHE_NUM_WAYS == 1) ? 1 : $clog2(CACHE_NUM_WAYS);
   
   parameter TASK_ENQ_DATA_WIDTH = (TQ_WIDTH + 1 + LOG_TSB_SIZE + LOG_N_TILES);
   parameter TASK_RESP_DATA_WIDTH = (LOG_TSB_SIZE + 1 + EPOCH_WIDTH + LOG_TQ_SIZE);
   parameter ABORT_CHILD_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH + LOG_N_TILES + LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK + 1);
   parameter ABORT_RESP_DATA_WIDTH = (LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK +1);
   parameter CUT_TIES_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH);

   parameter LOG_RW_WIDTH = $clog2(RW_WIDTH)-3;
   parameter N_SUB_TYPES = 2**LOG_N_SUB_TYPES;

  
   `include "spill_config.vh"
   `include "types.vh"
   `include "addr_map.vh"

endpackage

`endif
