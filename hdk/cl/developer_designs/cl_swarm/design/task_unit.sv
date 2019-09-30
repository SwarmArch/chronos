
import swarm::*;

typedef struct packed {
   ts_t ts;
   tq_slot_t slot;
   logic splitter;
   logic producer;
   logic non_spec;
   epoch_t epoch; 
} tq_heap_elem_t;


module task_unit 
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


   enum logic [1:0] {TQ_NORMAL, TQ_DEQ_MAX, TQ_OVERFLOW} tq_state;

   // 1. Tied bitvector
   logic       tied_task [0:2**LOG_TQ_SIZE-1];
   logic       tied_task_wr_en;
   tq_slot_t   tied_task_wr_addr;
   logic       tied_task_wr_data;

   always_ff @(posedge clk) begin
      if (tied_task_wr_en) begin
         tied_task[tied_task_wr_addr] <= tied_task_wr_data;
      end 
   end

   // 2. Dequeued / CQ slot

   logic       dequeued_task [0:2**LOG_TQ_SIZE-1];
   logic       dequeued_task_wr_en;
   tq_slot_t   dequeued_task_wr_addr;
   logic       dequeued_task_wr_data;

   always_ff @(posedge clk) begin
      if (dequeued_task_wr_en) begin
         dequeued_task[dequeued_task_wr_addr] <= dequeued_task_wr_data;
      end 
   end

   cq_slice_slot_t   cq_slot [0:2**LOG_TQ_SIZE-1];
   logic             cq_slot_wr_en;
   tq_slot_t         cq_slot_wr_addr;
   cq_slice_slot_t   cq_slot_wr_data;

   always_ff @(posedge clk) begin
      if (cq_slot_wr_en) begin
         cq_slot[cq_slot_wr_addr] <= cq_slot_wr_data;
      end 
   end
  
   // 3. Epoch
   epoch_t     epoch [0:2**LOG_TQ_SIZE-1];
   logic       epoch_wr_en;
   tq_slot_t   epoch_wr_addr;
   epoch_t     epoch_wr_data;
   
   initial begin
      for (integer i =0;i<2**LOG_TQ_SIZE;i++) begin
         epoch[i] = 0;
         tied_task[i] = 0;
         dequeued_task[i] = 0;
      end
   end

   always_ff @(posedge clk) begin
      if (epoch_wr_en) begin
         epoch[epoch_wr_addr] <= epoch_wr_data;
      end 
   end
   
   //4. Task Args
   tq_slot_t      tq_read_addr;
   tq_slot_t      tq_write_addr;

   task_t         tq_write_data;
   task_t         tq_read_data;
   task_t         tq_read_data_q;
   
   logic          tq_write_valid;

   task_array TASK_ARRAY
   (
      .clk(clk),
      .rstn(rstn),

      .raddr(tq_read_addr),
      .waddr(tq_write_addr),
   
      .rdata(tq_read_data),
      .wdata(tq_write_data),
      .en(1'b1),
      .wr(tq_write_valid)

   );
   
   // 5. Task heap
   tq_heap_elem_t next_insert_elem;
   logic          next_insert_elem_set;
   logic          next_insert_elem_clear;
   
   tq_heap_elem_t reg_next_insert_elem ;
   logic          reg_next_insert_elem_valid;

   logic          heap_re_enq_elem_valid; // when deq_max returns a tied task
   tq_heap_elem_t heap_re_enq_elem;

   tq_heap_elem_t heap_enq_elem;

   
   logic heap_ready;
   logic heap_out_valid;
   heap_op_t heap_in_op;

   tq_heap_elem_t next_deque_elem;
   tq_heap_elem_t next_max_elem, reg_spill_heap_enq;
   logic next_max_elem_valid, reg_spill_heap_enq_valid;
   logic deq_task;
   logic spill_heap_deq_task;
   logic [TQ_STAGES-1:0] heap_capacity;

   logic unused_1, unused_2;
   
   min_heap #(
      .N_STAGES(TQ_STAGES),
      .PRIORITY_WIDTH(TS_WIDTH+1),
      .DATA_WIDTH(LOG_TQ_SIZE+ EPOCH_WIDTH + 2)
   ) HEAP (
      .clk(clk),
      .rstn(rstn),

      .in_ts({heap_enq_elem.ts, heap_enq_elem.producer}),
      .in_data( {heap_enq_elem.slot, heap_enq_elem.splitter, heap_enq_elem.epoch, heap_enq_elem.non_spec} ),
      .in_op(heap_in_op),
      .ready(heap_ready),

      .out_ts({next_deque_elem.ts, unused_1}),  
      .out_data( {next_deque_elem.slot, next_deque_elem.splitter, next_deque_elem.epoch, next_deque_elem.non_spec} ),
      .out_valid(heap_out_valid),
   
      .capacity(heap_capacity),

      .max_out_ts({next_max_elem.ts, next_max_elem.producer} ),
      .max_out_data( {next_max_elem.slot, next_max_elem.splitter, next_max_elem.epoch, next_max_elem.non_spec}),
      .max_out_valid(next_max_elem_valid)
   );

   // 6. Spill heap
   
   ts_t      spill_next_insert_elem_ts ;
   tq_slot_t spill_next_insert_elem_slot;

   
   logic spill_heap_ready;
   logic spill_heap_out_valid;
   heap_op_t spill_heap_in_op;

   ts_t      spill_next_deque_elem_ts ;
   tq_slot_t spill_next_deque_elem_slot;
   logic [LOG_TQ_SPILL_SIZE-1:0] spill_heap_capacity;

   logic overflow_epoch_fifo_full, overflow_epoch_fifo_empty;
   tq_slot_t overflow_epoch_fifo_rd_data;
   logic overflow_epoch_fifo_rd_en;

generate
if (!NO_SPILLING) begin
   min_heap #(
      .N_STAGES(LOG_TQ_SPILL_SIZE),
      .PRIORITY_WIDTH(TS_WIDTH),
      .DATA_WIDTH(LOG_TQ_SIZE)
   ) SPILL_HEAP (
      .clk(clk),
      .rstn(rstn),

      .in_ts(spill_next_insert_elem_ts),
      .in_data(spill_next_insert_elem_slot),
      .in_op(spill_heap_in_op),
      .ready(spill_heap_ready),

      .out_ts(spill_next_deque_elem_ts),  
      .out_data(spill_next_deque_elem_slot),
      .out_valid(spill_heap_out_valid),
   
      .capacity(spill_heap_capacity),

      .max_out_ts(),
      .max_out_data(),
      .max_out_valid()
   );
end else begin
   assign spill_next_deque_elem_ts = '0;
   assign spill_next_deque_elem_slot = 0;
   assign spill_heap_ready = 1;
   assign spill_heap_capacity = 0;
end   
endgenerate
   
   fifo #(
      .LOG_DEPTH(2)
   ) OVERFLOW_EPOCH_UPDATE (
      .clk(clk),
      .rstn(rstn),

      .wr_en(spill_heap_deq_task),
      .rd_en(overflow_epoch_fifo_rd_en),
      .wr_data(spill_next_deque_elem_slot),

      .full(overflow_epoch_fifo_full), 
      .empty(overflow_epoch_fifo_empty),
      .rd_data(overflow_epoch_fifo_rd_data),

      .size()
   );

   // 7. Free List
   
   tq_slot_t      next_free_tq_slot; // FIFO output
   tq_slot_t      add_free_tq_slot; 

   logic next_free_tq_slot_valid;
   logic add_free_tq_slot_valid;
   logic next_free_tq_slot_deque;
   

   logic free_list_empty;
   assign next_free_tq_slot_valid = !free_list_empty;

   free_list_bram #(
      .LOG_DEPTH(LOG_TQ_SIZE)
   ) FREE_LIST (
      .clk(clk),
      .rstn(rstn),

      .wr_en(add_free_tq_slot_valid),
      .rd_en(next_free_tq_slot_deque),
      .wr_data(add_free_tq_slot),

      .full(), 
      .empty(free_list_empty),
      .rd_data(next_free_tq_slot),

      .size()
   );

   //misc
   tq_slot_t task_spill_threshold;
   tq_slot_t task_unit_tied_capacity;
   logic [TQ_STAGES-1:0] task_unit_clean_threshold;
   logic [LOG_TQ_SPILL_SIZE-1:0] task_unit_spill_size;

   tq_slot_t n_tied_tasks;
   tq_slot_t n_tasks;

   logic tq_stall;
   logic tq_started;

   logic is_transactional;
   logic [23:0] transaction_id;
   logic [23:0] maxflow_global_relabel_trigger_mask;
   logic [23:0] maxflow_global_relabel_trigger_inc;

   ts_t modified_task_enq_ts;
   logic [3:0] four_bit_tile_id;
   assign four_bit_tile_id = TILE_ID;
   always_ff @(posedge clk) begin
      if (!rstn) begin
        transaction_id <= 1; 
     end else begin
        if (is_transactional & task_enq_valid & task_enq_ready & task_enq_data.ttype == 0) begin
            if ((transaction_id & maxflow_global_relabel_trigger_mask) == 0) begin
               transaction_id <= transaction_id + maxflow_global_relabel_trigger_inc;
            end else begin
               // increasing timestamps
               if (task_enq_data.ts[31:4] > {transaction_id, four_bit_tile_id}) begin
                  transaction_id <= modified_task_enq_ts[31:8] + 1;
               end else begin
                  transaction_id <= transaction_id + 1;
               end
            end
        end
     end
   end
   
   always_comb begin
      if (is_transactional & task_enq_valid & (task_enq_data.ttype == 0)) begin
         if (task_enq_data.ts[31:4] > {transaction_id, four_bit_tile_id}) begin
            modified_task_enq_ts = {task_enq_data.ts[31:8] + 1'b1, four_bit_tile_id, 4'b0};
         end else begin
            modified_task_enq_ts = {transaction_id, four_bit_tile_id, 4'b0};
         end
      end else begin
         modified_task_enq_ts = task_enq_data.ts;
      end
   end

   logic task_deq_valid_reg;
   ts_t task_unit_throttle_margin;
   ts_t task_unit_throttle_ts;
   always_ff @(posedge clk) begin
      if (task_unit_throttle_margin == 0) begin
         task_unit_throttle_ts <= '1;
      end else begin
         task_unit_throttle_ts <= gvt.ts + task_unit_throttle_margin;
      end
   end

   logic can_issue_deq_max;
   logic [15:0] deq_max_count;

   logic deq_max_propagation_delay_inc;
   assign can_issue_deq_max = (tq_state == TQ_DEQ_MAX) & !empty & (deq_max_count != 2 * task_unit_spill_size);
   assign deq_max_propagation_delay_inc =  (empty | (deq_max_count == 2*task_unit_spill_size) | 
               (spill_heap_capacity < ( 2**LOG_TQ_SPILL_SIZE -1 - task_unit_spill_size)) );

   logic [3:0] deq_max_propagation_delay;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         deq_max_propagation_delay <= 0;
      end else begin
         if (deq_max_propagation_delay_inc) begin
            deq_max_propagation_delay <= deq_max_propagation_delay + 1;
         end else begin
            deq_max_propagation_delay <=0;
         end
      end
   end
   
   // tq_state FSM
   always_ff @(posedge clk) begin
      if (!rstn) begin
         tq_state <= TQ_NORMAL;
      end else if (!tq_stall) begin
         case (tq_state) 
            TQ_NORMAL: begin
               if ( ((n_tasks >= task_spill_threshold) | (heap_capacity < 16)) & (!NO_SPILLING)) begin
                  tq_state <= TQ_DEQ_MAX;
                  deq_max_count <= 0;
               end
            end
            TQ_DEQ_MAX: begin
               if ( deq_max_propagation_delay_inc & (deq_max_propagation_delay == '1)) begin
                   tq_state <= TQ_OVERFLOW;
                end
                if (heap_in_op == DEQ_MAX) begin
                  deq_max_count <= deq_max_count + 1;
                end
            end
            TQ_OVERFLOW: begin
               if (spill_heap_capacity == ( 2**LOG_TQ_SPILL_SIZE - 1)) begin
                  tq_state <= TQ_NORMAL;
               end
            end
         endcase
      end
   end

   tq_slot_t tq_read_addr_q;
   tq_slot_t splitter_deq_slot;

   logic spill_heap_deq_task_q;
   
   //did we take a abort_child msg last cycle; 
   //if so the value read from the array is not of the next_deque_elem 
   logic abort_child_ready_q;  

   logic cut_ties_epoch_match;
   logic deq_epoch_match, max_epoch_match;
   assign cut_ties_epoch_match = (epoch[cut_ties_tq_slot] == cut_ties_epoch);
   
   // Scheduler
   always_comb begin
      task_enq_ready = 1'b0;
      coal_child_ready = 1'b0;
      cut_ties_ready = 1'b0;
      commit_task_ready = 1'b0;
      abort_child_ready = 1'b0;
      abort_task_ready = 1'b0;

      deq_task = 1'b0;
      spill_heap_deq_task = 1'b0;

      tq_read_addr = 'x;
      if (!tq_stall) begin
         tq_read_addr = next_deque_elem.slot;
         // commit OR abort_child
         if (commit_task_valid) begin
            commit_task_ready = 1'b1;
         end else if (abort_child_valid & !cq_child_abort_valid & !abort_resp_valid &
               // If a task that is waiting to be accepted by the CQ 
               // receives an abort msg, wait until CQ accepts it 
               // (OR until n cycles have elapsed, so deq_valid could be
               // temperorily pulled down) before processing the abort.
                  !(task_deq_valid_reg & task_deq_valid &
                     (task_deq_tq_slot == abort_child_tq_slot))      
                  ) begin
            // epoch checking unnecessary. there is no op that can increase
            // the epoch before an abort_child msg
            abort_child_ready = 1'b1;
            tq_read_addr = abort_child_tq_slot; // to read the ts: hold back lvt
         end
         // enq OR (cut_tie AND (deq (if not abort_child) OR abort_requeue))
         if ( coal_child_valid & !reg_next_insert_elem_valid) begin
            coal_child_ready = 1'b1;   
         end else if (task_enq_valid & !reg_next_insert_elem_valid & !task_resp_valid & !almost_full) begin
            task_enq_ready = 1'b1;
         end else begin
            if (cut_ties_valid) begin
               cut_ties_ready = 1'b1;
            end
            if (abort_task_valid & !reg_next_insert_elem_valid) begin
               abort_task_ready = 1'b1;
            end else if (heap_ready & heap_out_valid & tq_started & !abort_child_ready 
                &  (next_deque_elem.ts < task_unit_throttle_ts)
                &  (!next_deque_elem.non_spec | (next_deque_elem.ts == gvt.ts))
               ) begin 
               tq_read_addr = next_deque_elem.slot;
               if (next_deque_elem.splitter) begin
                  deq_task = !splitter_deq_valid & !commit_task_ready; 
               end else begin
                  deq_task = !task_deq_valid_reg | !deq_epoch_match; 
               end
            end else if (!abort_child_ready & (tq_state == TQ_OVERFLOW)  
                  & overflow_ready // Ideally, this check should be done next cycle, but it not change until then
                  & spill_heap_ready & !overflow_epoch_fifo_full & (spill_heap_capacity != '1)) begin
               tq_read_addr = spill_next_deque_elem_slot;
               spill_heap_deq_task = 1'b1;
            end
         end
      end
   end

   always_ff @(posedge clk) begin
      tq_read_addr_q <= tq_read_addr;
      abort_child_ready_q <= abort_child_ready;
      spill_heap_deq_task_q <= spill_heap_deq_task;
   end

   assign overflow_valid = spill_heap_deq_task_q;
  
   assign max_epoch_match = (epoch[next_max_elem.slot] == next_max_elem.epoch);
   assign deq_epoch_match = (epoch[next_deque_elem.slot] == next_deque_elem.epoch); 
   logic deq_splitter, deq_non_splitter;
   logic deq_splitter_q, deq_non_splitter_q;

   always_comb begin
      deq_splitter = 1'b0;
      deq_non_splitter = 1'b0;
      if (deq_task & deq_epoch_match) begin
         if (next_deque_elem.splitter) begin
            deq_splitter = 1'b1;
         end else begin
            deq_non_splitter = 1'b1;
         end
      end
   end

   logic max_elem_is_tied;
   always_comb begin
      max_elem_is_tied = tied_task[next_max_elem.slot];
   end

   always_ff @(posedge clk) begin
      if (!rstn) begin
         heap_re_enq_elem_valid <= 1'b0;
         reg_spill_heap_enq_valid <= 1'b0;
      end else begin
         if (next_max_elem_valid & max_epoch_match & max_elem_is_tied) begin
            heap_re_enq_elem_valid <= 1'b1;
            heap_re_enq_elem <= next_max_elem;
         end else if (heap_ready) begin
            // heap has priority for taking this
            heap_re_enq_elem_valid <= 1'b0;
         end
         if (next_max_elem_valid & max_epoch_match & !max_elem_is_tied ) begin
            reg_spill_heap_enq_valid <= 1'b1;
            reg_spill_heap_enq <= next_max_elem;
         end else begin
            // No need to ensure spill_heap is ready. it should be given the
            // 2 cycles/task throughput of both heaps.
            reg_spill_heap_enq_valid <= 1'b0;
         end
      end
   end

   
   logic [2:0] deq_valid_cycle_count; 
   // If the CQ did not accept the task even after 7 cycles, temperorily set
   // deq_valid = 0, so that deq_task can be checked for a child abort msg
   assign task_deq_valid = (task_deq_valid_reg & (deq_valid_cycle_count != 7));
   // if non_spec, cannot accept commit_task msgs if spilling
   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_deq_valid_reg <= 1'b0;
         splitter_deq_valid <= 1'b0;
         deq_splitter_q <= 1'b0;
         deq_non_splitter_q <= 1'b0;
         task_deq_force <= 1'b0;
         deq_valid_cycle_count <= 0;
      end else begin
         if (deq_splitter)  begin
            splitter_deq_valid <= 1'b1;
            splitter_deq_slot <= next_deque_elem.slot; 
         end else if (splitter_deq_valid & splitter_deq_ready) begin
            splitter_deq_valid <= 1'b0;
         end
         if (deq_non_splitter) begin
            task_deq_valid_reg <= 1'b1;
            task_deq_epoch <= next_deque_elem.epoch;
            task_deq_tq_slot <= next_deque_elem.slot;
         end else if (task_deq_valid & task_deq_ready) begin
            task_deq_valid_reg <= 1'b0;
         end else if (task_deq_valid_reg 
               & abort_child_ready & (task_deq_tq_slot == abort_child_tq_slot)) begin
            //$display("Child abort on deq_task");
            task_deq_valid_reg <= 1'b0;
         end
         if (deq_non_splitter) begin
            deq_valid_cycle_count <= 0;
         end else if (task_deq_valid_reg) begin
            deq_valid_cycle_count <= deq_valid_cycle_count + 1;
         end
         deq_splitter_q <= deq_splitter;
         deq_non_splitter_q <= deq_non_splitter;
         if (task_deq_valid & !task_deq_ready & 
              (heap_out_valid &
               (next_deque_elem.ts < task_deq_data.ts) & (next_deque_elem.ts < cq_max_vt_ts )
              ) 
            ) begin
            // The condition on cq_max_vt_ts is necessary because otherwise cq
            // might resource-abort a task that has a lower vt than any
            // unfinished task in the tile; causing the GVT to temperorily 
            // go back while the abort is being completed
            task_deq_force <= 1'b1;
         end else begin
            task_deq_force <= 1'b0;
         end
      end
   end

   task_t reg_splitter_task, reg_non_splitter_task;
   always_ff @(posedge clk) begin
      if (deq_splitter_q) begin
         reg_splitter_task <= tq_read_data;
      end
      if (deq_non_splitter_q) begin
         reg_non_splitter_task <= tq_read_data;
      end
   end
   
   assign splitter_deq_task = (deq_splitter_q) ? tq_read_data : reg_splitter_task;
   assign task_deq_data = (deq_non_splitter_q) ? tq_read_data : reg_non_splitter_task;

   assign overflow_data = tq_read_data;

   logic task_enq_ack;
   assign task_enq_ack = !(task_enq_tied & (n_tied_tasks == task_unit_tied_capacity));
   
   // Controllers for individual data structures
   //1. tied_task write
   always_comb begin
      tied_task_wr_en = 1'b0;
      tied_task_wr_addr = 'x;
      tied_task_wr_data = 'x;
      if (coal_child_ready | task_enq_ready) begin
         tied_task_wr_en = 1'b1;
         tied_task_wr_addr = next_free_tq_slot;
         tied_task_wr_data = coal_child_ready ? 1'b0 : task_enq_tied;
      end else if (cut_ties_ready & cut_ties_epoch_match) begin
         tied_task_wr_en = 1'b1;
         tied_task_wr_addr = cut_ties_tq_slot;
         tied_task_wr_data = 1'b0;
      end
   end

   // 2. Dequeued / cq_slot
   always_comb begin
      dequeued_task_wr_en = 1'b0;
      dequeued_task_wr_addr = 'x;
      dequeued_task_wr_data = 'x;
      if (coal_child_ready | task_enq_ready) begin
         dequeued_task_wr_en = 1'b1;
         dequeued_task_wr_addr = next_free_tq_slot;
         dequeued_task_wr_data = 1'b0;
      end else if (deq_splitter | deq_non_splitter) begin
         dequeued_task_wr_en = 1'b1;
         dequeued_task_wr_addr = next_deque_elem.slot;
         dequeued_task_wr_data = 1'b1;
      end else if (abort_task_ready) begin
         dequeued_task_wr_en = 1'b1;
         dequeued_task_wr_addr = abort_task_slot;
         dequeued_task_wr_data = 1'b0;
      end
   end

   assign cq_slot_wr_en = task_deq_valid & task_deq_ready;
   assign cq_slot_wr_addr = task_deq_tq_slot;
   assign cq_slot_wr_data = task_deq_cq_slot;


   // 3. epoch write / free_list enq
   always_comb begin 
      epoch_wr_en = 1'b0;
      epoch_wr_addr = 'x;
      overflow_epoch_fifo_rd_en = 1'b0;
      if (commit_task_ready) begin
         epoch_wr_en = 1'b1;
         epoch_wr_addr = commit_task_slot;
      end else if (abort_child_ready) begin
         epoch_wr_en = 1'b1;
         epoch_wr_addr = abort_child_tq_slot;
      end else if (deq_splitter) begin
         epoch_wr_en = 1'b1;
         epoch_wr_addr = next_deque_elem.slot;
      end else if (!overflow_epoch_fifo_empty) begin
         epoch_wr_en = 1'b1;
         epoch_wr_addr = overflow_epoch_fifo_rd_data;
         overflow_epoch_fifo_rd_en = 1'b1;
      end
      epoch_wr_data = epoch[epoch_wr_addr]+1;
      add_free_tq_slot_valid = epoch_wr_en;
      add_free_tq_slot = epoch_wr_addr;
      
   end

   // 4. spill_heap enq
   assign spill_next_insert_elem_ts = reg_spill_heap_enq.ts;
   assign spill_next_insert_elem_slot = reg_spill_heap_enq.slot;
   always_comb begin
      spill_heap_in_op = NOP;
      if (spill_heap_ready) begin
         if (reg_spill_heap_enq_valid) begin
            spill_heap_in_op = ENQ;
         end else if (spill_heap_deq_task) begin
            spill_heap_in_op = DEQ_MIN;
         end
      end

   end

   // Task_heap enq / task_array write / free_list deq
   always_comb begin
      next_insert_elem_set = 1'b0;
      next_insert_elem = 'x;
      next_free_tq_slot_deque = 1'b0;
      tq_write_valid = 1'b0;
      tq_write_addr = 'x;
      tq_write_data = 'x;
      next_insert_elem.non_spec = 1'b0;
      if (coal_child_ready) begin
         next_insert_elem_set = 1'b1;
         next_insert_elem.ts = coal_child_data.ts; 
         next_insert_elem.epoch = epoch[next_free_tq_slot];
         next_insert_elem.slot = next_free_tq_slot;
         next_insert_elem.splitter = 1'b1;
         next_insert_elem.producer = 1'b1;
         next_free_tq_slot_deque = 1'b1;
         tq_write_valid = 1'b1;
         tq_write_data = coal_child_data; 
         tq_write_addr = next_free_tq_slot;
      end else if (task_enq_ready) begin
         if (task_enq_ack) begin
            next_insert_elem_set = 1'b1;
            next_insert_elem.ts = modified_task_enq_ts; 
            next_insert_elem.epoch = epoch[next_free_tq_slot];
            next_insert_elem.slot = next_free_tq_slot;
            next_insert_elem.splitter = (task_enq_data.ttype == TASK_TYPE_SPLITTER);
            next_insert_elem.producer = task_enq_data.producer;
            next_insert_elem.non_spec = task_enq_data.non_spec;
            next_free_tq_slot_deque = 1'b1;
            tq_write_valid = 1'b1;
            tq_write_data = task_enq_data;
            tq_write_data.ts = modified_task_enq_ts;
            tq_write_addr = next_free_tq_slot;
         end
      end else if (abort_task_ready) begin
         next_insert_elem_set = 1'b1;
         next_insert_elem.ts = abort_task_ts; 
         next_insert_elem.epoch = abort_task_epoch;
         next_insert_elem.slot = abort_task_slot;
         next_insert_elem.splitter = 1'b0;
         next_insert_elem.producer = 1'b0;
      end
   end

   // task_resp
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_resp_valid <= 1'b0;
      end else begin
         if (task_enq_ready) begin
            task_resp_valid <= 1'b1;
            task_resp_ack <= task_enq_ack;
            task_resp_dest_tile <= task_enq_resp_tile;
            task_resp_epoch <= epoch[next_free_tq_slot];
            task_resp_tsb_id <= task_enq_resp_tsb_id;
            task_resp_tq_slot <= next_free_tq_slot;
         end else if (task_resp_ready) begin
            task_resp_valid <= 1'b0;
         end
      end
   end

   // abort_resp
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
         abort_resp_valid <= 1'b0;
      end else begin
         if (abort_child_ready) begin
            abort_resp_valid <= 1'b1;
            abort_resp_tile <= abort_child_resp_tile;
            abort_resp_cq_slot <= abort_child_resp_cq_slot;
            abort_resp_child_id <= abort_child_resp_child_id;
         end else if (abort_resp_ready) begin
            abort_resp_valid <= 1'b0;
         end
      end
   end
   
   ts_t cq_child_abort_ts; // for LVT 
   logic cq_child_abort_valid_q;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         cq_child_abort_valid <= 1'b0;
         cq_child_abort_valid_q <= 1'b0;
      end else begin
         if (abort_child_ready & (dequeued_task[abort_child_tq_slot]) 
               & !(task_deq_valid_reg & (task_deq_tq_slot == abort_child_tq_slot)) ) begin
            cq_child_abort_valid <= 1'b1;
            cq_child_abort_slot <= cq_slot[abort_child_tq_slot];
         end else if (cq_child_abort_ready) begin
            cq_child_abort_valid <= 1'b0;
         end
      end
      cq_child_abort_valid_q <= cq_child_abort_valid;
      if (abort_child_ready_q) begin
         cq_child_abort_ts <= tq_read_data.ts; 
      end
   end
   
   

   // heap controller
   // Register the incoming task

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


   always_comb begin
      heap_in_op = NOP;
      next_insert_elem_clear = 1'b0;
      heap_enq_elem = 'x;
      if (!rstn) begin
      end else begin
         if (heap_ready) begin // cannot start if started last cycle
            if ( (reg_next_insert_elem_valid | heap_re_enq_elem_valid) & deq_task)  begin
               heap_in_op = REPLACE;
               next_insert_elem_clear = !heap_re_enq_elem_valid;
               heap_enq_elem = (heap_re_enq_elem_valid ? heap_re_enq_elem : reg_next_insert_elem);
            end else if (reg_next_insert_elem_valid | heap_re_enq_elem_valid) begin
               heap_in_op = ENQ;
               next_insert_elem_clear = !heap_re_enq_elem_valid;
               heap_enq_elem = (heap_re_enq_elem_valid ? heap_re_enq_elem : reg_next_insert_elem);
            end else if (deq_task) begin
               heap_in_op = DEQ_MIN;
            end else if (can_issue_deq_max) begin
               heap_in_op = DEQ_MAX;
            end
         end
      end
   end
   
   always_ff @ (posedge clk) begin
      if (deq_task) assert(heap_ready)  else $error("Trying to deq when heap not ready");
   end

   logic n_tied_tasks_inc;
   logic n_tied_tasks_dec_cut_ties;
   logic n_tied_tasks_dec_abort_child;
   logic n_tied_tasks_dec_commit_task;
   assign n_tied_tasks_inc = (task_enq_ready & task_enq_tied & task_enq_ack);

   assign n_tied_tasks_dec_cut_ties = (cut_ties_ready & cut_ties_epoch_match);
   assign n_tied_tasks_dec_abort_child =  (abort_child_ready & tied_task[abort_child_tq_slot])
                  & !(n_tied_tasks_dec_cut_ties & (cut_ties_tq_slot == abort_child_tq_slot)) ; 
   assign n_tied_tasks_dec_commit_task =  (commit_task_ready & tied_task[commit_task_slot])
                  & !(n_tied_tasks_dec_cut_ties & (cut_ties_tq_slot == commit_task_slot)) ; 

   tq_slot_t new_n_tied_tasks, new_n_tasks;
   assign new_n_tasks= n_tasks + next_free_tq_slot_deque - add_free_tq_slot_valid;               
   assign new_n_tied_tasks = n_tied_tasks + n_tied_tasks_inc -
                        n_tied_tasks_dec_cut_ties -
                        n_tied_tasks_dec_abort_child - 
                        n_tied_tasks_dec_commit_task;


   always_ff @(posedge clk) begin
      if (!rstn) begin
         n_tied_tasks <= 0;
         n_tasks <= 0;
      end else begin
         n_tasks <= new_n_tasks;
         n_tied_tasks <= new_n_tied_tasks;
      end
   end



   logic last_op_was_enq; 
   // prevents a corner case where empty is asserted even when an enq was in the pipeline. 
   always_ff @(posedge clk) 
      last_op_was_enq <= (heap_in_op==ENQ);
   assign empty = (heap_capacity ==  2**(TQ_STAGES) -1) & !last_op_was_enq;
   assign full =  (heap_capacity == 0);
   assign almost_full = ((heap_capacity < 10) & task_enq_tied) | (full & !task_enq_tied);

   ts_t lvt_heap;
   ts_t lvt_abort;
   ts_t lvt_deq_task;
   ts_t lvt_splitter_task;
   ts_t lvt_deq_splitter;

   assign lvt_deq_task = (task_deq_valid ? task_deq_data.ts : '1);
   assign lvt_splitter_task = (splitter_deq_valid ? splitter_deq_task.ts : '1);

   ts_t lvt_main_heap, lvt_spill_heap;
   assign lvt_main_heap = heap_out_valid? next_deque_elem.ts : '1;
   assign lvt_spill_heap = spill_heap_out_valid ? spill_next_deque_elem_ts : '1; 

   
   // A replace op can temperorily set the heap top to be new insert element
   // Therefore take the minimum value of last two cycles
   ts_t lvt_heap_1, lvt_heap_2;
   always @(posedge clk) begin
      if (!rstn) begin 
         lvt_deq_splitter <= '1;
         lvt_heap_1 <= '1;
         lvt_heap_2 <= '1;
      end else begin
         lvt_deq_splitter <= (lvt_deq_task < lvt_splitter_task) ?
                                 lvt_deq_task : lvt_splitter_task;
         if (!tq_started) begin
            lvt_heap_1 <= 0;
         end else if (lvt_main_heap < lvt_spill_heap) begin
            lvt_heap_1 <= lvt_main_heap;
         end else begin
            lvt_heap_1 <= lvt_spill_heap;
         end
         lvt_heap_2 <= (lvt_heap_1 < lvt_deq_splitter) ? lvt_heap_1 : lvt_deq_splitter;
      end
      lvt_heap <= (lvt_heap_1 < lvt_heap_2) ? lvt_heap_1 : lvt_heap_2;
      // A delay of 1 cycle in cq_child_abort_ts is fine since the abort
      // inducing task will continue to hold back the GVT in the mean time
      lvt_abort <= cq_child_abort_valid_q ? cq_child_abort_ts : '1;
      lvt <= lvt_heap < lvt_abort ? lvt_heap : lvt_abort;
   end
   

   
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
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) task_enqueue slot:%4d ts:%8x locale:%8x ttype:%1x args:(%4d %4d) tied:%d \t\t resp:(ack:%d tile:%2d tsb:%2d) \n", 
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, next_free_tq_slot, 
               modified_task_enq_ts, task_enq_data.locale, 
               task_enq_data.ttype,
               task_enq_data.args[63:32], task_enq_data.args[23:0],
               task_enq_tied, task_enq_ack,
               task_enq_resp_tile, task_enq_resp_tsb_id
            ) ;
         end
         if (coal_child_valid & coal_child_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) coal_child   slot:%4d ts:%8x locale:%8x \n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, next_free_tq_slot,
               coal_child_data.ts, coal_child_data.locale) ;
         end
         if (overflow_valid & overflow_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) overflow     slot:%4d ts:%8x locale:%8x \n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, tq_read_addr_q,
               overflow_data.ts, overflow_data.locale) ;
         end
         if (task_deq_valid & task_deq_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) task_deq     slot:%4d ts:%8x locale:%8x cq_slot:%2d\n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, task_deq_tq_slot,
               task_deq_data.ts, task_deq_data.locale, task_deq_cq_slot) ;
         end
         if (splitter_deq_valid & splitter_deq_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) splitter_deq slot:%4d ts:%8x locale:%8x \n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, splitter_deq_slot,
               splitter_deq_task.ts, splitter_deq_task.locale ) ;
         end
         if (cut_ties_valid & cut_ties_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) cut_ties     slot:%4d epoch(%3d,%3d) tied:%d \n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, cut_ties_tq_slot,
               epoch[cut_ties_tq_slot], cut_ties_epoch, tied_task[cut_ties_tq_slot] ) ;
         end
         if (commit_task_valid & commit_task_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) commit_task  slot:%4d epoch(%3d,%3d) tied:%d \n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, commit_task_slot,
               epoch[commit_task_slot], commit_task_epoch, tied_task[commit_task_slot] ) ;
         end
         if (abort_child_valid & abort_child_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) abort_child  slot:%4d epoch(%3d,%3d) tied:%d dequeued:%d \n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, abort_child_tq_slot,
               epoch[abort_child_tq_slot], abort_child_epoch, tied_task[abort_child_tq_slot],
               dequeued_task[abort_child_tq_slot] ) ;
         end
         if (abort_task_valid & abort_task_ready) begin
            $fwrite(file,"[%5d] [rob-%2d] (%4d:%4d:%4d) abort_task   slot:%4d epoch(%3d,%3d) tied:%d \n",
               cycle, TILE_ID, new_n_tasks, new_n_tied_tasks, heap_capacity, abort_task_slot,
               epoch[abort_task_slot], abort_task_epoch, tied_task[abort_task_slot] ) ;
         end
         $fflush(file);
      end
   end
`endif


   logic [31:0] n_untied_enq, n_tied_enq_ack, n_tied_enq_nack;
   logic [31:0] n_deq_task, n_splitter_deq, n_deq_epoch_mismatch;
   logic [31:0] n_cut_ties_epoch_match, n_cut_ties_epoch_mismatch;
   logic [31:0] n_commit_tied, n_commit_untied;
   logic [31:0] n_abort_child_dequeued, n_abort_child_not_dequeued;
   logic [31:0] n_abort_task;

   logic [31:0] n_abort_child_epoch_mismatch; // has to be zero
   logic [31:0] n_commit_epoch_mismatch;
   logic [31:0] n_cut_ties_and_commit_or_abort; 
   
   logic [31:0] n_coal_child;
   logic [31:0] n_overflow;

   logic [31:0] n_cycles_task_deq_valid; 


   logic [31:0] state_stats [0:7];

   logic [31:0] n_heap_enq;
   logic [31:0] n_heap_replace;
   logic [31:0] n_heap_deq;

   logic [47:0] cum_tasks;
   logic [47:0] cum_heap_util;
generate
if(TQ_STATS[TILE_ID]) begin // Approximate cost: 1000 LUTs/500 FFs
   initial begin
      for (integer i=0;i<8;i++) begin
         state_stats[i] = 0;
      end
   end
   always_ff @(posedge clk) begin
      if (n_tasks != 0) begin
         state_stats[tq_state] <= state_stats[tq_state] + 1;
      end
   end
   always_ff @(posedge clk) begin
      if (!rstn) begin
         n_untied_enq <= 0;
         n_tied_enq_ack <= 0;
         n_tied_enq_nack <= 0;

         n_deq_task <= 0;
         n_splitter_deq <= 0;
         n_deq_epoch_mismatch <= 0;

         n_cut_ties_epoch_match <= 0;
         n_cut_ties_epoch_mismatch <= 0;

         n_commit_tied <= 0;
         n_commit_untied <= 0;
         n_commit_epoch_mismatch <= 0;

         n_abort_child_dequeued <= 0;
         n_abort_child_not_dequeued <= 0;
         n_abort_child_epoch_mismatch <= 0;

         n_abort_task <= 0;
         
         n_cut_ties_and_commit_or_abort <= 0;

         n_coal_child <= 0;
         n_overflow <= 0;

         n_cycles_task_deq_valid <= 0;

         n_heap_enq <= 0;
         n_heap_deq <= 0;
         n_heap_replace <= 0;

         cum_tasks <= 0;
         cum_heap_util <= 0;
      end else begin
         if (task_enq_valid & task_enq_ready) begin
            if (!task_enq_tied) begin
               n_untied_enq <= n_untied_enq + 1;
            end else begin
               if (task_enq_ack) begin
                  n_tied_enq_ack <= n_tied_enq_ack + 1;
               end else begin
                  n_tied_enq_nack <= n_tied_enq_nack + 1;
               end
            end
         end

         cum_tasks <= cum_tasks + n_tasks;
         cum_heap_util <= cum_heap_util + (2**TQ_STAGES - 1 - heap_capacity);

         if (heap_in_op == ENQ) begin
            n_heap_enq <= n_heap_enq+1;
         end
         if (heap_in_op == DEQ_MIN) begin
            n_heap_deq <= n_heap_deq+1;
         end
         if (heap_in_op == REPLACE) begin
            n_heap_replace <= n_heap_replace+1;
         end

         if (task_deq_valid & task_deq_ready) begin
            n_deq_task <= n_deq_task + 1;
         end
         if (splitter_deq_valid & splitter_deq_ready) begin
            n_splitter_deq <= n_splitter_deq + 1;
         end
         if (deq_task & !deq_epoch_match ) begin
            n_deq_epoch_mismatch <= n_deq_epoch_mismatch + 1;
         end
         if (cut_ties_valid & cut_ties_ready) begin
            if (cut_ties_epoch_match) begin
               n_cut_ties_epoch_match <= n_cut_ties_epoch_match + 1;
            end else begin
               n_cut_ties_epoch_mismatch <= n_cut_ties_epoch_mismatch + 1;
            end
         end
         if (commit_task_valid & commit_task_ready) begin
            if (tied_task[commit_task_slot]) begin
               n_commit_tied <= n_commit_tied + 1;
            end else begin
               n_commit_untied <= n_commit_untied + 1;
            end
            if (commit_task_epoch != epoch[commit_task_slot]) begin
               n_commit_epoch_mismatch <= n_commit_epoch_mismatch + 1;
            end
         end
         if (abort_child_valid & abort_child_ready) begin
            if (dequeued_task[abort_child_tq_slot]) begin
               n_abort_child_dequeued <= n_abort_child_dequeued + 1;
            end else begin
               n_abort_child_not_dequeued <= n_abort_child_not_dequeued + 1;
            end
            if (abort_child_epoch != epoch[abort_child_tq_slot]) begin
               n_abort_child_epoch_mismatch <= n_abort_child_epoch_mismatch + 1;
            end
         end
         if (abort_task_valid & abort_task_ready) begin
            n_abort_task <= n_abort_task + 1;    
         end
         if (cut_ties_ready & cut_ties_epoch_match) begin
            if (abort_child_ready & tied_task[abort_child_tq_slot] 
                  & (cut_ties_tq_slot == abort_child_tq_slot)) begin
               n_cut_ties_and_commit_or_abort <= n_cut_ties_and_commit_or_abort + 1;
            end else if (commit_task_ready & tied_task[commit_task_slot] &
                     (cut_ties_tq_slot == commit_task_slot)) begin
               n_cut_ties_and_commit_or_abort <= n_cut_ties_and_commit_or_abort + 1;
            end
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

   logic [1:0] alt_log_word; // 0-enq_args, 1-deq_ts,locale, 2-heap_ops

   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_unit_throttle_margin <= NON_SPEC ? 1000 : 0;
         task_spill_threshold <= SPILL_THRESHOLD;
         task_unit_tied_capacity <= (2**(LOG_TQ_SIZE-2) -1 );
         task_unit_clean_threshold <= 40;
         task_unit_spill_size <= 32; // has to be muliple of 8
         tq_stall <= 0;
         tq_started <= 0;
         alt_log_word <= 0;

         is_transactional <= 1'b0;
         maxflow_global_relabel_trigger_mask <= '1;
         maxflow_global_relabel_trigger_inc <= 1;
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               TASK_UNIT_THROTTLE_MARGIN : task_unit_throttle_margin <= reg_bus.wdata;
               TASK_UNIT_SPILL_THRESHOLD : task_spill_threshold <= reg_bus.wdata;
               TASK_UNIT_TIED_CAPACITY : task_unit_tied_capacity <= reg_bus.wdata;
               TASK_UNIT_CLEAN_THRESHOLD : task_unit_clean_threshold <= reg_bus.wdata;
               TASK_UNIT_SPILL_SIZE   : begin 
                     task_unit_spill_size <= reg_bus.wdata;
                  end
               TASK_UNIT_STALL : tq_stall <= reg_bus.wdata;
               TASK_UNIT_START : tq_started <= reg_bus.wdata;
               TASK_UNIT_ALT_LOG : alt_log_word <= reg_bus.wdata;

               TASK_UNIT_IS_TRANSACTIONAL: is_transactional <= reg_bus.wdata;
               TASK_UNIT_GLOBAL_RELABEL_START_MASK : maxflow_global_relabel_trigger_mask <= reg_bus.wdata;
               TASK_UNIT_GLOBAL_RELABEL_START_INC : maxflow_global_relabel_trigger_inc <= reg_bus.wdata;
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
            TASK_UNIT_HEAP_CAPACITY : reg_bus.rdata <= heap_capacity;
            DEBUG_CAPACITY : reg_bus.rdata <= log_size;
            TASK_UNIT_LVT : reg_bus.rdata <= lvt;
            TASK_UNIT_N_TASKS : reg_bus.rdata <= n_tasks;
            TASK_UNIT_N_TIED_TASKS : reg_bus.rdata <= n_tied_tasks;
            
            TASK_UNIT_STAT_N_UNTIED_ENQ          : reg_bus.rdata <= n_untied_enq;
            TASK_UNIT_STAT_N_TIED_ENQ_ACK        : reg_bus.rdata <= n_tied_enq_ack;
            TASK_UNIT_STAT_N_TIED_ENQ_NACK       : reg_bus.rdata <= n_tied_enq_nack;
            TASK_UNIT_STAT_N_DEQ_TASK            : reg_bus.rdata <= n_deq_task;
            TASK_UNIT_STAT_N_SPLITTER_DEQ        : reg_bus.rdata <= n_splitter_deq;
            TASK_UNIT_STAT_N_DEQ_MISMATCH        : reg_bus.rdata <= n_deq_epoch_mismatch;
            TASK_UNIT_STAT_N_CUT_TIES_MATCH      : reg_bus.rdata <= n_cut_ties_epoch_match;
            TASK_UNIT_STAT_N_CUT_TIES_MISMATCH   : reg_bus.rdata <= n_cut_ties_epoch_mismatch; 
            TASK_UNIT_STAT_N_CUT_TIES_COM_ABO    : reg_bus.rdata <= n_cut_ties_and_commit_or_abort;
            TASK_UNIT_STAT_N_COMMIT_TIED         : reg_bus.rdata <= n_commit_tied;
            TASK_UNIT_STAT_N_COMMIT_UNTIED       : reg_bus.rdata <= n_commit_untied;
            TASK_UNIT_STAT_N_COMMIT_MISMATCH     : reg_bus.rdata <= n_commit_epoch_mismatch;
            TASK_UNIT_STAT_N_ABORT_CHILD_DEQ     : reg_bus.rdata <= n_abort_child_dequeued;
            TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ : reg_bus.rdata <= n_abort_child_not_dequeued;
            TASK_UNIT_STAT_N_ABORT_CHILD_MISMATCH: reg_bus.rdata <= n_abort_child_epoch_mismatch;
            TASK_UNIT_STAT_N_ABORT_TASK          : reg_bus.rdata <= n_abort_task;
            TASK_UNIT_STAT_N_COAL_CHILD          : reg_bus.rdata <= n_coal_child;
            TASK_UNIT_STAT_N_OVERFLOW            : reg_bus.rdata <= n_overflow;
            TASK_UNIT_STAT_N_CYCLES_DEQ_VALID    : reg_bus.rdata <= n_cycles_task_deq_valid;
   
            TASK_UNIT_STAT_N_HEAP_ENQ   : reg_bus.rdata <= n_heap_enq;
            TASK_UNIT_STAT_N_HEAP_DEQ   : reg_bus.rdata <= n_heap_deq;
            TASK_UNIT_STAT_N_HEAP_REPLACE   : reg_bus.rdata <= n_heap_replace;
            
            TASK_UNIT_STAT_AVG_TASKS   : reg_bus.rdata <= cum_tasks[47:16];
            TASK_UNIT_STAT_AVG_HEAP_UTIL   : reg_bus.rdata <= cum_heap_util[47:16];
            
            TASK_UNIT_STATS_0_BEGIN : reg_bus.rdata <= state_stats[{1'b0, reg_bus.araddr[3:2]}];
            TASK_UNIT_STATS_1_BEGIN : reg_bus.rdata <= state_stats[{1'b1, reg_bus.araddr[3:2]}];

            TASK_UNIT_MISC_DEBUG : reg_bus.rdata <= {overflow_valid, overflow_ready, abort_child_valid, task_enq_valid, cut_ties_valid, cq_child_abort_valid, abort_task_valid, abort_resp_valid, task_deq_valid_reg, commit_task_valid, task_deq_ready};
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
      ts_t gvt_tb;
      ts_t gvt_ts;
      
      locale_t deq_locale;
      ts_t deq_ts;

      msg_type_t  commit_task_abort_child;
      msg_type_t  abort_task;
      msg_type_t  cut_ties;
      msg_type_t  deq_task;
      msg_type_t  overflow_task;
      msg_type_t  enq_task_coal_child;


      // enq parameters 
      locale_t enq_locale; 
      ts_t   enq_ts;
      
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
      log_word.heap_capacity = heap_capacity; 
      log_word.n_tasks = new_n_tasks;
      log_word.n_tied_tasks = new_n_tied_tasks;


      log_word.overflow_task.valid = overflow_valid;
      log_word.overflow_task.ready = overflow_ready;
      log_word.overflow_task.slot = add_free_tq_slot;
      log_word.deq_task.valid = task_deq_valid;
      log_word.deq_task.ready = task_deq_ready;
      log_word.deq_task.epoch_1 = task_deq_cq_slot; // valid for task and splitter deq
      log_word.deq_task.epoch_2 = epoch[task_deq_tq_slot]; 
      log_word.cut_ties.valid = cut_ties_valid;
      log_word.cut_ties.ready = cut_ties_ready;
      log_word.abort_task.valid = abort_task_valid;
      log_word.abort_task.ready = abort_task_ready;

      log_word.splitter_deq_valid = splitter_deq_valid;
      log_word.splitter_deq_ready = splitter_deq_ready;

      log_word.resp_tsb_id = task_enq_resp_tsb_id;
      log_word.resp_tile_id = task_enq_resp_tile;
      log_word.resp_ack = task_enq_ack;

      log_word.gvt_tb = gvt.tb;
      log_word.gvt_ts = gvt.ts;

      if (task_enq_valid & task_enq_ready) begin
        log_word.enq_task_n_coal_child = 1'b1;
        log_word.enq_ttype = task_enq_data.ttype;
        log_word.enq_locale  = task_enq_data.locale;
        log_word.enq_ts    = modified_task_enq_ts;
        log_word.enq_task_coal_child.tied  = task_enq_tied;
        log_word.enq_task_coal_child.valid = task_enq_valid;
        log_word.enq_task_coal_child.ready = task_enq_ready;
        log_word.enq_task_coal_child.slot  = next_free_tq_slot;
        log_word.enq_task_coal_child.epoch_1 = epoch[next_free_tq_slot];
        if ( (alt_log_word==1) & ARG_WIDTH >= 32) begin
           log_word.deq_locale = task_enq_data.args[31:0] ;
        end
        if ( (alt_log_word==1) & ARG_WIDTH >= 64) begin
           log_word.deq_ts   = task_enq_data.args[63:32];
        end
        if (alt_log_word & ARG_WIDTH >= 65) begin
           //log_word.gvt_tb = task_enq_data.args[95:64];
        end
        log_valid = 1;
     end else if (coal_child_valid & coal_child_ready) begin
        log_word.enq_task_n_coal_child = 1'b0;
        log_word.enq_ttype = coal_child_data.ttype;
        log_word.enq_locale  = coal_child_data.locale;
        log_word.enq_ts    = coal_child_data.ts;
        log_word.enq_task_coal_child.valid = coal_child_valid;
        log_word.enq_task_coal_child.ready = coal_child_ready;
        log_word.enq_task_coal_child.slot  = next_free_tq_slot;
        log_word.enq_task_coal_child.epoch_1 = epoch[next_free_tq_slot];
        log_valid = 1;
     end 
     if (task_deq_valid & task_deq_ready) begin
        log_word.deq_task.slot    = task_deq_tq_slot;
        log_word.deq_task.tied    = tied_task[task_deq_tq_slot];

        if (alt_log_word == 0) begin
           log_word.deq_locale = task_deq_data.locale;
           log_word.deq_ts   = task_deq_data.ts;
        end
        log_valid = 1;
     end else if (splitter_deq_valid & splitter_deq_ready) begin
        log_word.deq_task.slot    =  splitter_deq_slot;
        if (alt_log_word ==0) begin
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
        log_word.commit_task_abort_child.epoch_2  = epoch[commit_task_slot];
        log_word.commit_task_abort_child.tied     = tied_task[commit_task_slot];
        log_valid = 1'b1;
     end else if (abort_child_valid & abort_child_ready) begin
        log_word.commit_n_abort_child = 1'b0;
        log_word.commit_task_abort_child.valid = 1'b1;
        log_word.commit_task_abort_child.ready = 1'b1;
        log_word.commit_task_abort_child.slot     = abort_child_tq_slot;
        log_word.commit_task_abort_child.epoch_1  = abort_child_epoch;
        log_word.commit_task_abort_child.epoch_2  = epoch[abort_child_tq_slot];
        log_word.commit_task_abort_child.tied     = tied_task[abort_child_tq_slot];
        log_valid = 1'b1;
     end
     if (cut_ties_valid & cut_ties_ready) begin
        log_word.cut_ties.slot     = cut_ties_tq_slot;
        log_word.cut_ties.epoch_1  = cut_ties_epoch;
        log_word.cut_ties.epoch_2  = epoch[cut_ties_tq_slot];
        log_word.cut_ties.tied     = tied_task[cut_ties_tq_slot];
        log_valid = 1'b1;
     end
     if (abort_task_valid & abort_task_ready) begin
        log_word.abort_task.slot     = abort_task_slot;
        log_word.abort_task.epoch_1  = abort_task_epoch;
        log_word.abort_task.epoch_2  = epoch[abort_task_slot];
        log_word.abort_task.tied     = tied_task[abort_task_slot];
        log_valid = 1'b1;
     end
     if (overflow_valid & overflow_ready) begin
        log_valid = 1'b1;
     end
     if ((alt_log_word == 2) & next_max_elem_valid) begin
        log_word.deq_ts[7:0] = next_max_elem.epoch; 
        log_word.deq_ts[15:8] = epoch[next_max_elem.slot];
        log_word.deq_ts[28:16] = next_max_elem.slot;
        log_word.deq_ts[29] = max_elem_is_tied;
        log_word.deq_ts[30] = 1'b1;
        log_word.deq_ts[31] = next_max_elem_valid;
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

module task_array 
( 
   input clk,
   input rstn,

   input tq_slot_t raddr,
   input tq_slot_t waddr,
   
   input  task_t wdata,
   output task_t rdata,
   input en,
   input wr

);
   localparam ENTRY_WIDTH = $bits(wdata);
   (* ram_style = "block" *)
   logic[ENTRY_WIDTH-1:0] array [0:2**LOG_TQ_SIZE-1];
   task_t out;
   
   always_ff @(posedge clk) begin
      if (en) begin
         if (wr) begin 
            array[waddr] <= wdata;
         end
         out <= array[raddr];
      end
   end
   
   // ensure write first behaviour in simulation.
   logic addr_collision;
   task_t p_wdata;
   always @(posedge clk) begin
      if (en) begin
         addr_collision <= (wr & (waddr == raddr));
         p_wdata <= wdata;
      end
   end

   assign rdata = addr_collision ? p_wdata : out;

endmodule

// Same as fifo from util.sv, but initialized to 1..2..2**LOG_TQ_SIZE-1
