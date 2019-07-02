
   parameter ID_RW_READ = 1;
   parameter ID_RW_WRITE = 2;
   parameter ID_RO_STAGE = 3;
   parameter ID_SPLITTER = 4;
   parameter ID_COAL = 5;
   parameter ID_TASK_UNIT = 6; 
   parameter CM_PORTS = 3;
   // end all modules with an L2 port
   parameter ID_L2_RW = 7;
   parameter ID_L2_RO = 8;
   parameter ID_TSB     = 9;
   parameter ID_CQ      = 10;
   parameter ID_CM      = 11;
   parameter ID_SERIALIZER    = 12;
   parameter ID_LAST = 13;
   
   parameter ID_ALL_CORES = 32;
   parameter ID_ALL_APP_CORES = 33;
   parameter ID_COAL_AND_SPLITTER = 34;

   parameter ID_GLOBAL = 48;
   
   parameter TASK_TYPE_TERMINATE = 12;
   // if a core has task_araddr = TASK_TYPE_ALL, it can accept any ttype less
   // than TASK_TYPE_ALL
   parameter TASK_TYPE_ALL = 13;
   parameter TASK_TYPE_SPLITTER = 14;
   parameter TASK_TYPE_UNDO_LOG_RESTORE = 15;

   parameter L2_ID_COAL = 1;
   parameter L2_ID_SPLITTER = 2;

   // CL Register Addresses OCL is only 32 MiB (25 bit)
   // [23:16] is tile, [15:8] component, [7:0] addr 

   // OCL_SLAVE address
   parameter OCL_TASK_ENQ_ARGS        = 8'h1c; // set the args of the task to be enqueued next
   parameter OCL_TASK_ENQ_LOCALE      = 8'h14; // set the locale of the task to be enqueued next
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
   parameter CORE_LOCALE              = 8'h30;
   parameter CORE_TS                  = 8'h34;
   parameter CORE_STATE_STATS_BEGIN   = 8'b01xx_xxxx; // deprecated
   parameter CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD = 8'h40;
   parameter CORE_THREAD_ID_FIFO_OCC = 8'h44;

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
   parameter CQ_LOOKUP_LOCALE          = 8'h24;
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
   parameter CQ_CUM_OCC_LSB   = 8'h88;
   parameter CQ_CUM_OCC_MSB   = 8'h8c;


   
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
   parameter DEQ_FIFO_NEXT_TASK_LOCALE = 8'h1c;

   parameter L2_FLUSH         = 8'h10;
   parameter L2_LOG_BVALID    = 8'h14;
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

   parameter SERIALIZER_N_THREADS = 8'h10;
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

   parameter CQ_LOCALE_DATA_BASE_ADDR = 8'h10;
   
   parameter DEBUG_CAPACITY   = 8'hf0; // For any component that does logging
   parameter MEM_XBAR_NUM_CTRL = 8'h10;

   parameter RISCV_DEQ_TASK      = 32'hc0000000;
   parameter RISCV_DEQ_TASK_LOCALE = 32'hc0000004;
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
