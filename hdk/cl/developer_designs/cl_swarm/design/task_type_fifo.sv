import swarm::*;

module task_type_fifo #(
   parameter ID = 0  
)	(
	input clk,
	input rstn,

   // from tq
	input s_wvalid,
	output logic s_wready,
	input task_t s_wdata,
   input cq_slice_slot_t s_wslot,

   // to coflict checker
   output task_t s_rdata,
   output cq_slice_slot_t s_rslot,
   output logic s_rvalid, 
   input s_rresp, // 0- accept, 1 -reject
   input s_rresp_valid,

   output fifo_empty, // for termination checking 

   output ts_t lvt,
   
   reg_bus_t.master reg_bus
);
   localparam WIDTH = $bits(s_wdata) + $bits(s_wslot);
   // Per task type FIFO queue. 

   logic fifo_full;
   logic fifo_wr_en, fifo_rd_en;
   logic [WIDTH-1:0] fifo_rd_data, fifo_wr_data;

   logic [6:0] fifo_size;
   logic [6:0] full_threshold;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         full_threshold <= 2; 
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               DEQ_FIFO_FULL_THRESHOLD: full_threshold <= reg_bus.wdata;
            endcase
         end
      end 
   end
   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
      end
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
         case (reg_bus.araddr) 
            DEQ_FIFO_FULL_THRESHOLD : reg_bus.rdata <= full_threshold;
            DEQ_FIFO_SIZE : reg_bus.rdata <= fifo_size;
            DEQ_FIFO_NEXT_TASK_TS : reg_bus.rdata <= s_rdata.ts;
            DEQ_FIFO_NEXT_TASK_HINT : reg_bus.rdata <= s_rdata.hint;
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end  
   
   fifo #(
         .WIDTH(WIDTH),
         .LOG_DEPTH(6)
      ) TASK_FIFO (
         .clk(clk),
         .rstn(rstn),
         .wr_en(fifo_wr_en),
         .wr_data(fifo_wr_data),

         .full(),
         .empty(fifo_empty),

         .rd_en(fifo_rd_en),
         .rd_data(fifo_rd_data),

         .size(fifo_size) 
      );
   
   assign {s_rdata, s_rslot} = fifo_rd_data;
   assign s_rvalid = !fifo_empty;

   assign fifo_full = (fifo_size == full_threshold); 
 
   // hoist this out. leads to to simulator deadlock otherwise.
   assign s_wready = (s_rresp_valid & s_rresp) ? 1'b0 : !fifo_full;

   always_comb begin
      if (s_rresp_valid & s_rresp) begin
         // conflict check failed. Re-enqueue fifo head
         // In case the FIFO is full, it should handle correctly
         fifo_wr_en = 1'b1;
         fifo_wr_data = fifo_rd_data;
         fifo_rd_en = 1'b1;
      end else begin
         fifo_wr_en = s_wvalid & s_wready;
         fifo_wr_data = {s_wdata, s_wslot};
         fifo_rd_en = s_rresp_valid;
      end
   end

endmodule
