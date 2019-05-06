import swarm::*;

module write_rw
#(
) (
   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input rw_write_t        task_in, 

   output logic        wvalid,
   input               wready,
   output logic [31:0] waddr, // directly index into the data_array bypassing tags
   output logic [511:0] wdata,
   output logic [63:0] wstrb,

   output logic            task_out_valid,
   input                   task_out_ready,
   output ro1_in_t         task_out,  
   output cq_slice_slot_t  task_out_cq_slot,  

   output logic        unlock_locale,
   output logic        finish_task,
   output thread_id_t  unlock_thread,
   
   reg_bus_t         reg_bus
);

assign unlock_thread = task_in.thread;

always_ff @(posedge clk) begin
   if (wvalid & wready) begin
      task_out <= task_in.task_desc;
      task_out_cq_slot <= task_in.cq_slot;
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      task_out_valid <= 1'b0;
   end else begin
      if (wvalid & wready) begin
         task_out_valid <= 1'b1;
      end else if (task_out_valid & task_out_ready) begin
         task_out_valid <= 1'b0;
      end
   end
end

logic [31:0] base_rw_addr;
always_comb begin 
   wvalid = 0;
   wdata = 'x;
   wstrb = 0;
   waddr = base_rw_addr + ( task_in.task_desc.locale << 2) ;
   wdata [ task_in.task_desc.locale[3:0]* 32 +: 32 ] = task_in.task_desc.ts;
   wstrb [ task_in.task_desc.locale[3:0]* 4 +: 4]  = '1;
   task_in_ready = 1'b0;
   if (task_in_valid) begin
      if (task_in.object > task_in.task_desc.ts) begin
         wvalid = !task_out_valid | task_out_ready;
         if (wvalid & wready) begin
            task_in_ready = 1'b1;
         end
         //waddr = task_in.cache_addr;
             
      end else begin
         task_in_ready = 1'b1;
      end
   end
end

assign unlock_locale = task_in_ready;
assign finish_task = task_in_ready;


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

endmodule
