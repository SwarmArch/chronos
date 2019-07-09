
import swarm::*;



module task_unit_unordered 
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
   tq_slot_t task_spill_threshold;
   logic [LOG_TQ_SPILL_SIZE-1:0] task_unit_spill_size;
   logic [LOG_TQ_SPILL_SIZE-1:0] spills_remaining;

   tq_slot_t n_tasks;

   logic tq_stall;
   logic tq_started;

   logic fifo_wr_en;
   task_t fifo_wr_data;
   logic fifo_full, fifo_empty;
   logic fifo_rd_en;
   task_t fifo_rd_data;

   fifo #(
      .WIDTH(TQ_WIDTH),
      .LOG_DEPTH(LOG_TQ_SIZE)
   ) TASK_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(fifo_wr_en),
      .wr_data(fifo_wr_data),

      .full(fifo_full),
      .empty(fifo_empty),

      .rd_en(fifo_rd_en),
      .rd_data(fifo_rd_data),

      .size(n_tasks)
   );
   assign full = fifo_full;
   assign empty = fifo_empty;
   assign almost_full = (n_tasks > task_spill_threshold);

   always_ff @(posedge clk) begin
      if (!rstn) begin
         spills_remaining <= 0;
      end else begin
         if ((spills_remaining==0)  & almost_full) begin
            spills_remaining <= task_unit_spill_size;
         end else if (overflow_valid & overflow_ready) begin
            spills_remaining <= spills_remaining - 1;
         end
      end
   end
   

   assign coal_child_ready = (coal_child_valid & !fifo_full);
   assign task_enq_ready = !coal_child_ready & task_enq_valid & !almost_full;
   assign fifo_wr_en = (coal_child_valid & coal_child_ready) | (task_enq_valid & task_enq_ready);
   assign fifo_wr_data = (coal_child_ready ? coal_child_data : task_enq_data);

   assign overflow_valid = !fifo_empty & (spills_remaining > 0);
   assign overflow_data = fifo_rd_data;

   assign task_deq_valid = !fifo_empty & (spills_remaining == 0) & (fifo_rd_data.ttype != TASK_TYPE_SPLITTER);
   assign task_deq_data = fifo_rd_data;

   assign splitter_deq_valid = !fifo_empty & (spills_remaining == 0) & (fifo_rd_data.ttype == TASK_TYPE_SPLITTER);
   assign splitter_deq_task = fifo_rd_data;

   assign fifo_rd_en = (overflow_valid & overflow_ready) | (task_deq_valid & task_deq_ready) | 
                       (splitter_deq_valid & splitter_deq_ready);


   assign task_resp_valid = 1'b0;
   assign abort_child_ready = 1'b1;
   assign abort_resp_valid = 1'b0;
   assign cut_ties_ready = 1'b1;
   assign task_deq_force = 1'b0;
   assign cq_child_abort_valid = 1'b0;
   assign abort_task_ready = 1'b1;
   assign commit_task_ready = 1'b1;

   
   assign lvt = empty ? '1 : 0;
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
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) task_enqueue slot:%4d ts:%8x locale:%8x ttype:%1x args:(%4d %4d) tied:%d \t\t resp:(ack:%d tile:%2d tsb:%2d) \n", 
               cycle, TILE_ID, n_tasks, 0, 0, 
               task_enq_data.ts, task_enq_data.locale, 
               task_enq_data.ttype,
               0, task_enq_data[31:0],
               task_enq_tied, 0,
               task_enq_resp_tile, task_enq_resp_tsb_id
            ) ;
         end
         if (coal_child_valid & coal_child_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) coal_child   slot:%4d ts:%8x locale:%8x \n",
               cycle, TILE_ID, n_tasks, 0, 0,
               coal_child_data.ts, coal_child_data.locale) ;
         end
         if (overflow_valid & overflow_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) overflow     slot:%4d ts:%8x locale:%8x \n",
               cycle, TILE_ID, n_tasks, 0, 0,
               overflow_data.ts, overflow_data.locale) ;
         end
         if (task_deq_valid & task_deq_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) task_deq     slot:%4d ts:%8x locale:%8x cq_slot:%2d\n",
               cycle, TILE_ID, n_tasks, 0, 0,
               task_deq_data.ts, task_deq_data.locale, task_deq_cq_slot) ;
         end
         if (splitter_deq_valid & splitter_deq_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d) splitter_deq slot:%4d ts:%8x locale:%8x \n",
               cycle, TILE_ID, n_tasks, 0, 0, 
               splitter_deq_task.ts, splitter_deq_task.locale ) ;
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


generate
if(TQ_STATS) begin 
   always_ff @(posedge clk) begin
      if (!rstn) begin
         n_untied_enq <= 0;

         n_deq_task <= 0;
         n_splitter_deq <= 0;

         n_coal_child <= 0;
         n_overflow <= 0;

         n_cycles_task_deq_valid <= 0;
      end else begin
         if (task_enq_valid & task_enq_ready) begin
               n_untied_enq <= n_untied_enq + 1;
         end

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

      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               TASK_UNIT_SPILL_THRESHOLD : task_spill_threshold <= reg_bus.wdata;
               TASK_UNIT_SPILL_SIZE   : task_unit_spill_size <= reg_bus.wdata; 
               TASK_UNIT_STALL : tq_stall <= reg_bus.wdata;
               TASK_UNIT_START : tq_started <= reg_bus.wdata;
               TASK_UNIT_ALT_LOG : alt_log_word <= reg_bus.wdata;

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
            
            TASK_UNIT_STAT_N_UNTIED_ENQ          : reg_bus.rdata <= n_untied_enq;
            TASK_UNIT_STAT_N_DEQ_TASK            : reg_bus.rdata <= n_deq_task;
            TASK_UNIT_STAT_N_SPLITTER_DEQ        : reg_bus.rdata <= n_splitter_deq;
            TASK_UNIT_STAT_N_COAL_CHILD          : reg_bus.rdata <= n_coal_child;
            TASK_UNIT_STAT_N_OVERFLOW            : reg_bus.rdata <= n_overflow;
            TASK_UNIT_STAT_N_CYCLES_DEQ_VALID    : reg_bus.rdata <= n_cycles_task_deq_valid;

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
      
      logic [31:0] deq_locale;
      logic [31:0] deq_ts;

      msg_type_t  commit_task_abort_child;
      msg_type_t  abort_task;
      msg_type_t  cut_ties;
      msg_type_t  deq_task;
      msg_type_t  overflow_task;
      msg_type_t  enq_task_coal_child;


      // enq parameters 
      logic [31:0] enq_locale; 
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
      log_word.cut_ties.valid = cut_ties_valid;
      log_word.cut_ties.ready = cut_ties_ready;
      log_word.abort_task.valid = abort_task_valid;
      log_word.abort_task.ready = abort_task_ready;

      log_word.splitter_deq_valid = splitter_deq_valid;
      log_word.splitter_deq_ready = splitter_deq_ready;

      if (task_enq_valid & task_enq_ready) begin
        log_word.enq_task_n_coal_child = 1'b1;
        log_word.enq_ttype = task_enq_data.ttype;
        log_word.enq_locale  = task_enq_data.locale;
        log_word.enq_ts    = task_enq_data.ts; 
        log_word.enq_task_coal_child.tied  = task_enq_tied;
        log_word.enq_task_coal_child.valid = task_enq_valid;
        log_word.enq_task_coal_child.ready = task_enq_ready;
        if (alt_log_word & ARG_WIDTH >= 32) begin
		
           log_word.deq_locale = task_enq_data.args[31:0] ;
           log_word.deq_ts   = task_enq_data.args[63:32];
           if (alt_log_word & ARG_WIDTH >= 64) begin
              log_word.gvt_tb = task_enq_data.args[95:64];
           end
        end
        log_valid = 1;
     end else if (coal_child_valid & coal_child_ready) begin
        log_word.enq_task_n_coal_child = 1'b0;
        log_word.enq_ttype = coal_child_data.ttype;
        log_word.enq_locale  = coal_child_data.locale;
        log_word.enq_ts    = coal_child_data.ts;
        log_word.enq_task_coal_child.valid = coal_child_valid;
        log_word.enq_task_coal_child.ready = coal_child_ready;
        log_valid = 1;
     end 
     if (task_deq_valid & task_deq_ready) begin
        log_word.deq_task.slot    = task_deq_tq_slot;
        if (!alt_log_word) begin
           log_word.deq_locale = task_deq_data.locale;
           log_word.deq_ts   = task_deq_data.ts;
        end
        log_valid = 1;
     end else if (splitter_deq_valid & splitter_deq_ready) begin
        if (!alt_log_word) begin
          log_word.deq_locale = splitter_deq_task.locale;
          log_word.deq_ts   = splitter_deq_task.ts;
        end
        log_valid = 1;
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
     if (cut_ties_valid & cut_ties_ready) begin
        log_word.cut_ties.slot     = cut_ties_tq_slot;
        log_word.cut_ties.epoch_1  = cut_ties_epoch;
        log_valid = 1'b1;
     end
     if (abort_task_valid & abort_task_ready) begin
        log_word.abort_task.slot     = abort_task_slot;
        log_word.abort_task.epoch_1  = abort_task_epoch;
        log_valid = 1'b1;
     end
     if (overflow_valid & overflow_ready) begin
        log_valid = 1'b1;
     end


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

