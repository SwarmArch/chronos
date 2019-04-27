`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

module queue_vertex
#(
   parameter CORE_ID=0,
   parameter TILE_ID=0,
   parameter THREADS=16
) (
   input clk,
   input rstn,

   axi_bus_t.slave l1,

   // Task Dequeue
   output logic         [THREADS-1:0]  task_arvalid,
   output task_type_t   [THREADS-1:0]  task_araddr,
   input                [THREADS-1:0]  task_rvalid,
   input task_t            task_rdata,
   input cq_slice_slot_t   task_rslot, 

   // Task Enqueue
   output logic            task_wvalid,
   output task_t           task_wdata, 
   input                   task_wready,
   output logic            task_enq_untied,
   output cq_slice_slot_t  task_cq_slot,
   output child_id_t       task_child_id,

   // Inform CQ that I have dequeued the task at this slot_id
   output logic            [THREADS-1:0] start_task_valid,
   input                   [THREADS-1:0] start_task_ready, 
   output cq_slice_slot_t  [THREADS-1:0] start_task_slot,

   // Finish Task
   output logic            [THREADS-1:0] finish_task_valid,
   input                   [THREADS-1:0] finish_task_ready,
   output cq_slice_slot_t  [THREADS-1:0] finish_task_slot,
   // Informs the CQ of the number of children I have enqueued and whether
   // I have made a write that needs to be reversed on abort
   output child_id_t       [THREADS-1:0] finish_task_num_children,
   output logic            [THREADS-1:0] finish_task_undo_log_write,

   input                  [THREADS-1:0]  abort_running_task,
   input cq_slice_slot_t   abort_running_slot,

   input                   gvt_task_slot_valid,
   input cq_slice_slot_t   gvt_task_slot,
   
   // Undo Log Writes
   output logic            [THREADS-1:0] undo_log_valid,
   input                   [THREADS-1:0] undo_log_ready,
   output undo_id_t        [THREADS-1:0] undo_log_id,
   output undo_log_addr_t  [THREADS-1:0] undo_log_addr,
   output undo_log_data_t  [THREADS-1:0] undo_log_data,
   output cq_slice_slot_t  [THREADS-1:0] undo_log_slot,

   reg_bus_t.master reg_bus,
   pci_debug_bus_t.master pci_debug
);

typedef enum logic[2:0] {
   UNUSED,
   ALLOCATED, 
   DIST_DONE,
   ABORTED 
} cb_state_t;
genvar i;
integer j;
localparam TT_ID = 1; // task_type that this core will accept
typedef enum logic[3:0] {
      READ_TARGET, WAIT_TARGET,
      READ_BASE_LATLON, WAIT_BASE_LATLON,
      READ_TARGET_COORD, WAIT_TARGET_COORD,
      NEXT_TASK
   } core_state_t;

generate
for (i=0;i<THREADS;i++) begin
   assign task_araddr[i] = TT_ID;
end
endgenerate

logic ap_start;
logic ap_done;
logic ap_idle;
logic ap_ready;

core_state_t state, state_next;

logic start;
logic initialized;

logic [31:0] dequeues_remaining;

logic [31:0] target_node;
logic [31:0] base_latlon;
logic [31:0] target_lat, target_lon;
logic [31:0] src_lat, src_lon;
logic [31:0] astar_dist;

localparam LOG_CB_SIZE = 4;
localparam CB_SIZE = 2**LOG_CB_SIZE; // completion buffer

logic [CB_SIZE-1 :0] cb_entry_valid;
cb_state_t [CB_SIZE-1 :0] cb_entry_state;
cq_slice_slot_t  cb_entry_cq_slot [0:CB_SIZE-1];
   
typedef struct packed {
   logic [31:0] vid;
   logic [31:0] fScore;
   logic [31:0] gScore;
   logic [31:0] parent;
}  cb_entry_t;
typedef logic[LOG_CB_SIZE-1:0] cb_id_t;

cb_entry_t cb_entry [0: CB_SIZE -1];
logic [31:0] cb_dist [0: CB_SIZE -1]; // dist module output
logic [LOG_CB_SIZE-1:0] next_cb_entry;

// in flight fifo
logic ift_fifo_wr_en;
logic ift_fifo_rd_en;
cb_id_t ift_fifo_wdata;
cb_id_t ift_fifo_rdata;
logic ift_fifo_empty;

// completed fifo
logic c_fifo_wr_en;
logic c_fifo_rd_en;
cb_id_t c_fifo_wdata_cb;
logic [31:0] c_fifo_wdata_dist;
cb_id_t c_fifo_rdata_cb;
logic [31:0] c_fifo_rdata_dist;
logic c_fifo_empty;


// A single-entry fifo for the task that has enqueued its child 
// and is awaiting finish
cb_id_t finish_task_cb_slot;
logic finish_task_entry_valid;

logic abort_running_task_q;
cb_id_t abort_running_cb_slot, abort_running_cb_slot_q;
cq_slice_slot_t abort_running_slot_q;

lowbit #(
   .OUT_WIDTH(LOG_CB_SIZE),
   .IN_WIDTH(2**LOG_CB_SIZE)
) CB_NEXT (
   .in(task_rvalid),
   .out(next_cb_entry)
);

lowbit #(
   .OUT_WIDTH(LOG_CB_SIZE),
   .IN_WIDTH(2**LOG_CB_SIZE)
) ABORT_NEXT (
   .in(abort_running_task),
   .out(abort_running_cb_slot)
);

localparam READ_TARGET_WORD = 8;
localparam READ_BASE_LATLON_WORD = 6;

logic start_task_fifo_wr_en;
logic start_task_fifo_rd_en;
cb_id_t start_task_fifo_wdata;
cb_id_t start_task_fifo_rdata;
logic [3:0] start_task_fifo_capacity;
logic start_task_fifo_empty;
logic start_task_fifo_almost_full;

logic read_coord_fifo_wr_en;
logic read_coord_fifo_rd_en;
cb_id_t read_coord_fifo_wdata;
cb_id_t read_coord_fifo_rdata;
logic read_coord_fifo_empty;
logic read_coord_fifo_full;

// 1 start task 
assign start_task_fifo_wdata = next_cb_entry;
assign start_task_fifo_wr_en = task_rvalid[next_cb_entry];

fifo #(
   .WIDTH(LOG_CB_SIZE),
   .LOG_DEPTH(LOG_CB_SIZE)
) START_TASK_FIFO (
   .clk(clk),
   .rstn(rstn),
   
   .wr_en(start_task_fifo_wr_en),
   .rd_en(start_task_fifo_rd_en),
   .wr_data(start_task_fifo_wdata),
   .rd_data(start_task_fifo_rdata),

   .full(),
   .empty(start_task_fifo_empty),
   .size(start_task_fifo_capacity)
);
assign start_task_fifo_almost_full = (start_task_fifo_capacity >= 6);

always_ff @(posedge clk) begin
   if (start_task_fifo_wr_en) begin
      cb_entry_cq_slot[next_cb_entry] <= task_rslot; 
      cb_entry[next_cb_entry].vid <= task_rdata.locale; 
      cb_entry[next_cb_entry].fScore <= task_rdata.args[31:0]; 
      cb_entry[next_cb_entry].gScore <= task_rdata.ts; 
      cb_entry[next_cb_entry].parent <= task_rdata.args[63:32]; 
   end
end

always_comb begin
   start_task_fifo_rd_en = 1'b0;
   start_task_valid = '0;
   start_task_slot = 'x;
   if (!start_task_fifo_empty) begin
      start_task_valid[ start_task_fifo_rdata ] = 1'b1; 
      start_task_slot[ start_task_fifo_rdata ] = cb_entry_cq_slot[start_task_fifo_rdata]; 
      if (start_task_ready[ start_task_fifo_rdata]) begin
         start_task_fifo_rd_en = 1'b1;
      end
   end
end

// 2. Read coordinates fifo
fifo #(
   .WIDTH(LOG_CB_SIZE),
   .LOG_DEPTH(LOG_CB_SIZE)
) READ_COORD_FIFO (
   .clk(clk),
   .rstn(rstn),
   
   .wr_en(read_coord_fifo_wr_en),
   .rd_en(read_coord_fifo_rd_en),
   .wr_data(read_coord_fifo_wdata),
   .rd_data(read_coord_fifo_rdata),

   .full(read_coord_fifo_full),
   .empty(read_coord_fifo_empty)
);

assign read_coord_fifo_wr_en = start_task_fifo_rd_en;
assign read_coord_fifo_wdata = start_task_fifo_rdata;

cb_id_t read_coord_cb_entry;
assign read_coord_cb_entry = read_coord_fifo_rdata;

assign l1.awvalid = 1'b0;
assign l1.wvalid = 1'b0;
// Bypass the L1 and connect to the arbiter directly
// No cache-line crossing accs because all reads are b4-bit aligned 64-bit reads

always_comb begin
   l1.arvalid = 1'b0;
   l1.araddr = 'x;
   l1.arlen = 0;
   l1.arsize = 6;
   l1.arid = (CORE_ID << 4);
   read_coord_fifo_rd_en = 1'b0;

   state_next = state;
   case(state)
      READ_TARGET: begin
         if (start) begin
            l1.araddr = READ_TARGET_WORD << 2; ;
            l1.arvalid = 1'b1;
            if (l1.arready) begin
               state_next = WAIT_TARGET;
            end
         end
      end
      WAIT_TARGET: begin
         if (l1.rvalid) begin
            state_next = READ_BASE_LATLON;
         end
      end
      READ_BASE_LATLON: begin
         if (start) begin
            l1.araddr = READ_BASE_LATLON_WORD << 2;
            l1.arvalid = 1'b1;
            if (l1.arready) begin
               state_next = WAIT_BASE_LATLON;
            end
         end
      end
      WAIT_BASE_LATLON: begin
         if (l1.rvalid) begin
            state_next = READ_TARGET_COORD;
         end
      end
      READ_TARGET_COORD: begin
         l1.araddr = base_latlon + (target_node * 8); 
         l1.arvalid = 1'b1;
         if (l1.arready) begin
            state_next = WAIT_TARGET_COORD;
         end
      end
      WAIT_TARGET_COORD: begin
         if (l1.rvalid & l1.rlast) begin
            state_next = NEXT_TASK;
         end
      end
      NEXT_TASK: begin
         l1.arid = (CORE_ID << 4) | read_coord_cb_entry;
         if (!read_coord_fifo_empty) begin
            l1.araddr = base_latlon  + ( cb_entry[read_coord_cb_entry].vid  * 8); 
            l1.arvalid = 1'b1;
            if (l1.arready) begin
               read_coord_fifo_rd_en = 1'b1;
            end
         end
      end
   endcase
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      initialized <= 1'b0;
   end else begin
      if (state == NEXT_TASK) begin
         initialized <= 1'b1;
      end
   end
end


logic [2:0] l1_rdata_word;
cb_entry_t l1_rid_cb_in;
assign l1_rid_cb_in = cb_entry[l1.rid[3:0]]; 
assign l1_rdata_word = l1_rid_cb_in.vid[2:0];

// 3. L1 Read Response handler
always_ff @(posedge clk) begin
   if (l1.rvalid) begin
      case (state)
         WAIT_TARGET: target_node <= l1.rdata[ READ_TARGET_WORD * 32 +: 32];
         WAIT_BASE_LATLON : base_latlon <= l1.rdata[READ_BASE_LATLON_WORD * 32 +: 32] << 2;

         WAIT_TARGET_COORD: begin 
            target_lat <= l1.rdata[ target_node[2:0]*64      +:32];
            target_lon <= l1.rdata[ target_node[2:0]*64 + 32 +:32];
         end
      endcase
   end
end
logic ap_start_q;
always_ff @(posedge clk) begin
   ap_start_q <= ap_start;
end
assign l1.rready = !initialized | !ap_start_q;
assign src_lat = l1.rdata[ l1_rdata_word*64 +: 32];
assign src_lon = l1.rdata[ l1_rdata_word*64 + 32 +: 32];

always_comb begin
   ift_fifo_wr_en = 1'b0;
   ift_fifo_wdata = 'x;
   ap_start = 1'b0;
   if (state == NEXT_TASK) begin
      if (l1.rvalid & l1.rlast & l1.rready) begin
         ift_fifo_wr_en = 1'b1;
         ift_fifo_wdata = l1.rid[3:0];
         ap_start = 1'b1;
      end
   end
end



// 4.1 Astar dist calculation pipeline. II = 2, and each rvalid takes a minimum
// of two cycles, so no need to check (ap_ready) before enqueuing new work
astar_dist DIST (
        .ap_clk (clk),
        .ap_rst (~rstn),
        .ap_start (ap_start),
        .ap_done  (ap_done),
        .ap_idle  (ap_idle),
        .ap_ready (ap_ready),
        .src_lat_V  (src_lat),
        .src_lon_V  (src_lon),
        .dst_lat_V  (target_lat),
        .dst_lon_V  (target_lon),
        .out_r      (astar_dist),
        .out_r_ap_vld (/*same_as_ap_done*/)
);

// 4.2 in_flight_task_fifo:  Stores the cb indices of tasks that are in the dist pipeline 
   fifo #(
      .WIDTH(LOG_CB_SIZE),
      .LOG_DEPTH(LOG_CB_SIZE)
   ) IN_FLIGHT_TASK_FIFO (
      .clk(clk),
      .rstn(rstn),
      
      .wr_en(ift_fifo_wr_en),
      .rd_en(ift_fifo_rd_en),
      .wr_data(ift_fifo_wdata),
      .rd_data(ift_fifo_rdata),

      .full(),
      .empty(ift_fifo_empty)
   );

assign ift_fifo_rd_en = ap_done;
assign c_fifo_wr_en = ap_done & (cb_entry_state[ift_fifo_rdata] == ALLOCATED) 
         &  !finish_task_valid[ift_fifo_rdata] ;
assign c_fifo_wdata_cb = ift_fifo_rdata;
always_ff @(posedge clk) begin
   if (ap_done) begin
      cb_dist[ift_fifo_rdata] <= astar_dist;
   end
end

// 5. Completed task fifo: Indices of tasks that have come out of the dist
// module and waiting for their child to be enqueued
always_comb begin
   c_fifo_wdata_dist = astar_dist + cb_entry[ift_fifo_rdata].fScore;
end
fifo #(
   .WIDTH(LOG_CB_SIZE + 32),
   .LOG_DEPTH(LOG_CB_SIZE)
) COMPLETED_TASK_FIFO (
   .clk(clk),
   .rstn(rstn),
   
   .wr_en(c_fifo_wr_en),
   .rd_en(c_fifo_rd_en),
   .wr_data({c_fifo_wdata_cb, c_fifo_wdata_dist}),
   .rd_data({c_fifo_rdata_cb, c_fifo_rdata_dist}),

   .full(),
   .empty(c_fifo_empty)
);
assign finish_task_undo_log_write = 0;

//X .Completion buffer handling (X because this is not a pipe stage)

cq_slice_slot_t finish_task_entry_cq_slot;
generate;
   for (i=0;i<CB_SIZE;i++) begin
      always_ff @(posedge clk) begin
         if (!rstn) begin
            cb_entry_state[i] <= UNUSED;
         end else begin
            case (cb_entry_state[i])
               UNUSED: begin
                  if ( start_task_fifo_wr_en & (i== start_task_fifo_wdata)) begin
                     cb_entry_state[i] <= ALLOCATED;
                  end
               end
               ALLOCATED: begin
                  if ( ap_done & (i== ift_fifo_rdata) & 
                        finish_task_valid[i] & finish_task_ready[i] ) begin
                     // corner case: was aborted at the same time as dist
                     // completion
                     cb_entry_state[i] <= UNUSED;
                  end else if ( ap_done & (i== ift_fifo_rdata) ) begin
                     cb_entry_state[i] <= DIST_DONE;
                  end else if (finish_task_valid[i] & finish_task_ready[i]) begin
                     cb_entry_state[i] <= ABORTED;
                  end
               end
               DIST_DONE: begin
                  if (finish_task_valid[i] & finish_task_ready[i]) begin
                     cb_entry_state[i] <= UNUSED;
                  end
               end
               ABORTED: begin
                  if ( ap_done & (i== ift_fifo_rdata) ) begin
                     cb_entry_state[i] <= UNUSED;
                  end else if (!c_fifo_empty & (c_fifo_rdata_cb == i) & c_fifo_rd_en) begin
                     cb_entry_state[i] <= UNUSED;
                  end else if (finish_task_valid[i] & finish_task_ready[i]) begin
                     cb_entry_state[i] <= UNUSED;
                  end
               end

            endcase
         end
      end 
      assign cb_entry_valid[i] = (cb_entry_state[i] != UNUSED);
   end
endgenerate

// 7. Task enqueue
assign task_cq_slot = cb_entry_cq_slot[c_fifo_rdata_cb];
assign task_child_id = 0;
assign task_enq_untied = (gvt_task_slot_valid & (gvt_task_slot == task_cq_slot));

logic last_enq_was_untied;
always_ff @(posedge clk) begin
   if (task_wvalid & task_wready) begin
      last_enq_was_untied <= task_enq_untied;
   end
end

logic [31:0] parentGScore;
logic enquing_task_is_being_aborted;
assign enquing_task_is_being_aborted = abort_running_task_q & 
                        (abort_running_cb_slot_q == c_fifo_rdata_cb);
always_comb begin
   parentGScore = cb_entry[c_fifo_rdata_cb].gScore;
end
always_comb begin
   task_wvalid = 1'b0;
   task_wdata = 'x;
   c_fifo_rd_en = 1'b0;
   if (!finish_task_entry_valid & !c_fifo_empty) begin
      if (enquing_task_is_being_aborted | cb_entry_state[c_fifo_rdata_cb]==ABORTED) begin
         c_fifo_rd_en = 1'b1;
      end else begin
         task_wvalid = 1'b1;
         task_wdata.ttype = 0;
         task_wdata.ts = (parentGScore > c_fifo_rdata_dist) ? parentGScore : c_fifo_rdata_dist;
         task_wdata.locale = cb_entry[c_fifo_rdata_cb].vid;
         task_wdata.args[63:32] = cb_entry[c_fifo_rdata_cb].parent;
         task_wdata.args[31:0] = cb_entry[c_fifo_rdata_cb].fScore;
         if (task_wready) begin
            c_fifo_rd_en = 1'b1;
         end
      end
   end
end
assign undo_log_valid = 0;

// 8. Finish task
assign finish_task_entry_cq_slot = cb_entry_cq_slot[finish_task_cb_slot];
always_ff @(posedge clk) begin
   if (!rstn) begin
      finish_task_entry_valid <= 1'b0;
   end else begin
      if (finish_task_entry_valid) begin
         if (finish_task_ready[finish_task_cb_slot]
               & (finish_task_slot[finish_task_cb_slot] == finish_task_entry_cq_slot)) begin
            finish_task_entry_valid <= 1'b0;
         end
      end else if (task_wvalid & task_wready) begin
         finish_task_entry_valid <= 1'b1;
         finish_task_cb_slot <= c_fifo_rdata_cb;
      end
   end
end
always_comb begin
   finish_task_valid = 0;
   for (j=0;j<THREADS;j++) begin
      finish_task_slot[j] = 'x;
      finish_task_num_children[j] = 0;
   end
   if (abort_running_task_q) begin
      if (cb_entry_valid[abort_running_cb_slot_q]) begin // not already finished
         finish_task_valid[abort_running_cb_slot_q] = 1'b1;
         finish_task_slot[abort_running_cb_slot_q] = abort_running_slot_q;
         if (finish_task_entry_valid & finish_task_entry_cq_slot == abort_running_slot_q) begin
            // corner case. abort msg received for task already awaiting finish
            finish_task_num_children[abort_running_cb_slot_q] = 1;
         end
      end
   end else if (finish_task_entry_valid) begin
      finish_task_valid[finish_task_cb_slot] = 1'b1;
      finish_task_slot[finish_task_cb_slot] = finish_task_entry_cq_slot;
      finish_task_num_children[finish_task_cb_slot] = last_enq_was_untied ? 0 : 1;
   end
end

// 9. Aborts
always_ff @(posedge clk) begin
   if (!rstn ) begin
      abort_running_task_q <= 1'b0;
   end else begin
      if (abort_running_task_q & finish_task_ready[abort_running_cb_slot_q]) begin
         abort_running_task_q <= 1'b0;
      end else if (abort_running_task[abort_running_cb_slot]) begin
         abort_running_task_q <= 1'b1;
         abort_running_cb_slot_q <= abort_running_cb_slot;
         abort_running_slot_q <=  cb_entry_cq_slot[abort_running_cb_slot];
      end else if (abort_running_task_q & !cb_entry_valid[abort_running_cb_slot_q]) begin
         // if abort_running_task was asserted in the same cycle as
         // finish_task_valid, reset it after the finish_task was acked.
         abort_running_task_q <= 1'b0;
      end
   end
end


generate 
for (i=0;i<THREADS;i++) begin
   assign task_arvalid[i] = (~cb_entry_valid[i] ) 
            & initialized & !(start_task_fifo_almost_full);
end
endgenerate

always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= READ_TARGET;
   end else begin
      state <= state_next;
   end
end

`ifdef DEBUG
integer cycle;
always_ff @(posedge clk) begin
   if (!rstn) cycle <= 0;
   else cycle <= cycle + 1;
end

generate 
for (i=0;i<THREADS;i++) begin
   always_ff @(posedge clk) begin
      if (state == NEXT_TASK) begin
         if (task_arvalid[i] & task_rvalid[i]) begin
            $display("[%5d][tile-%2d][core-%2d][%2d] dequeue_task: ts:%5d  vid:%5d  args:%4x  slot:%3d",
               cycle, TILE_ID, CORE_ID, i,
               task_rdata.ts, task_rdata.locale, task_rdata.args, task_rslot);
         end
      end
      if (abort_running_task[i] & !abort_running_task_q) begin
            $display("[%5d][tile-%2d][core-%2d][%2d] \tabort running task slot:%d", 
               cycle, TILE_ID, CORE_ID, i, cb_entry_cq_slot[abort_running_cb_slot]);
      end
   end
end
endgenerate
always_ff @(posedge clk) begin
   if (task_wvalid & task_wready) begin
         $display("[%5d][tile-%2d][core-%2d][%2d] \tenqueue_task: ts:%5d  vid:%5d  args:%4x",
            cycle, TILE_ID, CORE_ID, c_fifo_rdata_cb,
            task_wdata.ts, task_wdata.locale, task_wdata.args);
   end
end


`endif

cb_id_t lookup_entry;

always_ff @(posedge clk) begin
   if (!rstn) begin
      start <= 1'b0;
      lookup_entry <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            CORE_START: start <= reg_bus.wdata[CORE_ID];
            8'h80 : lookup_entry <= reg_bus.wdata[3:0];
         endcase
      end
   end 
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      dequeues_remaining <= 32'hffff_ffff;
   end else if (reg_bus.wvalid & reg_bus.waddr == CORE_N_DEQUEUES) begin
      dequeues_remaining <= reg_bus.wdata;
   end else if ((task_rvalid != 0) & (task_arvalid != 0)) begin
      dequeues_remaining <= dequeues_remaining - 1; 
   end
end

logic [31:0] num_enqueues, num_dequeues;

always_ff @(posedge clk) begin
   if (!rstn) begin
      num_enqueues <= 0;
      num_dequeues <= 0;
   end else begin
      if (task_wvalid & task_wready) begin
         num_enqueues <= num_enqueues + 1;
      end
      if ((task_arvalid != 0) & (task_rvalid !=0) ) begin
         num_dequeues <= num_dequeues + 1;
      end
   end
end



always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_bus.rvalid <= 1'b0;
      reg_bus.rdata <= 'x;
   end
   if (reg_bus.arvalid) begin
      reg_bus.rvalid <= 1'b1;
      casex (reg_bus.araddr) 
         CORE_N_DEQUEUES  : reg_bus.rdata <= dequeues_remaining;
         CORE_NUM_ENQ     : reg_bus.rdata <= num_enqueues;
         CORE_NUM_DEQ     : reg_bus.rdata <= num_dequeues;
         CORE_STATE       : reg_bus.rdata <= state;
         8'h90      : reg_bus.rdata <= cb_entry_state[lookup_entry]; 
         8'h94      : reg_bus.rdata <= cb_entry_cq_slot[lookup_entry]; 
         8'h98      : reg_bus.rdata <= cb_entry[lookup_entry].vid; 
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end  



// So that the relevant bits of rdata can be explicitly viewable on waveform 
logic [31:0] l1_rdata_32bit [0:15];
generate 
for (i=0;i<16;i=i+1) begin
   assign l1_rdata_32bit[i] = l1.rdata[i*32+:32];
end
endgenerate


endmodule
