`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

module core
#(
   parameter CORE_ID=0,
   parameter TILE_ID=0
) (
   input clk,
   input rstn,

   axi_bus_t.slave l1,

   // Task Dequeue
   output logic            task_arvalid,
   output task_type_t      task_araddr,
   input                   task_rvalid,
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
   output logic            start_task_valid,
   input                   start_task_ready, 
   output cq_slice_slot_t  start_task_slot,

   // Finish Task
   output logic            finish_task_valid,
   input                   finish_task_ready,
   output cq_slice_slot_t  finish_task_slot,
   // Informs the CQ of the number of children I have enqueued and whether
   // I have made a write that needs to be reversed on abort
   output child_id_t       finish_task_num_children,
   output logic            finish_task_undo_log_write,

   input                   abort_running_task,
   input cq_slice_slot_t   abort_running_slot,
   input                   gvt_task_slot_valid,
   input cq_slice_slot_t   gvt_task_slot,
   
   // Undo Log Writes
   output logic            undo_log_valid,
   input                   undo_log_ready,
   output undo_id_t        undo_log_id,
   output undo_log_addr_t  undo_log_addr,
   output undo_log_data_t  undo_log_data,
   output cq_slice_slot_t  undo_log_slot,

   reg_bus_t.master reg_bus,
   pci_debug_bus_t.master pci_debug
);

localparam TT_ID = 0; // task_type that this core will accept

typedef enum logic[2:0] {
      NEXT_TASK, INFORM_CQ,
      START_CORE, WAIT_CORE,
      ABORT_TASK, FINISH_TASK,
      WAIT_BVALID, WAIT_RVALID
   } core_state_t;

logic ap_rst_n;

logic ap_start;
logic ap_done;
logic ap_idle;

logic ap_l1_bready;
logic ap_l1_rready;

logic ap_l1_rvalid;
logic ap_l1_rlast;
logic ap_l1_bvalid;

logic        task_out_valid;
logic        task_out_ready;
logic [TQ_WIDTH-1:0] task_out_data;

logic        app_undo_log_valid;
logic        app_undo_log_ready;
logic [63:0] app_undo_log_data;

core_state_t state, state_next;

logic start;
logic [31:0] dequeues_remaining;

logic abort_running_task_q;

child_id_t child_id;
assign finish_task_num_children = child_id;

cq_slice_slot_t cq_slot;
always_ff @(posedge clk) begin
   if ((state == NEXT_TASK) & task_rvalid) begin
      cq_slot <= task_rslot;
   end
end
always_ff @(posedge clk) begin
   if ((state == NEXT_TASK) & task_rvalid) begin
      finish_task_undo_log_write <= 1'b0;
   end else if (app_undo_log_valid) begin
      finish_task_undo_log_write <= 1'b1;
   end
end
always_ff @(posedge clk) begin
   if (!rstn ) begin
      abort_running_task_q <= 1'b0;
   end else begin
      if (state == NEXT_TASK) begin
         abort_running_task_q <= 1'b0;
      end else if (abort_running_task) begin
         abort_running_task_q <= 1'b1;
      end 
   end
end

assign task_cq_slot = cq_slot;
assign task_child_id = child_id;

assign start_task_valid = (state == INFORM_CQ);
assign start_task_slot = cq_slot;

assign finish_task_valid = (state == FINISH_TASK) & !task_wvalid;
assign finish_task_slot = cq_slot;

logic [2:0] reads_left;
logic [2:0] writes_left;
always_ff @(posedge clk) begin
   if (state==NEXT_TASK) begin
      reads_left <= 0;
   end else if (l1.arvalid & l1.arready) begin
      reads_left <= reads_left + 1;
   end else if (l1.rvalid & l1.rready & l1.rlast) begin
      reads_left <= reads_left - 1;
   end
end
always_ff @(posedge clk) begin
   if (state==NEXT_TASK) begin
      writes_left <= 0;
   end else if (l1.awvalid & l1.awready) begin
      writes_left <= writes_left + 1;
   end else if (l1.bvalid & l1.bready) begin
      writes_left <= writes_left - 1;
   end
end

task_t task_in;
always_ff @(posedge clk) begin
   if (task_arvalid & task_rvalid) begin
      task_in <= task_rdata;
   end
end

assign ap_start = (state == START_CORE) | (state == WAIT_CORE) & ap_rst_n;

assign task_arvalid = (state == NEXT_TASK) & start & (dequeues_remaining >0) & ap_rst_n;

always_comb begin

   state_next = state;
   case(state)
      NEXT_TASK: begin
         if (task_arvalid & task_rvalid) begin
            state_next = INFORM_CQ;
         end
      end
      INFORM_CQ: begin
         if (start_task_ready) begin
            state_next = abort_running_task_q ? FINISH_TASK : START_CORE;
         end
      end
      START_CORE: begin
         state_next = WAIT_CORE;
      end
      WAIT_CORE: begin
         if (!ap_rst_n) begin
            state_next = ABORT_TASK;
         end else if (ap_done) begin
            state_next = FINISH_TASK;
         end
      end
      ABORT_TASK: begin
         if (ap_idle) begin
            state_next = FINISH_TASK;
         end
      end
      FINISH_TASK: begin
         if (finish_task_valid & finish_task_ready) begin
            state_next = (reads_left | writes_left) ? WAIT_BVALID : NEXT_TASK;
         end else if (abort_running_task_q) begin
            state_next = ABORT_TASK; 
         end
      end
      WAIT_BVALID: begin
         if (writes_left == 0) begin                     
            state_next = WAIT_RVALID;
         end
      end
      WAIT_RVALID: begin
         if (reads_left == 0) begin
            state_next = NEXT_TASK;
         end
      end

   endcase
end

// If the app_core was aborted with pending mem requeuest,
// core should stall until all have a response
always_comb begin
   if ( (state == WAIT_BVALID) | (state == WAIT_RVALID)) begin
      l1.bready = 1'b1;
      l1.rready = 1'b1;
      ap_l1_rlast = 1'b0;
      ap_l1_rvalid = 1'b0;
      ap_l1_bvalid = 1'b0;
   end else begin
      l1.bready = ap_l1_bready;
      l1.rready = ap_l1_rready;
      ap_l1_rlast = l1.rlast;
      ap_l1_rvalid = l1.rvalid;
      ap_l1_bvalid = l1.bvalid;
   end   
end

always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= NEXT_TASK;
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
always_ff @(posedge clk) begin
   if (state == NEXT_TASK) begin
      if (task_arvalid & task_rvalid) begin
         $display("[%5d][tile-%2d][core-%2d] dequeue_task: ts:%5x  hint:%5x ttype:%2d args:(%4d, %4d) slot:%3d",
            cycle, TILE_ID, CORE_ID, task_rdata.ts, task_rdata.hint, task_rdata.ttype,
            task_rdata.args[63:32], task_rdata.args[31:0], task_rslot);
      end
   end

   if (task_wvalid & task_wready) begin
         $display("[%5d][tile-%2d][core-%2d] \tenqueue_task: ts:%5x  hint:%5x ttype:%2d args:(%4d, %4d)",
            cycle, TILE_ID, CORE_ID, task_wdata.ts, task_wdata.hint, task_wdata.ttype,
            task_wdata.args[63:32], task_wdata[31:0]);
   end
   if (abort_running_task & !abort_running_task_q) begin
         $display("[%5d][tile-%2d][core-%2d] \tabort running task", 
            cycle, TILE_ID, CORE_ID);
   end
end


`endif


always_ff @(posedge clk) begin
   if (!rstn) begin
      start <= 1'b0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            CORE_START: start <= reg_bus.wdata[CORE_ID];
         endcase
      end
   end 
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      dequeues_remaining <= 32'hffff_ffff;
   end else if (reg_bus.wvalid & reg_bus.waddr == CORE_N_DEQUEUES) begin
      dequeues_remaining <= reg_bus.wdata;
   end else if (task_rvalid & task_arvalid) begin
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
      if (task_arvalid & task_rvalid) begin
         num_dequeues <= num_dequeues + 1;
      end
   end
end

always_ff @(posedge clk) begin
   if (state == NEXT_TASK) begin
      child_id <= 0;
   end else if (task_wvalid & task_wready & !task_enq_untied) begin
      // once this task is committed only children enqueued tied will 
      // be sent cut_tie messages
      child_id <= child_id + 1;
   end
end


always_ff @(posedge clk) begin
   task_enq_untied = gvt_task_slot_valid & ( gvt_task_slot == cq_slot);
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_bus.rvalid <= 1'b0;
      reg_bus.rdata <= 'x;
   end
   if (reg_bus.arvalid) begin
      reg_bus.rvalid <= 1'b1;
      casex (reg_bus.araddr) 
         CORE_HINT        : reg_bus.rdata <= task_in.hint;
         CORE_TS          : reg_bus.rdata <= task_in.ts;
         CORE_N_DEQUEUES  : reg_bus.rdata <= dequeues_remaining;
         CORE_NUM_ENQ     : reg_bus.rdata <= num_enqueues;
         CORE_NUM_DEQ     : reg_bus.rdata <= num_dequeues;
         CORE_STATE       : reg_bus.rdata <= state;
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end  

// Core abort is implemented by resetting the core.
// Hold the rst_n for 6 cycles 
logic [2:0] rst_counter;
always_ff @(posedge clk) begin
   if (!rstn) begin
      rst_counter <= 0;
      ap_rst_n <= 1'b0;
   end else begin
      if (state == WAIT_CORE & !ap_done) begin
         if (abort_running_task_q) begin
            rst_counter <= (rst_counter < '1) ? rst_counter + 1 : '1;
         end
      end else begin
         rst_counter <= 0;
      end
      ap_rst_n <= !((rst_counter > 0) &  (rst_counter < '1));
   end
end



always_ff @(posedge clk) begin
   if (!rstn) begin
      task_wvalid <= 1'b0;
      task_wdata <= 'x;
   end else begin
      if (task_out_valid & task_out_ready) begin
         task_wvalid <= 1'b1;
         {task_wdata.args, task_wdata.ttype, task_wdata.hint, task_wdata.ts}
                  <= task_out_data;
      end else if (task_wready) begin
         task_wvalid <= 1'b0;
      end else if (state == ABORT_TASK) begin
         // drop any task waiting to be enqueued on an abort
         task_wvalid <= 1'b0;
      end
   end
end
assign task_out_ready = !task_wvalid;

always_ff @(posedge clk) begin
   if (!rstn) begin
      undo_log_valid <= 1'b0;
      undo_log_addr <= 'x;
      undo_log_data <= 'x;
   end else begin
      if (app_undo_log_valid & app_undo_log_ready) begin
         undo_log_valid <= 1'b1;
         {undo_log_data, undo_log_addr} <= app_undo_log_data;
      end else if (undo_log_ready) begin
         undo_log_valid <= 1'b0;
      end
   end
end
assign app_undo_log_ready = !undo_log_valid;
always_ff @(posedge clk) begin
   if (!rstn) begin
      undo_log_id <= 0;
   end else begin
      if (finish_task_valid) begin
         undo_log_id <= 0;
      end else if (undo_log_valid & undo_log_ready) begin
         undo_log_id <= undo_log_id + 1; 
      end
   end
end

assign undo_log_slot = cq_slot; 
assign l1.awaddr[63:32] = 0;
assign l1.araddr[63:32] = 0;
assign l1.wstrb[63:4] = 0; 

assign l1.awid = 0;
assign l1.wid = 0;
assign l1.arid = 0;

// So that the relevant bits of w/rdata can be explicitly viewable on waveform 
logic [31:0] l1_wdata_32bit;
logic [31:0] l1_rdata_32bit;

assign l1_wdata_32bit = l1.wdata[31:0];
assign l1_rdata_32bit = l1.rdata[31:0];

`include "gen_core_spec.vh"

endmodule
