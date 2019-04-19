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
      logic [63:0] wstrb;
      logic [31:0] awaddr;
      logic [31:0] araddr;
      logic [31:0] arid;
      logic [31:0] awid;
      logic [31:0] wid;
      logic [31:0] wdata_32;
      logic [0:0] unused_1;
      logic wlast;
      logic [7:0] awlen;
      logic [3:0] awsize;
      logic [7:0] arlen;
      logic [3:0] arsize;
      logic awvalid;
      logic awready;
      logic wvalid;
      logic wready;
      logic arvalid;
      logic arready;

   } pci_log_t;
   pci_log_t log_word;
   assign log_word.wstrb = pci.wstrb;
   assign log_word.awaddr = pci.awaddr;
   assign log_word.araddr = pci.araddr;
   assign log_word.awid = pci.awid;
   assign log_word.arid = pci.arid;
   assign log_word.wid = pci.wid;
   assign log_word.wdata_32 = pci.wdata[31:0];
   assign log_word.awlen = pci.awlen;
   assign log_word.awsize = pci.awsize;
   assign log_word.arlen = pci.arlen;
   assign log_word.arsize = pci.arsize;
   assign log_word.wlast = pci.wlast;
   assign log_word.awvalid = pci.awvalid;
   assign log_word.wvalid = pci.wvalid;
   assign log_word.arvalid = pci.arvalid;
   assign log_word.arready = pci.arready;
   assign log_word.awready = pci.awready;
   assign log_word.wready = pci.wready;
   assign log_valid = pci.awvalid | pci.wvalid | pci.arvalid;

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

