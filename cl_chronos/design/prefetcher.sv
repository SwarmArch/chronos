
module prefetcher
(
   input clk,
   input rstn,
   
   input task_in_valid,
   task_t task_in,

   output logic prefetch_valid,
   output axi_addr_t prefetch_addr,

   input reg_bus_wvalid, 
   input [31:0] reg_bus_waddr, 
   input [31:0] reg_bus_wdata 
);

`ifdef USE_PIPELINED_TEMPLATE

   reg_bus_t reg_bus();
   assign reg_bus.wvalid = reg_bus_wvalid;
   assign reg_bus.waddr = reg_bus_waddr;
   assign reg_bus.wdata = reg_bus_wdata;
   assign reg_bus.arvalid = 1'b0;

   `RW_READER  RW_READER (
      .clk(clk),
      .rstn(rstn),
      .task_in(task_in),
      
      .araddr(prefetch_addr[31:0]),
      .reg_bus(reg_bus)
  );
  assign prefetch_addr[63:32] = 0;
  assign prefetch_valid = task_in_valid;

`else 
  assign prefetch_valid = task_in_valid;
  logic [31:0] base_rw_addr;
  logic [3:0] log_rw_width;
  assign prefetch_addr = base_rw_addr + (task_in.object << (log_rw_width) );

   always_ff @(posedge clk) begin
      if (!rstn) begin
         base_rw_addr <= 0;
         log_rw_width <= 2;
      end else begin
         if (reg_bus_wvalid) begin
            case (reg_bus_waddr) 
               PREFETCHER_BASE_ADDR : base_rw_addr <= {reg_bus_wdata[29:0], 2'b00};
               PREFETCHER_OBJECT_SIZE : log_rw_width <= reg_bus_wdata[3:0];
            endcase
         end
      end
   end
`endif

endmodule
