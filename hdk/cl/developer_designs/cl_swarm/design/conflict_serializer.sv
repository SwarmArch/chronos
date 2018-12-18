import swarm::*;

module conflict_serializer #( 
		parameter NUM_CORES = 10  
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

   output all_cores_idle  // for termination checking

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

   // checks if m_task is in conflict with any other task, either in the ready
   // list or the running task list
   logic next_insert_task_conflict;
   logic [READY_LIST_SIZE-1:0] next_insert_task_conflict_ready_list;
   logic [NUM_CORES-1:0] next_insert_task_conflict_running_tasks;

   generate 
      for (i=0;i<READY_LIST_SIZE;i++) begin
         assign next_insert_task_conflict_ready_list[i] = ready_list_valid[i] & 
                     (ready_list[i].hint == m_task.hint);
      end
      for (i=0;i<NUM_CORES;i++) begin
         assign next_insert_task_conflict_running_tasks[i] = running_task_hint_valid[i] & 
                     (running_task_hint[i] == m_task.hint) & 
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
               ready_list[i] <= m_task;
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
               ready_list[i] <= m_task;
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
endmodule
