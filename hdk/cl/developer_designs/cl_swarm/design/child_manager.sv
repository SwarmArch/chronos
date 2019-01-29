`include "config.sv"

import swarm::*;

typedef enum logic [1:0] {CHILD_SENT, CHILD_ACKED, CHILD_NACKED, CHILD_FINALIZED} child_state_t;
typedef enum logic [0:0] {REQ_CUT_TIE, REQ_ABORT} child_req_t;

typedef struct packed {
   child_state_t state;
   tile_id_t tile;
   tq_slot_t slot; // doubles up for tsb_slot when (CHILD_NACKED).
                   // Any resonable implementation should have a TQ at least as
                   // large as TSB. TODO (add assert)
   epoch_t   epoch; 
} child_ptr_t;

typedef logic [31:0] cycle_t; 

typedef struct packed {
   child_req_t       req_type;
   cq_slice_slot_t   cq_slot;
   child_id_t       child_id;
   child_id_t       max_children;
} req_fifo_data_t;

typedef struct packed {
   cq_slice_slot_t   cq_slot;
   child_id_t       child_id;
   tsb_entry_id_t    tsb_slot;
   cycle_t           retry_cycle;
} nack_fifo_data_t;

localparam CHILD_PTR_WIDTH = (LOG_N_TILES + LOG_TQ_SIZE + EPOCH_WIDTH); //excluding state
module child_manager #(
		parameter NUM_SI = 2
	) (
	input clk,
	input rstn,
    
    // from cores
	input                   [NUM_SI-1:0] s_wvalid ,
	output logic            [NUM_SI-1:0] s_wready,
	input task_t            [NUM_SI-1:0] s_wdata,
   input                   [NUM_SI-1:0] s_enq_untied,
	input cq_slice_slot_t   [NUM_SI-1:0] s_cq_slot,
	input child_id_t        [NUM_SI-1:0] s_child_id,

    // TSB: Task Req
	output logic            task_enq_valid,
	input                   task_enq_ready,
	output task_t           task_enq_data,
   output logic            task_enq_tied,
   output cq_slice_slot_t  task_enq_resp_cq_slot,
   output child_id_t       task_enq_resp_child_id,

   input                   task_enq_only_untied,

   // TSB: Task retry after nack
   output logic            task_retry_valid,
   input                   task_retry_ready,
   output tsb_entry_id_t   task_retry_tsb_id,
   output logic            task_retry_abort,
   output logic            task_retry_tied,

   // TSB: Task Resp
   input                   task_resp_valid,
   output                  task_resp_ready,
   input                   task_resp_ack,
   input cq_slice_slot_t   task_resp_cq_slot, 
   input tsb_entry_id_t    task_resp_tsb_slot,
   input child_id_t        task_resp_child_id,
   input epoch_t           task_resp_epoch,
   input tq_slot_t         task_resp_tq_slot,
   input tile_id_t         task_resp_tile_id,

   // CQ: Abort children
   input                   cq_abort_children_valid,
   output logic            cq_abort_children_ready,
   input cq_slice_slot_t   cq_abort_children_cq_slot,
   input child_id_t        cq_abort_children_count,

   input                   cq_cut_ties_valid,
   output logic            cq_cut_ties_ready,
   input cq_slice_slot_t   cq_cut_ties_cq_slot,
   input child_id_t        cq_cut_ties_count,

   // Tile : Abort Req
   output logic            abort_child_valid,
   input                   abort_child_ready,
   output epoch_t          abort_child_epoch,
   output tq_slot_t        abort_child_tq_slot,
   output tile_id_t        abort_child_tile_id,
   output child_id_t       abort_child_resp_child_id,
   output cq_slice_slot_t  abort_child_resp_cq_slot,
   
   // Tile : Cut Ties Req
   output logic            cut_ties_valid,
   input                   cut_ties_ready,
   output epoch_t          cut_ties_epoch,
   output tq_slot_t        cut_ties_tq_slot,
   output tile_id_t        cut_ties_tile_id,

   // Tile : Abort Resp
   input logic             abort_resp_valid,
   output logic            abort_resp_ready,
   input cq_slice_slot_t   abort_resp_cq_slot,
   input child_id_t        abort_resp_child_id,

   // CQ: Abort ACK
   output logic            abort_children_ack_valid,
   input logic             abort_children_ack_ready,
   output cq_slice_slot_t  abort_children_ack_cq_slot,

   output logic            cut_ties_ack_valid,
   input logic             cut_ties_ack_ready,
   output cq_slice_slot_t  cut_ties_ack_cq_slot,
   
   output ts_t    lvt,
   reg_bus_t         reg_bus

);
   // Major structures
   // 1. Request FIFO : buffers the incoming cut_tie and abort_children requests,
   //    format = {type, cq_slot, child_id, max_children}
   // 2. Children Array : Stores the state and location of children
   // 3. Blocked Req: If the current child at the head of the request fifo is in
   //    a CHILD_SENT state, block the request until the child's response arrives
   // 4. NACK buffer: If a task nacks, keep a record of when it should be sent 
   //    Ideally this should be a priority queue for exponential back-off
   //    algorithms but for now I'll keep this a FIFO
   // 5. Abort Acks left: A small array to find out the when the abort_ack
   //    message can be sent back to the CQ. Set on abort_children request and
   //    decremented for each abort_ack response
   // 6. Tied bitvector: Records if a child task can be sent untied. Set upon
   //    each cut_tie message and reset when the cut_tie_ack is sent
   
generate
if (NON_SPEC) begin : gen

   localparam LOG_NUM_SI = $clog2(NUM_SI);
   logic [LOG_NUM_SI-1:0] write_select; 
   genvar i;

   lowbit #(
      .OUT_WIDTH(LOG_NUM_SI),
      .IN_WIDTH(NUM_SI)
   ) WRITE_SELECT (
      .in(s_wvalid),
      .out(write_select)
   );

   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_enq_valid <= 1'b0;
      end else begin
         if (!task_enq_valid & s_wvalid[write_select]) begin 
            task_enq_valid <= 1'b1;
            task_enq_data <= s_wdata[write_select];
         end else if (task_enq_valid & task_enq_ready) begin
            task_enq_valid <= 1'b0;
         end
      end
   end
   
   for (i=0;i<NUM_SI;i++) begin
      assign s_wready[i] = !task_enq_valid & s_wvalid[i] & (write_select == i); 
   end
   assign task_enq_tied = 1'b0;
   assign task_enq_resp_cq_slot = 0;
   assign task_enq_resp_child_id = 0;

   assign task_retry_valid = 1'b0;
   assign task_resp_ready = 1'b1;
   assign cq_abort_children_ready = 1'b1;
   assign cq_cut_ties_ready = 1'b1;
   assign abort_child_valid = 1'b0;
   assign cut_ties_valid = 1'b0;
   assign abort_resp_ready = 1'b1;
   assign abort_children_ack_valid = 1'b0;
   assign cut_ties_ack_valid = 1'b0;
   assign lvt = '1;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
         reg_bus.rdata <= 'x;
      end else
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end


end else begin : gen
   
   genvar i;
   localparam LOG_NUM_SI = $clog2(NUM_SI);
   localparam BLOCKED_REQ_SIZE = 8;

   localparam TASK_NACK_RETRY_LATENCY = 16;
   
   child_id_t child_id_zero;
   assign child_id_zero = 0;
   
   // --- Nets / Regs ---
   
   cycle_t cycle;

   // 1.Request FIFO 
   req_fifo_data_t   req_fifo_in, req_fifo_out;
   logic req_fifo_wr_en;
   logic req_fifo_rd_en;
   logic req_fifo_empty, req_fifo_full;

   // 2.Children Array 
   logic [CHILD_PTR_WIDTH-1:0] children [0: 2**(LOG_CQ_SLICE_SIZE+LOG_CHILDREN_PER_TASK) - 1];
   child_state_t children_state [0: 2**(LOG_CQ_SLICE_SIZE+LOG_CHILDREN_PER_TASK) - 1];
   child_ptr_t    child_ptr_rd_data;
   logic [LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK-1:0] child_write_addr;
   logic [LOG_CQ_SLICE_SIZE + LOG_CHILDREN_PER_TASK-1:0] child_read_addr, child_read_addr_q;
      
   logic children_array_process_resp;
   logic children_array_process_nack;
   logic children_array_process_new_enq;

   // 3.blocked Requests
   req_fifo_data_t [BLOCKED_REQ_SIZE-1:0] blocked_req;
   logic           [BLOCKED_REQ_SIZE-1:0] blocked_req_valid;
   
   logic  [$clog2(BLOCKED_REQ_SIZE)-1:0] next_blocked_id;
   logic  block_cur_request;
   logic  next_blocked_id_available;

   logic  [$clog2(BLOCKED_REQ_SIZE)-1:0] unblock_id;
   logic  unblock_valid;
   logic  unblock_ready;
   
   // 4.Nack buffer 
   nack_fifo_data_t   nack_fifo_in, nack_fifo_out;
   logic nack_fifo_wr_en;
   logic nack_fifo_rd_en;
   logic nack_fifo_empty;
   logic nack_fifo_full; // Nack FIFO shall never be full; its size cannot exceed TSB entries
   logic nack_fifo_valid;

   logic nacked_task_is_aborted;
   logic nacked_task_is_untied;
   
   // 5.Abort Acks Left
   child_id_t abort_acks_left [0:2**LOG_CQ_SLICE_SIZE-1];
   logic abort_acks_process_resp;
   logic abort_acks_process_nack;
   logic abort_acks_process_new_enq;

   initial begin
      for (int i=0;i<2**LOG_CQ_SLICE_SIZE;i++) begin
         abort_acks_left[i] = 0;
      end
   end

   // 6. Tied bitvector
   logic tied_vector [0:2**LOG_CQ_SLICE_SIZE-1];

   // --- Control Logic ---
   
   // Misc
   assign task_resp_ready = children_array_process_resp; 
   always_ff @(posedge clk) begin
      if (!rstn) begin
         cycle <= 0;
      end else begin
         cycle <= cycle + 1;
      end
   end

   // 1. Request FIFO
   req_fifo_data_t reg_request;
   logic           reg_request_valid;

   logic req_stalled;
   
   // if reg_request has more children
   req_fifo_data_t requeue_req;
   logic requeue_valid;

   always_comb begin
      req_fifo_wr_en = 1'b0;
      req_fifo_in = 'x;
      unblock_ready = 1'b0;
      cq_cut_ties_ready = 1'b0;
      cq_abort_children_ready = 1'b0;
      if (requeue_valid) begin
         // assert (req_fifo_rd_en)
         req_fifo_in = requeue_req;
         req_fifo_wr_en = 1'b1;
      end else 
      if (!req_fifo_full) begin 
         if (unblock_valid) begin
            unblock_ready = 1'b1;
            req_fifo_in = blocked_req[unblock_id];
            req_fifo_wr_en = 1'b1;
         end else if (cq_cut_ties_valid & !cut_ties_ack_valid) begin
            req_fifo_in = {REQ_CUT_TIE, cq_cut_ties_cq_slot, child_id_zero, cq_cut_ties_count};
            req_fifo_wr_en = 1'b1;
            cq_cut_ties_ready = 1'b1;
         end else if (cq_abort_children_valid & abort_acks_process_new_enq) begin
            req_fifo_in = {REQ_ABORT, cq_abort_children_cq_slot, 
                  child_id_zero, cq_abort_children_count};
            req_fifo_wr_en = 1'b1;
            cq_abort_children_ready = 1'b1;
         end
      end
   end

   always_comb begin
      requeue_req = reg_request;
      requeue_req.child_id = reg_request.child_id + 1;
   end
   
   fifo #(
      .WIDTH( 1 + LOG_CQ_SLICE_SIZE + (LOG_CHILDREN_PER_TASK + 1)*2),
      .LOG_DEPTH(5)
   ) REQ_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(req_fifo_wr_en),
      .wr_data(req_fifo_in),

      .full(req_fifo_full),
      .empty(req_fifo_empty),

      .rd_en(req_fifo_rd_en),
      .rd_data(req_fifo_out)

   );

   assign req_fifo_rd_en = !req_fifo_empty & !req_stalled;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_request_valid <= 1'b0;
      end else begin
         if (req_fifo_rd_en) begin
            reg_request_valid <= 1'b1;
            reg_request <= req_fifo_out;
         end else if (reg_request_valid & !req_stalled) begin
            reg_request_valid <= 1'b0;
         end
      end
   end

   child_id_t cur_read_child, next_read_child, reg_read_child;
   always_comb begin
      req_stalled = 1'b0; 
      block_cur_request = 1'b0;
      cut_ties_valid = 1'b0;
      abort_child_valid = 1'b0;
      requeue_valid = 1'b0;
      if (reg_request_valid) begin
         case (child_ptr_rd_data.state) 
            CHILD_SENT: begin
               if (next_blocked_id_available) begin 
                  block_cur_request = 1'b1;
               end else begin
                  req_stalled = 1'b1;
               end
            end
            CHILD_ACKED: begin
               if (reg_request.req_type == REQ_CUT_TIE) begin
                  cut_ties_valid = 1'b1;
                  if (!cut_ties_ready) begin
                     req_stalled = 1'b1;
                  end
               end else begin
                  abort_child_valid = 1'b1;
                  if (!abort_child_ready) begin
                     req_stalled = 1'b1;
                  end
               end
               if (!req_stalled) begin
                  requeue_valid = (reg_request.child_id < (reg_request.max_children-1));
               end
            end
            CHILD_NACKED: begin
               // The nack_fifo should have an entry for this child.
               // Block this requeuest until this entry is dequeued
               if (next_blocked_id_available) begin 
                  block_cur_request = 1'b1;
               end else begin
                  req_stalled = 1'b1;
               end
            end
            CHILD_FINALIZED: begin
               // task has been cut_tied or aborted and the tsb already notified.
               // Just move on to the next child
               requeue_valid = reg_request.child_id < (reg_request.max_children -1);
            end
         endcase
      end
   end
   assign cut_ties_ack_cq_slot = reg_request.cq_slot;
   assign cut_ties_ack_valid = reg_request_valid & (reg_request.req_type == REQ_CUT_TIE) &
                                       !req_stalled & !requeue_valid & !block_cur_request;


   assign cut_ties_tile_id = child_ptr_rd_data.tile;
   assign cut_ties_tq_slot = child_ptr_rd_data.slot;
   assign cut_ties_epoch   = child_ptr_rd_data.epoch; 

   assign abort_child_tile_id = child_ptr_rd_data.tile;
   assign abort_child_tq_slot = child_ptr_rd_data.slot;
   assign abort_child_epoch   = child_ptr_rd_data.epoch; 
   assign abort_child_resp_child_id = reg_request.child_id;
   assign abort_child_resp_cq_slot = reg_request.cq_slot; 

   
   // 2. Children Array
   logic [LOG_NUM_SI-1:0] write_select, write_select_untied, write_select_all; 

   lowbit #(
      .OUT_WIDTH(LOG_NUM_SI),
      .IN_WIDTH(NUM_SI)
   ) WRITE_SELECT (
      .in(s_wvalid),
      .out(write_select_all)
   );

   logic [NUM_SI-1:0] s_task_is_untied;
   assign s_task_is_untied = s_wvalid & s_enq_untied;
   
   lowbit #(
      .OUT_WIDTH(LOG_NUM_SI),
      .IN_WIDTH(NUM_SI)
   ) WRITE_SELECT_UNTIED (
      .in(s_task_is_untied),
      .out(write_select_untied)
   );

   assign write_select = (s_wvalid[write_select_untied] & s_enq_untied[write_select_untied]) ? 
                     write_select_untied  : write_select_all;


   logic can_take_new_task;
   logic can_take_new_retry;
   assign can_take_new_task = (!task_enq_valid | (task_enq_valid & task_enq_ready) ); 
   assign can_take_new_retry = (!task_retry_valid | (task_retry_valid & task_retry_ready));

      for (i=0;i<NUM_SI;i++) begin
         assign s_wready[i] = children_array_process_new_enq & s_wvalid[i] & (write_select == i); 
      end

   
   child_ptr_t child_wr_data, child_rd_data;
   logic child_wr_en;

   always_comb begin
      children_array_process_resp = 1'b0;
      children_array_process_nack = 1'b0;
      children_array_process_new_enq = 1'b0;
      child_write_addr = 'x;
      child_wr_data = 'x;
      if (task_resp_valid) begin
         children_array_process_resp = 1'b1;
         child_write_addr[LOG_CHILDREN_PER_TASK-1:0] = task_resp_child_id;
         child_write_addr[LOG_CHILDREN_PER_TASK +: LOG_CQ_SLICE_SIZE] = task_resp_cq_slot;
         if (task_resp_ack) begin
            child_wr_data = {CHILD_ACKED, 
                     task_resp_tile_id, task_resp_tq_slot, task_resp_epoch};
         end else begin
            child_wr_data.state = CHILD_NACKED;
         end
      end else if (can_take_new_task & s_wvalid[write_select] &
                      (!task_enq_only_untied | s_enq_untied[write_select])) begin
         children_array_process_new_enq = 1'b1;
         // Unfortunate to be calling this variable
         // 'children_array_process_new_enq' even when the new enq does not
         // result in a children_array write. //FIXME
         if (!s_enq_untied[write_select]) begin
            child_write_addr[LOG_CHILDREN_PER_TASK-1:0] = s_child_id[write_select];
            child_write_addr[LOG_CHILDREN_PER_TASK +: LOG_CQ_SLICE_SIZE] = s_cq_slot[write_select];
            if (s_enq_untied[write_select]) begin
               child_wr_data.state = CHILD_ACKED;
            end else begin
               child_wr_data.state = CHILD_SENT;
            end
         end
      end else if (can_take_new_retry & nack_fifo_valid) begin
         children_array_process_nack = 1'b1;
         child_write_addr[LOG_CHILDREN_PER_TASK-1:0] = nack_fifo_out.child_id; 
         child_write_addr[LOG_CHILDREN_PER_TASK +: LOG_CQ_SLICE_SIZE] = nack_fifo_out.cq_slot;
         if (nacked_task_is_untied | nacked_task_is_aborted) begin
            child_wr_data.state = CHILD_FINALIZED;
         end else begin
            child_wr_data.state = CHILD_SENT;
         end
      end
   end

   assign child_wr_en = (children_array_process_resp | children_array_process_nack |
                          (children_array_process_new_enq & !s_enq_untied[write_select]) );
   assign child_read_addr[LOG_CHILDREN_PER_TASK-1:0] = req_fifo_rd_en ? 
            req_fifo_out.child_id[LOG_CHILDREN_PER_TASK-1:0] : 
             reg_request.child_id[LOG_CHILDREN_PER_TASK-1:0] ; 
   assign child_read_addr[LOG_CHILDREN_PER_TASK +: LOG_CQ_SLICE_SIZE] =  req_fifo_rd_en ?
            req_fifo_out.cq_slot : reg_request.cq_slot ;

   always_ff @(posedge clk) begin
      if (!rstn) begin

      end else begin
         if (child_wr_en) begin
            { children_state[child_write_addr], children[child_write_addr]} <= child_wr_data;
         end
         if (req_fifo_rd_en | req_stalled) begin
            child_rd_data <= (child_wr_en & (child_write_addr == child_read_addr)) ?
                                 child_wr_data : 
                                 {children_state[child_read_addr], children[child_read_addr]};
         end
      end
      child_read_addr_q <= child_read_addr;

   end
   
   assign child_ptr_rd_data = ( child_wr_en & (child_write_addr == child_read_addr_q)) 
                           ? child_wr_data: child_rd_data ;

   // try to workaround some weird simulator behaviour where
   // s_enq_untied[] observes its value one cycle ahead when read 
   // in an always_ff block
   logic task_enq_tied_next;
   always_comb begin
      if (s_enq_untied[write_select]) begin
         task_enq_tied_next = 1'b0;
      end else begin
         task_enq_tied_next = 1'b1;
      end
   end

   always_ff @(posedge clk) begin
      if (!rstn) begin
      end else begin
         if (children_array_process_resp) begin
         end else if (children_array_process_nack) begin
            if (!nacked_task_is_untied) begin
               task_retry_tied <= 1'b1;
            end else begin
               // untied tasks will not receive a response
               task_retry_tied <= 1'b0;
            end
            task_retry_tsb_id <= nack_fifo_out.tsb_slot;
            task_retry_abort <= nacked_task_is_aborted; 
         end else if (children_array_process_new_enq) begin
            // tied_vector cannot be unset when the task is still running
            task_enq_tied <= task_enq_tied_next;
            task_enq_data <= s_wdata[write_select];
            task_enq_resp_cq_slot <= s_cq_slot[write_select];
            task_enq_resp_child_id <= s_child_id[write_select];
         end
      end
   end

   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_enq_valid <= 1'b0;
         task_retry_valid <= 1'b0;
      end else begin
         if (children_array_process_new_enq) begin 
            task_enq_valid <= 1'b1;
         end else if (task_enq_valid & task_enq_ready) begin
            task_enq_valid <= 1'b0;
         end

         if (children_array_process_nack) begin
            task_retry_valid <= 1'b1;
         end else if (task_retry_valid & task_retry_ready) begin
            task_retry_valid <= 1'b0;
         end
      end
   end
/*
   assign nacked_task_is_aborted = (children_state[ {nack_fifo_out.cq_slot, 
               nack_fifo_out.child_id[LOG_CHILDREN_PER_TASK-1:0] } ] == CHILD_NACKED ) &
               (abort_acks_left[nack_fifo_out.cq_slot] != 0); */
   assign nacked_task_is_aborted = abort_acks_left[nack_fifo_out.cq_slot] != 0;
   assign nacked_task_is_untied = !tied_vector[nack_fifo_out.cq_slot];
   // 3. Blocked Requests
   
   logic [BLOCKED_REQ_SIZE-1:0] unblock_this_req;
   
   lowbit #(
      .OUT_WIDTH($clog2(BLOCKED_REQ_SIZE)),
      .IN_WIDTH(BLOCKED_REQ_SIZE)
   ) NEXT_BLOCKED_ID (
      .in(~blocked_req_valid),
      .out(next_blocked_id)
   );

   assign next_blocked_id_available = !blocked_req_valid[next_blocked_id];

   always_ff @(posedge clk) begin
      if (block_cur_request) begin
         blocked_req[next_blocked_id] <= reg_request;
      end
   end
   
   for (i=0;i<BLOCKED_REQ_SIZE;i++) begin
      always_ff @(posedge clk) begin
         if (!rstn) begin 
            blocked_req_valid[i] <= 1'b0;
            unblock_this_req[i] <= 1'b0;
         end else begin
            if (block_cur_request & (next_blocked_id==i)) begin
               blocked_req_valid[i] <= 1'b1;
            end else if (blocked_req_valid[i]) begin
               if (task_resp_valid & task_resp_ack & task_resp_ready 
                  & (task_resp_cq_slot == blocked_req[i].cq_slot) 
                  & (task_resp_child_id == blocked_req[i].child_id) ) begin
                     unblock_this_req[i] <= 1'b1;
               end else if (nack_fifo_valid & children_array_process_nack
                  & (nack_fifo_out.cq_slot == blocked_req[i].cq_slot)
                  & (nack_fifo_out.child_id == blocked_req[i].child_id) ) begin
                     unblock_this_req[i] <= 1'b1;
               end else if (unblock_valid & unblock_ready 
                     & unblock_id ==i) begin
                  blocked_req_valid[i] <= 1'b0;
                  unblock_this_req[i] <= 1'b0;
               end
            end
         end
      end
   end
  
   lowbit #(
      .OUT_WIDTH($clog2(BLOCKED_REQ_SIZE)),
      .IN_WIDTH(BLOCKED_REQ_SIZE)
   ) UNBLOCK_ID (
      .in(unblock_this_req),
      .out(unblock_id)
   );
   assign unblock_valid = unblock_this_req[unblock_id];

   // 4. Nack FIFO
   
   fifo #(
      .WIDTH( $bits(nack_fifo_in)),
      .LOG_DEPTH(LOG_TSB_SIZE)
   ) NACK_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(nack_fifo_wr_en),
      .wr_data(nack_fifo_in),

      .full(nack_fifo_full),
      .empty(nack_fifo_empty),

      .rd_en(nack_fifo_rd_en),
      .rd_data(nack_fifo_out)
   );

   assign nack_fifo_wr_en = (task_resp_valid & task_resp_ready & !task_resp_ack);
   assign nack_fifo_in = { task_resp_cq_slot, task_resp_child_id,
                           task_resp_tsb_slot, cycle+ TASK_NACK_RETRY_LATENCY};
   always_comb begin
      nack_fifo_valid = 1'b0;
      if (!nack_fifo_empty) begin
         if (nacked_task_is_aborted | nacked_task_is_untied) begin
            nack_fifo_valid = 1'b1;
         end else if (nack_fifo_out.retry_cycle < cycle) begin
            nack_fifo_valid = 1'b1;
         end
      end
   end
   assign nack_fifo_rd_en = children_array_process_nack;

   // 5. Abort Acks Left
   always_comb begin
      abort_acks_process_nack = 1'b0;
      abort_acks_process_resp = 1'b0;
      abort_acks_process_new_enq = 1'b0;
      if (children_array_process_nack & nacked_task_is_aborted) begin
         abort_acks_process_nack = 1'b1;
      end else if (abort_resp_valid & !abort_children_ack_valid) begin
         abort_acks_process_resp = 1'b1;
      end else if (cq_abort_children_valid) begin
         abort_acks_process_new_enq = 1'b1;
      end
   end

   always_ff @(posedge clk) begin
      if (abort_acks_process_nack) begin
         abort_acks_left[nack_fifo_out.cq_slot] <= abort_acks_left[nack_fifo_out.cq_slot] - 1;
      end else if (abort_acks_process_resp) begin
         abort_acks_left[abort_resp_cq_slot] <= abort_acks_left[abort_resp_cq_slot] - 1;
      end else if (abort_acks_process_new_enq & cq_abort_children_ready) begin
         abort_acks_left[cq_abort_children_cq_slot] <= cq_abort_children_count;
      end
   end

   assign abort_resp_ready = abort_acks_process_resp;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         abort_children_ack_valid <= 1'b0;
      end else begin
         if (abort_resp_valid & abort_resp_ready 
            & (abort_acks_left[abort_resp_cq_slot] ==1)) begin
            abort_children_ack_valid <= 1'b1;
            abort_children_ack_cq_slot <= abort_resp_cq_slot;
         end else if (abort_acks_process_nack & (abort_acks_left[nack_fifo_out.cq_slot] ==1)) begin
            abort_children_ack_valid <= 1'b1;
            abort_children_ack_cq_slot <= nack_fifo_out.cq_slot;
         end else if (abort_children_ack_valid & abort_children_ack_ready) begin
            abort_children_ack_valid <= 1'b0;
         end   
      end
   end

   // 6:Tied bitvector
   initial begin
      for (int i=0;i<(2**LOG_CQ_SLICE_SIZE);i++) begin
         tied_vector[i] = 1'b1;         
      end
   end
   always_ff @(posedge clk) begin
      if (cq_cut_ties_valid & cq_cut_ties_ready) begin
         tied_vector[cq_cut_ties_cq_slot] <= 1'b0;
      end else if (cut_ties_ack_valid) begin
         assert(cut_ties_ack_ready) else $error("cut_tie_ack_valid & !cut_tie_ack_ready");
         tied_vector[cut_ties_ack_cq_slot] <= 1'b1;
      end
   end

   //ts_t lvt_task, lvt_abort;
   assign lvt = task_enq_valid ? task_enq_data.ts : '1;
   //assign lvt_abort = reg_abort_children_valid ? abort_ts : '1;
   //assign lvt = lvt_task < lvt_abort ? lvt_task : lvt_abort;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
      end else
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
         case (reg_bus.araddr) 
            CM_BLOCKED_VALID : reg_bus.rdata <= blocked_req_valid;
            CM_REG_REQUEST : reg_bus.rdata <= { reg_request_valid, req_stalled, reg_request};
            CM_CHILD_PTR_DATA : reg_bus.rdata <= child_ptr_rd_data;
            CM_MISC : reg_bus.rdata <= {  children_array_process_resp, children_array_process_nack, children_array_process_new_enq };
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end

end
endgenerate
endmodule
