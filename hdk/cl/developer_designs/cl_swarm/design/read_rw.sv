import swarm::*;

module read_rw
#(
   parameter TILE_ID
) (
   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            task_in, 
   input cq_slice_slot_t   cq_slot_in,
   input thread_id_t       thread_id_in,
   
   input logic         gvt_task_slot_valid,
   cq_slice_slot_t     gvt_task_slot,

   output logic        arvalid,
   input               arready,
   output logic [31:0] araddr,
   output id_t         arid,

   input               rvalid,
   output logic        rready,
   input id_t          rid,
   input logic [511:0] rdata,
   input cache_addr_t  rindex,

   output logic        task_out_valid,
   input               task_out_ready,
   output rw_write_t   task_out,  

   input fifo_size_t   task_out_fifo_occ, 
   
   reg_bus_t         reg_bus,
   pci_debug_bus_t   pci_debug
);


task_t task_desc [0:N_THREADS-1];
cq_slice_slot_t task_cq_slot [0:N_THREADS-1];

logic [31:0] base_rw_addr;

fifo_size_t fifo_out_almost_full_thresh;
logic [31:0] dequeues_remaining;

assign arid = thread_id_in;
assign araddr = base_rw_addr + (task_in.locale <<  RW_ARSIZE);

logic can_dequeue; 
assign can_dequeue = (dequeues_remaining > 0) & 
   ( (task_out_fifo_occ < fifo_out_almost_full_thresh) 
    | (gvt_task_slot_valid & (gvt_task_slot == cq_slot_in)));

always_comb begin
   arvalid = 1'b0;
   task_in_ready = 1'b0;
   if (task_in_valid & can_dequeue) begin
      if (task_in.no_read) begin
         task_in_ready = 1'b1;
      end else begin
         arvalid = 1'b1;
         if (arready) begin
            task_in_ready = 1'b1;
         end
      end
   end
end

always_ff @(posedge clk) begin
   if (task_in_valid & task_in_ready) begin
      task_desc[thread_id_in] <= task_in;
      task_cq_slot[thread_id_in] <= cq_slot_in;
   end
end

object_t undo_log [0:2**LOG_CQ_SLICE_SIZE-1];
object_t undo_log_read_word;

logic             reg_task_valid;
task_t            reg_task;
cq_slice_slot_t   reg_slot;
thread_id_t       reg_thread;

always_ff @(posedge clk) begin
   if (task_out_valid & task_out_ready) begin
      undo_log[task_out.cq_slot] <= task_out.object;
   end
   if (task_in_valid & task_in_ready & task_in.ttype == TASK_TYPE_UNDO_LOG_RESTORE) begin
      undo_log_read_word <= undo_log[cq_slot_in];
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_task_valid <= 1'b0;
   end
   if (task_in_valid & task_in_ready) begin
      reg_task <= task_in;
      reg_slot <= cq_slot_in;
      reg_thread <= thread_id_in;
      reg_task_valid <= 1'b1;
   end else if (task_out_valid & task_out_ready) begin
      reg_task_valid <= 1'b0;
   end

end


always_comb begin
   task_out.task_desc = task_desc[rid];
   task_out.cq_slot = task_cq_slot[rid];
   task_out.thread = rid;
   task_out.object = rdata[ task_out.task_desc.locale[3:0] * 32 +: 32 ]; 
   // TODO: generalize above to all RW_ARSIZEs
   task_out.cache_addr = rindex;
   task_out_valid = 1'b0;
   rready = 1'b0;
   if (reg_task_valid & (reg_task.ttype == TASK_TYPE_UNDO_LOG_RESTORE)) begin
      task_out.task_desc = reg_task;
      task_out.cq_slot = reg_slot;
      task_out.thread = reg_thread;
      task_out.object = undo_log_read_word;
      task_out_valid = 1'b1;
   end else if (rvalid) begin
      task_out_valid = 1'b1;
      if (task_out_ready) begin
         rready = 1'b1;
      end
   end
end


logic [LOG_LOG_DEPTH:0] log_size; 
always_ff @(posedge clk) begin
   if (!rstn) begin
      base_rw_addr <= 0;
      fifo_out_almost_full_thresh <= '1;
      dequeues_remaining <= '1;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            RW_BASE_ADDR : base_rw_addr <= {reg_bus.wdata[29:0], 2'b00};
            CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD : fifo_out_almost_full_thresh <= reg_bus.wdata;
            CORE_N_DEQUEUES: dequeues_remaining <= reg_bus.wdata;
         endcase
      end else begin
         if (task_in_valid & task_in_ready) begin
            dequeues_remaining <= dequeues_remaining - 1;
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
         CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD : reg_bus.rdata <= task_out_fifo_occ;
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end
         
`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [read_rw] [%2d] [thread-%2d] ts:%8d locale:%4d type:%1x",
            cycle, TILE_ID, cq_slot_in, thread_id_in,
            task_in.ts, task_in.locale, task_in.ttype) ;
      end
   end 
`endif

if (READ_RW_LOGGING[TILE_ID]) begin
   logic log_valid;
   typedef struct packed {
      
      logic task_in_valid;
      logic task_in_ready;
      logic task_out_valid;
      logic task_out_ready;
      logic arvalid;
      logic arready;
      logic rvalid;
      logic rready;
      logic [7:0] out_fifo_occ;
      logic [15:0] out_thread;
      
      logic [7:0] in_cq_slot;
      logic [7:0] in_thread;
      logic [11:0] rid;
      logic [3:0]  task_in_ttype;

      logic [31:0] task_in_ts;
      logic [31:0] task_in_locale;

      logic [31:0] araddr;

      logic [31:0] out_object;
      logic [31:0] out_ts;
      logic [31:0] out_locale;
      
   } rw_read_log_t;
   rw_read_log_t log_word;
   always_comb begin
      log_valid = (task_in_valid & task_in_ready) | (task_out_valid & task_out_ready) ;

      log_word = '0;

      log_word.task_in_valid = task_in_valid;
      log_word.task_in_ready = task_in_ready;
      log_word.task_out_valid = task_out_valid;
      log_word.task_out_ready = task_out_ready;
      log_word.arvalid = arvalid;
      log_word.arready = arready;
      log_word.rvalid = rvalid;
      log_word.rready = rready;
      log_word.out_fifo_occ = task_out_fifo_occ;

      log_word.in_cq_slot = cq_slot_in;
      log_word.in_thread = thread_id_in;

      log_word.rid = rid;
      log_word.task_in_ttype = task_in.ttype; 
      log_word.task_in_ts = task_in.ts; 
      log_word.task_in_locale = task_in.locale; 
      log_word.araddr = araddr; 
      log_word.out_object = task_out.object;
      log_word.out_thread = task_out.thread; 
      log_word.out_ts = task_out.task_desc.ts;
      log_word.out_locale = task_out.task_desc.locale;

   end

   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) RW_READ_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid(log_valid),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end

endmodule
