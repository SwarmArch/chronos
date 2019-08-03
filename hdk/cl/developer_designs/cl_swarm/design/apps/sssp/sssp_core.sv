
module sssp_rw
#(
   parameter TILE_ID=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input object_t          in_data,
   input cq_slice_slot_t   in_cq_slot,
   
   output logic            wvalid,
   output logic [31:0]     waddr,
   output data_t           wdata,

   output logic            out_valid,
   output task_t           out_task,

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   reg_bus_t               reg_bus

);

logic [31:0] base_rw_addr;
assign task_in_ready = sched_task_valid & sched_task_ready;
assign sched_task_valid = task_in_valid;
always_comb begin 
   wvalid = 0;
   wdata = 'x;
   waddr = base_rw_addr + ( in_task.locale << 2) ;
   wdata = in_task.ts;
   out_valid = 1'b0;

   out_task = in_task;

   if (task_in_valid) begin
      if (in_data > in_task.ts) begin
         wvalid = 1'b1;
         out_valid = 1'b1;
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

         
`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [write_rw] [%2d] ts:%8d locale:%4d type:%1x",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.locale, in_task.ttype) ;
      end
   end 
`endif


endmodule

module sssp_worker
#(
   parameter SUBTYPE=0,
   parameter TILE_ID=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input data_t            in_data,
   input byte_t            in_word_id,
   input cq_slice_slot_t   in_cq_slot,
   
   output cq_slice_slot_t   out_cq_slot,
   
   output logic            arvalid,
   output logic [31:0]     araddr,
   output logic [2:0]      arsize,
   output logic [7:0]      arlen,
   output task_t           resp_task, //each mem resp will create a new task with this parameters
   output subtype_t        resp_subtype,
   output logic            resp_mark_last, // mark the last resp task as last

   output logic            out_valid,
   output task_t           out_task,
   output subtype_t        out_subtype,

   output logic            out_task_is_child, // if 0, out_task is re-enqueued back to a FIFO, else sent to CM

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   output logic [31:0]     log_output,

   reg_bus_t               reg_bus

);

logic [31:0] offset_base_addr;
logic [31:0] neighbors_base_addr;

assign sched_task_valid = task_in_valid;
assign task_in_ready = sched_task_ready;

assign out_cq_slot = in_cq_slot;

assign resp_task = in_task;
always_comb begin
   araddr = 'x;
   arsize = 2;
   arlen = 0;
   arvalid = 1'b0;
   out_valid = 1'b0;
   resp_mark_last = 1'b0;
   out_task = in_task;
   out_task_is_child = 1'b1;
   resp_subtype = 'x;
   
   if (task_in_valid) begin
      case (SUBTYPE) 
         0: begin
            araddr = offset_base_addr + (in_task.locale <<  2);
            arsize = 3;
            arvalid = 1'b1;
            arlen = 0;
            resp_subtype = 1;
         end
         1: begin
            araddr = neighbors_base_addr + (in_data[31:0] <<  3);
            arvalid = (in_data[63:32] != in_data[31:0]);
            arsize = 3;
            arlen = (in_data[63:32] - in_data[31:0])-1;
            resp_subtype = 2;
            resp_mark_last = 1'b1;
         end
         2: begin
            out_valid = 1'b1;
            out_task.locale = in_data[31:0];
            out_task.ts = in_task.ts + in_data[63:32];
            out_task_is_child = 1'b1;
         end
      endcase

   end 
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      offset_base_addr <= 0;
      neighbors_base_addr <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr)
            OFFSET_BASE_ADDR : offset_base_addr <= (reg_bus.wdata << 2);
            NEIGHBOR_BASE_ADDR : neighbors_base_addr <= (reg_bus.wdata << 2);
         endcase
      end
   end
end

`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [ro %2d] [%3d] ts:%8d locale:%4d data:(%5d %5d)",
            cycle, TILE_ID, SUBTYPE, in_cq_slot,
            in_task.ts, in_task.locale, in_data[63:32], in_data[31:0] ) ;
      end
   end 
`endif


endmodule
