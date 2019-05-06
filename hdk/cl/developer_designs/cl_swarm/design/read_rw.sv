import swarm::*;

module read_rw
#(
) (
   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            task_in, 
   input cq_slice_slot_t   cq_slot_in,
   input thread_id_t       thread_id_in,

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
   
   reg_bus_t         reg_bus
);


task_t task_desc [0:N_THREADS-1];
cq_slice_slot_t task_cq_slot [0:N_THREADS-1];

logic [31:0] base_rw_addr;

assign arid = thread_id_in;
assign araddr = base_rw_addr + (task_in.locale <<  RW_ARSIZE);
always_comb begin
   arvalid = 1'b0;
   task_in_ready = 1'b0;
   if (task_in_valid) begin
      arvalid = 1'b1;
      if (arready) begin
         task_in_ready = 1'b1;
      end
   end
end

always_ff @(posedge clk) begin
   if (task_in_valid & task_in_ready) begin
      task_desc[thread_id_in] <= task_in;
      task_cq_slot[thread_id_in] <= cq_slot_in;
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
   if (rvalid) begin
      task_out_valid = 1'b1;
      if (task_out_ready) begin
         rready = 1'b1;
      end
   end
end



always_ff @(posedge clk) begin
   if (!rstn) begin
      base_rw_addr <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            RW_BASE_ADDR : base_rw_addr <= {reg_bus.wdata[29:0], 2'b00};
         endcase
      end
   end
end
always_ff @(posedge clk) begin
   reg_bus.rvalid <= reg_bus.arvalid;
end
assign reg_bus.rdata = 0;
         
`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [read_rw] [thread-%2d] ts:%8d locale:%4d",
            cycle, 0 /*TILE_ID*/, thread_id_in,
            task_in.ts, task_in.locale) ;
      end
   end 
`endif

endmodule
