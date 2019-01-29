`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

module riscv_core
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

localparam TT_ID = TASK_TYPE_ALL; // task_type that this core will accept

typedef enum logic[2:0] {
      WAIT_CORE, NEXT_TASK, INFORM_CQ,
      IO_READ,
      FINISH_TASK, FINISH_TASK_ABORT,
      ABORT_TASK
   } core_state_t;

logic ap_rst_n;

logic ap_done;
logic ap_idle;
logic ap_ready;

logic ap_l1_bready;
logic ap_l1_rready;

logic ap_l1_rvalid;
logic ap_l1_rlast;
logic ap_l1_bvalid;

logic        task_out_valid;
logic        task_out_ready;
logic [TQ_WIDTH-1:0] task_out_data;

logic        app_undo_log_valid;
logic [63:0] app_undo_log_data;

core_state_t state, state_next;

logic start;
logic [31:0] dequeues_remaining;

logic dBus_cmd_valid;
logic dBus_cmd_ready;
logic dBus_cmd_payload_wr;
logic [31:0] dBus_cmd_addr;
logic [31:0] dBus_cmd_data;
logic dBus_rsp_valid;
logic [31:0] dBus_rsp_data;

logic [31:0] debug_pc;

logic rst_core;

logic abort_running_task_q;
logic [4:0] interrupt_counter;
logic interrupt;
   
logic [LOG_LOG_DEPTH:0] log_size; 

logic [31:0] cur_cycle;
logic debug_mode;

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
      if (abort_running_task) begin
         if (state == FINISH_TASK) begin
            abort_running_task_q <= 1'b0;
         end else begin
            abort_running_task_q <= 1'b1;
         end
      end else if ((state == ABORT_TASK & (debug_pc == 32'h80000000)) |
                   (state_next == NEXT_TASK) ) begin
         abort_running_task_q <= 1'b0;
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn ) begin
      interrupt_counter <= 0;
   end else begin
      if (state == ABORT_TASK) begin
         interrupt_counter <= interrupt_counter + 1;
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn ) begin
      cur_cycle <= 0;
   end else begin
      cur_cycle <= cur_cycle + 1;
   end
end

assign task_cq_slot = cq_slot;
assign task_child_id = child_id;

assign start_task_valid = (state == INFORM_CQ);
assign start_task_slot = cq_slot;

logic [31:0] io_read_addr;
always_comb begin
   finish_task_valid = 1'b0;
   if (state == FINISH_TASK || state == FINISH_TASK_ABORT) begin
      finish_task_valid = !task_wvalid;
   end else if (state == IO_READ) begin
      if (io_read_addr == RISCV_DEQ_TASK & abort_running_task_q) begin
         finish_task_valid = 1'b1;
      end
   end
end
assign finish_task_slot = cq_slot;
/*
logic [2:0] i_reads_left;
logic [2:0] d_reads_left;
logic [2:0] i_writes_left;
always_ff @(posedge clk) begin
   if (state==NEXT_TASK) begin
      i_reads_left <= 0;
   end else if (iBus_in.arvalid & iBus_in.arready) begin
      i_reads_left <= i_reads_left + 1;
   end else if (iBus_in.rvalid & iBus_in.rready & iBus_in.rlast) begin
      i_reads_left <= i_reads_left - 1;
   end
end
always_ff @(posedge clk) begin
   if (state==NEXT_TASK) begin
      i_reads_left <= 0;
   end else if (iBus_in.arvalid & iBus_in.arready) begin
      i_reads_left <= i_reads_left + 1;
   end else if (iBus_in.rvalid & iBus_in.rready & iBus_in.rlast) begin
      i_reads_left <= i_reads_left - 1;
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
*/
task_t task_in;
always_ff @(posedge clk) begin
   if (task_arvalid & task_rvalid) begin
      task_in <= task_rdata;
   end
end

assign task_arvalid = (state == NEXT_TASK) & start & (dequeues_remaining >0) 
            & !abort_running_task_q;
assign task_araddr = TT_ID;

assign ap_done = dBus_cmd_valid & (dBus_cmd_addr == RISCV_FINISH_TASK)  & dBus_cmd_payload_wr; 

always_ff @(posedge clk) begin
   if (dBus_cmd_valid & dBus_cmd_ready & !dBus_cmd_payload_wr) begin
      io_read_addr <= dBus_cmd_addr;
   end
end
logic [2:0] writes_left;
always_ff @(posedge clk) begin
   if (!rstn) begin
      writes_left <= 0;
   end else begin
      if (state==NEXT_TASK) begin
         writes_left <= 0;
      end else if (dBus_in.awvalid & dBus_in.awready) begin
         writes_left <= writes_left + 1;
      end else if (dBus_in.bvalid & dBus_in.bready) begin
         writes_left <= writes_left - 1;
      end
   end
end

always_comb begin

   state_next = state;
   case(state)
      WAIT_CORE: begin
         if (dBus_cmd_valid & !dBus_cmd_payload_wr) begin
            case (dBus_cmd_addr) 
               RISCV_DEQ_TASK_HINT,
               RISCV_DEQ_TASK_ARG0, 
               RISCV_DEQ_TASK_ARG1, 
               RISCV_CUR_CYCLE, 
               RISCV_TILE_ID, RISCV_CORE_ID,
               RISCV_DEQ_TASK_TTYPE : state_next = IO_READ;
               RISCV_DEQ_TASK : begin 
                  if (writes_left == 0) begin
                     state_next = NEXT_TASK;
                  end
               end
               default: state_next = state;
            endcase
         end else if (ap_done) begin
            state_next = FINISH_TASK;
         end else if (abort_running_task_q) begin
            state_next = FINISH_TASK_ABORT;
         end
      end
      NEXT_TASK: begin
         if (task_arvalid & task_rvalid) begin
            state_next = INFORM_CQ;
         end
      end
      INFORM_CQ: begin
         if (start_task_ready) begin
            state_next = IO_READ;
         end
      end
      FINISH_TASK: begin
         if (finish_task_valid & finish_task_ready) begin
            state_next = WAIT_CORE;
         end
      end
      FINISH_TASK_ABORT: begin
         if (finish_task_valid & finish_task_ready) begin
            state_next = ABORT_TASK;
         end
      end
      IO_READ: begin
         if (io_read_addr == RISCV_DEQ_TASK & abort_running_task_q) begin
            if (finish_task_valid & finish_task_ready) begin
               state_next = NEXT_TASK;
            end
         end else begin
            state_next = WAIT_CORE;
         end
      end
      ABORT_TASK: begin
         if (debug_pc == 32'h80000000) begin
            state_next = WAIT_CORE;
         end
      end

   endcase
end
assign interrupt = (state == ABORT_TASK) | 
                   (state_next == FINISH_TASK_ABORT) | 
                   (state == FINISH_TASK_ABORT) | 
                   (state == ABORT_TASK);

always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= WAIT_CORE;
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
      debug_mode <= 1'b0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            CORE_START: start <= reg_bus.wdata[CORE_ID];
            CORE_DEBUG_MODE: debug_mode <= reg_bus.wdata[CORE_ID];
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
         CORE_PC          : reg_bus.rdata <= debug_pc;
         DEBUG_CAPACITY : reg_bus.rdata <= log_size;
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end  



always_ff @(posedge clk) begin
   if (!rstn) begin
      task_wvalid <= 1'b0;
      task_wdata.ts <= 'x; 
   end else begin
      if (task_out_valid & task_out_ready) begin
         task_wvalid <= 1'b1;
      end else if (task_wready) begin
         task_wvalid <= 1'b0;
      end else if (state == FINISH_TASK_ABORT) begin
         // drop any task waiting to be enqueued on an abort
         task_wvalid <= 1'b0;
      end
   end
end
always_ff @ (posedge clk) begin
   if (dBus_cmd_valid & dBus_cmd_payload_wr & !task_wvalid) begin
      case (dBus_cmd_addr) 
         RISCV_DEQ_TASK      : task_wdata.ts <= dBus_cmd_data;
         RISCV_DEQ_TASK_HINT : task_wdata.hint <= dBus_cmd_data; 
         RISCV_DEQ_TASK_TTYPE: task_wdata.ttype <= dBus_cmd_data;
         RISCV_DEQ_TASK_ARG0 : task_wdata.args[31:0] <= dBus_cmd_data;
         RISCV_DEQ_TASK_ARG1 : task_wdata.args[63:32] <= dBus_cmd_data;
         RISCV_UNDO_LOG_ADDR : undo_log_addr <= dBus_cmd_data;
         RISCV_UNDO_LOG_DATA : undo_log_data <= dBus_cmd_data;
      endcase
   end
end

assign task_out_ready = !task_wvalid;

always_ff @(posedge clk) begin
   if (!rstn) begin
      undo_log_valid <= 1'b0;
   end else begin
      if (app_undo_log_valid) begin
         undo_log_valid <= 1'b1;
      end else if (undo_log_ready) begin
         undo_log_valid <= 1'b0;
      end
   end
end
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

// So that the relevant bits of w/rdata can be explicitly viewable on waveform 
logic [31:0] l1_wdata_32bit;
logic [31:0] l1_rdata_32bit;

assign l1_wdata_32bit = l1.wdata[31:0];
assign l1_rdata_32bit = l1.rdata[31:0];

axi_bus_t iBus_in ();
axi_bus_t iBus_out ();
axi_bus_t dBus_in ();
axi_bus_t dBus_out ();
assign iBus_in.arsize = 2;

assign rst_core = !(rstn & start);

assign dBus_in.awsize = 2;
assign dBus_in.arsize = 2;
assign dBus_in.wstrb = 4'b1111;
assign dBus_in.awlen = 0;
assign dBus_in.arlen = 0;
assign dBus_in.wlast = 1'b1;
assign dBus_in.rready = 1'b1;
assign dBus_in.bready = 1'b1;
assign dBus_in.awaddr = dBus_cmd_addr;
assign dBus_in.araddr = dBus_cmd_addr;
assign dBus_in.wdata = dBus_cmd_data;
always_comb begin
   dBus_cmd_ready = 1'b0;
   dBus_in.awvalid = 1'b0;
   dBus_in.wvalid = 1'b0;
   dBus_in.arvalid = 1'b0;

   task_out_valid = 1'b0;
   app_undo_log_valid = 1'b0;

   if (dBus_cmd_valid) begin
      if (dBus_cmd_payload_wr) begin
         case (dBus_cmd_addr) 
            RISCV_FINISH_TASK: dBus_cmd_ready = (finish_task_valid & finish_task_ready);
            RISCV_DEQ_TASK_HINT,
            RISCV_DEQ_TASK_ARG0,
            RISCV_DEQ_TASK_ARG1,
            RISCV_DEQ_TASK_TTYPE: dBus_cmd_ready = !(task_wvalid);
            RISCV_DEQ_TASK: begin
               if (!task_wvalid) begin
                  task_out_valid = 1'b1 & !abort_running_task_q;
                  dBus_cmd_ready = 1'b1;
               end
            end
            RISCV_UNDO_LOG_DATA: begin
               app_undo_log_valid = 1'b1;
               dBus_cmd_ready = 1'b1;
            end
            RISCV_UNDO_LOG_ADDR: begin
               dBus_cmd_ready = 1'b1;
            end
            RISCV_DEBUG_PRINTF : begin
               dBus_cmd_ready = 1'b1;
            end
            // no writing to CORE_ID, TILE_ID
            default: begin
               dBus_in.awvalid = 1'b1; 
               dBus_in.wvalid = 1'b1; 
               if (dBus_in.awready) begin
                  dBus_cmd_ready = 1'b1;
               end
            end
         endcase
      end else begin
         if (state == WAIT_CORE || state == ABORT_TASK) begin
            case (dBus_cmd_addr) 
               RISCV_DEQ_TASK_HINT,
               RISCV_DEQ_TASK_TTYPE,
               RISCV_DEQ_TASK_ARG0,
               RISCV_TILE_ID,
               RISCV_CORE_ID,
               RISCV_DEQ_TASK_ARG1: begin
                  dBus_cmd_ready = 1'b1;
               end
               RISCV_DEQ_TASK: begin
                  dBus_cmd_ready = (writes_left == 0);
               end
               // no reading from printf
               RISCV_CUR_CYCLE: begin
                  dBus_cmd_ready = 1'b1;
               end
               default: begin
                  dBus_in.arvalid = 1'b1;
                  if (dBus_in.arready) begin
                     dBus_cmd_ready = 1'b1;
                  end
               end
            endcase
         end
      end
   end
end 
always_comb begin
   dBus_rsp_valid = 1'b0;
   dBus_rsp_data = 'x;
   if (state == IO_READ) begin
      case (io_read_addr) 
         RISCV_DEQ_TASK      : dBus_rsp_data = task_in.ts;
         RISCV_DEQ_TASK_HINT : dBus_rsp_data = task_in.hint; 
         RISCV_DEQ_TASK_TTYPE: dBus_rsp_data = task_in.ttype; 
         RISCV_DEQ_TASK_ARG0 : dBus_rsp_data = task_in.args[31:0]; 
         RISCV_DEQ_TASK_ARG1 : dBus_rsp_data = task_in.args[63:32]; 
         RISCV_CUR_CYCLE     : dBus_rsp_data = cur_cycle; 
         RISCV_TILE_ID       : dBus_rsp_data = TILE_ID; 
         RISCV_CORE_ID       : dBus_rsp_data = CORE_ID; 
      endcase
      if (io_read_addr == RISCV_DEQ_TASK) begin
         // if task was aborted don't respond yet 
         if (!abort_running_task_q) dBus_rsp_valid = 1'b1;
      end else begin
         dBus_rsp_valid = 1'b1;
      end
   end else begin
      dBus_rsp_valid = dBus_in.rvalid;
      dBus_rsp_data = dBus_in.rdata[31:0];
   end

end
   assign iBus_in.araddr[63:32] = 0;
   assign iBus_in.arlen = 7;
   assign iBus_in.rready = 1'b1;
   assign iBus_in.bready = 1'b1;

   VexRiscv RISCV (
      .timerInterrupt            (1'b0),
      .externalInterrupt         (interrupt),
      .iBus_cmd_valid            (iBus_in.arvalid),
      .iBus_cmd_ready            (iBus_in.arready),
      .iBus_cmd_payload_address  (iBus_in.araddr[31:0]),
      .iBus_cmd_payload_size     (),
      .iBus_rsp_valid            (iBus_in.rvalid),
      .iBus_rsp_payload_data     (iBus_in.rdata[31:0]),
      .iBus_rsp_payload_error    (1'b0),
      .dBus_cmd_valid            (dBus_cmd_valid),
      .dBus_cmd_ready            (dBus_cmd_ready),
      .dBus_cmd_payload_wr       (dBus_cmd_payload_wr),
      .dBus_cmd_payload_address  (dBus_cmd_addr),
      .dBus_cmd_payload_size     (),
      .dBus_cmd_payload_data     (dBus_cmd_data),
      .dBus_rsp_ready            (dBus_rsp_valid),
      .dBus_rsp_data             (dBus_rsp_data),
      .dBus_rsp_error            (1'b0),
      .clk                       (clk),
      .reset                     (rst_core),
      .debug_pc                  (debug_pc)
   );

   axi_decoder #(
      .ID_BASE( (TILE_ID<<11) + ((CORE_ID) << 4)),
      .MAX_AWSIZE(2),
      .MAX_ARSIZE(5),
      .LOG_MAX_REQUESTS(2)
   ) IBUS_CONVERT (
     .clk(clk),
     .rstn(rstn),

      .core(iBus_in),
      .l2(iBus_out)
   );
   
   axi_decoder #(
      .ID_BASE( (TILE_ID<<11) + ((CORE_ID) << 4) + 8),
      .MAX_AWSIZE(2),
      .MAX_ARSIZE(5),
      .LOG_MAX_REQUESTS(2)
   ) DBUS_CONVERT (
     .clk(clk),
     .rstn(rstn),

      .core(dBus_in),
      .l2(dBus_out)
   );
   
   axi_mux #(
      .ID_BIT(3),
      .DELAY(0)
   ) AXI_MUX (
     .clk(clk),
     .rstn(rstn),

      .a(iBus_out),
      .b(dBus_out),

      .out_q(l1)
   );
generate 
if (CORE_LOGGING[TILE_ID] & (CORE_ID == 1)) begin
   
   logic log_valid;
   typedef struct packed {
     
      logic [31:0] debug_pc;

      logic [31:0] dBus_cmd_addr;
      logic [31:0] dBus_cmd_data;
      logic [31:0] dBus_rsp_data;

      logic [15:0] awid;
      logic [15:0] arid;
      logic [15:0] rid;
      logic [15:0] bid;
      logic [31:0] awaddr;
      logic [31:0] wdata;
      logic [31:0] araddr;
      logic [31:0] rdata;
     
      logic [11:0] unused;
      logic dBus_cmd_valid;
      logic dBus_cmd_ready;
      logic dBus_cmd_payload_wr;
      logic dBus_rsp_valid;

      logic [3:0] state;
     
      logic awvalid;
      logic awready;
      logic wvalid;
      logic wready;
      logic arvalid;
      logic arready;
      logic rvalid;
      logic rready;
      logic bvalid;
      logic bready;
      logic rlast;
      logic wlast;


   } riscv_log_t;
   riscv_log_t  log_word;
   always_comb begin
      log_valid = 1'b0;

      log_word = '0;
      log_word.awid = l1.awid; 
      log_word.arid = l1.arid; 
      log_word.rid = l1.rid; 
      log_word.bid = l1.bid; 
      log_word.awaddr = l1.awaddr; 
      log_word.araddr = l1.araddr; 
      log_word.wdata =  l1.wdata; 
      log_word.rdata = l1.rdata; 
      log_word.state = state; 
      log_word.debug_pc  = debug_pc; 

      log_word.awvalid  = l1.awvalid;
      log_word.awready  = l1.awready;
      log_word.wvalid   = l1.wvalid ;
      log_word.wready   = l1.wready ;
      log_word.arvalid  = l1.arvalid;
      log_word.arready  = l1.arready;
      log_word.rvalid   = l1.rvalid ;
      log_word.rready   = l1.rready ;
      log_word.bvalid   = l1.bvalid ;
      log_word.bready   = l1.bready ;
      log_word.rlast    = l1.rlast  ;
      log_word.wlast    = l1.wlast  ;
      
      log_word.dBus_cmd_valid    = dBus_cmd_valid  ;
      log_word.dBus_cmd_ready    = dBus_cmd_ready  ;
      log_word.dBus_cmd_payload_wr   = dBus_cmd_payload_wr  ;
      log_word.dBus_rsp_valid    = dBus_rsp_valid  ;
      log_word.dBus_cmd_addr    = dBus_cmd_addr  ;
      log_word.dBus_cmd_data    = dBus_cmd_data  ;
      log_word.dBus_rsp_data    = dBus_rsp_data  ;
      
      if (debug_mode) begin
         log_valid = dBus_cmd_valid & dBus_cmd_payload_wr & 
            (dBus_cmd_addr == RISCV_DEBUG_PRINTF);
      end else begin
         log_valid = (l1.awvalid | l1.arvalid | l1.wvalid | l1.rvalid | l1.bvalid | 
                  dBus_cmd_valid | dBus_rsp_valid);
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
