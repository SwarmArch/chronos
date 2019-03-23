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

   `include "config_app.vh"
   parameter N_TILES = 1;

   parameter TASK_UNIT_LOGGING = 0;
   parameter COMMIT_QUEUE_LOGGING = 0;
   parameter SPLITTER_LOGGING = 0;
   parameter UNDO_LOG_LOGGING = 0;
   parameter SERIALIZER_LOGGING = 0;
   parameter L2_LOGGING = 0;
   parameter CORE_LOGGING = 0;
   parameter CORE_STATE_STATS = 0;
   parameter SERIALIZER_STATS = 1;
   parameter TQ_STATS = 1;
   parameter CQ_STATS = 1;
   parameter CQ_CONFIG = 1;

   // how many tiles go directly into the axi xbar. has to be a power of two
   parameter XBAR_IN_TILES = 1;

   parameter NO_SPILLING = 0; 
   parameter NON_SPEC = 0;

   // both of the following should be changed together. Unfortunately cannot 
   // `define inside and if block in SV.
   parameter UNORDERED = 0;
   //`define TASK_UNIT_MODULE task_unit_unordered
   `define TASK_UNIT_MODULE task_unit

   parameter N_DDR_CTRL = 1;
   
   // has to be set for des
   parameter ALL_OCL    = 0; 

   parameter LOG_CQ_SLICE_SIZE = 7;
   parameter LOG_TQ_SIZE = 12;
   parameter TQ_STAGES = 13; 
   parameter LOG_READY_LIST_SIZE = 3;
   parameter LOG_L2_BANKS = 0;

   parameter LOG_LAST_DEQ_VT_CACHE = 9; // must be >=4, 0 to turn off

   parameter TS_WIDTH = UNORDERED ? 1 : 32;
   parameter HINT_WIDTH = 32;
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


   
   // Total Address Space Size = 16GB = 34 bits 
   parameter ADDR_BITS = 34;
   parameter CACHE_BYTE_WIDTH = 6; // 64 bytes per line
   parameter CACHE_INDEX_WIDTH = 11; // 1K lines
   parameter CACHE_NUM_WAYS = 4; 
   parameter CACHE_TAG_WIDTH = ADDR_BITS - CACHE_BYTE_WIDTH - CACHE_INDEX_WIDTH; //18
                                    
   parameter LOG_N_MSHR = 4;

   parameter L2_BANKS = (1<<LOG_L2_BANKS);
   parameter C_N_TILES = (2**$clog2(N_TILES));
   
   // 'Core' is any module that gets tasks from CC. OCL is a special case 
   // APP_COREs have IDs {1..N_APP_CORES}
   parameter N_CORES = N_APP_CORES + 1; 
   parameter N_THREADS = N_APP_THREADS + 1; 

   parameter UNDO_LOG_THREADS = UNORDERED ? 1 : 4;
   
   parameter ID_SPLITTER = N_CORES;
   parameter ID_COAL = N_CORES + 1;
   parameter N_L1 = ID_COAL + 1; // +1 for OCL
   // end all modules with an L1 
   parameter ID_UNDO_LOG = N_CORES + 2;
   parameter ID_TASK_UNIT = N_CORES + 3; 
   parameter L2_PORTS = ID_UNDO_LOG + 1;
   parameter CM_PORTS = ID_SPLITTER + 1;
   // end all modules with an L2 port
   parameter ID_L2 = N_CORES + 4;
   parameter ID_L2_LAST = ID_L2 + (1<<LOG_L2_BANKS -1);
   parameter ID_MEM_ARB = ID_L2_LAST + 1;
   parameter ID_PCI_ARB = ID_L2_LAST + 2;
   parameter ID_TSB     = ID_L2_LAST + 3;
   parameter ID_CQ      = ID_L2_LAST + 4;
   parameter ID_CM      = ID_L2_LAST + 5;
   parameter ID_SERIALIZER    = ID_L2_LAST + 6;
   parameter ID_LAST = ID_L2_LAST + 7;
   
   parameter ID_ALL_CORES = 32;
   parameter ID_ALL_APP_CORES = 33;
   parameter ID_COAL_AND_SPLITTER = 34;

   parameter ID_TASK_XBAR = 48;

   parameter TASK_TYPE_TERMINATE = 12;
   // if a core has task_araddr = TASK_TYPE_ALL, it can accept any ttype less
   // than TASK_TYPE_ALL
   parameter TASK_TYPE_ALL = 13;
   parameter TASK_TYPE_SPLITTER = 14;
   parameter TASK_TYPE_UNDO_LOG_RESTORE = 15;

   typedef struct packed {
      logic [CACHE_TAG_WIDTH-1:0] tag;
      logic [CACHE_INDEX_WIDTH-1:0] index;
      logic [CACHE_BYTE_WIDTH-1:0] word; // use 'word' because 'byte' is reserved
   }  mem_addr_t;
   typedef struct packed {
      logic [TS_WIDTH-1:0] ts;
      logic [TB_WIDTH-1:0] tb;
   }  vt_t;
   typedef logic [TS_WIDTH+TB_WIDTH-1:0] vt_unpacked_t;

   parameter UNDO_LOG_ADDR_WIDTH = 32;
   parameter UNDO_LOG_DATA_WIDTH = 32;

   typedef logic [UNDO_LOG_ADDR_WIDTH-1:0] undo_log_addr_t;
   typedef logic [UNDO_LOG_DATA_WIDTH-1:0] undo_log_data_t;

   // derived parameters
   parameter LOG_N_TILES = (N_TILES == 1) ? 1 : $clog2(N_TILES);
   parameter TQ_WIDTH = (TS_WIDTH + TASK_TYPE_WIDTH + HINT_WIDTH + ARG_WIDTH);
   //parameter TASK_WIDTH = (TS_WIDTH + HINT_WIDTH + ARG_WIDTH);
   parameter CACHE_LOG_WAYS = (CACHE_NUM_WAYS == 1) ? 1 : $clog2(CACHE_NUM_WAYS);
   
   parameter TASK_ENQ_DATA_WIDTH = (TASK_TYPE_WIDTH + TS_WIDTH + HINT_WIDTH + ARG_WIDTH+ 1 + LOG_TSB_SIZE + LOG_N_TILES);
   parameter TASK_RESP_DATA_WIDTH = (LOG_TSB_SIZE + 1 + EPOCH_WIDTH + LOG_TQ_SIZE);
   parameter ABORT_CHILD_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH + LOG_N_TILES + LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK + 1);
   parameter ABORT_RESP_DATA_WIDTH = (LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK +1);
   parameter CUT_TIES_DATA_WIDTH = (LOG_TQ_SIZE + EPOCH_WIDTH);

   // Task Spilling parameters
   parameter LOG_TQ_SPILL_SIZE = 8;
   // Spilled tasks are organized into two hierachical levels. 8 Tasks go into
   // 1 splitter and 16 splitters go into one chunk. (Configurable below)
   // TODO: (find a better term than splitter; this is used for both the task type and
   // the 8 task set)

   // These four parameters are fixed at design time. Base addresses are
   // software configurable
   // Splitters are allocated in terms of chunks. A LIFO stack of free chunks is
   // maintained in memory by coalescer and splitter cores collaboratively. The
   // coalescer would pop one entry and store the 16 subsequent splitters 
   // into the space allocated for this chunk. When the splitter (core) finishes the 
   // last splitter (task) of a chunk, it is added to back on the stack.
   // The splitter core will not receive all splitter tasks of the same chunks
   // contiguously, hence it maintains a scratchpad of bit vectors to maintain
   // which tasks of which chunks are free.  
   parameter TASKS_PER_SPLITTER = 8;  
   parameter SPLITTERS_PER_CHUNK = 16;
`ifdef XILINX_SIMULATOR
   parameter LOG_SPLITTER_STACK_SIZE = 9; // max(16) - limited by stack entry width
`else
   parameter LOG_SPLITTER_STACK_SIZE = 12; // max(16) - limited by stack entry width
`endif
   parameter LOG_SPLITTER_STACK_ENTRY_WIDTH = 4; // 16-bit index
  
   // Dervied:
   parameter LOG_SPLITTERS_PER_CHUNK = $clog2(SPLITTERS_PER_CHUNK); // 16-bit splitters
   parameter LOG_SPLITTER_CHUNK_WIDTH = $clog2(TQ_WIDTH) -3 + $clog2(TASKS_PER_SPLITTER);
   parameter LOG_SPLITTER_ENTRIES = (LOG_SPLITTER_STACK_SIZE + LOG_SPLITTERS_PER_CHUNK);

   // Memory requirement for each structure
   parameter LOG_PER_TILE_SPILL_SCRATCHPAD_SIZE_BYTES = (LOG_SPLITTER_ENTRIES - 3); // 8K
   parameter LOG_PER_TILE_SPILL_STACK_SIZE_BYTES = 
      LOG_SPLITTER_STACK_SIZE + LOG_SPLITTER_STACK_ENTRY_WIDTH - 3;  // 8K
   parameter LOG_PER_TILE_SPILL_TASK_SIZE_BYTES = 
      LOG_SPLITTER_ENTRIES + LOG_SPLITTER_CHUNK_WIDTH; // 8M
   // Tasks + Stack + Scratchpad + stack_ptr (8M + 8K + 8K + 64B) 

   parameter STACK_PTR_ADDR_OFFSET = 0;
   parameter STACK_BASE_OFFSET = 64;
   parameter SCRATCHPAD_BASE_OFFSET = STACK_BASE_OFFSET + (1<<(LOG_PER_TILE_SPILL_STACK_SIZE_BYTES));
   parameter SCRATCHPAD_END_OFFSET = SCRATCHPAD_BASE_OFFSET + 
         (1<<(LOG_PER_TILE_SPILL_SCRATCHPAD_SIZE_BYTES));
   parameter SPILL_TASK_BASE_OFFSET = 1<<(LOG_PER_TILE_SPILL_TASK_SIZE_BYTES); 
   
   parameter TOTAL_SPILL_ALLOCATION = SPILL_TASK_BASE_OFFSET * 2;

   parameter LOG_LOG_DEPTH = 14; // Logarithm of Log depth
   
   typedef logic [TASK_TYPE_WIDTH-1:0] task_type_t;
   typedef logic [TS_WIDTH-1:0] ts_t;
   typedef logic [HINT_WIDTH-1:0] hint_t;
   typedef logic [ARG_WIDTH-1:0] args_t;

   typedef logic [$clog2(CACHE_NUM_WAYS)-1:0] lru_width_t;

   typedef logic [31:0] reg_data_t;
   
   typedef logic [TB_WIDTH-1:0] tb_t;

   // Gloabl type definitions
   typedef struct packed {
      logic [TASK_TYPE_WIDTH-1:0] ttype;
      logic [TS_WIDTH-1:0] ts;
      logic [HINT_WIDTH-1:0] hint;
      logic [ARG_WIDTH-1:0] args;
   } task_t;

   typedef enum logic[2:0] {NOP, ENQ, DEQ_MIN, REPLACE ,DEQ_MAX } heap_op_t;
   
   typedef logic [511:0] cache_line_t;
   
   typedef logic [15:0] axi_id_t;
   typedef logic [63:0] axi_addr_t;
   typedef logic [63:0] axi_strb_t;
   typedef logic [7:0]  axi_len_t;
   typedef logic [2:0] axi_size_t;
   typedef logic [1:0] axi_resp_t;
   typedef logic [511:0] axi_data_t;



   typedef logic [LOG_N_TILES-1:0] tile_id_t;
   typedef logic [LOG_TSB_SIZE-1:0] tsb_entry_id_t;
   typedef logic [LOG_CHILDREN_PER_TASK:0] child_id_t; 
   typedef logic [LOG_UNDO_LOG_ENTRIES_PER_TASK-1:0] undo_id_t; 

   typedef logic [LOG_TQ_SIZE-1:0] tq_slot_t;
   typedef logic [LOG_CQ_SLICE_SIZE-1:0] cq_slice_slot_t;
   typedef logic [4:0] core_id_t;
   typedef logic [EPOCH_WIDTH-1:0] epoch_t;
   
   // Default values for configurable parameters
   parameter SPILL_THRESHOLD = (2**LOG_TQ_SIZE) - 5; // Start coalescing when TQ size is this
   parameter DEQUE_FIFO_FULL_THRESHOLD = 4;
   
   // CL Register Addresses OCL is only 32 MiB (25 bit)
   // [23:16] is tile, [15:8] component, [7:0] addr 

   // OCL_SLAVE address
   parameter OCL_TASK_ENQ_ARGS        = 8'h1c; // set the args of the task to be enqueued next
   parameter OCL_TASK_ENQ_HINT        = 8'h14; // set the hint of the task to be enqueued next
   parameter OCL_TASK_ENQ_TTYPE       = 8'h18; // set the ttype of the task to be enqueued next
   parameter OCL_TASK_ENQ             = 8'h10; // Enq task with ts (wdata)
   parameter OCL_ACCESS_MEM_SET_MSB   = 8'h24; // set bits [63:32] of mem addr
   parameter OCL_ACCESS_MEM_SET_LSB   = 8'h28; // set bits [31: 0] of mem addr
   parameter OCL_ACCESS_MEM           = 8'h20;  
   parameter OCL_TASK_ENQ_ARG_WORD    = 8'h2c;
   parameter OCL_CUR_CYCLE_MSB        = 8'h30;
   parameter OCL_CUR_CYCLE_LSB        = 8'h34;
   parameter OCL_LAST_MEM_LATENCY     = 8'h38;
   parameter OCL_DONE                 = 8'h40;

   parameter OCL_PARAM_N_TILES             = 8'h50;
   parameter OCL_PARAM_LOG_TQ_HEAP_STAGES  = 8'h54;
   parameter OCL_PARAM_LOG_TQ_SIZE         = 8'h58;
   parameter OCL_PARAM_LOG_CQ_SIZE         = 8'h5c;
   parameter OCL_PARAM_N_APP_CORES         = 8'h60;
   parameter OCL_PARAM_LOG_SPILL_Q_SIZE    = 8'h64;
   parameter OCL_PARAM_NON_SPEC            = 8'h68;
   parameter OCL_PARAM_LOG_READY_LIST_SIZE = 8'h6c;
   parameter OCL_PARAM_LOG_L2_BANKS        = 8'h70;

   parameter CORE_START               = 8'ha0; //  wdata - bitmap of which cores are activated 
   parameter CORE_N_DEQUEUES          = 8'hb0;
   parameter CORE_NUM_ENQ             = 8'hc0;
   parameter CORE_NUM_DEQ             = 8'hc4;
   parameter CORE_STATE               = 8'hc8;
   parameter CORE_PC                  = 8'hcc;
   parameter CORE_DEBUG_MODE          = 8'hb4;

   parameter CORE_SET_QUERY_STATE     = 8'h10;
   parameter CORE_QUERY_STATE_STAT    = 8'h14; 
   parameter CORE_QUERY_AP_STATE_STAT = 8'h18; 
   
   //Since these are cache line aligned, send excluding the LSB 6 bits
   parameter CORE_BASE_EDGE_OFFSET    = 8'h20;
   parameter CORE_BASE_DIST           = 8'h24;
   parameter CORE_BASE_NEIGHBORS      = 8'h28;
   parameter CORE_HINT                = 8'h30;
   parameter CORE_TS                  = 8'h34;
   parameter CORE_STATE_STATS_BEGIN   = 8'b01xx_xxxx;

   parameter DES_SPARSE_OUTPUT       = 8'h80;

   parameter SPILL_BASE_TASKS        = 8'h60;
   parameter SPILL_BASE_STACK        = 8'h64;
   parameter SPILL_BASE_SCRATCHPAD   = 8'h68;
   parameter SPILL_ADDR_STACK_PTR    = 8'h6c;

   parameter TASK_UNIT_HEAP_CAPACITY   = 8'h10;
   parameter TASK_UNIT_N_TASKS         = 8'h14;
   parameter TASK_UNIT_N_TIED_TASKS    = 8'h18;
   parameter TASK_UNIT_STALL           = 8'h20;
   parameter TASK_UNIT_START           = 8'h24;
   parameter TASK_UNIT_SPILL_THRESHOLD = 8'h30;
   parameter TASK_UNIT_CLEAN_THRESHOLD = 8'h34;
   parameter TASK_UNIT_SPILL_SIZE      = 8'h38;
   parameter TASK_UNIT_THROTTLE_MARGIN = 8'h3c;
   parameter TASK_UNIT_TIED_CAPACITY   = 8'h40;
   parameter TASK_UNIT_LVT             = 8'h44;
   
   parameter TASK_UNIT_STAT_AVG_TASKS              = 8'h48; // << 16
   parameter TASK_UNIT_STAT_AVG_HEAP_UTIL          = 8'h4c; // << 16
   
   parameter TASK_UNIT_IS_TRANSACTIONAL           = 8'h50;
   // if start_mask == 0, increment tx id by start_inc
   parameter TASK_UNIT_GLOBAL_RELABEL_START_MASK = 8'h54;
   parameter TASK_UNIT_GLOBAL_RELABEL_START_INC  = 8'h58;
   parameter TX_ID_OFFSET_BITS = 8;

   parameter TASK_UNIT_STAT_N_UNTIED_ENQ           = 8'h60;
   parameter TASK_UNIT_STAT_N_TIED_ENQ_ACK         = 8'h64;
   parameter TASK_UNIT_STAT_N_TIED_ENQ_NACK        = 8'h68;
   parameter TASK_UNIT_STAT_N_DEQ_TASK             = 8'h70;
   parameter TASK_UNIT_STAT_N_SPLITTER_DEQ         = 8'h74;
   parameter TASK_UNIT_STAT_N_DEQ_MISMATCH         = 8'h78;
   parameter TASK_UNIT_STAT_N_CUT_TIES_MATCH       = 8'h80;
   parameter TASK_UNIT_STAT_N_CUT_TIES_MISMATCH    = 8'h84;
   parameter TASK_UNIT_STAT_N_CUT_TIES_COM_ABO     = 8'h88;
   parameter TASK_UNIT_STAT_N_COMMIT_TIED          = 8'h90;
   parameter TASK_UNIT_STAT_N_COMMIT_UNTIED        = 8'h94;
   parameter TASK_UNIT_STAT_N_COMMIT_MISMATCH      = 8'h98;


   parameter TASK_UNIT_STAT_N_ABORT_CHILD_DEQ      = 8'ha0;
   parameter TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ  = 8'ha4;
   parameter TASK_UNIT_STAT_N_ABORT_CHILD_MISMATCH = 8'ha8;
   parameter TASK_UNIT_STAT_N_ABORT_TASK           = 8'hb0;

   parameter TASK_UNIT_STAT_N_HEAP_ENQ             = 8'hb4;
   parameter TASK_UNIT_STAT_N_HEAP_DEQ             = 8'hb8;
   parameter TASK_UNIT_STAT_N_HEAP_REPLACE         = 8'hbc;


   parameter TASK_UNIT_STAT_N_COAL_CHILD           = 8'hc0;
   parameter TASK_UNIT_STAT_N_OVERFLOW             = 8'hc4;
   parameter TASK_UNIT_STAT_N_CYCLES_DEQ_VALID     = 8'hc8;

   parameter TASK_UNIT_STATS_0_BEGIN               = 8'hdx;
   parameter TASK_UNIT_STATS_1_BEGIN               = 8'hex;

   parameter TASK_UNIT_MISC_DEBUG                  = 8'hf4;
   parameter TASK_UNIT_ALT_LOG                     = 8'hf8;
   
   parameter TSB_LOG_N_TILES           = 8'h10;
   parameter TSB_ENTRY_VALID           = 8'h20;

   parameter CQ_SIZE                   = 8'h10;
   parameter CQ_USE_TS_CACHE           = 8'h1c;
   parameter CQ_STATE                  = 8'h14;
   parameter CQ_LOOKUP_ENTRY           = 8'h18;
   parameter CQ_LOOKUP_STATE           = 8'h20;
   parameter CQ_LOOKUP_HINT            = 8'h24;
   parameter CQ_LOOKUP_MODE            = 8'h2c;
   parameter CQ_GVT_TS                 = 8'h30;
   parameter CQ_GVT_TB                 = 8'h34;
   parameter CQ_MAX_VT_POS             = 8'h38;
   parameter CQ_DEQ_TASK_TS            = 8'h3c;

   parameter CQ_STATE_STATS            = 8'b010x_xxxx; // 4x, 5x
   parameter CQ_STAT_N_RESOURCE_ABORTS = 8'h60;
   parameter CQ_STAT_N_GVT_ABORTS      = 8'h64;
   parameter CQ_STAT_N_IDLE_CQ_FULL    = 8'h70;
   parameter CQ_STAT_N_IDLE_CC_FULL    = 8'h74;
   parameter CQ_STAT_N_IDLE_NO_TASK    = 8'h78;
   parameter CQ_STAT_CYCLES_IN_RESOURCE_ABORT    = 8'h80;
   parameter CQ_STAT_CYCLES_IN_GVT_ABORT    = 8'h84;
   
   parameter CQ_LOOKUP_TS              = 8'h90;
   parameter CQ_LOOKUP_TB              = 8'h94;
   parameter CQ_N_GVT_GOING_BACK       = 8'h98;
   
   parameter CQ_DEQ_TASK_STATS         = 8'hb0;
   parameter CQ_COMMIT_TASK_STATS      = 8'hb4;

   parameter CQ_N_TASK_NO_CONFLICT     = 8'hc0;
   parameter CQ_N_TASK_CONFLICT_MITIGATED  = 8'hc4;
   parameter CQ_N_TASK_CONFLICT_MISS   = 8'hc8;
   parameter CQ_N_TASK_REAL_CONFLICT   = 8'hcc;

   parameter CQ_N_CUM_COMMIT_CYCLES_H    = 8'hd0;
   parameter CQ_N_CUM_COMMIT_CYCLES_L    = 8'hd4;
   parameter CQ_N_CUM_ABORT_CYCLES_H    = 8'hd8;
   parameter CQ_N_CUM_ABORT_CYCLES_L    = 8'hdc;

   
   parameter DEQ_FIFO_FULL_THRESHOLD   = 8'h10;
   parameter DEQ_FIFO_SIZE             = 8'h14;
   parameter DEQ_FIFO_NEXT_TASK_TS     = 8'h18;
   parameter DEQ_FIFO_NEXT_TASK_HINT   = 8'h1c;

   parameter L2_FLUSH         = 8'h10;
   parameter L2_READ_HITS     = 8'h20;
   parameter L2_READ_MISSES   = 8'h24;
   parameter L2_WRITE_HITS    = 8'h28;
   parameter L2_WRITE_MISSES  = 8'h2c;
   parameter L2_EVICTIONS     = 8'h30;
   parameter L2_RETRY_STALL   = 8'h34;
   parameter L2_RETRY_NOT_EMPTY   = 8'h38;
   parameter L2_RETRY_COUNT   = 8'h3c;
   parameter L2_STALL_IN      = 8'h40;
   

   parameter CM_BLOCKED_VALID = 8'h20;
   parameter CM_REG_REQUEST   = 8'h24;
   parameter CM_CHILD_PTR_DATA= 8'h28;
   parameter CM_MISC          = 8'h2c;

   parameter SERIALIZER_ARVALID = 8'h20;
   parameter SERIALIZER_READY_LIST = 8'h24;
   parameter SERIALIZER_REG_VALID = 8'h28;
   parameter SERIALIZER_CAN_TAKE_REQ_0 = 8'h30;
   parameter SERIALIZER_CAN_TAKE_REQ_1 = 8'h34;
   parameter SERIALIZER_CAN_TAKE_REQ_2 = 8'h38;
   parameter SERIALIZER_CAN_TAKE_REQ_3 = 8'h3c;
   parameter SERIALIZER_SIZE_CONTROL = 8'h40; // {0, stall, full, almost_full}
   parameter SERIALIZER_CQ_STALL_COUNT = 8'h44; // bits [39:8]
   parameter SERIALIZER_STAT_READ = 8'h48; // write to set addr, followed by read

   parameter CQ_HINT_DATA_BASE_ADDR = 8'h10;
   
   parameter DEBUG_CAPACITY   = 8'hf0; // For any component that does logging

   parameter RISCV_DEQ_TASK      = 32'hc0000000;
   parameter RISCV_DEQ_TASK_HINT = 32'hc0000004;
   parameter RISCV_DEQ_TASK_TTYPE= 32'hc0000008;
   parameter RISCV_DEQ_TASK_ARG0 = 32'hc000000c;
   parameter RISCV_DEQ_TASK_ARG1 = 32'hc0000010;
   parameter RISCV_FINISH_TASK   = 32'hc0000020;
   parameter RISCV_UNDO_LOG_ADDR = 32'hc0000030;
   parameter RISCV_UNDO_LOG_DATA = 32'hc0000034;
   parameter RISCV_DEBUG_PRINTF  = 32'hc0000040;
   parameter RISCV_CUR_CYCLE     = 32'hc0000050;
   parameter RISCV_TILE_ID       = 32'hc0000060;
   parameter RISCV_CORE_ID       = 32'hc0000064;

   
endpackage

`endif
