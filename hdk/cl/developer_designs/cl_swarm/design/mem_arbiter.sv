import swarm::*;


module mem_arbiter(
   input clk,
   input rstn,

   axi_bus_t.master l2,
   axi_bus_t.master pci,

   axi_bus_t.slave mem
);
   
   logic sel; 
   logic last_tx_l2; 
  // Hack until a proper AXI Xbar is implemented
   always_ff @(posedge clk) begin
      if (!rstn) begin
         last_tx_l2 <= 1'b0;
      end else begin
         if (l2.arvalid | l2.awvalid) begin
            last_tx_l2 <= 1;
         end else if (pci.awvalid | pci.arvalid) begin
            last_tx_l2 <= 0;
         end
      end
   end
  
   always_comb begin
      sel = last_tx_l2;
      if (l2.arvalid | l2.awvalid) begin
         sel = 1;
      end else if (pci.awvalid | pci.arvalid) begin
         sel = 0;
      end
   end

   assign l2.awready = mem.awready; 
   assign l2.arready = mem.arready; 
   assign l2.wready  = !sel ? 0: mem.wready;
   assign l2.bid     = !sel ? 0: mem.bid;
   assign l2.bresp   = !sel ? 0: mem.bresp;
   assign l2.bvalid  = !sel ? 0: mem.bvalid;
   assign l2.rid     = !sel ? 0: mem.rid;
   assign l2.rdata   = !sel ? 0: mem.rdata;
   assign l2.rresp   = !sel ? 0: mem.rresp;
   assign l2.rlast   = !sel ? 0: mem.rlast;
   assign l2.rvalid  = !sel ? 0: mem.rvalid;

   assign pci.awready = mem.awready;
   assign pci.arready = mem.arready;
   assign pci.wready  = sel ? 0: mem.wready;
   assign pci.bid     = sel ? 0: mem.bid;
   assign pci.bresp   = sel ? 0: mem.bresp;
   assign pci.bvalid  = sel ? 0: mem.bvalid;
   assign pci.rid     = sel ? 0: mem.rid;
   assign pci.rdata   = sel ? 0: mem.rdata;
   assign pci.rresp   = sel ? 0: mem.rresp;
   assign pci.rlast   = sel ? 0: mem.rlast;
   assign pci.rvalid  = sel ? 0: mem.rvalid;

   always_comb begin
      if (sel) begin
         mem.awid       = l2.awid;
         mem.awaddr     = l2.awaddr;
         mem.awlen      = l2.awlen;
         mem.awsize     = l2.awsize;
         mem.awvalid    = l2.awvalid;

         mem.arid       = l2.arid;
         mem.araddr     = l2.araddr;
         mem.arlen      = l2.arlen;
         mem.arsize     = l2.arsize;
         mem.arvalid    = l2.arvalid;
   
         mem.bready     = l2.bready;

         mem.wid        = l2.wid;
         mem.wdata      = l2.wdata;
         mem.wstrb      = l2.wstrb;
         mem.wlast      = l2.wlast;
         mem.wvalid     = l2.wvalid;

         mem.rready     = l2.rready;
      end else begin
         mem.awid       = pci.awid;
         mem.awaddr     = pci.awaddr;
         mem.awlen      = pci.awlen;
         mem.awsize     = pci.awsize;
         mem.awvalid    = pci.awvalid;

         mem.arid       = pci.arid;
         mem.araddr     = pci.araddr;
         mem.arlen      = pci.arlen;
         mem.arsize     = pci.arsize;
         mem.arvalid    = pci.arvalid;
   
         mem.bready     = pci.bready;

         mem.wid        = pci.wid;
         mem.wdata      = pci.wdata;
         mem.wstrb      = pci.wstrb;
         mem.wlast      = pci.wlast;
         mem.wvalid     = pci.wvalid;

         mem.rready     = pci.rready;
      end

   end



endmodule

