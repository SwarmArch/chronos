`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif

import swarm::*;

typedef enum logic[2:0] {
   UNUSED,
   DEQUEUED,  // cleared conflict detection, but not hint serializer
   RUNNING, // actively running on a core
   ABORTED, // waiting for child-abort acks to be received (or for a core to start this task if the task was aborted before it started running)
   UNDO_LOG_WAITING, // undo-log request sent, waiting for completion
   FINISHED, // task ran to completion. but waiting for GVT to advance to this task's vt
   COMMITTED // waiting for cut_ties_ack before the slot can be freed
} cq_state_t;
typedef vt_t [2**LOG_CQ_TS_BANKS -1:0] ts_vt_out; 

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

   // Start Task - Core notifies the CQ of it starting a task
   input [N_THREADS-1:0]                    start_task_valid,
   output logic [N_THREADS-1:0]             start_task_ready,
   input cq_slice_slot_t [N_THREADS-1:0]    start_task_slot,
   
   // Finish Task - Core notifies the CQ of it finishing a task
   input                       finish_task_valid,
   input cq_slice_slot_t       finish_task_slot,
   input                       finish_task_is_undo_log_restore,
   input child_id_t            finish_task_num_children,
   input                       finish_task_undo_log_write,
   output logic                finish_task_ready,
   
   // Abort Task to Core
   output logic [N_THREADS-1:0]             abort_running_task,
   output cq_slice_slot_t                 abort_running_slot,


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

   input logic [63:0]                     cur_cycle,
   pci_debug_bus_t.master                 pci_debug,
   reg_bus_t.master                       reg_bus
);
generate
if (NON_SPEC) begin : gen 
   
   ts_t drop_task_ts;

   assign out_task_valid = deq_task_valid;
   always_comb begin
      out_task = deq_task;
      if (deq_task.ts > drop_task_ts) begin
         out_task.ttype = TASK_TYPE_TERMINATE;
      end
   end
   assign out_task_slot = 0;
   assign deq_task_ready = out_task_ready;
   assign deq_task_cq_slot = 0;
   assign start_task_ready = '1;
   assign finish_task_ready = 1;
   assign abort_running_task = '0;
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
   


typedef enum logic[2:0] {IDLE, DEQ_CHECK_TS, ABORT_CHILDREN, ABORT_REQUEUE, UNDO_LOG_RESTORE,
      DEQ_PUSH_TASK } cq_fsm_state_t;
cq_fsm_state_t state;

logic      [2**LOG_CQ_SLICE_SIZE-1:0]  cq_valid; 

cq_state_t   cq_state [0:2**LOG_CQ_SLICE_SIZE-1];
hint_t       cq_hint  [0:2**LOG_CQ_SLICE_SIZE-1];
epoch_t      tq_epoch [0:2**LOG_CQ_SLICE_SIZE-1];
tq_slot_t    cq_tq_slot [0:2**LOG_CQ_SLICE_SIZE-1];

task_type_t  cq_ttype [0:2**LOG_CQ_SLICE_SIZE-1];

logic       cq_terminate_task [ 0:2**LOG_CQ_SLICE_SIZE-1];

core_id_t  cq_running_core [0:2**LOG_CQ_SLICE_SIZE-1];
child_id_t cq_num_children [0:2**LOG_CQ_SLICE_SIZE-1];  
logic      cq_undo_log_write [0:2**LOG_CQ_SLICE_SIZE-1];  

cq_slice_slot_t      cq_undo_log_ack_pending[0:2**LOG_CQ_SLICE_SIZE-1];

cq_slice_slot_t ts_array_raddr;
cq_slice_slot_t ts_check_id;
vt_t check_vt;
vt_t [0:2**LOG_CQ_TS_BANKS-1] rdata_lvt;

vt_t ts_write_data;
logic ts_write_valid;

assign ts_write_data.ts = out_task.ts; 
assign ts_write_data.tb = cur_cycle[TB_WIDTH-1:0];
assign ts_write_valid = out_task_valid & (state == DEQ_PUSH_TASK);

logic [LOG_GVT_PERIOD-1:0] lvt_cycle;
assign lvt_cycle = cur_cycle[LOG_GVT_PERIOD-1:0];

// bitmap of tasks whose undo log tasks have not been sent out
logic [2**LOG_CQ_SLICE_SIZE-1:0] undo_log_abort_pending; 
// in the current iterations
logic [2**LOG_CQ_SLICE_SIZE-1:0] undo_log_abort_scratchpad; 

logic [2**LOG_CQ_SLICE_SIZE-1:0] undo_log_abort_pending_diff; 
logic [2**LOG_CQ_SLICE_SIZE-1:0] undo_log_abort_scratchpad_diff; 
cq_slice_slot_t undo_log_abort_max_ts_index;
cq_slice_slot_t undo_log_abort_next_cand;
vt_t            undo_log_abort_max_ts;

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
      end else if (state == UNDO_LOG_WAITING) begin
         ts_array_raddr = undo_log_abort_next_cand;
      end
   end
end

logic resource_abort_start;
logic gvt_induced_abort_start;

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
         //cq_size <= 2**LOG_CQ_SLICE_SIZE;
         lookup_entry <= 'x;
         lookup_mode <= 1'b0;
         use_ts_cache <= 1'b1;
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
           //    CQ_SIZE : cq_size <= reg_bus.wdata;
               CQ_LOOKUP_MODE : lookup_mode <= reg_bus.wdata;
               CQ_LOOKUP_ENTRY : lookup_entry <= reg_bus.wdata;
               CQ_USE_TS_CACHE : use_ts_cache <= reg_bus.wdata[0];
            endcase
         end
      end 
   end
   assign cq_size = 2**LOG_CQ_SLICE_SIZE;


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

// tasks who did not have any same hint tasks on dequeue
logic [31:0] n_tasks_no_conflict;
// has same hint tasks, but conflict checks were skipped because the cache was
// effective
logic [31:0] n_tasks_conflict_mitigated;
// has same hint tasks, but could not skip conflict checks because cache miss
logic [31:0] n_tasks_conflict_miss; 
// has same hint tasks which were real conflicts
logic [31:0] n_tasks_real_conflict; 




always_comb begin
   undo_log_abort_pending_diff = undo_log_abort_pending;
   undo_log_abort_pending_diff[undo_log_abort_next_cand] = 1'b0;
   undo_log_abort_scratchpad_diff = undo_log_abort_scratchpad;
   undo_log_abort_scratchpad_diff[undo_log_abort_next_cand] = 1'b0;
end

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
   
   .query_hint(deq_task.hint),
   .query_out_valid(last_deq_ts_cache_hit),
   .query_out_ts(last_deq_ts_cache_ts),

   .wr_en(ts_write_valid),
   .write_hint(out_task.hint),
   .write_ts(out_task.ts)

);

// Nuke core 1 on a gvt induced abort. FIXME This will not work if core 1 does
// not support gvt task type
cq_slice_slot_t core_1_running_task_slot;
logic can_abort_core_1_task;
always_ff @(posedge clk) begin
   if (!rstn) begin
      can_abort_core_1_task <= 1'b0;
      core_1_running_task_slot <= 'x;
   end else
   if (start_task_valid[1] & start_task_ready[1]) begin
      core_1_running_task_slot <= start_task_slot[1];
      can_abort_core_1_task <= 1'b1;
   end else if (gvt_induced_abort_start & !(from_tq_abort_valid & from_tq_abort_ready)) begin
      can_abort_core_1_task <= 1'b0;
   end
end

assign resource_abort_start = (state == IDLE) 
            & deq_task_valid & ((deq_task.ts < max_vt_fixed.ts) |
                  // do not start resource abort if max_vt task just changed
                  // tq asserted force signal based on its previous value
                                 (deq_task_force & !(lvt_cycle == (LOG_CQ_TS_BANKS+1)))  )
            & (cq_next_idle_in ==0) 
            & (     (cq_state[max_vt_pos_fixed] == RUNNING) 
                  | (cq_state[max_vt_pos_fixed] == FINISHED)); 
assign gvt_induced_abort_start = (state == IDLE) & can_abort_core_1_task & gvt_task_slot_valid & 
                           (cq_state[gvt_task_slot] == DEQUEUED) & no_idle_cores & 
                           (cq_state[core_1_running_task_slot] == RUNNING) & 
                           tsb_almost_full ;



hint_t ref_hint;
always_comb begin
   if (state==IDLE) begin
      if (from_tq_abort_valid) begin
         ref_hint = { 1'b0, cq_hint[from_tq_abort_slot][30:0]};
      end else if (resource_abort_start) begin
         ref_hint = { 1'b0, cq_hint[max_vt_pos_fixed][30:0]};
      end else if (gvt_induced_abort_start) begin
         ref_hint = { 1'b0, cq_hint[core_1_running_task_slot][30:0]}; 
      end else begin
         ref_hint = deq_task.hint;
      end      
   end else begin
      ref_hint = cur_task.hint;
   end
end

genvar i;
for (i=0;i<2**LOG_CQ_SLICE_SIZE;i++) begin
   assign cq_conflict[i] = cq_valid[i] & (cq_hint[i][30:0] == ref_hint[30:0])
            // if MSB of hint is set, its a read-only hint. No conflicts between
            // RO tasks
            &  !( cq_hint[i][31] & ref_hint[31])
            & (cq_state[i] != ABORTED) & (cq_state[i] != UNDO_LOG_WAITING);
   assign cq_next_idle_in[i] = !cq_valid[i] & (i < cq_size) ;
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
cq_slice_slot_t reg_from_tq_abort_slot;


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
            if (from_tq_abort_valid & from_tq_abort_ready) begin
               reg_conflict <= cq_conflict;
               state <= DEQ_CHECK_TS;
               in_tq_abort <= 1'b1;
               ref_tb <= check_vt.tb; 
               cur_task.ts <= check_vt.ts;
               cur_task.hint <= ref_hint;
               reg_from_tq_abort_slot <= from_tq_abort_slot;
            end else 
            if (gvt_induced_abort_start) begin
               reg_conflict <= cq_conflict;
               state <= DEQ_CHECK_TS;
               in_gvt_induced_abort <= 1'b1;
               ref_tb <= gvt.tb;
               cur_task.ts <= gvt.ts;
               cur_task.hint <= ref_hint;
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
                     // ts than the previous dequeued task of the same hint
                     state <= DEQ_CHECK_TS;
                     reg_conflict <= cq_conflict;
                  end else begin
                     state <= DEQ_PUSH_TASK;
                  end
               end
               cq_terminate_task[deq_task_cq_slot] <= 
                     (deq_task.ttype == TASK_TYPE_TERMINATE);
            end else 
            if (resource_abort_start) begin
               reg_conflict <= cq_conflict;
               state <= DEQ_CHECK_TS;
               in_resource_abort <= 1'b1;
               ref_tb <= max_vt_fixed.tb;
               cur_task.ts <= max_vt_fixed.ts;
               cur_task.hint <= ref_hint;
            end 
         end
         DEQ_CHECK_TS: begin
            if (reg_conflict ==0) begin
               state <= (undo_log_abort_pending != 0)   ? UNDO_LOG_RESTORE : DEQ_PUSH_TASK;
               undo_log_abort_scratchpad <= undo_log_abort_pending;
               undo_log_abort_max_ts <= '0;
            end else begin
               if (abort_ts_check_task) begin
                  if (cq_state[ts_check_id] == FINISHED) begin
                     // if undo_log_write[] then heap_ready
                     state <=(cq_num_children[ts_check_id] == 0)
                                       ? ABORT_REQUEUE : ABORT_CHILDREN;
                     if (cq_undo_log_write[ts_check_id]) begin
                        // undo_log_walk_required = 1
                        undo_log_abort_pending[ts_check_id] <= 1'b1;
                     end
                  end else if (cq_state[ts_check_id] == DEQUEUED) begin
                     // task dequeued but a core has not started running yet
                     state <= ABORT_REQUEUE;
                  end
               end else begin
                  reg_conflict[ts_check_id] <= 1'b0;
                  state <= DEQ_CHECK_TS;
               end
            end
         end
         ABORT_CHILDREN: begin
            if (abort_children_valid & abort_children_ready) begin
               state <= ABORT_REQUEUE;
            end
         end
         ABORT_REQUEUE: begin
            if (to_tq_abort_valid & to_tq_abort_ready | 
                  // Do not requeue the task from a task_queue induced abort,
                  // but requeue later ts tasks with the same hint
                  ( in_tq_abort & (reg_from_tq_abort_slot == ts_check_id)) ) begin
                  // no special treatment for resource aborts, they should
                  // requeue 
               state <= DEQ_CHECK_TS;
               reg_conflict[ts_check_id] <= 1'b0;
            end
         end
         UNDO_LOG_RESTORE: begin
            // double loop
            // first check inner loop, if it is terminating check outer loop
            if (undo_log_abort_scratchpad_diff == 0) begin
               // out_task_valid should be set
               if (out_task_valid & out_task_ready) begin
                  if (undo_log_abort_pending_diff == 0) begin
                     state <= DEQ_PUSH_TASK;
                  end
                  // start next outer loop iteration after removing current cand
                  // element
                  undo_log_abort_scratchpad <= undo_log_abort_pending_diff;
                  undo_log_abort_max_ts <= '0;
                  undo_log_abort_pending <= undo_log_abort_pending;
                  undo_log_abort_pending[out_task_slot] <= 1'b0;
               end
            end else begin
               if (undo_log_abort_max_ts < check_vt) begin
                  undo_log_abort_max_ts <= check_vt;
                  undo_log_abort_max_ts_index <= undo_log_abort_next_cand;
               end
               undo_log_abort_scratchpad <= undo_log_abort_scratchpad_diff;
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
   out_task_valid = 1'b0;
   out_task = 'x;
   out_task_slot = 'x;
   if (state == DEQ_PUSH_TASK) begin
      out_task_valid = !in_tq_abort & !in_resource_abort & !in_gvt_induced_abort;
      out_task = cur_task;
      out_task_slot = cur_task_slot;
   end else if (state == UNDO_LOG_RESTORE) begin
      if (undo_log_abort_scratchpad_diff == 0) begin
         out_task_valid = 1'b1;
         out_task.ttype = TASK_TYPE_UNDO_LOG_RESTORE;
         out_task.hint = cur_task.hint;
         // other fields doesn't matter
         if (undo_log_abort_max_ts < check_vt) begin
            out_task_slot = undo_log_abort_next_cand;
         end else begin
            out_task_slot = undo_log_abort_max_ts_index;
         end
      end
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

cq_slice_slot_t start_task_slot_select;
core_id_t start_core_select;

assign abort_ts_check_task = (state == DEQ_CHECK_TS) & (check_vt >= ref_vt) & (reg_conflict != 0);
for (i=0;i<N_THREADS;i++) begin
   assign abort_running_task[i] = (abort_ts_check_task & 
         // aborting task is already running
       (  ( (cq_state[ts_check_id] == RUNNING)   & (cq_running_core[ts_check_id] == i)) |
          // OR aborting task is being started this cycle
          ( (start_task_slot_select==ts_check_id & start_task_valid[start_core_select]) 
               & start_core_select == i)  ) ) |
         // task was aborted, but is starting now
            start_task_valid[start_core_select] & (cq_state[start_task_slot_select] == ABORTED) 
               & (start_core_select == i)

               ;
end
assign abort_running_slot = ts_check_id;

assign abort_children_valid = (state == ABORT_CHILDREN);
assign abort_children_cq_slot = ts_check_id;
assign abort_children_count = cq_num_children[ts_check_id];

assign deq_task_ready = (state == IDLE) & !from_tq_abort_valid & 
            (cq_next_idle_in != 0) &
            // if cc is almost full, only let the gvt task proceed
            (!cc_almost_full | (deq_task_valid & ((deq_task.ts == gvt.ts) | deq_task_force))) &
            !gvt_induced_abort_start; 


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
      if (commit_task_valid & commit_task_ready & cq_num_children[commit_task_slot] !=0) begin
         cut_ties_valid <= 1'b1;
         cut_ties_cq_slot <= commit_task_slot;
         cut_ties_num_children <= cq_num_children[commit_task_slot];
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


lowbit #(
   .OUT_WIDTH($bits(start_core_select)),
   .IN_WIDTH(N_THREADS)
) START_TASK_SELECT (
   .in(start_task_valid),
   .out(start_core_select)
);


always_comb begin
   start_task_slot_select = start_task_slot[start_core_select];
end

cq_state_t start_task_state;
assign start_task_state = cq_state[start_task_slot_select];

logic undo_log_walk_required;
assign undo_log_walk_required = abort_ts_check_task & (cq_state[ts_check_id] == FINISHED) & 
          (cq_undo_log_write[ts_check_id]);
always_comb begin
   if (undo_log_walk_required) begin
      // conflict on cq_undo_log_ack_pending
      finish_task_ready = 1'b0; 
   end else begin
      finish_task_ready = finish_task_valid; 
   end
end

for (i=0;i<N_THREADS;i++) begin
   assign start_task_ready[i] = start_task_valid[i] & (i==start_core_select); 
end

assign abort_ack_ready = 1'b1;
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

logic start_task_at [0:2**LOG_CQ_SLICE_SIZE-1];
logic abort_task_at [0:2**LOG_CQ_SLICE_SIZE-1];

for (i=0;i<2**LOG_CQ_SLICE_SIZE;i++) begin
   assign cq_valid[i] = (cq_state[i] != UNUSED);
   assign abort_task_at[i] = (ts_check_id == i) & abort_ts_check_task;
   assign start_task_at[i] = (start_task_slot_select == i) 
                        & start_task_valid[start_core_select]
                        & start_task_ready[start_core_select] ;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         cq_state[i] <= UNUSED;
         cq_hint[i] <= 'x;
      end else begin
         case (cq_state[i]) 
            UNUSED: begin
               if (out_task_valid & out_task_ready) begin
                  if (state== DEQ_PUSH_TASK & (i==out_task_slot) ) begin
                     cq_hint [i] <= out_task.hint;
                     cq_ttype[i] <= out_task.ttype;
                     cq_state[i] <= DEQUEUED;
                  end else if (state == UNDO_LOG_RESTORE & (i==out_task_slot) & 
                           out_task_valid & out_task_ready) begin
                     cq_state[i] <=UNDO_LOG_WAITING;
                  end
               end
            end
            DEQUEUED: begin
               // a race is possible between start_task and abort_ts_check_task; 
               // Let the abort win;, core is notified by asserting both 
               // start_task_ready & abort_running_task
               if ( abort_task_at[i] ) begin
                  cq_state[i] <= start_task_at[i] ? UNUSED : ABORTED;
               end else if ( start_task_at[i] ) begin
                  cq_state[i] <= RUNNING;
               end
            end   
            RUNNING: begin 
               if (finish_task_valid & finish_task_ready & (finish_task_slot == i)) begin
                  cq_state[i] <= FINISHED;
               end
            end
            FINISHED: begin
               if (commit_task_valid & commit_task_ready & (commit_task_slot == i)  )  begin
                  cq_state[i] <= (cq_num_children[i] == 0) ? UNUSED : COMMITTED;
               end else if (abort_ts_check_task & (ts_check_id == i)) begin
                  if (cq_num_children[i] == 0) begin
                     cq_state[i] <= UNUSED;
                  end else begin
                     cq_state[i] <= ABORTED;
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
                  // Task was found to be aborted on dequeue
                  cq_state[i] <= UNUSED;
               end else if (abort_ack_valid & abort_ack_ready & (abort_ack_cq_slot ==i)) begin
                  if (cq_undo_log_ack_pending[i] > 0) begin
                     cq_state[i] <= UNDO_LOG_WAITING;
                  end else begin
                     cq_state[i] <= UNUSED;
                  end
               end
            end
            UNDO_LOG_WAITING: begin
               if (cq_undo_log_ack_pending[i] == 0) begin
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
   if (undo_log_walk_required) begin 
      cq_undo_log_ack_pending[ts_check_id] <= 1'b1;
   end else if (finish_task_valid & finish_task_ready & finish_task_is_undo_log_restore) begin
      cq_undo_log_ack_pending[finish_task_slot] <= 1'b0;
   end
end

always_ff @(posedge clk) begin
   if (state==DEQ_PUSH_TASK & out_task_valid & out_task_ready) begin
      tq_epoch  [out_task_slot] <= cur_task_epoch;
      cq_tq_slot[out_task_slot] <= cur_task_tq_slot;

   end
end
always_ff @(posedge clk) begin
   if (start_task_valid[start_core_select]) begin
      cq_running_core[start_task_slot_select] <= start_core_select;
   end
end

always_ff @(posedge clk) begin
   if (finish_task_valid & finish_task_ready) begin
      cq_num_children[finish_task_slot] <= finish_task_num_children;
      cq_undo_log_write[finish_task_slot] <= finish_task_undo_log_write;
   end
end
  
lowbit #(
   .OUT_WIDTH(LOG_CQ_SLICE_SIZE),
   .IN_WIDTH(2**LOG_CQ_SLICE_SIZE)
) UNDO_LOG_WALK_CAND (
   .in(undo_log_abort_scratchpad),
   .out(undo_log_abort_next_cand)
);


logic [31:0] cycles_in_resource_abort;
logic [31:0] cycles_in_gvt_abort;

if (CQ_STATS) begin
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
         if (resource_abort_start) begin
            if ( !(from_tq_abort_valid & from_tq_abort_ready) & (!gvt_induced_abort_start) 
               & !(deq_task_valid & deq_task_ready)) begin
               n_resource_aborts <= n_resource_aborts + 1;
            end
         end 
         if (gvt_induced_abort_start) begin
            n_gvt_aborts <= n_gvt_aborts + 1;
         end
         if (in_resource_abort) begin
            cycles_in_resource_abort <= cycles_in_resource_abort + 1;
         end
         if (in_gvt_induced_abort) begin
            cycles_in_gvt_abort <= cycles_in_gvt_abort + 1;
         end
         if (cq_valid != 0) begin
            cq_state_stats[state] <= cq_state_stats[state] + 1;
            if (state == IDLE) begin
               if (!from_tq_abort_valid) begin
                  if (cq_next_idle_in == 0) begin
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
         CQ_LOOKUP_HINT  : reg_bus.rdata <= cq_hint[lookup_entry];
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
         
         CQ_DEQ_TASK_STATS : reg_bus.rdata <= deq_stats[lookup_entry];
         CQ_COMMIT_TASK_STATS : reg_bus.rdata <= commit_stats[lookup_entry];
         
         CQ_N_GVT_GOING_BACK : reg_bus.rdata <= n_gvt_going_back;
         
         CQ_N_TASK_NO_CONFLICT : reg_bus.rdata <= n_tasks_no_conflict;
         CQ_N_TASK_CONFLICT_MITIGATED : reg_bus.rdata <= n_tasks_conflict_mitigated;
         CQ_N_TASK_CONFLICT_MISS : reg_bus.rdata <= n_tasks_conflict_miss;
         CQ_N_TASK_REAL_CONFLICT : reg_bus.rdata <= n_tasks_real_conflict;
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
      logic [5:0] out_task_cq_slot;
      logic [3:0] out_task_ttype;
      logic [19:0] out_task_hint;


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
      logic [29:0] unused_4;

      logic [31:0] abort_running_task; 
      

   } cq_log_t;
   cq_log_t log_word;
   always_comb begin
      log_valid = 1'b0;

      log_word = '0;

      log_word.gvt_tb = gvt.tb;
      log_word.gvt_ts = gvt.ts;

      if (start_task_valid[start_core_select] & start_task_ready[start_core_select]) begin
         log_valid = 1'b1;
      end
      log_word.start_task_valid = start_task_valid[start_core_select];
      log_word.start_task_ready = start_task_ready[start_core_select];
      log_word.start_task_core = start_core_select;
      log_word.start_task_slot = start_task_slot_select;

      if (finish_task_valid) begin
         log_valid = 1'b1;
      end
      log_word.finish_task_valid = finish_task_valid;
      log_word.finish_task_ready = finish_task_ready;
      log_word.finish_task_slot = finish_task_slot;
      log_word.finish_task_num_children = finish_task_num_children;
      log_word.finish_task_undo_log_write = finish_task_undo_log_write;

      if (|abort_running_task) begin
         log_valid = 1'b1;
      end
      log_word.abort_running_task = abort_running_task;
      log_word.gvt_task_slot_valid = gvt_task_slot_valid;
      log_word.gvt_task_slot = gvt_task_slot;
      log_word.abort_running_slot = abort_running_slot;
      log_word.max_vt_slot = max_vt_pos_fixed; 
     
      if (to_tq_abort_valid & to_tq_abort_ready) begin
         log_valid = 1'b1;
      end
      log_word.to_tq_abort_valid = to_tq_abort_valid;
      log_word.to_tq_resource_abort = in_resource_abort; 

      if (abort_children_valid & abort_children_ready) begin
         log_valid = 1'b1;
      end
      log_word.abort_children_valid = abort_children_valid;
      log_word.abort_children_ready = abort_children_ready;
      log_word.abort_children_cq_slot = abort_children_cq_slot;
      log_word.abort_children_count = abort_children_count;

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
      log_word.out_task_hint = out_task.hint;
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
      if (start_task_valid[start_core_select]  & start_task_ready[start_core_select]) begin
         $fwrite(file,"[%5d] [cq-%2d] start_task core:%2d slot:%4d \n",
            cycle, 0, 
            start_core_select, start_task_slot_select) ;
      end
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
// comes after the last dequeued ts for the same hint, then no conflict
// detection is required.
module last_deq_ts_cache 
(
   input clk,
   input rstn,

   input hint_t query_hint,
   output logic query_out_valid,
   output ts_t query_out_ts,

   input wr_en,
   input hint_t write_hint,
   input ts_t   write_ts
);
generate
if (LOG_LAST_DEQ_VT_CACHE >0) begin
   hint_t tag  [0:2**LOG_LAST_DEQ_VT_CACHE-1];
   ts_t data   [0:2**LOG_LAST_DEQ_VT_CACHE-1];

   // skip bits[7:4] in indexing, since they may be constant if the task is
   // mapped to the current tile.
   logic [LOG_LAST_DEQ_VT_CACHE-1:0] rd_addr;
   assign rd_addr = {query_hint[8+:(LOG_LAST_DEQ_VT_CACHE-4)],  query_hint[3:0]};
   logic [LOG_LAST_DEQ_VT_CACHE-1:0] wr_addr;
   assign wr_addr =  {write_hint[8+:(LOG_LAST_DEQ_VT_CACHE-4)],  write_hint[3:0]};
   initial begin
      for (integer i=0;i<2**LOG_LAST_DEQ_VT_CACHE;i+=1) begin
         tag[i] = 0;
         data[i] = 0;
      end
   end
   assign query_out_valid = (tag[rd_addr][30:0] == query_hint[30:0]);
   assign query_out_ts = data[rd_addr];
   // a read-only task may not have aborted all its successors. Therefore its
   // not safe to update the last_deq_ts with current task's ts
   ts_t current_ts;
   assign current_ts = (tag[wr_addr][30:0] == write_hint[30:0]) ? data[wr_addr] : 0;
   ts_t new_write_ts;
   always_comb begin
      new_write_ts = write_ts;
      if (write_hint[31] == 1'b1) begin
         if (current_ts > write_ts) begin
            new_write_ts = current_ts;
         end
      end
   end
   
   always_ff @(posedge clk) begin
      if (wr_en) begin
         tag[wr_addr] <= {1'b0, write_hint[30:0]};
         data[wr_addr] <= new_write_ts;
      end
   end
end else begin
   assign query_out_valid = 1'b0;
end

endgenerate
endmodule

