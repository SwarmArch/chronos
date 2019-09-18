`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif

import swarm::*;

typedef enum logic[2:0] {
   UNUSED,
   RUNNING, // actively running on a core or waiting in serializer
   ABORTED, // aborted but waiting for pipeline to be cleared
   // waiting for child-abort acks to be received (or for a core to start this task if the task was aborted before it started running)
   WAITING_CHILDREN, // Waiting for child abort acks
   UNDO_LOG_WAITING, // waiting for undo-log-restore complete
   FINISHED, // task ran to completion. but waiting for GVT to advance to this task's vt
   COMMITTED // waiting for cut_ties_ack before the slot can be freed
} cq_state_t;
typedef vt_t [2**LOG_CQ_TS_BANKS -1:0] ts_vt_out; 
typedef logic [2**LOG_CQ_SLICE_SIZE-1:0] filter_entry_t;

module cq_slice 
#( 
   parameter TILE_ID = 0
) (
   input clk,
   input rstn,

   // Task Deq from TQ
   input                   deq_task_valid,
   output logic            deq_task_ready,
   input task_t            deq_task,
   input epoch_t           deq_task_epoch,
   input tq_slot_t         deq_task_tq_slot,
   output cq_slice_slot_t  deq_task_cq_slot, 

   input                   deq_task_force,

   // To FIFOs
   output task_t           out_task,
   output cq_slice_slot_t  out_task_slot,
   output logic            out_task_valid,
   input                   out_task_ready,

   // Finish Task - Core notifies the CQ of it finishing a task
   input                       finish_task_valid,
   input cq_slice_slot_t       finish_task_slot,
   input                       finish_task_is_undo_log_restore,
   input child_id_t            finish_task_num_children,
   output logic                finish_task_ready,
   
   output logic [2**LOG_CQ_SLICE_SIZE-1:0] task_aborted,

   output logic                           gvt_task_slot_valid,
   output cq_slice_slot_t                 gvt_task_slot,

   // If all cores are busy and the gvt_task is not running, nuke one task to make way
   input                                  no_idle_cores,
   input                                  all_idle_cores,
   input                                  cc_almost_full,
   input                                  tsb_almost_full,
   
   // Abort Task To TQ (always with requeue) 
   // due to data dependence or resource violation
   output logic                           to_tq_abort_valid,
   input                                  to_tq_abort_ready,
   output tq_slot_t                       to_tq_abort_slot,
   output epoch_t                         to_tq_abort_epoch,
   output ts_t                            to_tq_abort_ts,
   
   // Commit Task notify TQ
   output logic                           tq_commit_task_valid,
   input                                  tq_commit_task_ready,
   output tq_slot_t                       tq_commit_task_slot,
   output epoch_t                         tq_commit_task_epoch,

   // Abort Task From TQ
   input                                  from_tq_abort_valid,
   output logic                           from_tq_abort_ready,
   input cq_slice_slot_t                  from_tq_abort_slot,
   
   // Abort Children  
   output logic                           abort_children_valid,
   input                                  abort_children_ready,
   output cq_slice_slot_t                 abort_children_cq_slot,
   output child_id_t                      abort_children_count,
   
   // All abort children have acked
   input                                  abort_ack_valid,
   output logic                           abort_ack_ready,
   input cq_slice_slot_t                  abort_ack_cq_slot,
   
   // Cut Ties with children  
   output logic                           cut_ties_valid,
   input                                  cut_ties_ready,
   output cq_slice_slot_t                 cut_ties_cq_slot,
   output child_id_t                      cut_ties_num_children,
   
   // All children cut_tie messages have been sent: Can free up CQ
   input                                  cut_ties_ack_valid,
   output logic                           cut_ties_ack_ready,
   input cq_slice_slot_t                  cut_ties_ack_cq_slot,

   input  vt_t                            gvt,
   output vt_t                            lvt,

   output ts_t                            max_vt_ts,
   output logic                           cq_full, 

   input logic [63:0]                     cur_cycle,
   pci_debug_bus_t.master                 pci_debug,
   reg_bus_t.master                       reg_bus
);
typedef enum logic[2:0] {IDLE, DEQ_CHECK_TS, ABORT_REQUEUE, UNDO_LOG_RESTORE,
      DEQ_PUSH_TASK } cq_fsm_state_t;
generate
if (NON_SPEC) begin : gen 
   
   ts_t drop_task_ts;

   free_list #(
      .LOG_DEPTH(LOG_CQ_SLICE_SIZE)
   ) FREE_LIST_CQ_ID  (
      .clk(clk),
      .rstn(rstn),

      .wr_en(finish_task_valid),
      .rd_en(out_task_valid & out_task_ready),
      .wr_data(finish_task_slot),

      .full(), 
      .empty(),
      .rd_data(out_task_slot),

      .size()
   );

   assign out_task_valid = deq_task_valid;
   always_comb begin
      out_task = deq_task;
      if (deq_task.ts > drop_task_ts) begin
         out_task.ttype = TASK_TYPE_TERMINATE;
      end
   end
   //assign out_task_slot = 0;
   assign deq_task_ready = out_task_ready;
   assign deq_task_cq_slot = 0;
   assign finish_task_ready = 1;
   assign abort_running_slot = 0;
   assign to_tq_abort_valid = 1'b0;
   
   // commit on dequeue
   assign tq_commit_task_valid = deq_task_valid & deq_task_ready;
   assign tq_commit_task_slot = deq_task_tq_slot;
   assign tq_commit_task_epoch = deq_task_epoch;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         drop_task_ts <= '1;
      end else begin
         if (deq_task_valid & deq_task_ready & (deq_task.ttype == TASK_TYPE_TERMINATE)) begin
            drop_task_ts <= deq_task.ts;
         end
      end
   end

   assign task_aborted = 0;

   assign from_tq_abort_ready = 1'b1;
   assign abort_children_valid = 1'b0;
   assign abort_ack_ready = 1'b0;
   assign cut_ties_valid = 1'b0;
   assign cut_ties_ack_ready = 1'b1;
   assign lvt = '1;
   assign max_vt_ts = '1;
   assign gvt_task_slot_valid = 1'b0;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
         reg_bus.rdata <= 'x;
      end else
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
         casex (reg_bus.araddr) 
            CQ_GVT_TS       : reg_bus.rdata <= (!all_idle_cores & gvt.ts == '1) ?
                                       '1 -1 : gvt.ts;
            CQ_GVT_TB       : reg_bus.rdata <= gvt.tb;
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end
end else begin : gen
   


cq_fsm_state_t state;

logic      [2**LOG_CQ_SLICE_SIZE-1:0]  cq_valid; 

cq_state_t   cq_state [0:2**LOG_CQ_SLICE_SIZE-1];
locale_t     cq_locale  [0:2**LOG_CQ_SLICE_SIZE-1];
epoch_t      tq_epoch [0:2**LOG_CQ_SLICE_SIZE-1];
tq_slot_t    cq_tq_slot [0:2**LOG_CQ_SLICE_SIZE-1];
logic        cq_read_only_task [0:2**LOG_CQ_SLICE_SIZE-1];

task_type_t  cq_ttype [0:2**LOG_CQ_SLICE_SIZE-1];

logic       cq_terminate_task [ 0:2**LOG_CQ_SLICE_SIZE-1];

child_id_t cq_num_children [0:2**LOG_CQ_SLICE_SIZE-1];  

logic      cq_undo_log_ack_pending[0:2**LOG_CQ_SLICE_SIZE-1];

cq_slice_slot_t ts_array_raddr;
cq_slice_slot_t ts_check_id;
vt_t check_vt;
vt_t [0:2**LOG_CQ_TS_BANKS-1] rdata_lvt;

initial begin
   for (integer i=0;i<2**LOG_CQ_SLICE_SIZE;i=i+1) begin
      cq_locale[i] = 0;
   end
end
vt_t ts_write_data;
logic ts_write_valid;

assign ts_write_data.ts = out_task.ts; 
assign ts_write_data.tb = cur_cycle[TB_WIDTH-1:0];
assign ts_write_valid = out_task_valid & (state == DEQ_PUSH_TASK);

logic [LOG_GVT_PERIOD-1:0] lvt_cycle;
assign lvt_cycle = cur_cycle[LOG_GVT_PERIOD-1:0];

// bitmap of tasks whose undo log tasks have not been sent out
logic [2**LOG_CQ_SLICE_SIZE-1:0] undo_log_abort_pending; 
cq_slice_slot_t undo_log_abort_max_ts_index;
vt_t            undo_log_abort_max_ts;
   
logic                           s_abort_children_valid;
logic                           s_abort_children_ready;
cq_slice_slot_t                 s_abort_children_cq_slot;
child_id_t                      s_abort_children_count;
logic             abort_children_fifo_full; // sized such that never becomes full
logic             abort_children_fifo_empty;

// A task of type TASK_TYPE_TERMINATE has committed; 
// All subsequently dequeud tasks should immediately finish
logic should_terminate;

cq_slice_slot_t max_vt_pos_fixed, max_vt_pos_rolling;
vt_t max_vt_fixed, max_vt_rolling;
cq_slice_slot_t lookup_entry;
logic lookup_mode;
assign max_vt_ts = max_vt_fixed.ts;
always_comb begin
   if (lookup_mode) begin
      ts_array_raddr = lookup_entry;
   end else begin
      ts_array_raddr = ts_check_id;
      if (state == IDLE) begin
         if (from_tq_abort_valid) begin
            ts_array_raddr = from_tq_abort_slot;
         end
      end
   end
end

logic resource_abort_start;

// Allows changing cq_size at runtime. This might be costly in terms of resources.
// Consider cutting it in when building high-tile-count systems
logic [LOG_CQ_SLICE_SIZE:0] cq_size;
vt_t gvt_q;
logic [15:0] n_gvt_going_back;
logic use_ts_cache;

logic [LOG_LOG_DEPTH:0] log_size; 
if (CQ_CONFIG) begin
   always_ff @(posedge clk) begin
      if (!rstn) begin
         cq_size <= 2**LOG_CQ_SLICE_SIZE;
         lookup_entry <= 'x;
         lookup_mode <= 1'b0;
         use_ts_cache <= 1'b1;
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               CQ_SIZE : cq_size <= reg_bus.wdata;
               CQ_LOOKUP_MODE : lookup_mode <= reg_bus.wdata;
               CQ_LOOKUP_ENTRY : lookup_entry <= reg_bus.wdata;
               CQ_USE_TS_CACHE : use_ts_cache <= reg_bus.wdata[0];
            endcase
         end
      end 
   end
   //assign cq_size = 2**LOG_CQ_SLICE_SIZE;


   always_ff @(posedge clk) begin
      if (!rstn) begin
         gvt_q <= 0;
         n_gvt_going_back <= 0;
      end else begin
         gvt_q <= gvt;
         if (gvt_q > gvt) begin
            n_gvt_going_back <= n_gvt_going_back + 1;
            $display("gvt going back (%d,%d) -> (%d,%d)", gvt_q.ts, gvt_q.tb, gvt.ts, gvt.tb);
         end
      end
   end
end else begin
   assign lookup_mode = 1'b0;
   assign cq_size = 2**LOG_CQ_SLICE_SIZE;
   assign lookup_entry = 0;
end

logic [31:0] cq_state_stats [0:7];
logic [31:0] deq_stats [0:N_TASK_TYPES-1];
logic [31:0] commit_stats [0:N_TASK_TYPES-1];
logic [31:0] n_resource_aborts;
logic [31:0] n_gvt_aborts;
logic [31:0] stall_cycles_cq_full;
logic [31:0] stall_cycles_cc_full;
logic [31:0] stall_cycles_no_task;

// tasks who did not have any same locale tasks on dequeue
logic [31:0] n_tasks_no_conflict;
// has same locale tasks, but conflict checks were skipped because the cache was
// effective
logic [31:0] n_tasks_conflict_mitigated;
// has same locale tasks, but could not skip conflict checks because cache miss
logic [31:0] n_tasks_conflict_miss; 
// has same locale tasks which were real conflicts
logic [31:0] n_tasks_real_conflict; 



// Task currently in the FSM, dequeued from TQ but not enqueued to FIFOs
task_t cur_task;
cq_slice_slot_t cur_task_slot;

// candidate task whose undo log needs to be restored

vt_array TS_ARRAY 
(
   .clk(clk),
   .rstn(rstn),

   .r_addr_1(ts_array_raddr),
   .r_addr_2(),
   .r_lvt_index(lvt_cycle),

   .w_addr(out_task_slot),

   .rdata_1(check_vt),
   .rdata_2(),

   .rdata_lvt(rdata_lvt), 

   .wdata(ts_write_data),
   .w_valid(ts_write_valid)
);
logic [2**LOG_CQ_SLICE_SIZE-1:0] cq_conflict, reg_conflict;
logic [2**LOG_CQ_SLICE_SIZE-1:0] cq_next_idle_in;

epoch_t cur_task_epoch;
tq_slot_t cur_task_tq_slot;

logic last_deq_ts_cache_hit; 
ts_t  last_deq_ts_cache_ts;

last_deq_ts_cache TS_CACHE 
(
   .clk(clk),
   .rstn(rstn),
   
   .query_locale(deq_task.locale),
   .query_out_valid(last_deq_ts_cache_hit),
   .query_out_ts(last_deq_ts_cache_ts),

   .wr_en(ts_write_valid),
   .write_locale(out_task.locale),
   .write_ts(out_task.ts),
   .wr_read_only(out_task.no_write)

);

locale_t bloom_query_locale;
logic [2**LOG_CQ_SLICE_SIZE-1:0] bloom_query_out_conflict;
logic bloom_wr_en;
cq_slice_slot_t bloom_wr_cq_slot; 
locale_t bloom_wr_locale; 
logic bloom_wr_set; 

assign bloom_query_locale = {1'b0, deq_task.locale[30:0]};

locale_t ref_locale;
logic  ref_read_only;
locale_bloom_filters locale_BLOOM
(
   .clk(clk),
   .rstn(rstn),
   
   .query_locale(ref_locale),
   .query_out_conflict(bloom_query_out_conflict),

   .wr_en(bloom_wr_en),
   .write_slot(bloom_wr_cq_slot),
   .write_locale(bloom_wr_locale),
   .write_set(bloom_wr_set) // set-1, reset-0 
);

always_comb begin
   bloom_wr_en = 1'b0;
   bloom_wr_set = 'x;
   bloom_wr_locale = 'x;
   bloom_wr_cq_slot = 'x;
   if (state == IDLE) begin
      bloom_wr_cq_slot = deq_task_cq_slot;
      bloom_wr_locale = cq_locale[deq_task_cq_slot];
      bloom_wr_set = 0;
      if (deq_task_valid & deq_task_ready) begin
         bloom_wr_en = 1'b1;
      end
   end else if (state == DEQ_PUSH_TASK) begin
      bloom_wr_cq_slot = out_task_slot;
      bloom_wr_locale = {1'b0, out_task.locale[30:0]}; 
      bloom_wr_set = 1;
      if (out_task_valid & out_task_ready) begin
         bloom_wr_en = 1'b1;
      end
   end
end



assign resource_abort_start = (state == IDLE) 
            & deq_task_valid & ((deq_task.ts < max_vt_fixed.ts) |
                  // do not start resource abort if max_vt task just changed
                  // tq asserted force signal based on its previous value
                                 (deq_task_force & !(lvt_cycle == (LOG_CQ_TS_BANKS+1)))  )
            & cq_full 
            & (     (cq_state[max_vt_pos_fixed] == RUNNING) 
                  | (cq_state[max_vt_pos_fixed] == FINISHED)); 

assign cq_full =  (deq_task_cq_slot >= cq_size) ||  (cq_next_idle_in == 0);

always_comb begin
   if (state==IDLE) begin
      if (from_tq_abort_valid) begin
         ref_locale = cq_locale[from_tq_abort_slot];
         ref_read_only = cq_read_only_task[from_tq_abort_slot];
      end else if (resource_abort_start) begin
         ref_locale = cq_locale[max_vt_pos_fixed];
         ref_read_only = cq_read_only_task[max_vt_pos_fixed];
      end else begin
         ref_locale = deq_task.locale;
         ref_read_only = deq_task.no_write;
      end      
   end else begin
      ref_locale = cur_task.locale;
      ref_read_only = cur_task.no_write;
   end
end

genvar i;
for (i=0;i<2**LOG_CQ_SLICE_SIZE;i++) begin
   assign cq_conflict[i] = cq_valid[i] 
            & bloom_query_out_conflict[i]  
            // & (ref_locale[30:0] == cq_locale[i][30:0])
            // if MSB of locale is set, its a read-only locale. No conflicts between
            // RO tasks
            &  !(cq_read_only_task[i] & ref_read_only)
            & (cq_state[i] != ABORTED) &  (cq_state[i] != WAITING_CHILDREN) &
                     (cq_state[i] != UNDO_LOG_WAITING);
   assign cq_next_idle_in[i] = !cq_valid[i];
end


lowbit #(
   .OUT_WIDTH(LOG_CQ_SLICE_SIZE),
   .IN_WIDTH(2**LOG_CQ_SLICE_SIZE)
) CONFLICT_AT (
   .in(reg_conflict),
   .out(ts_check_id)
);

lowbit #(
   .OUT_WIDTH(LOG_CQ_SLICE_SIZE),
   .IN_WIDTH(2**LOG_CQ_SLICE_SIZE)
) NEXT_POS (
   .in(cq_next_idle_in),
   .out(deq_task_cq_slot)
);
/*
always_ff @(posedge clk) begin
   ts_check_id <= next_ts_check_id;
end
*/
logic commit_task_valid;
logic commit_task_ready;
cq_slice_slot_t commit_task_slot;

always_ff @(posedge clk) begin
   if (!rstn) begin
      should_terminate <= 1'b0;
   end else begin
      if (commit_task_valid & commit_task_ready & 
            cq_terminate_task[commit_task_slot] ) begin
         should_terminate <= 1'b1;
      end
   end
end

assign from_tq_abort_ready = (state == IDLE);

logic abort_ts_check_task;
logic in_tq_abort;
logic in_resource_abort;
logic in_gvt_induced_abort;


tb_t ref_tb;
cq_slice_slot_t reg_from_tq_abort_slot; // probably redundant with cur_task_slot


ts_t cur_task_ts; // cur_task.ts or child_abort_task_ts --> LVT
always_ff @(posedge clk) begin
   if (!rstn) begin
      state <= IDLE;
      in_tq_abort <= 1'b0;
      in_resource_abort <= 1'b0;
      in_gvt_induced_abort <= 1'b0;
      reg_conflict <= 0;
      cur_task <= 'x;
      reg_from_tq_abort_slot <= 'x;
      cur_task_slot <= 'x;
      cur_task_epoch <= 'x;
      cur_task_tq_slot <= 'x;
      undo_log_abort_pending <= 0;
   end else begin
      case (state) 
         IDLE: begin
            reg_conflict <= cq_conflict;
            if (from_tq_abort_valid & from_tq_abort_ready) begin
               state <= DEQ_CHECK_TS;
               in_tq_abort <= 1'b1;
               ref_tb <= check_vt.tb; 
               cur_task.ts <= check_vt.ts;
               cur_task.locale <= ref_locale;
               cur_task_slot <= from_tq_abort_slot;
               reg_from_tq_abort_slot <= from_tq_abort_slot;
            end else 
            if (deq_task_valid & deq_task_ready) begin
               cur_task <= deq_task;
               if (should_terminate) begin
                  cur_task.ttype <= TASK_TYPE_TERMINATE;
               end
               cur_task_slot <= deq_task_cq_slot;
               cur_task_epoch <= deq_task_epoch;
               cur_task_tq_slot <= deq_task_tq_slot;
               if (cq_conflict == 0) begin
                  state <= DEQ_PUSH_TASK;
               end else begin
                  if ( !use_ts_cache | !last_deq_ts_cache_hit |
                        (deq_task.ts < last_deq_ts_cache_ts) ) begin
                     // bypass conflict checks if dequeing a task with a larger
                     // ts than the previous dequeued task of the same locale
                     state <= DEQ_CHECK_TS;
                  end else begin
                     state <= DEQ_PUSH_TASK;
                  end
               end
               cq_terminate_task[deq_task_cq_slot] <= 
                     (deq_task.ttype == TASK_TYPE_TERMINATE);
            end else 
            if (resource_abort_start) begin
               state <= DEQ_CHECK_TS;
               in_resource_abort <= 1'b1;
               ref_tb <= max_vt_fixed.tb;
               cur_task.ts <= max_vt_fixed.ts;
               cur_task.locale <= ref_locale;
            end 
            undo_log_abort_max_ts <= '1;
         end
         DEQ_CHECK_TS: begin
            if (reg_conflict ==0) begin
               state <= (undo_log_abort_max_ts < '1) ? UNDO_LOG_RESTORE : DEQ_PUSH_TASK;
            end else begin
               if (abort_ts_check_task) begin
                  if (cq_state[ts_check_id] == FINISHED) begin
                     if (!s_abort_children_valid | s_abort_children_ready) begin
                        state <= ABORT_REQUEUE;
                     end
                  end else if (cq_state[ts_check_id] == RUNNING) begin
                     state <= ABORT_REQUEUE;
                  end
                  if (check_vt < undo_log_abort_max_ts) begin
                     undo_log_abort_max_ts <= check_vt;
                     undo_log_abort_max_ts_index <= ts_check_id;
                  end
               end else begin
                  reg_conflict[ts_check_id] <= 1'b0;
                  state <= DEQ_CHECK_TS;
               end
            end
         end
         ABORT_REQUEUE: begin
            if (to_tq_abort_valid & to_tq_abort_ready | 
                  // Do not requeue the task from a task_queue induced abort,
                  // but requeue later ts tasks with the same locale
                  ( in_tq_abort & (reg_from_tq_abort_slot == ts_check_id)) ) begin
                  // no special treatment for resource aborts, they should
                  // requeue 
               state <= DEQ_CHECK_TS;
               reg_conflict[ts_check_id] <= 1'b0;
            end
         end
         UNDO_LOG_RESTORE: begin
            if (out_task_valid & out_task_ready) begin
               state <= DEQ_PUSH_TASK;
            end
         end
         DEQ_PUSH_TASK: begin
            if ((out_task_valid & out_task_ready) | in_tq_abort | in_resource_abort
                  | in_gvt_induced_abort) begin
               state <= IDLE;
               in_tq_abort <= 1'b0;
               in_resource_abort <= 1'b0;
               in_gvt_induced_abort <= 1'b0;
            end
         end
      endcase
   end
end


always_comb begin
   if (state == DEQ_PUSH_TASK) begin
      out_task_valid = !in_tq_abort & !in_resource_abort & !in_gvt_induced_abort;
      out_task = cur_task;
      out_task_slot = cur_task_slot;
   end else if (state == UNDO_LOG_RESTORE) begin
      out_task_valid = 1'b1; 
      out_task.ttype = TASK_TYPE_UNDO_LOG_RESTORE;
      out_task.locale = cur_task.locale;
      out_task.ts = 'x;
      out_task.args = 'x;
      out_task.no_read = 1'b1;
      out_task.no_write = 1'b0;
      out_task.producer = 1'b0;
      // other fields doesn't matter
      out_task_slot = undo_log_abort_max_ts_index;
   end else begin
      out_task_valid = 1'b0;
      out_task = 'x;
      out_task_slot = 'x;
   end

end

vt_t ref_vt;
always_comb begin
   ref_vt.ts = cur_task.ts;
   if (in_tq_abort | in_resource_abort) begin
      ref_vt.tb = ref_tb;
   end else if (in_gvt_induced_abort) begin
      ref_vt = gvt;
   end else begin
      ref_vt.tb = cur_cycle[TB_WIDTH-1:0];
   end
end


assign abort_ts_check_task = (state == DEQ_CHECK_TS) 
   & (check_vt >= ref_vt) 
   & (cur_task.locale == cq_locale[ts_check_id]) // not a false hit in BF 
   & (reg_conflict != 0);

`ifdef XILINX_SIMULATOR
always_ff @(posedge clk) begin
   if (abort_ts_check_task) begin
      $display("Abort cq slot %3d", ts_check_id);
   end
end
`endif

always_comb begin
   s_abort_children_valid = 1'b0;
   s_abort_children_cq_slot = 'x;
   s_abort_children_count = 0;
   if (state == DEQ_CHECK_TS) begin
      if (abort_ts_check_task & (cq_state[ts_check_id] == FINISHED)
            & (cq_num_children[ts_check_id] > 0) ) begin
         s_abort_children_valid = 1'b1;
         s_abort_children_cq_slot = ts_check_id;
         s_abort_children_count = cq_num_children[ts_check_id];
      end
   end else if (finish_task_valid & finish_task_ready &
         task_aborted[finish_task_slot] & finish_task_num_children >0) begin
      s_abort_children_valid = 1'b1;
      s_abort_children_cq_slot = finish_task_slot;
      s_abort_children_count = finish_task_num_children;
   end
end

child_id_t commit_children_count;
assign commit_children_count = cq_num_children[commit_task_slot];


assign deq_task_ready = (state == IDLE) & !from_tq_abort_valid & 
            !cq_full &
            // if cc is almost full, only let the gvt task proceed
            (!cc_almost_full | (deq_task_valid & ((deq_task.ts == gvt.ts) | deq_task_force))) 
            ; 


// Commit Task
logic tq_commit_task_can_take_new;
logic cut_ties_can_take_new;
assign tq_commit_task_can_take_new = (!tq_commit_task_valid | (tq_commit_task_valid & tq_commit_task_ready));
assign cut_ties_can_take_new = (!cut_ties_valid | (cut_ties_valid & cut_ties_ready));
assign commit_task_ready = tq_commit_task_can_take_new & cut_ties_can_take_new;
logic commit_task_epoch_match;


always_ff @(posedge clk) begin
   if (!rstn) begin
      tq_commit_task_valid <= 1'b0;
      cut_ties_valid <= 1'b0;
      tq_commit_task_slot <= 'x;
      tq_commit_task_epoch <= 'x;
      cut_ties_cq_slot <= 'x;
      cut_ties_cq_slot <= 'x;
      cut_ties_num_children <= 'x;
   end else begin
      if (commit_task_valid & commit_task_ready) begin
         tq_commit_task_valid <= 1'b1;
         tq_commit_task_slot <= cq_tq_slot[commit_task_slot];
         tq_commit_task_epoch <= tq_epoch[commit_task_slot];
      end else begin
         if (tq_commit_task_valid & tq_commit_task_ready) begin
            tq_commit_task_valid <= 1'b0;
         end
      end
      if (commit_task_valid & commit_task_ready & commit_children_count !=0) begin
         cut_ties_valid <= 1'b1;
         cut_ties_cq_slot <= commit_task_slot;
         cut_ties_num_children <= commit_children_count;
      end else begin
         if (cut_ties_valid & cut_ties_ready) begin
            cut_ties_valid <= 1'b0;
         end
      end
   end
end



assign to_tq_abort_valid = (state == ABORT_REQUEUE) & 
                            !( in_tq_abort & (reg_from_tq_abort_slot == ts_check_id));
assign to_tq_abort_slot = cq_tq_slot[ts_check_id];
assign to_tq_abort_epoch = tq_epoch[ts_check_id];
// The task unit needs to know which ts to enq back into the heap.
// Reading it from its task_array BRAM is a 2 cycle operation.
// TQ logic can be simplified if the CQ can provide this timestamp
assign to_tq_abort_ts = check_vt.ts; 

always_comb begin
   if ( (state == DEQ_CHECK_TS) || (state == ABORT_REQUEUE) || (state == UNDO_LOG_RESTORE)) begin  
      // conflict on abort_children
      finish_task_ready = 1'b0; 
      abort_ack_ready = 1'b0;
   end else begin
      abort_ack_ready = 1'b1;
      finish_task_ready = finish_task_valid; 
   end
end

assign cut_ties_ack_ready = 1'b1;

cq_slice_slot_t cur_ts_read_indices [0:2**LOG_CQ_TS_BANKS-1];
cq_state_t cur_ts_read_state [0:2**LOG_CQ_TS_BANKS-1];
logic [2**LOG_CQ_TS_BANKS-1:0] cur_ts_read_task_can_commit;

logic [LOG_CQ_TS_BANKS-1:0] cur_ts_read_commit_index;

lowbit #(
   .OUT_WIDTH(LOG_CQ_TS_BANKS),
   .IN_WIDTH(2**LOG_CQ_TS_BANKS)
) COMMIT_TASK_SELECT (
   .in(cur_ts_read_task_can_commit),
   .out(cur_ts_read_commit_index)
);

assign commit_task_slot = cur_ts_read_indices[cur_ts_read_commit_index];
assign commit_task_valid = cur_ts_read_task_can_commit[cur_ts_read_commit_index];

logic abort_task_at [0:2**LOG_CQ_SLICE_SIZE-1];

for (i=0;i<2**LOG_CQ_SLICE_SIZE;i++) begin
   assign cq_valid[i] = (cq_state[i] != UNUSED);
   assign abort_task_at[i] = (ts_check_id == i) & abort_ts_check_task;
   assign task_aborted[i] = (cq_state[i] == ABORTED);
   always_ff @(posedge clk) begin
      if (!rstn) begin
         cq_state[i] <= UNUSED;
      end else begin
         case (cq_state[i]) 
            UNUSED: begin
               if (out_task_valid & out_task_ready) begin
                  if (state== DEQ_PUSH_TASK & (i==out_task_slot) ) begin
                     cq_state[i] <= RUNNING;
                  end
               end
            end
            RUNNING: begin
               if (abort_task_at[i]) begin
                  cq_state[i] <= ABORTED;
               end else if (finish_task_valid & finish_task_ready & (finish_task_slot == i)) begin
                  cq_state[i] <= FINISHED;
               end
            end
            FINISHED: begin
               if (commit_task_valid & commit_task_ready & (commit_task_slot == i)  )  begin
                  cq_state[i] <= (commit_children_count == 0) ? UNUSED : COMMITTED;
               end else if (abort_task_at[i]) begin
                  if (s_abort_children_count == 0) begin
                     if (check_vt < undo_log_abort_max_ts) begin // potential undo_log_write
                        cq_state[i] <= UNDO_LOG_WAITING;
                     end else begin
                        cq_state[i] <= UNUSED;
                     end
                  end else if (s_abort_children_valid & s_abort_children_ready) begin
                     cq_state[i] <= WAITING_CHILDREN;
                  end
               end
            end
            COMMITTED: begin
               if (cut_ties_ack_valid & cut_ties_ack_ready & (cut_ties_ack_cq_slot == i)  )  begin
                  cq_state[i] <= UNUSED;
               end 
            end
            ABORTED: begin
               if (finish_task_valid & finish_task_ready &
                     (finish_task_slot == i) &
                     !finish_task_is_undo_log_restore) begin
                  if (s_abort_children_valid & s_abort_children_ready) begin
                     cq_state[i] <= WAITING_CHILDREN;
                  end else if (cq_undo_log_ack_pending[i]) begin
                     cq_state[i] <= UNDO_LOG_WAITING;
                  end else begin
                     cq_state[i] <= UNUSED;
                  end
               end
            end
            WAITING_CHILDREN: begin
               if (abort_ack_valid & abort_ack_ready & (abort_ack_cq_slot ==i)) begin
                  if (cq_undo_log_ack_pending[i]) begin
                     cq_state[i] <= UNDO_LOG_WAITING;
                  end else begin
                     cq_state[i] <= UNUSED;
                  end
               end
            end
            UNDO_LOG_WAITING: begin
               if ( (state == DEQ_CHECK_TS) || (state == ABORT_REQUEUE) || (state == UNDO_LOG_RESTORE)) begin  
                  // do not do anything. undo_log_ack_pending is valid only
                  // after UNDO_LOG_RESTRORE
               end else if (!cq_undo_log_ack_pending[i]) begin
                  cq_state[i] <= UNUSED;
               end
            end
         endcase
      end
   end
end

initial begin
   for (integer j=0;j<2**LOG_CQ_SLICE_SIZE;j=j+1) begin
      cq_undo_log_ack_pending[j] = 0;
   end
end
always_ff @(posedge clk) begin
   if (state == UNDO_LOG_RESTORE) begin 
      cq_undo_log_ack_pending[undo_log_abort_max_ts_index] <= 1'b1;
   end else if (finish_task_valid & finish_task_ready & finish_task_is_undo_log_restore) begin
      cq_undo_log_ack_pending[finish_task_slot] <= 1'b0;
   end
end

always_ff @(posedge clk) begin
   if (state==DEQ_PUSH_TASK & out_task_valid & out_task_ready) begin
      tq_epoch  [out_task_slot] <= cur_task_epoch;
      cq_tq_slot[out_task_slot] <= cur_task_tq_slot;
      cq_locale [out_task_slot] <= out_task.locale;
      cq_read_only_task [out_task_slot] <= out_task.no_write;
      cq_ttype[out_task_slot] <= out_task.ttype;

   end
end

always_ff @(posedge clk) begin
   if (finish_task_valid & finish_task_ready) begin
      cq_num_children[finish_task_slot] <= finish_task_num_children;
   end
end
 

// Need to buffer abort_children requests since the main FSM cannot handle
// when s_abort_children_valid & !s_abort_children_ready; A FIFO the the size of 
// CQ size ensures this does not happen
fifo #(
      .WIDTH( $bits(s_abort_children_cq_slot) + $bits(s_abort_children_count)),
      .LOG_DEPTH(LOG_CQ_SLICE_SIZE)
   ) ABORT_CHILDREN_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(s_abort_children_valid & s_abort_children_ready),
      .wr_data({s_abort_children_cq_slot, s_abort_children_count}),

      .full(abort_children_fifo_full),
      .empty(abort_children_fifo_empty),

      .rd_en(abort_children_valid & abort_children_ready),
      .rd_data({abort_children_cq_slot, abort_children_count})

   );

assign abort_children_valid = !abort_children_fifo_empty;
assign s_abort_children_ready = !abort_children_fifo_full;


logic [31:0] cycles_in_resource_abort;
logic [31:0] cycles_in_gvt_abort;

logic [63:0] cum_commit_cycles;
logic [63:0] cum_abort_cycles;

logic [47:0] cum_occ;
logic [31:0] start_task_cycle [0:2**LOG_CQ_SLICE_SIZE-1];
logic [31:0] task_cycles [0:2**LOG_CQ_SLICE_SIZE-1];

if (CQ_STATS[TILE_ID]) begin
   initial begin
      for (integer i=0;i<8;i++) begin
         cq_state_stats[i] = 0;
      end
      for (integer i=0;i<N_TASK_TYPES;i++) begin
         deq_stats[i] = 0;
         commit_stats[i] = 0;
      end
   end
   always_ff@(posedge clk) begin
      if (deq_task_valid & deq_task_ready) begin
         deq_stats[ deq_task.ttype] <= deq_stats[deq_task.ttype] + 1;
      end
      if (commit_task_valid & commit_task_ready) begin
         commit_stats[ cq_ttype[commit_task_slot] ] <= 
            commit_stats[ cq_ttype[commit_task_slot] ] + 1; 
      end
   end

   always_ff @(posedge clk) begin
      if (finish_task_valid & finish_task_ready & !finish_task_is_undo_log_restore) begin
         task_cycles[ finish_task_slot] <= (cur_cycle - start_task_cycle[finish_task_slot]); 
      end
      if (!rstn) begin
         cum_commit_cycles <= 0;
         cum_abort_cycles <= 0;
      end else begin
         if (commit_task_valid & commit_task_ready) begin
            cum_commit_cycles <= cum_commit_cycles + task_cycles[commit_task_slot];
         end
         if (to_tq_abort_valid & to_tq_abort_ready | 
                  ( in_tq_abort & (reg_from_tq_abort_slot == ts_check_id)) ) begin
            cum_abort_cycles <= cum_abort_cycles + task_cycles[ts_check_id]; 
         end
      end
   end

   // Turn these off because they are in the critical path
   /*
   always_ff @(posedge clk) begin
      if (!rstn) begin
         n_tasks_no_conflict <= 0;
         n_tasks_conflict_mitigated <= 0;
         n_tasks_conflict_miss <= 0;
         n_tasks_real_conflict <= 0;
      end else begin
         if (deq_task_valid & deq_task_ready) begin
            if (cq_conflict == 0) begin
               n_tasks_no_conflict <= n_tasks_no_conflict + 1;
            end else begin
               if (!use_ts_cache) begin
                  n_tasks_real_conflict <= n_tasks_real_conflict + 1;
               end else if (!last_deq_ts_cache_hit) begin
                  n_tasks_conflict_miss <= n_tasks_conflict_miss + 1;
               end else if (deq_task.ts < last_deq_ts_cache_ts) begin
                  n_tasks_real_conflict <= n_tasks_real_conflict + 1;
               end else begin
                  n_tasks_conflict_mitigated <= n_tasks_conflict_mitigated + 1;
               end
            end
         end
      end
   end
   */
   
   logic [7:0] cq_occupancy;
   logic cq_occ_inc;
   logic cq_occ_dec_commit;
   logic cq_occ_dec_task_abort;
   logic cq_occ_dec_child_abort;
   assign cq_occ_inc = (deq_task_valid & deq_task_ready);
   assign cq_occ_dec_commit = (tq_commit_task_valid & tq_commit_task_ready);
   assign cq_occ_dec_task_abort = (to_tq_abort_valid & to_tq_abort_ready);
   assign cq_occ_dec_child_abort = (from_tq_abort_valid & from_tq_abort_ready) & 
                     !(cq_occ_dec_task_abort & (ts_check_id == from_tq_abort_slot));
   always_ff @(posedge clk) begin
      if (!rstn) begin
         cq_occupancy <= 0;
         cum_occ <= 0;
      end else begin
         cq_occupancy <= cq_occupancy + cq_occ_inc - 
                         (cq_occ_dec_commit + cq_occ_dec_task_abort + 
                          cq_occ_dec_child_abort);
         //cum_occ <=  cum_occ + cq_occupancy;
         //Ugly hack before the deadline FIXME
         cum_occ <=  cum_occ + (cq_valid[cur_cycle[LOG_CQ_SLICE_SIZE-1:0]]);
      end

   end


   always_ff@(posedge clk) begin
      if (!rstn) begin
         n_resource_aborts <= 0;
         n_gvt_aborts <= 0;
         stall_cycles_cc_full <= 0;
         stall_cycles_cq_full <= 0;
         stall_cycles_no_task <= 0;
         cycles_in_resource_abort <= 0;
         cycles_in_gvt_abort <= 0;
      end else begin
         if (in_resource_abort) begin
            cycles_in_resource_abort <= cycles_in_resource_abort + 1;
            if (state == DEQ_PUSH_TASK) begin
               n_resource_aborts <= n_resource_aborts + 1;
            end
         end
         if (in_gvt_induced_abort) begin
            cycles_in_gvt_abort <= cycles_in_gvt_abort + 1;
            if (state == DEQ_PUSH_TASK) begin
               n_gvt_aborts <= n_gvt_aborts + 1;
            end
         end
         if (cq_valid != 0) begin
            cq_state_stats[state] <= cq_state_stats[state] + 1;
            if (state == IDLE) begin
               if (!from_tq_abort_valid) begin
                  if (cq_full) begin
                     stall_cycles_cq_full <= stall_cycles_cq_full + 1;
                  end else if (!deq_task_valid) begin 
                     stall_cycles_no_task <= stall_cycles_no_task + 1;
                  end else if (cc_almost_full) begin
                     stall_cycles_cc_full <= stall_cycles_cc_full + 1;
                  end
               end
            end
         end
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_bus.rvalid <= 1'b0;
      reg_bus.rdata <= 'x;
   end else
   if (reg_bus.arvalid) begin
      reg_bus.rvalid <= 1'b1;
      casex (reg_bus.araddr) 
         DEBUG_CAPACITY : reg_bus.rdata <= log_size;
         CQ_STATE  : reg_bus.rdata <= state;
         CQ_LOOKUP_STATE : reg_bus.rdata <= cq_state[lookup_entry];
         CQ_LOOKUP_LOCALE  : reg_bus.rdata <= cq_locale[lookup_entry];
         CQ_LOOKUP_TS    : reg_bus.rdata <= check_vt.ts;
         CQ_LOOKUP_TB    : reg_bus.rdata <= check_vt.tb;
         CQ_GVT_TS       : reg_bus.rdata <= gvt.ts;
         CQ_GVT_TB       : reg_bus.rdata <= gvt.tb;
         CQ_MAX_VT_POS   : reg_bus.rdata <= max_vt_pos_fixed;
         CQ_DEQ_TASK_TS  : reg_bus.rdata <= deq_task.ts;
         
         CQ_STATE_STATS  : reg_bus.rdata <= cq_state_stats[reg_bus.araddr[4:2]];

         CQ_STAT_N_RESOURCE_ABORTS : reg_bus.rdata <= n_resource_aborts;
         CQ_STAT_N_GVT_ABORTS      : reg_bus.rdata <= n_gvt_aborts;
         CQ_STAT_N_IDLE_CQ_FULL    : reg_bus.rdata <= stall_cycles_cq_full;
         CQ_STAT_N_IDLE_CC_FULL    : reg_bus.rdata <= stall_cycles_cc_full;
         CQ_STAT_N_IDLE_NO_TASK    : reg_bus.rdata <= stall_cycles_no_task;
         
         CQ_STAT_CYCLES_IN_RESOURCE_ABORT : reg_bus.rdata <= cycles_in_resource_abort;
         CQ_STAT_CYCLES_IN_GVT_ABORT : reg_bus.rdata <= cycles_in_gvt_abort;
         
         CQ_CUM_OCC_LSB : reg_bus.rdata <= cum_occ[31:0];
         CQ_CUM_OCC_MSB : reg_bus.rdata <= cum_occ[47:32];
         
         CQ_DEQ_TASK_STATS : reg_bus.rdata <= deq_stats[lookup_entry];
         CQ_COMMIT_TASK_STATS : reg_bus.rdata <= commit_stats[lookup_entry];
         
         CQ_N_GVT_GOING_BACK : reg_bus.rdata <= n_gvt_going_back;
         
         CQ_N_TASK_NO_CONFLICT : reg_bus.rdata <= n_tasks_no_conflict;
         CQ_N_TASK_CONFLICT_MITIGATED : reg_bus.rdata <= n_tasks_conflict_mitigated;
         CQ_N_TASK_CONFLICT_MISS : reg_bus.rdata <= n_tasks_conflict_miss;
         CQ_N_TASK_REAL_CONFLICT : reg_bus.rdata <= n_tasks_real_conflict;

         CQ_N_CUM_COMMIT_CYCLES_H : reg_bus.rdata <= cum_commit_cycles[63:32];
         CQ_N_CUM_COMMIT_CYCLES_L : reg_bus.rdata <= cum_commit_cycles[31: 0];
         CQ_N_CUM_ABORT_CYCLES_H : reg_bus.rdata <= cum_abort_cycles[63:32];
         CQ_N_CUM_ABORT_CYCLES_L : reg_bus.rdata <= cum_abort_cycles[31: 0];
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end  


logic [2**LOG_CQ_TS_BANKS-1:0] cur_ts_is_gvt;
logic [LOG_CQ_TS_BANKS-1:0] cur_ts_gvt_index;

lowbit #(
   .OUT_WIDTH(LOG_CQ_TS_BANKS),
   .IN_WIDTH(2**LOG_CQ_TS_BANKS)
) GVT_TASK_INDEX (
   .in(cur_ts_is_gvt),
   .out(cur_ts_gvt_index)
);

always_ff @(posedge clk) begin
   if (!rstn) begin
      gvt_task_slot_valid <= 1'b0;
      gvt_task_slot <= 'x;
   end else begin 
      if (finish_task_valid & finish_task_ready & (finish_task_slot == gvt_task_slot)) begin
         gvt_task_slot_valid <= 1'b0;
      end else if (commit_task_valid & commit_task_ready & 
                     (commit_task_slot == gvt_task_slot)) begin
         gvt_task_slot_valid <= 1'b0;
      end else if (cur_ts_is_gvt != 0) begin
         gvt_task_slot_valid <= 1'b1;
         gvt_task_slot <= cur_ts_read_indices[cur_ts_gvt_index]; 
      end
   end
end

vt_t min_tree [LOG_CQ_TS_BANKS+1][2**LOG_CQ_TS_BANKS];
vt_t max_tree [LOG_CQ_TS_BANKS+1][2**LOG_CQ_TS_BANKS];
cq_slice_slot_t max_tree_index [LOG_CQ_TS_BANKS+1][2**LOG_CQ_TS_BANKS];
   for (i=0;i<2**LOG_CQ_TS_BANKS;i++) begin
      assign cur_ts_read_indices[i] = (i<<LOG_GVT_PERIOD) | lvt_cycle;
      assign cur_ts_read_state  [i] = cq_state[cur_ts_read_indices[i]];
      assign min_tree[LOG_CQ_TS_BANKS][i]   = 
         ((cur_ts_read_state[i] == UNUSED) || 
          (cur_ts_read_state[i] == COMMITTED) || 
          (cur_ts_read_state[i] == FINISHED)) 
            ? '1 : rdata_lvt[i];
      assign max_tree[LOG_CQ_TS_BANKS][i]   = 
         ((cur_ts_read_state[i] == UNUSED) || 
          (cur_ts_read_state[i] == COMMITTED) || 
          (cur_ts_read_state[i] == UNDO_LOG_WAITING) || 
          (cur_ts_read_state[i] == ABORTED)) 
            ? '0 : rdata_lvt[i];
      assign max_tree_index[LOG_CQ_TS_BANKS][i] = (i<<LOG_GVT_PERIOD | lvt_cycle);
      assign cur_ts_read_task_can_commit[i] = (cur_ts_read_state[i] == FINISHED)
               & (gvt > rdata_lvt[i]);
      assign cur_ts_is_gvt[i] =  (gvt == rdata_lvt[i]) & (cur_ts_read_state[i] != UNUSED);
   end
genvar j;
   for (i=LOG_CQ_TS_BANKS-1;i>=0;i--) begin
      for (j=0;j< 2**i;  j++) begin
         always_ff @(posedge clk) begin
            min_tree[i][j] <= (min_tree[i+1][j*2] < min_tree[i+1][j*2+1]) ? 
                                       min_tree[i+1][j*2] : min_tree[i+1][j*2+1];
         end
         always_ff @(posedge clk) begin
            if (max_tree[i+1][j*2] > max_tree[i+1][j*2+1]) begin
               max_tree[i][j] <= max_tree[i+1][j*2];
               max_tree_index[i][j] <= max_tree_index[i+1][j*2];
            end else begin
               max_tree[i][j] <= max_tree[i+1][j*2+1];
               max_tree_index[i][j] <= max_tree_index[i+1][j*2+1];
            end
         end
      end
   end
if (COMMIT_QUEUE_LOGGING[TILE_ID]) begin
   logic log_valid;
   typedef struct packed {
      ts_t gvt_tb;
      ts_t gvt_ts;

      //32
      logic out_task_valid;
      logic out_task_ready;
      logic [6:0] out_task_cq_slot;
      logic [3:0] out_task_ttype;
      logic [18:0] out_task_locale;


      // 32 
      logic cut_ties_valid;
      logic cut_ties_ready;
      logic [6:0] cut_ties_cq_slot;
      logic [3:0] cut_ties_count;
      logic [18:0] unused_cut_ties;

      // 32 
      logic abort_children_valid;
      logic abort_children_ready;
      logic [6:0] abort_children_cq_slot;
      logic [3:0] abort_children_count;
      logic [18:0] unused_abort_children;
      
      // 32
      logic start_task_valid;
      logic start_task_ready;
      logic [5:0] start_task_core;
      logic [6:0] start_task_slot;
      logic [16:0] unused_1;
   
      // 32
      logic finish_task_valid;
      logic finish_task_ready;
      logic [6:0] finish_task_slot;
      logic [3:0] finish_task_num_children;
      logic finish_task_undo_log_write;
      logic [17:0] unused_2;
   
      // 32
      logic gvt_task_slot_valid;
      logic [6:0] gvt_task_slot;
      logic [6:0] abort_running_slot;
      logic [6:0] max_vt_slot;
      logic [9:0] unused_3;

      // 32
      logic to_tq_abort_valid;
      logic to_tq_resource_abort;
      logic to_tq_abort_ready;
      logic [3:0] state;
      logic [24:0] n_resource_aborts;

      logic [23:0] check_vt; 
      logic [6:0] ts_check_id;
      logic abort_ts_check_task;
      

   } cq_log_t;
   cq_log_t log_word;
   always_comb begin
      log_valid = 1'b0;

      log_word = '0;

      log_word.gvt_tb = gvt.tb;
      log_word.gvt_ts = gvt.ts;


      if (finish_task_valid & finish_task_ready) begin
         log_valid = 1'b1;
      end
      log_word.finish_task_valid = finish_task_valid;
      log_word.finish_task_ready = finish_task_ready;
      log_word.finish_task_slot = finish_task_slot;
      log_word.finish_task_num_children = finish_task_num_children;
      log_word.finish_task_undo_log_write = finish_task_is_undo_log_restore;

      log_word.gvt_task_slot_valid = gvt_task_slot_valid;
      log_word.gvt_task_slot = gvt_task_slot;
      log_word.max_vt_slot = max_vt_pos_fixed; 
     
      if (to_tq_abort_valid & to_tq_abort_ready) begin
         log_valid = 1'b1;
      end
      log_word.to_tq_abort_valid = to_tq_abort_valid;
      log_word.to_tq_abort_ready = to_tq_abort_ready;
      log_word.to_tq_resource_abort = in_resource_abort; 
      log_word.n_resource_aborts = n_resource_aborts; // to debug why this counter is so off
      //if (in_resource_abort) log_valid = 1'b1;

      if (s_abort_children_valid & s_abort_children_ready) begin
         log_valid = 1'b1;
      end
      log_word.abort_children_valid = s_abort_children_valid;
      log_word.abort_children_ready = s_abort_children_ready;
      log_word.abort_children_cq_slot = s_abort_children_cq_slot;
      log_word.abort_children_count = s_abort_children_count;

      if (cut_ties_valid & cut_ties_ready) begin
         log_valid = 1'b1;
      end
      log_word.cut_ties_valid = cut_ties_valid;
      log_word.cut_ties_ready = cut_ties_ready;
      log_word.cut_ties_cq_slot = cut_ties_cq_slot;
      log_word.cut_ties_count = cut_ties_num_children;
      if (out_task_valid & out_task_ready) begin
         log_valid = 1'b1;
      end
      log_word.out_task_valid = out_task_valid;
      log_word.out_task_ready = out_task_ready;
      log_word.out_task_cq_slot = out_task_slot;
      log_word.out_task_ttype = out_task.ttype;
      log_word.out_task_locale = out_task.locale;

      log_word.state = state;
      log_word.ts_check_id = ts_check_id;
      log_word.abort_ts_check_task = abort_ts_check_task;
      log_word.check_vt = check_vt.ts;
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

`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   integer file,r;
   string file_name;
   initial begin
      $sformat(file_name, "cq_%0d.log", 0);
      file = $fopen(file_name,"w");
   end
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
   end

   always_ff @(posedge clk) begin
      if (finish_task_valid & finish_task_ready & !finish_task_is_undo_log_restore) begin
         $fwrite(file,"[%5d] [cq-%2d] finish_task slot:%4d \n",
            cycle, 0, 
            finish_task_slot) ;
      end
      $fflush(file);
   end
`endif
// FIXED: minimum lvt in the last GVT period, rolling: minimum lvt in the
// current GVT period
ts_t cur_task_lvt_fixed_p;
vt_t cur_task_lvt_fixed;
ts_t cur_task_lvt_rolling;
if (LOG_CQ_TS_BANKS > 0) begin
lib_pipe #(
   .WIDTH(TS_WIDTH),
   .STAGES(LOG_CQ_TS_BANKS)
) LVT_TQ_PIPE (
   .clk(clk), 
   .rst_n(rstn),
   
   .in_bus ( cur_task_lvt_fixed_p ),
   .out_bus( cur_task_lvt_fixed.ts )
); 
end else begin
   assign cur_task_lvt_fixed.ts = cur_task_lvt_fixed_p;
end
tb_t cur_tb;
assign cur_tb[TB_WIDTH-1: LOG_GVT_PERIOD] = cur_cycle[TB_WIDTH-1:LOG_GVT_PERIOD] -1;
assign cur_tb[LOG_GVT_PERIOD-1:0] = 0;
assign cur_task_lvt_fixed.tb = cur_tb;

ts_t cur_task_lvt_ts;
assign cur_task_lvt_ts = (state != IDLE) ? cur_task.ts : '1;

vt_t array_lvt_fixed, array_lvt_rolling;

// Candidate task for resource aborts
always_ff @(posedge clk) begin
   if (!rstn) begin
      array_lvt_fixed <= 0;
      array_lvt_rolling <= 0;

      cur_task_lvt_fixed_p <= 0;
      cur_task_lvt_rolling <= 0;

      max_vt_fixed <= 0;
      max_vt_rolling <= 0;
   end else begin
      if (lvt_cycle == LOG_CQ_TS_BANKS) begin
         array_lvt_fixed <= array_lvt_rolling; 
         array_lvt_rolling <= min_tree[0][0];
      end else begin
         if (min_tree[0][0] < array_lvt_rolling) begin
            array_lvt_rolling <= min_tree[0][0];
         end
      end
      if (lvt_cycle == LOG_CQ_TS_BANKS) begin
         max_vt_fixed <= max_vt_rolling; 
         max_vt_rolling <= max_tree[0][0];
         max_vt_pos_rolling <= max_tree_index[0][0];
         max_vt_pos_fixed <= max_vt_pos_rolling;
      end else begin
         if (max_tree[0][0] > max_vt_rolling) begin
            max_vt_rolling <= max_tree[0][0];
            max_vt_pos_rolling <= max_tree_index[0][0];
         end
      end

      if (lvt_cycle == 0) begin
         cur_task_lvt_fixed_p <= cur_task_lvt_rolling;
         cur_task_lvt_rolling <= cur_task_lvt_ts;
      end else begin
         if (cur_task_lvt_ts <= cur_task_lvt_rolling) begin
            cur_task_lvt_rolling <= cur_task_lvt_ts;
         end
      end
      
      // In total, cq_lvt is delayed by (LOG_GVT_PERIOD+1) cycles 
      lvt <= (cur_task_lvt_fixed < array_lvt_fixed) ? cur_task_lvt_fixed : array_lvt_fixed;
   end   
end
end // else  NON_SPEC
endgenerate
endmodule

module vt_array 
(
   input clk,
   input rstn,

   input logic [LOG_CQ_SLICE_SIZE-1:0] r_addr_1,
   input logic [LOG_CQ_SLICE_SIZE-1:0] r_addr_2,
   input logic [LOG_GVT_PERIOD-1:0] r_lvt_index,

   input logic [LOG_CQ_SLICE_SIZE-1:0] w_addr,

   output vt_t rdata_1,
   output vt_t rdata_2,

   output vt_t [0:2**LOG_CQ_TS_BANKS-1] rdata_lvt, 

   input vt_t wdata,
   logic w_valid
);

typedef ts_t [0:2**LOG_GVT_PERIOD -1] ts_bank;
typedef tb_t [0:2**LOG_GVT_PERIOD -1] tb_bank;

ts_bank arr_ts [0:2**LOG_CQ_TS_BANKS -1];
tb_bank arr_tb [0:2**LOG_CQ_TS_BANKS -1];
vt_t read_out_1 [0:2**LOG_CQ_TS_BANKS-1];
vt_t read_out_2 [0:2**LOG_CQ_TS_BANKS-1];
generate genvar i;

for (i=0;i<2**LOG_CQ_TS_BANKS;i++) begin
   assign read_out_1[i].ts = arr_ts[i][r_addr_1[LOG_GVT_PERIOD-1:0]];
   assign read_out_1[i].tb = arr_tb[i][r_addr_1[LOG_GVT_PERIOD-1:0]];
   assign read_out_2[i].ts = arr_ts[i][r_addr_2[LOG_GVT_PERIOD-1:0]];
   assign read_out_2[i].tb = arr_tb[i][r_addr_2[LOG_GVT_PERIOD-1:0]];
   if (LOG_CQ_TS_BANKS ==0) begin
      always @(posedge clk) begin
         if (w_valid) begin
            arr_ts[i][w_addr[LOG_GVT_PERIOD-1:0]] <= wdata.ts;
            arr_tb[i][w_addr[LOG_GVT_PERIOD-1:0]] <= wdata.tb;
         end
      end
   end else begin
      always @(posedge clk) begin
         if (w_valid & (w_addr[LOG_CQ_SLICE_SIZE-1:LOG_GVT_PERIOD]==i)) begin
            arr_ts[i][w_addr[LOG_GVT_PERIOD-1:0]] <= wdata.ts;
            arr_tb[i][w_addr[LOG_GVT_PERIOD-1:0]] <= wdata.tb;
         end
      end
   end
   assign rdata_lvt[i].ts = arr_ts[i][r_lvt_index];
   assign rdata_lvt[i].tb = arr_tb[i][r_lvt_index];
end

if (LOG_CQ_TS_BANKS ==0 ) begin
   assign rdata_1 = read_out_1[0];
   assign rdata_2 = read_out_2[0];
end else begin
   assign rdata_1 = read_out_1[r_addr_1[LOG_CQ_SLICE_SIZE-1:LOG_GVT_PERIOD]];
   assign rdata_2 = read_out_2[r_addr_2[LOG_CQ_SLICE_SIZE-1:LOG_GVT_PERIOD]];
end
endgenerate
endmodule

// looks up of the last dequeued ts for a given ts
// used to accelerate conflict detection where if the currently dequeued task
// comes after the last dequeued ts for the same locale, then no conflict
// detection is required.
module last_deq_ts_cache 
(
   input clk,
   input rstn,

   input locale_t query_locale,
   output logic query_out_valid,
   output ts_t query_out_ts,

   input wr_en,
   input locale_t write_locale,
   input ts_t   write_ts,
   input wr_read_only
);
generate
if (LOG_LAST_DEQ_VT_CACHE >0) begin
   locale_t tag  [0:2**LOG_LAST_DEQ_VT_CACHE-1];
   ts_t data   [0:2**LOG_LAST_DEQ_VT_CACHE-1];

   // skip bits[4+LOG_N_TILES -1:4] in indexing, since they may be constant if the task is
   // mapped to the current tile.
   logic [LOG_LAST_DEQ_VT_CACHE-1:0] rd_addr;
   assign rd_addr = {query_locale[(LOG_N_TILES+4)+:(LOG_LAST_DEQ_VT_CACHE-4)],  query_locale[3:0]};
   logic [LOG_LAST_DEQ_VT_CACHE-1:0] wr_addr;
   assign wr_addr =  {write_locale[(LOG_N_TILES+4)+:(LOG_LAST_DEQ_VT_CACHE-4)],  write_locale[3:0]};
   initial begin
      for (integer i=0;i<2**LOG_LAST_DEQ_VT_CACHE;i+=1) begin
         tag[i] = 0;
         data[i] = 0;
      end
   end
   assign query_out_valid = (tag[rd_addr] == query_locale);
   assign query_out_ts = data[rd_addr];
   // a read-only task may not have aborted all its successors. Therefore its
   // not safe to update the last_deq_ts with current task's ts
   ts_t current_ts;
   assign current_ts = (tag[wr_addr] == write_locale) ? data[wr_addr] : 0;
   ts_t new_write_ts;
   always_comb begin
      new_write_ts = write_ts;
      if (wr_read_only == 1'b1) begin
         if (current_ts > write_ts) begin
            new_write_ts = current_ts;
         end
      end
   end
   
   always_ff @(posedge clk) begin
      if (wr_en) begin
         tag[wr_addr] <= write_locale;
         data[wr_addr] <= new_write_ts;
      end
   end
end else begin
   assign query_out_valid = 1'b0;
end

endgenerate
endmodule

module locale_bloom_filters
(
   input clk,
   input rstn,

   input locale_t query_locale,
   output logic [2**LOG_CQ_SLICE_SIZE-1:0] query_out_conflict,

   input wr_en,
   input cq_slice_slot_t write_slot,
   input locale_t write_locale,
   input write_set // set-1, reset-0 
);

   localparam N_FILTERS = 4;
   localparam FILTER_DEPTH = 16;


   filter_entry_t [N_FILTERS-1:0]  filter_out;


   generate
   genvar i;
      for (i=0;i<N_FILTERS;i=i+1) begin
         bloom_bank #(
            .FILTER_DEPTH(FILTER_DEPTH),
            .BANK_ID(i)
         ) BANK (
            .clk(clk),
            .rstn(rstn),
            .query_locale(query_locale),
            .filter_out(filter_out[i]),

            .wr_en(wr_en),
            .write_slot(write_slot),
            .write_locale(write_locale),
            .write_set(write_set)
         );
      end

   endgenerate
   assign query_out_conflict = filter_out[0] & filter_out[1] & filter_out[2] & filter_out[3];

endmodule

module bloom_bank 
#( 
   parameter FILTER_DEPTH = 8,
   parameter BANK_ID = 0
) (
   input clk,
   input rstn,

   input locale_t query_locale,
   output logic [2**LOG_CQ_SLICE_SIZE-1:0] filter_out,

   input wr_en,
   input cq_slice_slot_t write_slot,
   input locale_t write_locale,
   input write_set // set-1, reset-0 
);
   typedef logic [$clog2(FILTER_DEPTH)-1:0] filter_addr_t;

   filter_addr_t query_addr ;
   filter_addr_t write_addr ;

   filter_entry_t write_current_data;
   filter_entry_t write_new_data;
   filter_entry_t read_data;

   filter_entry_t filters [0:FILTER_DEPTH-1];       

   // random 32-bit numbers generated from 
   // https://www.browserling.com/tools/random-hex
   localparam logic [0:15] [31:0] hash_keys = {
    32'h2cccc93a,
    32'h05c4357e,
    32'h95bd7e36,
    32'h62e721fa,
    32'h3bbc49a6,
    32'h2da9f278,
    32'he39243ce,
    32'h8329b91a,
    32'h1cd8549a,
    32'hfe73b4f1,
    32'h64d611a0,
    32'h04a16e92,
    32'hc8c3c457,
    32'hecd2efd0,
    32'h3a2c194f,
    32'h3aa2ce85
   };  // not used anymore
   localparam BIT_OFFSET = BANK_ID * $clog2(FILTER_DEPTH);

   generate genvar j;
      for (j=0;j<$clog2(FILTER_DEPTH);j+=1) begin
         assign query_addr[j] = query_locale[BIT_OFFSET +j] ^ query_locale[ 12+ BIT_OFFSET+j];
         assign write_addr[j] = write_locale[BIT_OFFSET +j] ^ write_locale[ 12+ BIT_OFFSET+j];
      end
   endgenerate
   always_comb begin
      write_new_data = write_current_data;
      write_new_data[write_slot] = write_set;
   end
   initial begin
      for (integer j=0;j<FILTER_DEPTH;j=j+1) begin
         filters[j] = 0;
      end
   end
   always_comb begin
      write_current_data = filters[write_addr]; 
      filter_out = filters[query_addr]; 
   end
   always @(posedge clk) begin
      if (wr_en) begin
         filters[write_addr] <= write_new_data;
      end
   end


endmodule
