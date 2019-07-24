import swarm::*;


module pci_arbiter(
   input clk,
   input rstn,

   axi_bus_t.master pci,
   
   output logic [N_TILES-1:0] pci_debug_arvalid,
   output logic [7:0] pci_debug_arlen,
   output logic pci_debug_rready,
   input cache_line_t [N_TILES-1:0] pci_debug_rdata,
   input [N_TILES-1:0] pci_debug_rvalid,
   input [N_TILES-1:0] pci_debug_rlast,

   output logic [7:0] pci_debug_comp, 

   axi_bus_t.slave mem,

   axi_bus_t.snoop ddr_snoop,

   logic [15:0] pci_log_size
);

   logic [7:0] tile;

   typedef enum logic [1:0] { PCI_DEBUG_IDLE, PCI_DEBUG_RECEIVED, PCI_DEBUG_WAITING} pci_debug_state;

   pci_debug_state debug_state;
   // pci addr space: 0-64GB - DDR: 
   // 64-128 GB PCI_DEBUG with bits [35:28] denoting tile id, [27:20] comp id
   localparam DEBUG_ADDR_BIT = 36;

   pci_debug_bus_t self_debug();

   logic [15:0] rid;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         debug_state <= PCI_DEBUG_IDLE;
      end else begin 
         case (debug_state) 
            PCI_DEBUG_IDLE: begin
               if (pci.arvalid & pci.arready & pci.araddr[DEBUG_ADDR_BIT]) begin
                  debug_state <= PCI_DEBUG_RECEIVED;
                  rid <= pci.arid;
                  tile <= pci.araddr[35:28];
                  pci_debug_comp <= pci.araddr[27:20]; // component within the tile
               end
            end
            PCI_DEBUG_RECEIVED: begin
               debug_state <= PCI_DEBUG_WAITING;
            end
            PCI_DEBUG_WAITING: begin
               if (pci.rlast & pci.rvalid) begin
                  debug_state <= PCI_DEBUG_IDLE;
               end
            end

         endcase
      end
   end

   localparam LOG_DDR = 1; // if set, logs the transactions of the chosen DDR ctrl instead of the pci controller

   // NOTE: This may not work correctly multiple outstading PCI transactions.
   // esp, the case where debug read comes in the middle of a memory
   // transactions
   always_comb begin
      if (debug_state == PCI_DEBUG_IDLE) begin
            pci.awready =  mem.awready;
            pci.arready =  mem.arready;
            pci.wready  =  mem.wready;
            pci.bid     =  mem.bid;
            pci.bresp   =  mem.bresp;
            pci.bvalid  =  mem.bvalid;
            pci.rid     =  mem.rid;
            pci.rdata   =  mem.rdata;
            pci.rresp   =  mem.rresp;
            pci.rlast   =  mem.rlast;
            pci.rvalid  =  mem.rvalid;
         end else begin
            pci.awready =  0;
            pci.arready =  0;
            pci.wready  =  0; 
            pci.bid     =  0; 
            pci.bresp   =  0; 
            pci.bvalid  =  0; 
            pci.rid     =  rid;
            pci.rresp   =  0;
            if (tile < N_TILES) begin
               pci.rdata   =  pci_debug_rdata[tile];
               pci.rlast   =  pci_debug_rlast[tile];
               pci.rvalid  =  pci_debug_rvalid[tile];
            end else begin
               pci.rdata = self_debug.rdata;
               pci.rlast = self_debug.rlast;
               pci.rvalid = self_debug.rvalid;
            end
         end
   end

   
   always_comb begin
      mem.awid       = pci.awid;
      mem.awaddr     = pci.awaddr;
      mem.awlen      = pci.awlen;
      mem.awsize     = pci.awsize;

      mem.arid       = pci.arid;
      mem.araddr     = pci.araddr;
      mem.arlen      = pci.arlen;
      mem.arsize     = pci.arsize;

      mem.wid        = pci.wid;
      mem.wdata      = pci.wdata;
      mem.wstrb      = pci.wstrb;
      mem.wlast      = pci.wlast;

      if (debug_state != PCI_DEBUG_IDLE) begin    
         mem.awvalid    = 1'b0;
         mem.arvalid    = 1'b0;
         mem.bready     = 1'b0;
         mem.wvalid     = 1'b0;
         mem.rready     = 1'b0;
      end else begin
         mem.awvalid    = pci.awvalid;
         mem.arvalid    = pci.arvalid & !pci.araddr[DEBUG_ADDR_BIT];
         mem.bready     = pci.bready;
         mem.wvalid     = pci.wvalid;
         mem.rready     = pci.rready;
      end
   end

   always_comb begin 
      for (integer i=0;i<N_TILES;i++) begin
         pci_debug_arvalid[i] = (i==tile) & (debug_state == PCI_DEBUG_RECEIVED); 
      end
      pci_debug_arlen = pci.arlen;  
      pci_debug_rready = pci.rready;
   end

   assign self_debug.arvalid = (tile == N_TILES) & (debug_state == PCI_DEBUG_RECEIVED);
   assign self_debug.arlen = pci.arlen;
   assign self_debug.rready = pci.rready; 

generate
if (PCI_LOGGING) begin
   
   logic log_valid;
   typedef struct packed {
      
      logic [15:0] arid;
      logic [15:0] awid;
      logic [15:0] wid;
      logic [15:0] rid;
      logic [15:0] bid;
      logic [31:0] awaddr;
      logic [31:0] araddr;
      logic [31:0] wdata_32;
      logic [31:0] rdata_32;

      // 64 
      logic [23:0] wstrb;
      logic [7:0] awlen;
      logic [3:0] awsize;
      logic [7:0] arlen;
      logic [3:0] arsize;

      // 16
      logic wlast;
      logic rlast;
      logic [1:0] rresp;
      logic [1:0] bresp;
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

   } pci_log_t;
   pci_log_t log_word;
always_comb begin
   log_word = 0;
   if (LOG_DDR) begin
      log_word.arid = ddr_snoop.arid;
      log_word.awid = ddr_snoop.awid;
      log_word.wid = ddr_snoop.wid;
      log_word.rid = ddr_snoop.rid;
      log_word.bid = ddr_snoop.bid;
      log_word.awaddr = ddr_snoop.awaddr;
      log_word.araddr = ddr_snoop.araddr;
      log_word.wdata_32 = ddr_snoop.wdata[31:0];
      log_word.rdata_32 = ddr_snoop.rdata[31:0];
      log_word.wstrb = ddr_snoop.wstrb;
      log_word.awlen = ddr_snoop.awlen;
      log_word.awsize = ddr_snoop.awsize;
      log_word.arlen = ddr_snoop.arlen;
      log_word.arsize = ddr_snoop.arsize;
      log_word.wlast = ddr_snoop.wlast;
      log_word.rlast = ddr_snoop.rlast;
      log_word.rresp = ddr_snoop.rresp;
      log_word.bresp = ddr_snoop.bresp;
      log_word.awvalid = ddr_snoop.awvalid;
      log_word.wvalid = ddr_snoop.wvalid;
      log_word.arvalid = ddr_snoop.arvalid;
      log_word.arready = ddr_snoop.arready;
      log_word.awready = ddr_snoop.awready;
      log_word.wready = ddr_snoop.wready;
      log_word.rvalid = ddr_snoop.rvalid;
      log_word.rready = ddr_snoop.rready;
      log_word.bvalid = ddr_snoop.bvalid;
      log_word.bready = ddr_snoop.bready;
      assign log_valid = ddr_snoop.awvalid | ddr_snoop.wvalid | ddr_snoop.arvalid | ddr_snoop.rvalid | ddr_snoop.bvalid;
   end else begin
      log_word.arid = pci.arid;
      log_word.awid = pci.awid;
      log_word.wid = pci.wid;
      log_word.rid = pci.rid;
      log_word.bid = pci.bid;
      log_word.awaddr = pci.awaddr;
      log_word.araddr = pci.araddr;
      log_word.wdata_32 = pci.wdata[31:0];
      log_word.rdata_32 = pci.rdata[31:0];
      log_word.wstrb = pci.wstrb;
      log_word.awlen = pci.awlen;
      log_word.awsize = pci.awsize;
      log_word.arlen = pci.arlen;
      log_word.arsize = pci.arsize;
      log_word.wlast = pci.wlast;
      log_word.rlast = pci.rlast;
      log_word.rresp = pci.rresp;
      log_word.bresp = pci.bresp;
      log_word.awvalid = pci.awvalid;
      log_word.wvalid = pci.wvalid;
      log_word.arvalid = pci.arvalid;
      log_word.arready = pci.arready;
      log_word.awready = pci.awready;
      log_word.wready = pci.wready;
      log_word.rvalid = pci.rvalid;
      log_word.rready = pci.rready;
      log_word.bvalid = pci.bvalid;
      log_word.bready = pci.bready;
      assign log_valid = pci.awvalid | pci.wvalid | pci.arvalid | pci.rvalid | pci.bvalid;
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

      .pci(self_debug),

      .size(pci_log_size[LOG_LOG_DEPTH:0])

   );
   assign pci_log_size[15:LOG_LOG_DEPTH+1] = 0;
end else begin
   assign self_debug.rvalid = 1'b1;
   assign pci_log_size = 0;
end


endgenerate
endmodule

