import chronos::*;


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

   logic [7:0] reg_arlen;

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
                  reg_arlen <= pci.arlen;
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
   // esp, the case where debug read comes in the middle of a memory access
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
      pci_debug_arlen = reg_arlen;  
      pci_debug_rready = pci.rready;
   end

   assign self_debug.arvalid = (tile == N_TILES) & (debug_state == PCI_DEBUG_RECEIVED);
   assign self_debug.arlen = reg_arlen;
   assign self_debug.rready = pci.rready; 

generate
if (PCI_LOGGING) begin
   
   logic log_valid;
   typedef struct packed {

      logic [7:0] pci_awlen;
      logic [7:0] pci_arlen;
      logic [15:0] pci_awid;
      logic [15:0] pci_wid;
      logic [15:0] pci_bid;
      logic [15:0] pci_arid;
      logic [15:0] pci_rid;
      logic [31:0] pci_awaddr;
      logic [31:0] pci_araddr;

      // 16
      logic [3:0] pci_awsize;
      logic pci_wlast;
      logic pci_rlast;
      logic pci_awvalid;
      logic pci_awready;
      logic pci_wvalid;
      logic pci_wready;
      logic pci_arvalid;
      logic pci_arready;
      logic pci_rvalid;
      logic pci_rready;
      logic pci_bvalid;
      logic pci_bready;
      
      logic [15:0] ddr_arid;
      logic [15:0] ddr_awid;
      logic [15:0] ddr_wid;
      logic [15:0] ddr_rid;
      logic [15:0] ddr_bid;
      logic [31:0] ddr_awaddr;
      logic [31:0] ddr_araddr;
      logic [31:0] ddr_wdata_32;
      logic [31:0] ddr_rdata_32;

      // 64 
      logic [23:0] ddr_wstrb;
      logic [7:0] ddr_awlen;
      logic [3:0] ddr_awsize;
      logic [7:0] ddr_arlen;
      logic [3:0] ddr_arsize;

      // 16
      logic ddr_wlast;
      logic ddr_rlast;
      logic [1:0] ddr_rresp;
      logic [1:0] ddr_bresp;
      logic ddr_awvalid;
      logic ddr_awready;
      logic ddr_wvalid;
      logic ddr_wready;
      logic ddr_arvalid;
      logic ddr_arready;
      logic ddr_rvalid;
      logic ddr_rready;
      logic ddr_bvalid;
      logic ddr_bready;

   } pci_log_t;
   pci_log_t log_word;
always_comb begin
   log_word = 0;
      log_word.ddr_arid = ddr_snoop.arid;
      log_word.ddr_awid = ddr_snoop.awid;
      log_word.ddr_wid = ddr_snoop.wid;
      log_word.ddr_rid = ddr_snoop.rid;
      log_word.ddr_bid = ddr_snoop.bid;
      log_word.ddr_awaddr = ddr_snoop.awaddr;
      log_word.ddr_araddr = ddr_snoop.araddr;
      log_word.ddr_wdata_32 = ddr_snoop.wdata[31:0];
      log_word.ddr_rdata_32 = ddr_snoop.rdata[31:0];
      log_word.ddr_wstrb = ddr_snoop.wstrb;
      log_word.ddr_awlen = ddr_snoop.awlen;
      log_word.ddr_awsize = ddr_snoop.awsize;
      log_word.ddr_arlen = ddr_snoop.arlen;
      log_word.ddr_arsize = ddr_snoop.arsize;
      log_word.ddr_wlast = ddr_snoop.wlast;
      log_word.ddr_rlast = ddr_snoop.rlast;
      log_word.ddr_rresp = ddr_snoop.rresp;
      log_word.ddr_bresp = ddr_snoop.bresp;
      log_word.ddr_awvalid = ddr_snoop.awvalid;
      log_word.ddr_wvalid = ddr_snoop.wvalid;
      log_word.ddr_arvalid = ddr_snoop.arvalid;
      log_word.ddr_arready = ddr_snoop.arready;
      log_word.ddr_awready = ddr_snoop.awready;
      log_word.ddr_wready = ddr_snoop.wready;
      log_word.ddr_rvalid = ddr_snoop.rvalid;
      log_word.ddr_rready = ddr_snoop.rready;
      log_word.ddr_bvalid = ddr_snoop.bvalid;
      log_word.ddr_bready = ddr_snoop.bready;
      log_valid = (ddr_snoop.awvalid & ddr_snoop.awready) |
                  (ddr_snoop.wvalid &  ddr_snoop.wready) | 
                  (ddr_snoop.arvalid & ddr_snoop.arready) |
                  (ddr_snoop.rvalid & ddr_snoop.rready) |
                  (ddr_snoop.bvalid & ddr_snoop.bready) |
                  (mem.awvalid | mem.wvalid | mem.arvalid | mem.rvalid | mem.bvalid);

                  ;

      log_word.pci_arid = mem.arid;
      log_word.pci_awid = mem.awid;
      log_word.pci_wid = mem.wid;
      log_word.pci_rid = pci.rid;
      log_word.pci_bid = mem.bid;
      log_word.pci_awaddr = mem.awaddr;
      log_word.pci_araddr = mem.araddr;
      //log_word.pci_wstrb = mem.wstrb;
      log_word.pci_awlen = mem.awlen;
      log_word.pci_awsize = mem.awsize;
      log_word.pci_arlen = mem.arlen;
      //log_word.pci_arsize = mem.arsize;
      log_word.pci_wlast = mem.wlast;
      log_word.pci_rlast = mem.rlast;
      //log_word.pci_rresp = mem.rresp;
      //log_word.pci_bresp = mem.bresp;
      log_word.pci_awvalid = mem.awvalid;
      log_word.pci_wvalid = mem.wvalid;
      log_word.pci_arvalid = mem.arvalid;
      log_word.pci_arready = mem.arready;
      log_word.pci_awready = mem.awready;
      log_word.pci_wready = mem.wready;
      log_word.pci_rvalid = mem.rvalid;
      log_word.pci_rready = mem.rready;
      log_word.pci_bvalid = mem.bvalid;
      log_word.pci_bready = mem.bready;
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

