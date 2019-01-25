import swarm::*;

module conflict_serializer #( 
		parameter NUM_CORES = 10,
      parameter TILE_ID = 0
	) (
	input clk,
	input rstn,

   // from cores
	input logic [NUM_CORES-1:0] s_arvalid, //no arready; s_rvalid serves the same purpose
	input task_type_t [NUM_CORES-1:0] s_araddr, 
	output logic [NUM_CORES-1:0] s_rvalid, // no rready, assumes core is always ready
	output task_t s_rdata, // only 1 deque per cycle
   output cq_slice_slot_t s_cq_slot,

   input finished_task_valid,
   input core_id_t finished_task_core,

   // to cq
   input task_t m_task,
   input cq_slice_slot_t m_cq_slot,
   input logic m_valid,
   output logic m_ready,

   output logic almost_full,

   output all_cores_idle,  // for termination checking
   pci_debug_bus_t.master                 pci_debug,
   reg_bus_t.master                       reg_bus

);

   // Takes Task Read requeusts from the cores, serves them while ensuring that
   // no two tasks with the same hint are running at the same time.
   //
   // This module maintains a shift register of pending tasks (ready_list), as well as
   // a bit for each task indicating if it conflicts with any running task.
   // When a core makes new a request, earliest conflict-free entry 
   // that matches the request's task-type will be served. 
   // Upon a task-finish, the earliest entry in the shift register with the
   // finishing tasks's hint will be set conflict-free.
   
   localparam LOG_N_CORES = $clog2(NUM_CORES);

   localparam LOG_READY_LIST_SIZE = 3;
   localparam READY_LIST_SIZE = 2**LOG_READY_LIST_SIZE;

   logic [LOG_N_CORES-1:0] reg_core_id;
   logic reg_valid;
   logic [LOG_READY_LIST_SIZE-1:0] reg_task_select, task_select;

   hint_t [NUM_CORES-1:0] running_task_hint; // Hint of the current task running on each core.
                                    // Packed array because all entries are
                                    // accessed simulataneously
   logic [NUM_CORES-1:0] running_task_hint_valid;

   task_t [READY_LIST_SIZE-1:0] ready_list;
   cq_slice_slot_t [READY_LIST_SIZE-1:0] ready_list_cq_slot;
   logic [READY_LIST_SIZE-1:0] ready_list_valid;
   logic [READY_LIST_SIZE-1:0] ready_list_conflict;

   logic [N_TASK_TYPES-1:0] [READY_LIST_SIZE-1:0] task_type_ready;
   
   genvar i,j;

   generate 
      for (i=0;i<N_TASK_TYPES;i++) begin
         for (j=0;j<READY_LIST_SIZE;j++) begin
            assign task_type_ready[i][j] = ready_list_valid[j] & !ready_list_conflict[j] 
                  & (i== TASK_TYPE_ALL ? (ready_list[j].ttype <= TASK_TYPE_ALL)
                                       : (ready_list[j].ttype == i) ) 
                  & !(reg_valid & reg_task_select == j); // this slot was not picked up last cycle
         end
      end
   endgenerate


   assign all_cores_idle = (running_task_hint_valid[NUM_CORES-1:1]==0); // ignore OCL

   // Stage 1: arbitrate among the cores

   logic [NUM_CORES-1:0] can_take_request; 
   generate 
      for (i=0;i<NUM_CORES;i=i+1) begin
         assign can_take_request[i] = 
               s_arvalid[i] & // Core is requesting
               (task_type_ready[s_araddr[i]] != 0) & //a task of this type is ready
               !(reg_valid & (i == reg_core_id)); //did not take a request from this core last cycle
      end
   endgenerate

   logic [LOG_N_CORES-1:0] core_select;
   lowbit #(
      .OUT_WIDTH(LOG_N_CORES),
      .IN_WIDTH(NUM_CORES)   
   ) CORE_SELECT (
      .in(can_take_request),
      .out(core_select)
   );

   logic [READY_LIST_SIZE-1:0] task_select_in;
   always_comb begin
      task_select_in = task_type_ready[s_araddr[core_select]];
   end
   
   lowbit #(
      .OUT_WIDTH(LOG_READY_LIST_SIZE),
      .IN_WIDTH(READY_LIST_SIZE)   
   ) TASK_SELECT (
      .in(task_select_in),
      .out(task_select)
   );



   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_valid <= 1'b0;
         reg_core_id <= 'x;
         reg_task_select <= 'x;
      end else begin
         reg_core_id <= core_select;
         reg_valid <= can_take_request[core_select];
         if (reg_valid & (task_select > reg_task_select)) begin
            // ready list is being right shifted this cycle
            reg_task_select <= task_select - 1;
         end else begin
            reg_task_select <= task_select;
         end
      end
   end


   // Stage 2: Update ready_list
   hint_t finished_task_hint;
   logic [READY_LIST_SIZE-1:0] finished_task_hint_match;
   logic [LOG_READY_LIST_SIZE-1:0] finished_task_hint_match_select;
   always_comb begin
      finished_task_hint = running_task_hint[finished_task_core];
   end
   generate 
      for(i=0;i<READY_LIST_SIZE;i++) begin
         assign finished_task_hint_match[i] = (finished_task_hint == ready_list[i].hint) &
                                                finished_task_valid & ready_list_valid[i];
      end
   endgenerate

   lowbit #(
      .OUT_WIDTH(LOG_READY_LIST_SIZE),
      .IN_WIDTH(READY_LIST_SIZE)   
   ) FINISHED_TASK_HINT_MATCH_SELECT (
      .in(finished_task_hint_match),
      .out(finished_task_hint_match_select)
   );
   logic [LOG_READY_LIST_SIZE-1:0] next_insert_location;
   
   lowbit #(
      .OUT_WIDTH(LOG_READY_LIST_SIZE),
      .IN_WIDTH(READY_LIST_SIZE)   
   ) NEXT_INSERT_LOC_SELECT (
      .in(~ready_list_valid),
      .out(next_insert_location)
   );

   assign m_ready = (m_valid & !ready_list_valid[next_insert_location]);

   task_t new_enq_task;
   always_comb begin
      new_enq_task = m_task;
      // read-only ness should not be propagated. If allowed to do so
      // a RO task and a non-RO would not be serialized
      new_enq_task.hint[31] = 1'b0;
   end

   // checks if new_enq_task is in conflict with any other task, either in the ready
   // list or the running task list
   logic next_insert_task_conflict;
   logic [READY_LIST_SIZE-1:0] next_insert_task_conflict_ready_list;
   logic [NUM_CORES-1:0] next_insert_task_conflict_running_tasks;

   generate 
      for (i=0;i<READY_LIST_SIZE;i++) begin
         assign next_insert_task_conflict_ready_list[i] = ready_list_valid[i] & 
                     (ready_list[i].hint == new_enq_task.hint);
      end
      for (i=0;i<NUM_CORES;i++) begin
         assign next_insert_task_conflict_running_tasks[i] = running_task_hint_valid[i] & 
                     (running_task_hint[i] == new_enq_task.hint) & 
                     !(finished_task_valid & finished_task_core ==i) ;
      end
   endgenerate
   assign next_insert_task_conflict = m_valid & ((next_insert_task_conflict_ready_list != 0) |
                                             (next_insert_task_conflict_running_tasks != 0));

   // Shift register operations 
   generate 
   for (i=0;i<READY_LIST_SIZE;i++) begin
      always_ff @(posedge clk) begin
         if (!rstn) begin
            ready_list_valid[i] <= 1'b0;
            ready_list_cq_slot[i] <= 'x;
            ready_list_conflict[i] <= 1'b0; 
            ready_list[i] <= 'x;
         end else
         if (reg_valid & (i >= reg_task_select)) begin
            // If a task dequeue and enqueue happens at the same cycle,  
            // shift right existing tasks with the incoming task going at the
            // back
            if (m_valid & m_ready & (next_insert_location== i+1)) begin
               ready_list[i] <= new_enq_task;
               ready_list_cq_slot[i] <= m_cq_slot;
               ready_list_valid[i] <= 1'b1;
               ready_list_conflict[i] <= next_insert_task_conflict; 
            end else if (i != READY_LIST_SIZE-1) begin
               ready_list[i] <= ready_list[i+1];
               ready_list_cq_slot[i] <= ready_list_cq_slot[i+1];
               ready_list_valid[i] <= ready_list_valid[i+1];
               if ((finished_task_hint_match_select == i+1) & finished_task_hint_match[i+1]) begin
                  ready_list_conflict[i] <= 1'b0;
               end else begin
                  ready_list_conflict[i] <= ready_list_conflict[i+1];
               end
            end else begin
               // (i== READY_LIST_SIZE-1) and dequeue/no_enqueue -> need to
               // shift in a 0 
               ready_list[i] <= 'x;
               ready_list_cq_slot[i] <= 'x; // set these to x so that waveform is easier to read
               ready_list_valid[i] <= 1'b0;
               ready_list_conflict[i] <= 1'b0;
            end
         end else begin
            // No dequeue, only enqueue
            if (m_valid & m_ready & (next_insert_location== i)) begin
               ready_list[i] <= new_enq_task;
               ready_list_cq_slot[i] <= m_cq_slot;
               ready_list_valid[i] <= 1'b1;
               ready_list_conflict[i] <= next_insert_task_conflict; 
            end else begin 
               if ((finished_task_hint_match_select == i) & finished_task_hint_match[i]) begin
                  ready_list_conflict[i] <= 1'b0;
               end
               // other fields unchanged
            end
         end

      end

   end
   endgenerate

   always_comb begin
      s_rdata = ready_list[reg_task_select];
      s_cq_slot = ready_list_cq_slot[reg_task_select];
   end

   logic [LOG_READY_LIST_SIZE-1:0] ready_list_size;
   logic ready_list_size_inc, ready_list_size_dec;
   assign ready_list_size_inc = (m_valid & m_ready);
   assign ready_list_size_dec = (reg_valid);
   always_ff @(posedge clk) begin
      if (!rstn) begin
         ready_list_size <= 0;
      end else begin
         ready_list_size <= ready_list_size + ready_list_size_inc - ready_list_size_dec;
      end
   end
   assign almost_full = (ready_list_size >= READY_LIST_SIZE - 4);
   
   
   generate
      for (i=0;i<NUM_CORES;i=i+1) begin
         assign s_rvalid[i] = reg_valid & (reg_core_id == i);
      end
   endgenerate

   // update hint tables
   always_ff @(posedge clk) begin
      if (!rstn) begin
         running_task_hint_valid <= 0;
         for (integer j=0;j<NUM_CORES;j=j+1) begin
            running_task_hint[j] <= 'x;
         end
      end else begin
         for (integer j=0;j<NUM_CORES;j=j+1) begin
            if (s_rvalid[j]) begin
               running_task_hint_valid[j] <= 1'b1;
               running_task_hint[j] <= s_rdata.hint;
            end else if (finished_task_valid & (finished_task_core ==j)) begin
               running_task_hint_valid[j] <= 1'b0;
               running_task_hint[j] <= 'x;
            end
         end
      end
   end

// Debug
logic [LOG_LOG_DEPTH:0] log_size; 
   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
         reg_bus.rdata <= 'x;
      end else
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
         casex (reg_bus.araddr) 
            DEBUG_CAPACITY : reg_bus.rdata <= log_size;
            SERIALIZER_ARVALID : reg_bus.rdata <= s_arvalid;
            SERIALIZER_READY_LIST : reg_bus.rdata <= {ready_list_valid, ready_list_conflict};
            SERIALIZER_REG_VALID : reg_bus.rdata <= {reg_core_id, reg_valid};
            SERIALIZER_CAN_TAKE_REQ_0 : reg_bus.rdata <=
               {can_take_request[ 3], can_take_request[ 2], can_take_request[ 1], can_take_request[ 0]};
            SERIALIZER_CAN_TAKE_REQ_1 : reg_bus.rdata <=
               {can_take_request[ 7], can_take_request[ 6], can_take_request[ 5], can_take_request[ 4]};
            SERIALIZER_CAN_TAKE_REQ_2 : reg_bus.rdata <=
               {can_take_request[11], can_take_request[10], can_take_request[ 9], can_take_request[ 8]};
            SERIALIZER_CAN_TAKE_REQ_3 : reg_bus.rdata <=
               {can_take_request[15], can_take_request[14], can_take_request[13], can_take_request[12]};
            // can_take_request;
            // ready_list_valid, ready_list_conflict
            // reg_valid, reg_core_id
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end

if (SERIALIZER_LOGGING[TILE_ID]) begin
   logic log_valid;
   typedef struct packed {

      logic [15:0] s_arvalid;
      logic [15:0] s_rvalid;
      logic [31:0] s_rdata_hint;
      logic [31:0] s_rdata_ts;

      // 32
      logic [5:0] s_cq_slot;
      logic [3:0] s_rdata_ttype;
      logic finished_task_valid;
      logic [4:0] finished_task_core;
      logic [7:0] ready_list_valid;
      logic [7:0] ready_list_conflict;

      logic [31:0] m_ts;
      logic [31:0] m_hint;

      logic [3:0] m_ttype;
      logic [5:0] m_cq_slot;
      logic m_valid;
      logic m_ready;
      logic [7:0] finished_task_hint_match;
      logic [11:0] unused_2;
      
   
      

   } cq_log_t;
   cq_log_t log_word;
   always_comb begin
      log_valid = (m_valid & m_ready) | (s_rvalid != 0) | finished_task_valid;

      log_word = '0;

      log_word.s_arvalid = s_arvalid;
      log_word.s_rvalid = s_rvalid;
      log_word.s_rdata_hint = s_rdata.hint;
      log_word.s_rdata_ts = s_rdata.ts;
      log_word.s_rdata_ttype = s_rdata.ttype;
      log_word.s_cq_slot = s_cq_slot;

      log_word.finished_task_valid = finished_task_valid;
      log_word.finished_task_core = finished_task_core;

      log_word.ready_list_valid = ready_list_valid;
      log_word.ready_list_conflict = ready_list_conflict;

      log_word.m_hint = new_enq_task.hint;
      log_word.m_ts = new_enq_task.ts;
      log_word.m_ttype = new_enq_task.ttype;
      log_word.m_cq_slot = m_cq_slot;

      log_word.finished_task_hint_match = finished_task_hint_match;

      log_word.m_valid = m_valid;
      log_word.m_ready = m_ready;
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
endmodule
