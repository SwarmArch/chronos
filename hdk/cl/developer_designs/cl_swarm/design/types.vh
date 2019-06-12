
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

   typedef logic [UNDO_LOG_ADDR_WIDTH-1:0] undo_log_addr_t;
   typedef logic [UNDO_LOG_DATA_WIDTH-1:0] undo_log_data_t;

   typedef logic [TASK_TYPE_WIDTH-1:0] task_type_t;
   typedef logic [TS_WIDTH-1:0] ts_t;
   typedef logic [LOCALE_WIDTH-1:0] locale_t;
   typedef logic [ARG_WIDTH-1:0] args_t;

   typedef logic [$clog2(CACHE_NUM_WAYS)-1:0] lru_width_t;

   typedef logic [31:0] reg_data_t;
   
   typedef logic [TB_WIDTH-1:0] tb_t;

   typedef logic [31:0] cache_addr_t;

   // Gloabl type definitions
   typedef struct packed {
      task_type_t ttype;
      ts_t ts;
      locale_t locale;
      args_t args;
      logic producer; // task is likely to generate additional tasks
      logic no_write; // task will not do any write
      logic no_read;  // task will not read any read-write data
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
   typedef logic [5:0] core_id_t;
   typedef logic [$clog2(N_THREADS)-1:0] thread_id_t;
   typedef logic [EPOCH_WIDTH-1:0] epoch_t;

   typedef logic [LOG_STAGE_FIFO_SIZE:0] fifo_size_t;
   
   typedef struct packed {
      task_t            task_desc;
      cq_slice_slot_t   cq_slot;
      thread_id_t       thread;
      object_t          object;
      cache_addr_t      cache_addr;
   } rw_write_t;
   