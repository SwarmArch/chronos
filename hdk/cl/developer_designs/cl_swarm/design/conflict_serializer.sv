import swarm::*;

module conflict_serializer #( 
      parameter TILE_ID = 0
	) (
	input clk,
	input rstn,

   // from cores
	output logic           s_valid, 
	input                  s_ready, 
	output task_t          s_rdata, 
   output cq_slice_slot_t s_cq_slot,
   output thread_id_t     s_thread,

   input                  unlock_valid,
   input thread_id_t      unlock_thread,

   // to cq
   input task_t m_task,
   input cq_slice_slot_t m_cq_slot,
   input logic m_valid,
   output logic m_ready,

   output logic almost_full,

   input cq_full,

   output all_cores_idle,  // for termination checking
   pci_debug_bus_t.master                 pci_debug,
   reg_bus_t.master                       reg_bus

);

   // Takes Task Read requeusts from the cores, serves them while ensuring that
   // no two tasks with the same locale are running at the same time.
   //
   // This module maintains a shift register of pending tasks (ready_list), as well as
   // a bit for each task indicating if it conflicts with any running task.
   // When a core makes new a request, earliest conflict-free entry 
   // that matches the request's task-type will be served. 
   // Upon a task-finish, the earliest entry in the shift register with the
   // finishing tasks's locale will be set conflict-free.
   
   typedef struct packed {
      logic [LOG_READY_LIST_SIZE-1:0] id;
      logic [LOCALE_WIDTH-1:0] locale;
   } task_t_ser;


   localparam READY_LIST_SIZE = 2**LOG_READY_LIST_SIZE;

   logic [LOG_READY_LIST_SIZE-1:0] task_select;

   // runtime configurable parameter on ready list
   logic [LOG_READY_LIST_SIZE-1:0] almost_full_threshold;
   logic [LOG_READY_LIST_SIZE-1:0] full_threshold;

   locale_t [N_THREADS-1:0] running_task_locale; // Hint of the current task running on each core.
                                    // Packed array because all entries are
                                    // accessed simulataneously
   logic [N_THREADS-1:0] running_task_locale_valid;

   task_t_ser [READY_LIST_SIZE-1:0] ready_list;

   task_t [READY_LIST_SIZE-1:0] ready_list_task;
   cq_slice_slot_t [READY_LIST_SIZE-1:0] ready_list_cq_slot;

   logic [READY_LIST_SIZE-1:0] ready_list_valid;
   logic [READY_LIST_SIZE-1:0] ready_list_conflict;


   logic [READY_LIST_SIZE-1:0] task_ready;
   
   genvar i,j;

   generate 
      for (j=0;j<READY_LIST_SIZE;j++) begin
         assign task_ready[j] = ready_list_valid[j] & !ready_list_conflict[j]; 
      end
   endgenerate

   always_comb begin
      s_valid = task_ready[task_select] & next_thread_valid;
   end
   assign all_cores_idle = (ready_list_valid ==0) && (running_task_locale_valid==0); 

   logic ready_list_free_empty;
   logic ready_list_free_full;
   logic [LOG_READY_LIST_SIZE-1:0] ready_list_next_free_id;
   logic [LOG_READY_LIST_SIZE:0] ready_list_free_occ, ready_list_size;

   logic next_thread_valid;
   logic issue_task;

   logic free_list_empty;

   assign next_thread_valid = !free_list_empty & (free_list_size > (N_THREADS - active_threads));
   assign issue_task = s_valid & s_ready;

   logic [ $clog2(N_THREADS):0] free_list_size, active_threads;
   
   task_t_ser out_entry;
   always_comb begin
      out_entry = ready_list[task_select];
   end

   free_list #(
      .LOG_DEPTH( LOG_READY_LIST_SIZE)
   ) READY_LIST_ID (
      .clk(clk),
      .rstn(rstn),

      .wr_en(s_valid & s_ready),
      .rd_en(m_valid & m_ready),
      .wr_data(out_entry.id),

      .full(ready_list_free_full), 
      .empty(ready_list_free_empty),
      .rd_data(ready_list_next_free_id),

      .size(ready_list_free_occ)
   );

   assign ready_list_size = (READY_LIST_SIZE - ready_list_free_occ);

   free_list #(
      .LOG_DEPTH( $clog2(N_THREADS) )
   ) FREE_LIST_THREAD (
      .clk(clk),
      .rstn(rstn),

      .wr_en(unlock_valid),
      .rd_en(issue_task),
      .wr_data(unlock_thread),

      .full(), 
      .empty(free_list_empty),
      .rd_data(s_thread),

      .size(free_list_size)
   );
   
   lowbit #(
      .OUT_WIDTH(LOG_READY_LIST_SIZE),
      .IN_WIDTH(READY_LIST_SIZE)   
   ) TASK_SELECT (
      .in(task_ready),
      .out(task_select)
   );



   // Stage 2: Update ready_list
   locale_t finished_task_locale;
   logic [READY_LIST_SIZE-1:0] finished_task_locale_match;
   logic [LOG_READY_LIST_SIZE-1:0] finished_task_locale_match_select;
   always_comb begin
      finished_task_locale = running_task_locale[unlock_thread];
   end
   generate 
      for(i=0;i<READY_LIST_SIZE;i++) begin
         assign finished_task_locale_match[i] = (finished_task_locale == ready_list[i].locale) &
                                                unlock_valid & ready_list_valid[i];
      end
   endgenerate

   lowbit #(
      .OUT_WIDTH(LOG_READY_LIST_SIZE),
      .IN_WIDTH(READY_LIST_SIZE)   
   ) FINISHED_TASK_LOCALE_MATCH_SELECT (
      .in(finished_task_locale_match),
      .out(finished_task_locale_match_select)
   );
   logic [LOG_READY_LIST_SIZE-1:0] next_insert_location;
   
   lowbit #(
      .OUT_WIDTH(LOG_READY_LIST_SIZE),
      .IN_WIDTH(READY_LIST_SIZE)   
   ) NEXT_INSERT_LOC_SELECT (
      .in(~ready_list_valid),
      .out(next_insert_location)
   );

   assign m_ready = (m_valid & !ready_list_valid[next_insert_location]) & 
      (ready_list_size <= full_threshold);

   task_t new_enq_task;
   always_comb begin
      new_enq_task = m_task;
   end

   // checks if new_enq_task is in conflict with any other task, either in the ready
   // list or the running task list
   logic next_insert_task_conflict;
   logic [READY_LIST_SIZE-1:0] next_insert_task_conflict_ready_list;
   logic [N_THREADS-1:0] next_insert_task_conflict_running_tasks;

   generate 
      for (i=0;i<READY_LIST_SIZE;i++) begin
         assign next_insert_task_conflict_ready_list[i] = ready_list_valid[i] & 
                     (ready_list[i].locale == new_enq_task.locale);
      end
      for (i=0;i<N_THREADS;i++) begin
         assign next_insert_task_conflict_running_tasks[i] = running_task_locale_valid[i] & 
                     (running_task_locale[i] == new_enq_task.locale) & 
                     !(unlock_valid & unlock_thread ==i) ;
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
            ready_list_conflict[i] <= 1'b0; 
            ready_list[i] <= 'x;
         end else
         if (issue_task & (i >= task_select)) begin
            // If a task dequeue and enqueue happens at the same cycle,  
            // shift right existing tasks with the incoming task going at the
            // back
            if (m_valid & m_ready & (next_insert_location== i+1)) begin
               ready_list[i].id <= ready_list_next_free_id;
               ready_list[i].locale <= new_enq_task.locale;
               ready_list_valid[i] <= 1'b1;
               ready_list_conflict[i] <= next_insert_task_conflict; 
            end else if (i != READY_LIST_SIZE-1) begin
               ready_list[i] <= ready_list[i+1];
               ready_list_valid[i] <= ready_list_valid[i+1];
               if ((finished_task_locale_match_select == i+1) & finished_task_locale_match[i+1]) begin
                  ready_list_conflict[i] <= 1'b0;
               end else begin
                  ready_list_conflict[i] <= ready_list_conflict[i+1];
               end
            end else begin
               // (i== READY_LIST_SIZE-1) and dequeue/no_enqueue -> need to
               // shift in a 0 
               ready_list[i] <= 'x;
               ready_list_valid[i] <= 1'b0;
               ready_list_conflict[i] <= 1'b0;
            end
         end else begin
            // No dequeue, only enqueue
            if (m_valid & m_ready & (next_insert_location== i)) begin
               ready_list[i].id <= ready_list_next_free_id;
               ready_list[i].locale <= new_enq_task.locale;
               ready_list_valid[i] <= 1'b1;
               ready_list_conflict[i] <= next_insert_task_conflict; 
            end else begin 
               if ((finished_task_locale_match_select == i) & finished_task_locale_match[i]) begin
                  ready_list_conflict[i] <= 1'b0;
               end
               // other fields unchanged
            end
         end

      end

   end
   endgenerate

   always_ff @(posedge clk) begin
      if (m_valid & m_ready) begin
         ready_list_task[ready_list_next_free_id] <= m_task;
         ready_list_cq_slot[ready_list_next_free_id] <= m_cq_slot;
      end
   end
   
   always_comb begin
      s_rdata = ready_list_task[out_entry.id];
      s_cq_slot = ready_list_cq_slot[out_entry.id];
   end

   assign almost_full = (ready_list_size >= almost_full_threshold);
   
   

   // update locale tables
   always_ff @(posedge clk) begin
      if (!rstn) begin
         running_task_locale_valid <= 0;
         for (integer j=0;j<N_THREADS;j=j+1) begin
            running_task_locale[j] <= 'x;
         end
      end else begin
         for (integer j=0;j<N_THREADS;j=j+1) begin
            if (s_valid & s_ready & (j==s_thread)) begin
               running_task_locale_valid[j] <= 1'b1;
               running_task_locale[j] <= s_rdata.locale;
            end else if (unlock_valid & (unlock_thread ==j)) begin
               running_task_locale_valid[j] <= 1'b0;
               running_task_locale[j] <= 'x;
            end
         end
      end
   end
   
   logic [4:0] ready_list_stall_threshold;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         almost_full_threshold    <= READY_LIST_SIZE - 4;
         full_threshold    <= READY_LIST_SIZE - 1;
         ready_list_stall_threshold <= READY_LIST_SIZE - 4;
         active_threads <= N_THREADS;
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               SERIALIZER_SIZE_CONTROL : begin
                  almost_full_threshold <= reg_bus.wdata[7:0];
                  full_threshold <= reg_bus.wdata[15:8];
                  ready_list_stall_threshold <= reg_bus.wdata[23:16];
               end
               SERIALIZER_N_THREADS: active_threads <= reg_bus.wdata;
            endcase
         end
      end
   end
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
            SERIALIZER_READY_LIST : reg_bus.rdata <= {ready_list_valid, ready_list_conflict};
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end

// Debug

if (SERIALIZER_LOGGING[TILE_ID]) begin
   logic log_valid;
   typedef struct packed {

      logic [15:0] s_arvalid;
      logic [15:0] s_rvalid;
      logic [31:0] s_rdata_locale;
      logic [31:0] s_rdata_ts;

      // 32
      logic [6:0] s_cq_slot;
      logic [3:0] s_rdata_ttype;
      logic finished_task_valid;
      logic [5:0] finished_task_thread;
      logic [13:0] unused_1;
      logic [31:0] ready_list_valid;
      logic [31:0] ready_list_conflict;

      logic [31:0] m_ts;
      logic [31:0] m_locale;

      logic [3:0] m_ttype;
      logic [6:0] m_cq_slot;
      logic m_valid;
      logic m_ready;
      logic [15:0] finished_task_locale_match;
      logic [2:0] unused_2;
      
   
      

   } cq_log_t;
   cq_log_t log_word;
   always_comb begin
      log_valid = (m_valid & m_ready) | (s_valid) | unlock_valid;

      log_word = '0;

      log_word.s_arvalid = s_valid;
      log_word.s_rvalid = s_ready;
      log_word.s_rdata_locale = s_rdata.locale;
      log_word.s_rdata_ts = s_rdata.ts;
      log_word.s_rdata_ttype = s_rdata.ttype;
      log_word.s_cq_slot = s_cq_slot;

      log_word.finished_task_valid = unlock_valid;
      log_word.finished_task_thread = unlock_thread;

      log_word.ready_list_valid = ready_list_valid;
      log_word.ready_list_conflict = ready_list_conflict;

      log_word.m_locale = new_enq_task.locale;
      log_word.m_ts = new_enq_task.ts;
      log_word.m_ttype = new_enq_task.ttype;
      log_word.m_cq_slot = m_cq_slot;

      log_word.finished_task_locale_match = finished_task_locale_match;

      log_word.m_valid = m_valid;
      log_word.m_ready = m_ready;
   end

   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) SERIALIZER_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid(log_valid),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end
endmodule
