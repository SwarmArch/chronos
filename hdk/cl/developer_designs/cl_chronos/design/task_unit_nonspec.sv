
import chronos::*;

module task_unit_nonspec 
#( 
   parameter TILE_ID = 0
) (
   input clk,
   input rstn,
   
   // -- Outer Tile interface --

   // Task Enq Reqest
   input                      task_enq_valid,
   output logic               task_enq_ready,
   input task_t               task_enq_data,
   input                      task_enq_tied,
   input tsb_entry_id_t       task_enq_resp_tsb_id,
   input tile_id_t            task_enq_resp_tile,

   // Task Enq Response

   output logic               task_resp_valid,
   input                      task_resp_ready,
   output tile_id_t           task_resp_dest_tile,
   output tsb_entry_id_t      task_resp_tsb_id,
   output logic               task_resp_ack,
   output epoch_t             task_resp_epoch,
   output tq_slot_t           task_resp_tq_slot,

   // Abort Task messages coming through the xbar, 
   // These messages are due to child aborts/ no requeue,
   // if task dequeued, need to inform CQ too
  
   input                      abort_child_valid,
   output logic               abort_child_ready,
   input tq_slot_t            abort_child_tq_slot,
   input epoch_t              abort_child_epoch,
   input tile_id_t            abort_child_resp_tile,
   input cq_slice_slot_t      abort_child_resp_cq_slot,
   input child_id_t           abort_child_resp_child_id,

   // Abort Child Response

   output logic               abort_resp_valid,
   input                      abort_resp_ready,
   output tile_id_t           abort_resp_tile,
   output cq_slice_slot_t     abort_resp_cq_slot,
   output child_id_t          abort_resp_child_id,

   // Cut Ties

   input                      cut_ties_valid,
   output logic               cut_ties_ready,
   input tq_slot_t            cut_ties_tq_slot,
   input epoch_t              cut_ties_epoch,
   
   // -- Commit Queue Interface --
      
   // Task Deq
   output logic               task_deq_valid,
   input                      task_deq_ready,
   input cq_slice_slot_t      task_deq_cq_slot,
   output task_t              task_deq_data,
   output epoch_t             task_deq_epoch,
   output tq_slot_t           task_deq_tq_slot,
   
   // if the heap_min is earlier than deq_task, force CQ to accept the deq_task 
   output logic               task_deq_force,

   // Inform the CQ of a child abort if task has been already dequeued,
   input                      cq_child_abort_ready,
   output logic               cq_child_abort_valid,
   output cq_slice_slot_t     cq_child_abort_slot,
   
   // Abort task messages from Commit Queue
   // These are a result of dependence violations/resource aborts
   // Requeue necessary
   input                      abort_task_valid,
   output logic               abort_task_ready,
   input tq_slot_t            abort_task_slot,
   input epoch_t              abort_task_epoch,
   input ts_t                 abort_task_ts,

   // commit task messages from CQ
   input                      commit_task_valid,
   output logic               commit_task_ready,
   input tq_slot_t            commit_task_slot,
   input epoch_t              commit_task_epoch,

   // -- SPILL Interface --   

   // Coalescer children Enq, Always accepted
   input                      coal_child_valid,
   output logic               coal_child_ready,
   input task_t               coal_child_data,

   // Task Overflow port to coalescer 
   input                      overflow_ready,
   output logic               overflow_valid,
   output task_t              overflow_data,

   // Splitter Deq
   output logic               splitter_deq_valid,
   input                      splitter_deq_ready,
   output task_t              splitter_deq_task,

   // Misc.
   output logic full,
   output logic almost_full, 
   output logic empty,
   
   reg_bus_t         reg_bus,
   pci_debug_bus_t.master pci_debug,

   input ts_t cq_max_vt_ts,
   output ts_t lvt,
   input vt_t gvt

);

   //misc
   logic [LOG_TQ_SPILL_SIZE-1:0] task_unit_spill_size;
   logic [LOG_TQ_SPILL_SIZE-1:0] spills_remaining;
   logic [LOG_TQ_SPILL_SIZE-1:0] spill_heap_occ;

   ts_t task_unit_throttle_margin;
   ts_t task_unit_throttle_ts;
   always_ff @(posedge clk) begin
      if (task_unit_throttle_margin == 0) begin
         task_unit_throttle_ts <= '1;
      end else begin
         task_unit_throttle_ts <= gvt.ts + task_unit_throttle_margin;
      end
   end

   logic tq_stall;
   logic tq_started;
   heap_op_t heap_in_op;

   logic [4:0] deq_max_propagation_delay;


   always_ff @(posedge clk) begin
      if (!rstn) begin
         spills_remaining <= 0;
      end else begin
         if ((spills_remaining==0)  & almost_full & (spill_heap_occ == '1) & !NO_SPILLING) begin
            spills_remaining <= task_unit_spill_size;
         end else if (heap_in_op == DEQ_MAX) begin
            spills_remaining <= spills_remaining - 1;
         end
      end

      if (!rstn) begin
         deq_max_propagation_delay <= '1;
      end else begin
         if (heap_in_op == DEQ_MAX) begin
            deq_max_propagation_delay = TQ_STAGES * 2 + 2;
         end else begin
            if (deq_max_propagation_delay != 0) begin
               deq_max_propagation_delay <= deq_max_propagation_delay -1;
            end
         end
      end
   end
   
   task_t         next_insert_elem;
   logic          next_insert_elem_set;
   logic          next_insert_elem_clear;
   
   task_t         reg_next_insert_elem ;
   logic          reg_next_insert_elem_valid;
   
   logic heap_ready;
   logic heap_out_valid;

   task_t next_deque_elem;
   logic deq_task;
   logic [TQ_STAGES-1:0] heap_capacity, task_spill_threshold, n_tasks;

   logic spill_fifo_full;
   logic spill_fifo_empty;

   logic spill_fifo_wr_en;
   logic spill_fifo_rd_en;

   task_t spill_fifo_rd_data;
   task_t spill_fifo_wr_data;
   
   min_heap #(
      .N_STAGES(TQ_STAGES),
      .PRIORITY_WIDTH(TS_WIDTH+1),
      .DATA_WIDTH( $bits(next_deque_elem) - TS_WIDTH - 1)
   ) HEAP (
      .clk(clk),
      .rstn(rstn),

      .in_ts({reg_next_insert_elem.ts, reg_next_insert_elem.producer}),
      .in_data( {
            reg_next_insert_elem.ttype,
            reg_next_insert_elem.object,
            reg_next_insert_elem.args,
            reg_next_insert_elem.no_write,
            reg_next_insert_elem.no_read,
            reg_next_insert_elem.non_spec
            } ),
      .in_op(heap_in_op),
      .ready(heap_ready),

      .out_ts({next_deque_elem.ts, next_deque_elem.producer}),  
      .out_data( {
            next_deque_elem.ttype,
            next_deque_elem.object,
            next_deque_elem.args,
            next_deque_elem.no_write,
            next_deque_elem.no_read,
            next_deque_elem.non_spec
         }),
      .out_valid(heap_out_valid),
   
      .capacity(heap_capacity),

      .max_out_ts({spill_fifo_wr_data.ts, spill_fifo_wr_data.producer}),
      .max_out_data( {
            spill_fifo_wr_data.ttype,
            spill_fifo_wr_data.object,
            spill_fifo_wr_data.args,
            spill_fifo_wr_data.no_write,
            spill_fifo_wr_data.no_read,
            spill_fifo_wr_data.non_spec
         }),
      .max_out_valid(spill_fifo_wr_en)
   );

   logic pre_enq_fifo_full, pre_enq_fifo_empty;
   logic [5:0] pre_enq_fifo_occ;


   assign n_tasks = (2**TQ_STAGES - 1 - heap_capacity);
   logic [47:0] cum_tasks;
   always_comb begin
      coal_child_ready = 1'b0;
      task_enq_ready = 1'b0;
      next_insert_elem = 'x;
      next_insert_elem_set = 1'b0;
      if (spills_remaining > 0) begin

      end else begin
         if (!pre_enq_fifo_full) begin
            if (coal_child_valid) begin
               coal_child_ready = 1'b1;
               next_insert_elem_set = 1'b1;
               next_insert_elem = coal_child_data;
            end else if (task_enq_valid) begin
               task_enq_ready = 1'b1;
               next_insert_elem_set = 1'b1;
               next_insert_elem = task_enq_data;
            end
         end
      end
   end
/* 
   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_next_insert_elem_valid <= 1'b0;
      end else begin
         if (!reg_next_insert_elem_valid & next_insert_elem_set ) begin
            reg_next_insert_elem_valid <= 1'b1;
            reg_next_insert_elem <= next_insert_elem;
         end else if (reg_next_insert_elem_valid & next_insert_elem_clear) begin
            reg_next_insert_elem_valid <= 1'b0;
         end
      end
   end 
*/

   logic [15:0] time_since_last_deq;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         time_since_last_deq <= 0;
      end else begin
         if (heap_in_op == DEQ_MIN || heap_in_op == REPLACE) begin
            time_since_last_deq <= 0;
         end else begin
            time_since_last_deq <= time_since_last_deq + 1;
         end
      end
   end

   logic [15:0] deq_tolerance, pre_enq_fifo_full_thresh; 

   always_comb begin
      reg_next_insert_elem_valid = 1'b0;
      // Try to maximize replace operations.
      // Enq a new element only if 
      // 1. Can do a heap DEQ in the same cycle
      // 2. "deq_tolerance" no. of cycles have elapsed since the last deq
      // 3. fifo is almost full
      if (!pre_enq_fifo_empty) begin
         if (deq_task) begin
            reg_next_insert_elem_valid = 1'b1;
         end else if (deq_tolerance < time_since_last_deq) begin
            reg_next_insert_elem_valid = 1'b1;
         end else if (pre_enq_fifo_occ > pre_enq_fifo_full_thresh) begin
            reg_next_insert_elem_valid = 1'b1;
         end
      end
   end

   always_comb begin
      heap_in_op = NOP;
      next_insert_elem_clear = 1'b0;
      if (!rstn) begin
      end else begin
         if (heap_ready) begin // cannot start if started last cycle
            if (spills_remaining > 0) begin
               //if (spill_heap_occ < 16) begin
               heap_in_op = DEQ_MAX;
               //end
            end else begin
               if (reg_next_insert_elem_valid & deq_task) begin
                  heap_in_op = REPLACE;
                  next_insert_elem_clear = 1'b1;
               end else if (reg_next_insert_elem_valid) begin
                  heap_in_op = ENQ;
                  next_insert_elem_clear = 1'b1;
               end else if (deq_task) begin
                  heap_in_op = DEQ_MIN;
               end
            end
         end
      end
   end
   fifo #(
      .WIDTH( TQ_WIDTH ),
      .LOG_DEPTH(5) // Size should be enough to hold the results of all DEQ_MAX requeusts in flight.
   ) PRE_ENQ_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(next_insert_elem_set),
      .wr_data(next_insert_elem),

      .full(pre_enq_fifo_full),
      .empty(pre_enq_fifo_empty),

      .rd_en(next_insert_elem_clear),
      .rd_data(reg_next_insert_elem),
      .size(pre_enq_fifo_occ)

   );

   logic spill_heap_ready;
   logic spill_heap_out_valid;
   heap_op_t spill_heap_in_op;

generate 
if (!NO_SPILLING) begin
   min_heap #(
      .N_STAGES(LOG_TQ_SPILL_SIZE),
      .PRIORITY_WIDTH(TS_WIDTH),
      .DATA_WIDTH( TQ_WIDTH)
   ) SPLITTER_HEAP (
      .clk(clk),
      .rstn(rstn),

      .in_ts(spill_fifo_wr_data.ts),
      .in_data(spill_fifo_wr_data ),
      .in_op(spill_heap_in_op),
      .ready(spill_heap_ready),

      .out_ts(),  
      .out_data(spill_fifo_rd_data),
      .out_valid(spill_heap_out_valid),
   
      .capacity(spill_heap_occ)

   );
end else begin
   assign spill_heap_occ = '1;
   assign spill_heap_out_valid = 1'b0;

end
endgenerate
  
   assign overflow_valid = spill_heap_out_valid & (spills_remaining == 0) & (deq_max_propagation_delay ==0) ;
   assign overflow_data = spill_fifo_rd_data;

   always_comb begin
      spill_heap_in_op = NOP;
      if (spill_heap_ready) begin
         if (spill_fifo_rd_en & spill_fifo_wr_en) begin
            spill_heap_in_op = REPLACE; // shouldn't happen
         end else if (spill_fifo_rd_en) begin
            spill_heap_in_op = DEQ_MIN;
         end else if (spill_fifo_wr_en) begin
            spill_heap_in_op = ENQ;
         end
      end
   end

   assign spill_fifo_rd_en = overflow_valid & overflow_ready;


   assign task_deq_valid = heap_ready & heap_out_valid &
                           (next_deque_elem.ttype != TASK_TYPE_SPLITTER) & tq_started & 
                           (spills_remaining == 0) &
                           (next_deque_elem.ts < task_unit_throttle_ts) ;
         
   assign task_deq_data = next_deque_elem;

   assign splitter_deq_valid = heap_ready & heap_out_valid & (next_deque_elem.ttype == TASK_TYPE_SPLITTER) & (spills_remaining == 0); 
   assign splitter_deq_task = next_deque_elem;

   assign deq_task = (task_deq_valid & task_deq_ready ) | (splitter_deq_valid & splitter_deq_ready);


   assign task_resp_valid = 1'b0;
   assign abort_child_ready = 1'b1;
   assign abort_resp_valid = 1'b0;
   assign cut_ties_ready = 1'b1;
   assign task_deq_force = 1'b0;
   assign cq_child_abort_valid = 1'b0;
   assign abort_task_ready = 1'b1;
   assign commit_task_ready = 1'b1;

   assign empty = (n_tasks == 0) & pre_enq_fifo_empty;
   assign almost_full = (n_tasks > task_spill_threshold);
   assign full = (heap_capacity == 10);

   ts_t last_deq_ts;
   always_ff @(posedge clk) begin
      last_deq_ts <= 0;
      if (task_deq_valid & task_deq_ready) last_deq_ts <= next_deque_elem.ts;
   end
   
   assign lvt = empty ? '1 : (heap_out_valid ? next_deque_elem.ts : last_deq_ts);
   assign task_deq_tq_slot = 0;
   assign task_deq_epoch = 0;
   

   
`ifdef XILINX_SIMULATOR
   if (1) begin
      logic [63:0] cycle;
      integer file,r;
      string file_name;
      initial begin
         $sformat(file_name, "rob_%0d.log", TILE_ID);
         file = $fopen(file_name,"w");
      end
      always_ff @(posedge clk) begin
         if (!rstn) cycle <=0;
         else cycle <= cycle + 1;
      end

      always_ff @(posedge clk) begin
         if (task_enq_valid & task_enq_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) task_enqueue slot:%4d ts:%8x object:%8x ttype:%1x args:(%4d %4d) tied:%d \t\t resp:(ack:%d tile:%2d tsb:%2d) \n", 
               cycle, TILE_ID, n_tasks, 0, 0, 
               task_enq_data.ts, task_enq_data.object, 
               task_enq_data.ttype,
               0, task_enq_data[31:0],
               task_enq_tied, 0,
               task_enq_resp_tile, task_enq_resp_tsb_id
            ) ;
         end
         if (coal_child_valid & coal_child_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) coal_child   slot:%4d ts:%8x object:%8x \n",
               cycle, TILE_ID, n_tasks, 0, 0,
               coal_child_data.ts, coal_child_data.object) ;
         end
         if (overflow_valid & overflow_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) overflow     slot:%4d ts:%8x object:%8x \n",
               cycle, TILE_ID, n_tasks, 0, 0,
               overflow_data.ts, overflow_data.object) ;
         end
         if (task_deq_valid & task_deq_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) task_deq     slot:%4d ts:%8x object:%8x cq_slot:%2d\n",
               cycle, TILE_ID, n_tasks, 0, 0,
               task_deq_data.ts, task_deq_data.object, task_deq_cq_slot) ;
         end
         if (splitter_deq_valid & splitter_deq_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) splitter_deq slot:%4d ts:%8x object:%8x \n",
               cycle, TILE_ID, n_tasks, 0, 0, 
               splitter_deq_task.ts, splitter_deq_task.object ) ;
         end
         $fflush(file);
      end
   end
`endif


   logic [31:0] n_untied_enq;
   logic [31:0] n_deq_task, n_splitter_deq;
   
   logic [31:0] n_coal_child;
   logic [31:0] n_overflow;

   logic [31:0] n_cycles_task_deq_valid; 

   logic [31:0] n_heap_enq;
   logic [31:0] n_heap_replace;
   logic [31:0] n_heap_deq;

generate
if(TQ_STATS) begin 
   always_ff @(posedge clk) begin
      if (!rstn) begin
         n_untied_enq <= 0;

         n_deq_task <= 0;
         n_splitter_deq <= 0;

         n_coal_child <= 0;
         n_overflow <= 0;
         
         n_heap_enq <= 0;
         n_heap_deq <= 0;
         n_heap_replace <= 0;

         n_cycles_task_deq_valid <= 0;
         cum_tasks <= 0;
      end else begin
         if (task_enq_valid & task_enq_ready) begin
            n_untied_enq <= n_untied_enq + 1;
         end
         cum_tasks <= cum_tasks + n_tasks;

         if (task_deq_valid & task_deq_ready) begin
            n_deq_task <= n_deq_task + 1;
         end
         if (splitter_deq_valid & splitter_deq_ready) begin
            n_splitter_deq <= n_splitter_deq + 1;
         end
         if (coal_child_valid & coal_child_ready) begin
            n_coal_child <= n_coal_child + 1;
         end
         if (overflow_valid & overflow_ready) begin
            n_overflow <= n_overflow + 1;
         end
         if (task_deq_valid) begin
            n_cycles_task_deq_valid <= n_cycles_task_deq_valid + 1; 
         end
         
         if (heap_in_op == ENQ) begin
            n_heap_enq <= n_heap_enq+1;
         end
         if (heap_in_op == DEQ_MIN) begin
            n_heap_deq <= n_heap_deq+1;
         end
         if (heap_in_op == REPLACE) begin
            n_heap_replace <= n_heap_replace+1;
         end
      end
   end
end 
endgenerate

   logic alt_log_word;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_spill_threshold <= SPILL_THRESHOLD;
         task_unit_spill_size <= 32; // has to be muliple of 8
         tq_stall <= 0;
         tq_started <= 0;
         alt_log_word <= 0;
         task_unit_throttle_margin <= NON_SPEC ? 1000 : 0;
         deq_tolerance <= 1;
         pre_enq_fifo_full_thresh <= 0;
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               TASK_UNIT_SPILL_THRESHOLD : task_spill_threshold <= reg_bus.wdata;
               TASK_UNIT_SPILL_SIZE   : task_unit_spill_size <= reg_bus.wdata; 
               TASK_UNIT_STALL : tq_stall <= reg_bus.wdata;
               TASK_UNIT_START : tq_started <= reg_bus.wdata;
               TASK_UNIT_ALT_LOG : alt_log_word <= reg_bus.wdata;
               TASK_UNIT_THROTTLE_MARGIN : task_unit_throttle_margin <= reg_bus.wdata;
               TASK_UNIT_PRE_ENQ_BUFFER_CONFIG : begin
                  deq_tolerance <= reg_bus.wdata[15:0];
                  pre_enq_fifo_full_thresh <= reg_bus.wdata[31:16];
               end

            endcase
         end
      end 
   end
   
   logic [LOG_LOG_DEPTH:0] log_size; 
   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
      end else
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
         casex (reg_bus.araddr) 
            DEBUG_CAPACITY : reg_bus.rdata <= log_size;
            TASK_UNIT_N_TASKS : reg_bus.rdata <= n_tasks;
            TASK_UNIT_LVT : reg_bus.rdata <= lvt;
            
            TASK_UNIT_STAT_N_UNTIED_ENQ          : reg_bus.rdata <= n_untied_enq;
            TASK_UNIT_STAT_N_DEQ_TASK            : reg_bus.rdata <= n_deq_task;
            TASK_UNIT_STAT_N_SPLITTER_DEQ        : reg_bus.rdata <= n_splitter_deq;
            TASK_UNIT_STAT_N_COAL_CHILD          : reg_bus.rdata <= n_coal_child;
            TASK_UNIT_STAT_N_OVERFLOW            : reg_bus.rdata <= n_overflow;
            TASK_UNIT_STAT_N_CYCLES_DEQ_VALID    : reg_bus.rdata <= n_cycles_task_deq_valid;
            TASK_UNIT_STAT_AVG_TASKS   : reg_bus.rdata <= cum_tasks[47:16];
            
            TASK_UNIT_STAT_N_HEAP_ENQ   : reg_bus.rdata <= n_heap_enq;
            TASK_UNIT_STAT_N_HEAP_DEQ   : reg_bus.rdata <= n_heap_deq;
            TASK_UNIT_STAT_N_HEAP_REPLACE   : reg_bus.rdata <= n_heap_replace;

            TASK_UNIT_MISC_DEBUG : reg_bus.rdata <= { abort_child_valid, task_enq_valid, cut_ties_valid, cq_child_abort_valid, abort_task_valid, abort_resp_valid, task_deq_valid, commit_task_valid, task_deq_ready};
            default: reg_bus.rdata <= 0;
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end  

   // END REG_BUS and PCI
generate 
if (TASK_UNIT_LOGGING[TILE_ID]) begin
   
   logic log_valid;
   typedef struct packed {
      logic valid;
      logic ready;
      logic tied;
      logic [12:0] slot; // tq_slot
      logic [7:0] epoch_1; // or cq_slot
      logic [7:0] epoch_2;
   } msg_type_t; // 32 bits each
   typedef struct packed {
      logic [31:0] gvt_tb;
      logic [31:0] gvt_ts;
      
      logic [31:0] deq_object;
      logic [31:0] deq_ts;

      msg_type_t  commit_task_abort_child;
      logic [31:0] overflow_object;
      logic [31:0] overflow_ts;
      msg_type_t  deq_task;
      msg_type_t  overflow_task;
      msg_type_t  enq_task_coal_child;


      // enq parameters 
      logic [31:0] enq_object; 
      logic [31:0] enq_ts;
      
      logic [3:0] enq_ttype;
      logic resp_ack;
      logic [2:0] resp_tile_id;
      logic [3:0] resp_tsb_id;
      logic commit_n_abort_child; // 1-commit , 0 -abort
      logic enq_task_n_coal_child; // 1-enq_task, 0 - coal_child
      logic splitter_deq_valid;
      logic splitter_deq_ready;

      logic [15:0] heap_capacity;
      logic [15:0] n_tied_tasks;
      logic [15:0] n_tasks;

   } task_unit_log_t;
   task_unit_log_t log_word;
   always_comb begin
      log_valid = 1'b0;

      log_word = '0;
      log_word.n_tasks = n_tasks;


      log_word.overflow_task.valid = overflow_valid;
      log_word.overflow_task.ready = overflow_ready;
      log_word.deq_task.valid = task_deq_valid;
      log_word.deq_task.ready = task_deq_ready;

      log_word.splitter_deq_valid = splitter_deq_valid;
      log_word.splitter_deq_ready = splitter_deq_ready;

      if (task_enq_valid & task_enq_ready) begin
        log_word.enq_task_n_coal_child = 1'b1;
        log_word.enq_ttype = task_enq_data.ttype;
        log_word.enq_object  = task_enq_data.object;
        log_word.enq_ts    = task_enq_data.ts; 
        log_word.enq_task_coal_child.tied  = task_enq_tied;
        log_word.enq_task_coal_child.valid = task_enq_valid;
        log_word.enq_task_coal_child.ready = task_enq_ready;
        if (alt_log_word & ARG_WIDTH >= 32) begin
           log_word.deq_object = task_enq_data.args[0+:32] ;
        end
        if (alt_log_word & ARG_WIDTH >= 64) begin
           log_word.deq_ts = task_enq_data.args[32+:32] ;
        end
        log_valid = 1;
     end else if (coal_child_valid & coal_child_ready) begin
        log_word.enq_task_n_coal_child = 1'b0;
        log_word.enq_ttype = coal_child_data.ttype;
        log_word.enq_object  = coal_child_data.object;
        log_word.enq_ts    = coal_child_data.ts;
        log_word.enq_task_coal_child.valid = coal_child_valid;
        log_word.enq_task_coal_child.ready = coal_child_ready;
        log_valid = 1;
     end 
     if (task_deq_valid) begin
        log_word.deq_task.slot    = task_deq_data.ttype;
        if (!alt_log_word) begin
           log_word.deq_object = task_deq_data.object;
           log_word.deq_ts   = task_deq_data.ts;
        end
        if (task_deq_ready) begin
           log_valid = 1;
        end
     end else if (splitter_deq_valid) begin
        log_word.deq_task.slot    = splitter_deq_task.ttype;
        if (!alt_log_word) begin
          log_word.deq_object = splitter_deq_task.object;
          log_word.deq_ts   = splitter_deq_task.ts;
        end
        if (splitter_deq_ready) begin
           log_valid = 1;
        end
     end
     if (commit_task_valid & commit_task_ready) begin
        log_word.commit_n_abort_child = 1'b1;
        log_word.commit_task_abort_child.valid = 1'b1;
        log_word.commit_task_abort_child.ready = 1'b1;
        log_word.commit_task_abort_child.slot     = commit_task_slot;
        log_word.commit_task_abort_child.epoch_1  = commit_task_epoch;
        log_valid = 1'b1;
     end else if (abort_child_valid & abort_child_ready) begin
        log_word.commit_n_abort_child = 1'b0;
        log_word.commit_task_abort_child.valid = 1'b1;
        log_word.commit_task_abort_child.ready = 1'b1;
        log_word.commit_task_abort_child.slot     = abort_child_tq_slot;
        log_word.commit_task_abort_child.epoch_1  = abort_child_epoch;
        log_valid = 1'b1;
     end
     if (overflow_valid & overflow_ready) begin
        log_valid = 1'b1;
     end
     log_word.overflow_object = overflow_data.object;
     log_word.overflow_ts = overflow_data.ts;


   end

   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) TASK_UNIT_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid(log_valid),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end
endgenerate
endmodule

