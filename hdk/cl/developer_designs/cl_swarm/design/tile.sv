import swarm::*;

module tile
#( 
   parameter TILE_ID = 0
) (


   input clk_main_a0,
   input rst_main_n_sync_p,

   axi_bus_t      .slave  mem_bus,

   axi_bus_t      .master ocl_bus,

   task_enq_req_t     .master task_enq_in,
   task_enq_req_t     .slave  task_enq_out,

   task_enq_resp_t    .master task_resp_in,
   task_enq_resp_t    .slave  task_resp_out,
   
   abort_child_req_t  .master abort_child_in,
   abort_child_req_t  .slave  abort_child_out,

   abort_child_resp_t .master abort_resp_in,
   abort_child_resp_t .slave  abort_resp_out,

   cut_ties_req_t     .master cut_ties_in,
   cut_ties_req_t     .slave  cut_ties_out,

   pci_debug_bus_t.master pci_debug_in,
   input [7:0]            pci_debug_comp,

   input vt_t     gvt,

   output vt_t    lvt

);

logic rst_main_n_sync;

   lib_pipe #(
      .WIDTH(1),
      .STAGES(3)
   ) RST_PIPE (
      .clk(clk_main_a0), 
      .rst_n(1'b1),
      
      .in_bus ( rst_main_n_sync_p ),
      .out_bus( rst_main_n_sync )
   ); 


logic  [CM_PORTS-1:0]     cores_cm_wvalid ;
logic  [CM_PORTS-1:0]     cores_cm_wready ;
task_t [CM_PORTS-1:0]     cores_cm_wdata  ;
logic  [CM_PORTS-1:0]     cores_cm_enq_untied ;
cq_slice_slot_t [CM_PORTS-1:0]     cores_cm_cq_slot  ;
child_id_t [CM_PORTS-1:0]     cores_cm_child_id  ;


logic finish_task_valid ;
logic finish_task_ready ;
cq_slice_slot_t finish_task_slot  ;
child_id_t      finish_task_num_children ;
logic finish_task_is_undo_log_restore;

logic                   gvt_task_slot_valid;
cq_slice_slot_t         gvt_task_slot;

logic [N_THREADS-1:0]     undo_log_valid ;
logic [N_THREADS-1:0]     undo_log_ready ;
undo_id_t       [N_THREADS-1:0] undo_log_id;
undo_log_addr_t [N_THREADS-1:0] undo_log_addr;
undo_log_data_t [N_THREADS-1:0] undo_log_data;
cq_slice_slot_t [N_THREADS-1:0] undo_log_slot  ;

logic coal_child_valid;
logic coal_child_ready;
task_t coal_child_task;

logic overflow_valid;
logic overflow_ready;
task_t overflow_task;

logic splitter_deq_valid;
logic splitter_deq_ready;
task_t splitter_deq_task;

cq_slice_slot_t cq_fifo_slot;

logic             tsb_almost_full;

// per task FIFOs to conflict checker
logic fifo_cc_valid;
task_t fifo_cc_data;
cq_slice_slot_t fifo_cc_slot;
logic fifo_cc_ready;



axi_bus_t coal_l1();
axi_bus_t splitter_l1();
axi_bus_t l1_arb[L2_PORTS](); // +Coal,  undo_log (TODO TQ prefetch)

reg_bus_t reg_bus[ID_LAST]();
logic [15:0] reg_bus_waddr;
logic [31:0] reg_bus_wdata;
logic [ID_LAST-1:0] reg_bus_wvalid;

logic [15:0] reg_bus_araddr;
logic [ID_LAST-1:0] reg_bus_arvalid;
logic [ID_LAST-1:0] reg_bus_rvalid;
reg_data_t [ID_LAST-1:0] reg_bus_rdata;

pci_debug_bus_t pci_debug[ID_LAST]();

logic coal_stack_lock;
logic splitter_stack_lock;
ts_t  splitter_lvt_out;

logic [63:0] cur_cycle;

genvar i;

// Decode reg_bus from OCL slave to send out to individual modules
generate;
   for (i=0;i<ID_LAST;i=i+1) begin
      assign reg_bus[i].araddr = reg_bus_araddr;
      assign reg_bus[i].arvalid = reg_bus_arvalid[i];
      assign reg_bus_rvalid[i] = reg_bus[i].rvalid;
      assign reg_bus_rdata[i] = reg_bus[i].rdata;

      assign reg_bus[i].waddr = reg_bus_waddr;
      assign reg_bus[i].wdata = reg_bus_wdata;
      assign reg_bus[i].wvalid = reg_bus_wvalid[i];
   end
endgenerate

cache_line_t [ID_LAST-1:0] pci_debug_rdata;
logic        [ID_LAST-1:0] pci_debug_rvalid;
logic        [ID_LAST-1:0] pci_debug_rlast;
logic pci_debug_rready;
// pipe stage. otherwise sh_pcis_rready is in the critical path
assign pci_debug_rready = !pci_debug_in.rvalid;
generate;   
   for (i=0;i<ID_LAST;i++) begin
      always_ff @(posedge clk_main_a0) begin
         pci_debug[i].arvalid <= (i==pci_debug_comp) ? pci_debug_in.arvalid : 0; 
         pci_debug[i].arlen <= pci_debug_in.arlen;  
      end
      
      assign pci_debug[i].rready = pci_debug_rready;

      assign pci_debug_rvalid[i] = pci_debug[i].rvalid;
      assign pci_debug_rlast [i] = pci_debug[i].rlast;
      assign pci_debug_rdata [i] = pci_debug[i].rdata;
   end
endgenerate
always_ff @(posedge clk_main_a0) begin
   if (pci_debug_comp < ID_LAST) begin
      if (pci_debug_rvalid[pci_debug_comp] & pci_debug_rready) begin 
         pci_debug_in.rdata   <=  pci_debug_rdata [pci_debug_comp]; 
         pci_debug_in.rlast   <=  pci_debug_rlast [pci_debug_comp];
         pci_debug_in.rvalid  <=  pci_debug_rvalid[pci_debug_comp];
      end else if (pci_debug_in.rvalid & pci_debug_in.rready) begin
         pci_debug_in.rvalid <= 0;
      end
   end else begin
      pci_debug_in.rvalid  <=  0;
   end
end


axi_bus_t arb_l2_p[L2_BANKS]();
axi_bus_t arb_l2[L2_BANKS]();
axi_bus_t rw_l2();
cache_addr_t  rw_l2_rindex;
axi_bus_t l2_out[2]();
axi_bus_t l2_out_d[2]();
axi_bus_t ocl_bus_q();
   
   axi_pipe 
   #(
      .STAGES(2)
   ) OCL_PIPE (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),

      .in(ocl_bus),
      .out(ocl_bus_q)
   );

axi_bus_t core_l1();
logic [31:0] done;
ocl_slave  
#(
   .TILE_ID(TILE_ID)
) OCL_SLAVE (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

  .ocl(ocl_bus_q),
   
  .reg_bus_waddr    (reg_bus_waddr),
  .reg_bus_wdata    (reg_bus_wdata),
  .reg_bus_wvalid   (reg_bus_wvalid),

  .reg_bus_araddr (reg_bus_araddr),
  .reg_bus_arvalid(reg_bus_arvalid),
  .reg_bus_rvalid (reg_bus_rvalid),
  .reg_bus_rdata  (reg_bus_rdata),

  .task_arvalid(  ),
  .task_araddr (  ),
  .task_rvalid ( 1'b0 ),
  .task_rdata  (      ),

  .task_wvalid(cores_cm_wvalid[0]),
  .task_wdata (cores_cm_wdata [0]),
  .task_wready(cores_cm_wready[0]),

  .l1(core_l1),
   
  .done(done),
  .cur_cycle(cur_cycle)

);
assign core_l1.arready = 1'b1;
assign core_l1.awready = 1'b1;
assign core_l1.wready = 1'b1;

assign cores_cm_cq_slot[0] = 0;
assign cores_cm_child_id[0] = 0;
assign cores_cm_enq_untied[0] = 1'b1;
assign cores_cm_enq_untied[2] = 1'b1;


generate
if (!NO_SPILLING) begin
coalescer 
#(
   .TILE_ID(TILE_ID),
   .CORE_ID(ID_COAL)
) COALESCER (

  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

  .l1(coal_l1),
  .reg_bus(reg_bus[ID_COAL]),
   
   .coal_child_valid(coal_child_valid),
   .coal_child_ready(coal_child_ready),
   .coal_child_task(coal_child_task),

   .overflow_valid(overflow_valid),
   .overflow_ready(overflow_ready),
   .overflow_task(overflow_task),

  .stack_lock_out(coal_stack_lock),
  .stack_lock_in (splitter_stack_lock)
);
axi_decoder #(
   .ID_BASE( L2_ID_COAL << 8 ),
   .MAX_ARSIZE(2),
   .MAX_AWSIZE( $clog2(TQ_WIDTH) -3 )
) COAL_L1 (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .core(coal_l1),
   .l2(l1_arb[L2_ID_COAL])
);


splitter #(
  .TILE_ID(TILE_ID),
  .CORE_ID(ID_SPLITTER)
) SPLITTER (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

  .reg_bus(reg_bus[ID_SPLITTER]),
   
  .splitter_valid(splitter_deq_valid),
  .splitter_ready(splitter_deq_ready),
  .splitter_task (splitter_deq_task ),

  .task_wvalid(cores_cm_wvalid[2]),
  .task_wdata (cores_cm_wdata [2]),
  .task_wready(cores_cm_wready[2]),

  .l1(splitter_l1),
  .stack_lock_in (coal_stack_lock),
  .stack_lock_out(splitter_stack_lock),
  
  .pci_debug(pci_debug[ID_SPLITTER]),
  .lvt (splitter_lvt_out)
);

axi_decoder #(
   .ID_BASE( L2_ID_SPLITTER << 8 ),
   .MAX_ARSIZE( $clog2(TQ_WIDTH) -3),
   .MAX_AWSIZE(2)
) SPLITTER_L1 (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .core(splitter_l1),
   .l2(l1_arb[L2_ID_SPLITTER])
);
end else begin
   assign overflow_ready = 1'b0;
   assign coal_child_valid = 1'b0;
   assign l1_arb[L2_ID_COAL].awvalid = 1'b0;
   assign l1_arb[L2_ID_COAL].arvalid = 1'b0;
   assign l1_arb[L2_ID_COAL].wvalid = 1'b0;
   assign l1_arb[L2_ID_COAL].bready = 1'b1;
   assign l1_arb[L2_ID_COAL].rready = 1'b1;
   assign reg_bus[ID_COAL].rvalid = 1'b1;
   
   assign l1_arb[L2_ID_SPLITTER].awvalid = 1'b0;
   assign l1_arb[L2_ID_SPLITTER].arvalid = 1'b0;
   assign l1_arb[L2_ID_SPLITTER].wvalid = 1'b0;
   assign l1_arb[L2_ID_SPLITTER].bready = 1'b1;
   assign l1_arb[L2_ID_SPLITTER].rready = 1'b1;
   assign reg_bus[ID_SPLITTER].rvalid = 1'b1;
   
   assign cores_cm_wvalid[2] = 1'b0; // so as not to confuse the tsb
   assign splitter_deq_ready = 1'b0;

   assign splitter_lvt_out = '1;
   
end

endgenerate

   
   l2 
   #(
      .TILE_ID(TILE_ID),
      .BANK_ID(0)
   ) L2_RW (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),

      .l1(rw_l2),
      .rindex(rw_l2_rindex),
      .mem_bus(l2_out[0]),

      .reg_bus(reg_bus[ID_L2_RW]),

      .pci_debug(pci_debug[ID_L2_RW])
   );

   // input to l2_arbiter
   axi_id_t    [L2_PORTS-1:0] l2_arb_in_awid;
   axi_addr_t  [L2_PORTS-1:0] l2_arb_in_awaddr;
   axi_len_t   [L2_PORTS-1:0] l2_arb_in_awlen;
   axi_size_t  [L2_PORTS-1:0] l2_arb_in_awsize;
   logic       [L2_PORTS-1:0] l2_arb_in_awvalid;
   logic       [L2_PORTS-1:0] l2_arb_in_awready;
   
   axi_id_t    [L2_PORTS-1:0] l2_arb_in_wid;
   axi_data_t  [L2_PORTS-1:0] l2_arb_in_wdata;
   axi_strb_t  [L2_PORTS-1:0] l2_arb_in_wstrb;
   logic       [L2_PORTS-1:0] l2_arb_in_wlast;
   logic       [L2_PORTS-1:0] l2_arb_in_wvalid;
   logic       [L2_PORTS-1:0] l2_arb_in_wready;

   axi_id_t    [L2_PORTS-1:0] l2_arb_in_bid;
   axi_resp_t  [L2_PORTS-1:0] l2_arb_in_bresp;
   logic       [L2_PORTS-1:0] l2_arb_in_bvalid;
   logic       [L2_PORTS-1:0] l2_arb_in_bready;

   axi_id_t    [L2_PORTS-1:0] l2_arb_in_arid;
   axi_addr_t  [L2_PORTS-1:0] l2_arb_in_araddr;
   axi_len_t   [L2_PORTS-1:0] l2_arb_in_arlen;
   axi_size_t  [L2_PORTS-1:0] l2_arb_in_arsize;
   logic       [L2_PORTS-1:0] l2_arb_in_arvalid;
   logic       [L2_PORTS-1:0] l2_arb_in_arready;

   axi_id_t    [L2_PORTS-1:0] l2_arb_in_rid;
   axi_data_t  [L2_PORTS-1:0] l2_arb_in_rdata;
   axi_resp_t  [L2_PORTS-1:0] l2_arb_in_rresp;
   logic       [L2_PORTS-1:0] l2_arb_in_rlast;
   logic       [L2_PORTS-1:0] l2_arb_in_rvalid;
   logic       [L2_PORTS-1:0] l2_arb_in_rready;
   // output from l2 arbiter
   axi_id_t    [L2_BANKS-1:0] l2_arb_out_awid;
   axi_addr_t  [L2_BANKS-1:0] l2_arb_out_awaddr;
   axi_len_t   [L2_BANKS-1:0] l2_arb_out_awlen;
   axi_size_t  [L2_BANKS-1:0] l2_arb_out_awsize;
   logic       [L2_BANKS-1:0] l2_arb_out_awvalid;
   logic       [L2_BANKS-1:0] l2_arb_out_awready;
   
   axi_id_t    [L2_BANKS-1:0] l2_arb_out_wid;
   axi_data_t  [L2_BANKS-1:0] l2_arb_out_wdata;
   axi_strb_t  [L2_BANKS-1:0] l2_arb_out_wstrb;
   logic       [L2_BANKS-1:0] l2_arb_out_wlast;
   logic       [L2_BANKS-1:0] l2_arb_out_wvalid;
   logic       [L2_BANKS-1:0] l2_arb_out_wready;

   axi_id_t    [L2_BANKS-1:0] l2_arb_out_bid;
   axi_resp_t  [L2_BANKS-1:0] l2_arb_out_bresp;
   logic       [L2_BANKS-1:0] l2_arb_out_bvalid;
   logic       [L2_BANKS-1:0] l2_arb_out_bready;

   axi_id_t    [L2_BANKS-1:0] l2_arb_out_arid;
   axi_addr_t  [L2_BANKS-1:0] l2_arb_out_araddr;
   axi_len_t   [L2_BANKS-1:0] l2_arb_out_arlen;
   axi_size_t  [L2_BANKS-1:0] l2_arb_out_arsize;
   logic       [L2_BANKS-1:0] l2_arb_out_arvalid;
   logic       [L2_BANKS-1:0] l2_arb_out_arready;

   axi_id_t    [L2_BANKS-1:0] l2_arb_out_rid;
   axi_data_t  [L2_BANKS-1:0] l2_arb_out_rdata;
   axi_resp_t  [L2_BANKS-1:0] l2_arb_out_rresp;
   logic       [L2_BANKS-1:0] l2_arb_out_rlast;
   logic       [L2_BANKS-1:0] l2_arb_out_rvalid;
   logic       [L2_BANKS-1:0] l2_arb_out_rready;

generate;
   for (i=0;i<L2_PORTS;i=i+1) begin
      assign l2_arb_in_awid    [i] = l1_arb[i].awid;
      assign l2_arb_in_awaddr  [i] = l1_arb[i].awaddr;
      assign l2_arb_in_awsize  [i] = l1_arb[i].awsize;
      assign l2_arb_in_awlen   [i] = l1_arb[i].awlen;
      assign l2_arb_in_awvalid [i] = l1_arb[i].awvalid;
      assign l1_arb[i].awready = l2_arb_in_awready [i];

      assign l2_arb_in_wid     [i] = l1_arb[i].wid;
      assign l2_arb_in_wdata   [i] = l1_arb[i].wdata;
      assign l2_arb_in_wlast   [i] = l1_arb[i].wlast;
      assign l2_arb_in_wstrb   [i] = l1_arb[i].wstrb;
      assign l2_arb_in_wvalid  [i] = l1_arb[i].wvalid;
      assign l1_arb[i].wready  = l2_arb_in_wready [i];

      assign l1_arb[i].bid    = l2_arb_in_bid    [i];
      assign l1_arb[i].bresp  = l2_arb_in_bresp  [i];
      assign l1_arb[i].bvalid = l2_arb_in_bvalid [i];
      assign l2_arb_in_bready  [i] = l1_arb[i].bready;
      
      assign l2_arb_in_arid    [i] = l1_arb[i].arid;
      assign l2_arb_in_araddr  [i] = l1_arb[i].araddr;
      assign l2_arb_in_arsize  [i] = l1_arb[i].arsize;
      assign l2_arb_in_arlen   [i] = l1_arb[i].arlen;
      assign l2_arb_in_arvalid [i] = l1_arb[i].arvalid;
      assign l1_arb[i].arready = l2_arb_in_arready [i];

      assign l1_arb[i].rid     = l2_arb_in_rid    [i];
      assign l1_arb[i].rresp   = l2_arb_in_rresp  [i];
      assign l1_arb[i].rvalid  = l2_arb_in_rvalid [i];
      assign l1_arb[i].rdata   = l2_arb_in_rdata  [i];
      assign l1_arb[i].rlast   = l2_arb_in_rlast  [i];
      assign l2_arb_in_rready  [i] = l1_arb[i].rready;
   end
   for (i=0;i<L2_BANKS;i=i+1) begin
      assign arb_l2_p[i].awid     = l2_arb_out_awid    [i];
      assign arb_l2_p[i].awaddr   = l2_arb_out_awaddr  [i];
      assign arb_l2_p[i].awsize   = l2_arb_out_awsize  [i];
      assign arb_l2_p[i].awlen    = l2_arb_out_awlen   [i];
      assign arb_l2_p[i].awvalid  = l2_arb_out_awvalid [i];
      assign l2_arb_out_awready[i] = arb_l2_p[i].awready ;

      assign arb_l2_p[i].wid      = l2_arb_out_wid  [i];
      assign arb_l2_p[i].wdata    = l2_arb_out_wdata[i];
      assign arb_l2_p[i].wlast    = l2_arb_out_wlast[i];
      assign arb_l2_p[i].wstrb    = l2_arb_out_wstrb[i];
      assign arb_l2_p[i].wvalid   = l2_arb_out_wvalid[i];
      assign l2_arb_out_wready[i]  = arb_l2_p[i].wready; 

      assign l2_arb_out_bid   [i] = arb_l2_p[i].bid    ;
      assign l2_arb_out_bresp [i] = arb_l2_p[i].bresp  ;
      assign l2_arb_out_bvalid[i] = arb_l2_p[i].bvalid ;
      assign arb_l2_p[i].bready  = l2_arb_out_bready[i];
      
      assign arb_l2_p[i].arid     = l2_arb_out_arid    [i];
      assign arb_l2_p[i].araddr   = l2_arb_out_araddr  [i];
      assign arb_l2_p[i].arsize   = l2_arb_out_arsize  [i];
      assign arb_l2_p[i].arlen    = l2_arb_out_arlen   [i];
      assign arb_l2_p[i].arvalid  = l2_arb_out_arvalid [i];
      assign l2_arb_out_arready [i] = arb_l2_p[i].arready ;

      assign l2_arb_out_rid   [i]  = arb_l2_p[i].rid    ;
      assign l2_arb_out_rresp [i]  = arb_l2_p[i].rresp  ;
      assign l2_arb_out_rvalid[i]  = arb_l2_p[i].rvalid ;
      assign l2_arb_out_rdata [i]  = arb_l2_p[i].rdata  ;
      assign l2_arb_out_rlast [i]  = arb_l2_p[i].rlast  ;
      assign arb_l2_p[i].rready  = l2_arb_out_rready[i];
   end
endgenerate




l2_arbiter 
#(
   .NUM_SI(L2_PORTS),
   .NUM_MI(1<<LOG_L2_BANKS)
) L2_ARBITER (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),
   
   .s_awid        (  l2_arb_in_awid      ),  
   .s_awaddr      (  l2_arb_in_awaddr    ),
   .s_awlen       (  l2_arb_in_awlen     ),
   .s_awsize      (  l2_arb_in_awsize    ),
   .s_awvalid     (  l2_arb_in_awvalid   ),
   .s_awready     (  l2_arb_in_awready   ),
   
   .s_wid         (  l2_arb_in_wid       ),
   .s_wdata       (  l2_arb_in_wdata     ),
   .s_wstrb       (  l2_arb_in_wstrb     ),
   .s_wlast       (  l2_arb_in_wlast     ),   
   .s_wvalid      (  l2_arb_in_wvalid    ),
   .s_wready      (  l2_arb_in_wready    ),
   
   .s_bid         (  l2_arb_in_bid       ),
   .s_bresp       (  l2_arb_in_bresp     ),
   .s_bvalid      (  l2_arb_in_bvalid    ),
   .s_bready      (  l2_arb_in_bready    ),
                        
   .s_arid        (  l2_arb_in_arid      ),
   .s_araddr      (  l2_arb_in_araddr    ),   
   .s_arlen       (  l2_arb_in_arlen     ),
   .s_arsize      (  l2_arb_in_arsize    ),
   .s_arvalid     (  l2_arb_in_arvalid   ),
   .s_arready     (  l2_arb_in_arready   ),
                        
   .s_rid         (  l2_arb_in_rid       ),
   .s_rdata       (  l2_arb_in_rdata     ),
   .s_rresp       (  l2_arb_in_rresp     ),
   .s_rlast       (  l2_arb_in_rlast     ),
   .s_rvalid      (  l2_arb_in_rvalid    ),   
   .s_rready      (  l2_arb_in_rready    ),      

  
   .m_awid        (  l2_arb_out_awid      ),  
   .m_awaddr      (  l2_arb_out_awaddr    ),
   .m_awlen       (  l2_arb_out_awlen     ),
   .m_awsize      (  l2_arb_out_awsize    ),
   .m_awvalid     (  l2_arb_out_awvalid   ),
   .m_awready     (  l2_arb_out_awready   ),
   
   .m_wid         (  l2_arb_out_wid       ),
   .m_wdata       (  l2_arb_out_wdata     ),
   .m_wstrb       (  l2_arb_out_wstrb     ),
   .m_wlast       (  l2_arb_out_wlast     ),   
   .m_wvalid      (  l2_arb_out_wvalid    ),
   .m_wready      (  l2_arb_out_wready    ),
                            
   .m_bid         (  l2_arb_out_bid       ),
   .m_bresp       (  l2_arb_out_bresp     ),
   .m_bvalid      (  l2_arb_out_bvalid    ),
   .m_bready      (  l2_arb_out_bready    ),
                             
   .m_arid        (  l2_arb_out_arid      ),
   .m_araddr      (  l2_arb_out_araddr    ),   
   .m_arlen       (  l2_arb_out_arlen     ),
   .m_arsize      (  l2_arb_out_arsize    ),
   .m_arvalid     (  l2_arb_out_arvalid   ),
   .m_arready     (  l2_arb_out_arready   ),
                            
   .m_rid         (  l2_arb_out_rid       ),
   .m_rdata       (  l2_arb_out_rdata     ),
   .m_rresp       (  l2_arb_out_rresp     ),
   .m_rlast       (  l2_arb_out_rlast     ),
   .m_rvalid      (  l2_arb_out_rvalid    ),   
   .m_rready      (  l2_arb_out_rready    )      
);



axi_pipe 
#(
   .STAGES(1),
   .NO_RESP(1)
) L2_PIPE (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .in(arb_l2_p[0]),
   .out(arb_l2[0])
);

l2 
#(
   .TILE_ID(TILE_ID),
   .BANK_ID(1)
) L2_RO (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .l1(arb_l2[0]),
   .rindex(),
   .mem_bus(l2_out[1]),

   .reg_bus(reg_bus[ID_L2_RO]),

   .pci_debug(pci_debug[ID_L2_RO])
);


  
// can't connect l2_out to the mux directly because of l2's valid signals
// depend on the ready's
axi_pipe 
#(
   .STAGES(1),
   .NO_RESP(1)
) L2_OUT_PIPE_0 (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .in(l2_out[0]),
   .out(l2_out_d[0])
);
axi_pipe 
#(
   .STAGES(1),
   .NO_RESP(1)
) L2_OUT_PIPE_1 (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .in(l2_out[1]),
   .out(l2_out_d[1])
);

axi_mux
#( 
   .ID_BIT(8),
   .DELAY(1)
) L2_OUT_MUX (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),
   .a(l2_out_d[0]),
   .b(l2_out_d[1]),

   .out_q(mem_bus)
);


logic tq_empty;
logic tsb_empty;
logic all_cores_idle;
   
ts_t lvt_tq_out; // 2 cycle delay
vt_t lvt_tq_fixed;
ts_t lvt_tq_rolling; 
vt_t lvt_cq_out; // (LOG_CQ_TS_BANKS+1) cycle delay
ts_t lvt_cm_out; // 0 cycle delay
vt_t lvt_cm_fixed;
ts_t lvt_cm_rolling; // 0 cycle delay
vt_t lvt_tsb_out; // (LOG_TSB_SIZE) cycle delay
vt_t lvt_splitter_fixed; 
ts_t lvt_splitter_rolling; 

vt_t lvt_tq_cq, lvt_cm_tsb;
vt_t lvt_tq_cq_cm_tsb;
tb_t cur_tb; // The LVT is associated with this cycle. 
//(i.e as of this cycle, the largest task existing in the tile cannot exceed {lvt.ts, cur_tb}
assign cur_tb[TB_WIDTH-1: LOG_GVT_PERIOD] = cur_cycle[TB_WIDTH-1:LOG_GVT_PERIOD] -1;
assign cur_tb[LOG_GVT_PERIOD-1:0] = 0;
assign lvt_tq_fixed.tb =  cur_tb;
assign lvt_cm_fixed.tb =  cur_tb; 
assign lvt_splitter_fixed.tb =  cur_tb; 
assign lvt_tsb_out.tb =  cur_tb; 


always_ff @(posedge clk_main_a0) begin
   if (!rst_main_n_sync) begin
      lvt_tq_fixed.ts <= 0;
      lvt_tq_rolling <= 0;

      lvt_cm_fixed.ts <= 0;
      lvt_cm_rolling <= 0;

      lvt_tq_cq <= 0;
      lvt_cm_tsb <= 0;
      lvt_tq_cq_cm_tsb <= 0;

      lvt_splitter_fixed.ts <= 0;
      lvt_splitter_rolling <= 0;

      lvt <= 0;
   end else begin 
      if (cur_cycle[LOG_GVT_PERIOD-1:0] == 2) begin
         lvt_tq_fixed.ts <= lvt_tq_rolling;
         lvt_tq_rolling <= lvt_tq_out;
      end else begin
         if (lvt_tq_out < lvt_tq_rolling) begin
            lvt_tq_rolling <= lvt_tq_out;
         end
      end
      
      if (cur_cycle[LOG_GVT_PERIOD-1:0] == 0) begin
         lvt_cm_fixed.ts <= lvt_cm_rolling;
         lvt_cm_rolling <= lvt_cm_out;
      end else begin
         if (lvt_cm_out < lvt_cm_rolling) begin
            lvt_cm_rolling <= lvt_cm_out;
         end
      end
      
      if (cur_cycle[LOG_GVT_PERIOD-1:0] == 0) begin
         lvt_splitter_fixed.ts <= lvt_splitter_rolling;
         lvt_splitter_rolling <= splitter_lvt_out;
      end else begin
         if (splitter_lvt_out < lvt_splitter_rolling) begin
            lvt_splitter_rolling <= splitter_lvt_out;
         end
      end
      
      if (cur_cycle[LOG_GVT_PERIOD-1:0] == 8) begin
         lvt_tq_cq <= (lvt_tq_fixed < lvt_cq_out) ? lvt_tq_fixed : lvt_cq_out;
         lvt_cm_tsb <= (lvt_cm_fixed < lvt_tsb_out) ? lvt_cm_fixed : lvt_tsb_out;
      end
      if (cur_cycle[LOG_GVT_PERIOD-1:0] == 9) begin
         lvt_tq_cq_cm_tsb <= (lvt_tq_cq < lvt_cm_tsb) ? lvt_tq_cq : lvt_cm_tsb;
      end
      if (cur_cycle[LOG_GVT_PERIOD-1:0] == 10) begin
         lvt <= (lvt_tq_cq_cm_tsb < lvt_splitter_fixed) ? lvt_tq_cq_cm_tsb : lvt_splitter_fixed;
      end
      
   end

end


   
logic               task_deq_valid;
logic               task_deq_ready;
cq_slice_slot_t     task_deq_cq_slot;
task_t              task_deq_data;
epoch_t             task_deq_epoch;
tq_slot_t           task_deq_tq_slot;

logic               task_deq_force;
ts_t                cq_max_vt_ts;

logic               cq_child_abort_ready;
logic               cq_child_abort_valid;
cq_slice_slot_t     cq_child_abort_slot;

logic               abort_task_valid;
logic               abort_task_ready;
tq_slot_t           abort_task_slot;
epoch_t             abort_task_epoch;
ts_t                abort_task_ts;

logic               tq_commit_task_valid;
logic               tq_commit_task_ready;
tq_slot_t           tq_commit_task_slot;
epoch_t             tq_commit_task_epoch;

`TASK_UNIT_MODULE  
#(
   .TILE_ID(TILE_ID)
) TASK_UNIT (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),
   
   // Task Enq Reqest
   .task_enq_valid        (task_enq_in.valid       ),
   .task_enq_ready        (task_enq_in.ready       ),
   .task_enq_data         (task_enq_in.task_data   ),
   .task_enq_tied         (task_enq_in.task_tied   ),
   .task_enq_resp_tsb_id  (task_enq_in.resp_tsb_id ),
   .task_enq_resp_tile    (task_enq_in.resp_tile   ),

   // Task Enq Response

   .task_resp_valid       (task_resp_out.valid     ),
   .task_resp_ready       (task_resp_out.ready     ),
   .task_resp_dest_tile   (task_resp_out.dest_tile ),
   .task_resp_tsb_id      (task_resp_out.tsb_id    ),
   .task_resp_ack         (task_resp_out.task_ack  ),
   .task_resp_epoch       (task_resp_out.task_epoch),  
   .task_resp_tq_slot     (task_resp_out.tq_slot   ),

   .abort_child_valid         (abort_child_in.valid         ),
   .abort_child_ready         (abort_child_in.ready         ),
   .abort_child_tq_slot       (abort_child_in.tq_slot       ),
   .abort_child_epoch         (abort_child_in.child_epoch   ),
   .abort_child_resp_tile     (abort_child_in.resp_tile     ),
   .abort_child_resp_cq_slot  (abort_child_in.resp_cq_slot  ),
   .abort_child_resp_child_id (abort_child_in.resp_child_id ),

   // Abort Child Response

   .abort_resp_valid          (abort_resp_out.valid         ),
   .abort_resp_ready          (abort_resp_out.ready         ),
   .abort_resp_tile           (abort_resp_out.dest_tile     ),
   .abort_resp_cq_slot        (abort_resp_out.cq_slot       ),
   .abort_resp_child_id       (abort_resp_out.child_id      ),

   // Cut Ties

   .cut_ties_valid            (cut_ties_in.valid            ),
   .cut_ties_ready            (cut_ties_in.ready            ),
   .cut_ties_tq_slot          (cut_ties_in.tq_slot          ),
   .cut_ties_epoch            (cut_ties_in.child_epoch      ),

   // CQ interface
  
   .task_deq_valid            (task_deq_valid               ),
   .task_deq_ready            (task_deq_ready               ),
   .task_deq_cq_slot          (task_deq_cq_slot             ),
   .task_deq_data             (task_deq_data                ),
   .task_deq_epoch            (task_deq_epoch               ),
   .task_deq_tq_slot          (task_deq_tq_slot             ),   

   .task_deq_force            (task_deq_force             ),   

   // Inform the CQ of a child abort if task has been already dequeued,
   .cq_child_abort_ready      (cq_child_abort_ready         ),
   .cq_child_abort_valid      (cq_child_abort_valid         ),
   .cq_child_abort_slot       (cq_child_abort_slot          ),
   
   // Abort task messages from Commit Queue
   // These are a result of dependence violations/resource aborts
   // Requeue necessary
   .abort_task_valid          (abort_task_valid             ),
   .abort_task_ready          (abort_task_ready             ),
   .abort_task_slot           (abort_task_slot              ),
   .abort_task_epoch          (abort_task_epoch             ),
   .abort_task_ts             (abort_task_ts                ),

   // commit task messages from CQ
   .commit_task_valid         (tq_commit_task_valid            ),
   .commit_task_ready         (tq_commit_task_ready            ),
   .commit_task_slot          (tq_commit_task_slot             ),
   .commit_task_epoch         (tq_commit_task_epoch            ),

   // -- SPILL Interface --   

   // Coalescer children Enq, Always accepted
   .coal_child_valid          (coal_child_valid             ),
   .coal_child_ready          (coal_child_ready             ),
   .coal_child_data           (coal_child_task              ),

   // Task Overflow port to coalescer 
   .overflow_valid            (overflow_valid               ),
   .overflow_ready            (overflow_ready               ),
   .overflow_data             (overflow_task                ),

   .splitter_deq_valid        (splitter_deq_valid           ),
   .splitter_deq_ready        (splitter_deq_ready           ),
   .splitter_deq_task         (splitter_deq_task            ),


   .full(),
   .almost_full(),
   .empty(tq_empty),

   .reg_bus(reg_bus[ID_TASK_UNIT]),
   .pci_debug(pci_debug[ID_TASK_UNIT]),

   .cq_max_vt_ts(cq_max_vt_ts),

   .lvt(lvt_tq_out),
   .gvt(gvt)
);


logic cq_out_task_valid, cq_out_task_ready;
task_t cq_out_task;
cq_slice_slot_t cq_out_task_slot;

// Abort / Cut-ties interface to child-manager
logic                           abort_children_valid;
logic                           abort_children_ready;
cq_slice_slot_t                 abort_children_cq_slot;
child_id_t                      abort_children_count;

logic                           abort_ack_valid;
logic                           abort_ack_ready;
cq_slice_slot_t                 abort_ack_cq_slot;

// Cut Ties with children  
logic                           cut_ties_valid;
logic                           cut_ties_ready;
cq_slice_slot_t                 cut_ties_cq_slot;
child_id_t                      cut_ties_num_children;

logic                           cut_ties_ack_valid;
logic                           cut_ties_ack_ready;
cq_slice_slot_t                 cut_ties_ack_cq_slot;

logic [2**LOG_CQ_SLICE_SIZE-1:0] task_aborted;

logic no_idle_cores;
assign no_idle_cores = 1'b0; 
logic cc_almost_full;
logic cq_full;

cq_slice #(
   .TILE_ID(TILE_ID)
) CQ_SLICE (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   // Task Deq from TQ
   .deq_task_valid      (task_deq_valid      ),
   .deq_task_ready      (task_deq_ready      ),
   .deq_task            (task_deq_data       ), 
   .deq_task_epoch      (task_deq_epoch      ), 
   .deq_task_tq_slot    (task_deq_tq_slot    ),
   .deq_task_cq_slot    (task_deq_cq_slot    ), 
   
   .deq_task_force      (task_deq_force    ), 

   // To FIFOs
   .out_task            (cq_out_task         ),
   .out_task_slot       (cq_out_task_slot    ),
   .out_task_valid      (cq_out_task_valid   ),
   .out_task_ready      (cq_out_task_ready   ),

   .finish_task_valid         (finish_task_valid         ),
   .finish_task_slot          (finish_task_slot       ),
   .finish_task_is_undo_log_restore    (finish_task_is_undo_log_restore       ),
   .finish_task_num_children  (finish_task_num_children  ),
   .finish_task_ready         (finish_task_ready         ),

   .task_aborted              (task_aborted),
   
   .gvt_task_slot_valid  (gvt_task_slot_valid ),
   .gvt_task_slot        (gvt_task_slot       ),

   .no_idle_cores       (no_idle_cores),
   .all_idle_cores       (all_cores_idle),
   .cc_almost_full      (cc_almost_full),
   .tsb_almost_full     (tsb_almost_full),

   
   // Abort Task To TQ (always with requeue)
   .to_tq_abort_valid      (abort_task_valid       ),
   .to_tq_abort_ready      (abort_task_ready       ),
   .to_tq_abort_slot       (abort_task_slot        ),
   .to_tq_abort_epoch      (abort_task_epoch       ),
   .to_tq_abort_ts         (abort_task_ts          ),
   
   .tq_commit_task_valid   (tq_commit_task_valid   ),
   .tq_commit_task_ready   (tq_commit_task_ready   ),
   .tq_commit_task_slot    (tq_commit_task_slot    ),
   .tq_commit_task_epoch   (tq_commit_task_epoch   ),

   // Abort Task From TQ
   .from_tq_abort_valid    (cq_child_abort_valid   ),
   .from_tq_abort_ready    (cq_child_abort_ready   ),
   .from_tq_abort_slot     (cq_child_abort_slot    ),
   
   // Abort/CutTie Children 
   .abort_children_valid   (abort_children_valid   ),
   .abort_children_ready   (abort_children_ready   ),
   .abort_children_cq_slot (abort_children_cq_slot ),
   .abort_children_count   (abort_children_count   ),
   
   .abort_ack_valid        (abort_ack_valid        ),
   .abort_ack_ready        (abort_ack_ready        ),
   .abort_ack_cq_slot      (abort_ack_cq_slot      ),
   
   .cut_ties_valid         (cut_ties_valid         ),
   .cut_ties_ready         (cut_ties_ready         ),
   .cut_ties_cq_slot       (cut_ties_cq_slot       ),
   .cut_ties_num_children  (cut_ties_num_children  ),
   
   .cut_ties_ack_valid     (cut_ties_ack_valid     ),
   .cut_ties_ack_ready     (cut_ties_ack_ready     ),
   .cut_ties_ack_cq_slot   (cut_ties_ack_cq_slot   ),
  
   .gvt(gvt),
   .lvt(lvt_cq_out),

   .max_vt_ts(cq_max_vt_ts),
   .cq_full(cq_full),

   .cur_cycle(cur_cycle),
   .pci_debug(pci_debug[ID_CQ]),
   .reg_bus(reg_bus[ID_CQ])
);

logic out_task_fifo_full, out_task_fifo_empty;
assign cq_out_task_ready = !out_task_fifo_full ;
assign fifo_cc_valid = !out_task_fifo_empty;

logic out_task_fifo_wr_en;
assign out_task_fifo_wr_en = cq_out_task_valid & cq_out_task_ready;

recirculating_fifo #(
      .WIDTH( $bits(cq_out_task) + $bits(cq_out_task_slot)),
      .LOG_DEPTH(1)
   ) OUT_TASK_FIFO (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),
      .wr_en(out_task_fifo_wr_en),
      .wr_data( {cq_out_task, cq_out_task_slot}),

      .full(out_task_fifo_full),
      .empty(out_task_fifo_empty),

      .rd_en(fifo_cc_ready),
      .rd_data({fifo_cc_data, fifo_cc_slot})

   );


logic issue_task_valid;
logic issue_task_ready;
task_t issue_task;
thread_id_t issue_task_thread;
cq_slice_slot_t issue_task_cq_slot;

logic unlock_thread_valid;
thread_id_t unlock_thread;

conflict_serializer #(
      .TILE_ID(TILE_ID)
   ) CONFLICT_SERIALIZER (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),
   
   .s_valid  (  issue_task_valid    ),
   .s_ready  (  issue_task_ready    ),
   .s_rdata  (  issue_task          ),
   .s_cq_slot(  issue_task_cq_slot  ),
   .s_thread (  issue_task_thread   ),

   .unlock_valid  ( unlock_thread_valid ), 
   .unlock_thread ( unlock_thread       ),

   .m_task        ( fifo_cc_data      ),
   .m_cq_slot     ( fifo_cc_slot      ),
   .m_valid       ( fifo_cc_valid      ),
   .m_ready       ( fifo_cc_ready      ),
   
   .cq_full       ( cq_full         ),
   .almost_full   ( cc_almost_full ),
   .all_cores_idle( all_cores_idle ),
   
   .pci_debug(pci_debug[ID_SERIALIZER]),
   .reg_bus(reg_bus[ID_SERIALIZER])
);

logic rw_read_out_fifo_full;
logic rw_read_out_fifo_empty;
fifo_size_t rw_read_out_fifo_occ;

logic rw_read_out_valid;
logic rw_read_out_ready;
rw_write_t rw_read_out_data, rw_write_in_data;
logic rw_write_in_valid;
logic rw_write_in_ready;
 
assign rw_read_out_ready = !rw_read_out_fifo_full;
assign rw_write_in_valid = !rw_read_out_fifo_empty;

read_rw  
#(
   .TILE_ID(TILE_ID)
) READ_RW (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),

   .task_in_valid (issue_task_valid),
   .task_in_ready (issue_task_ready),

   .task_in       (issue_task      ), 
   .cq_slot_in    (issue_task_cq_slot),
   .thread_id_in  (issue_task_thread),
   
   .gvt_task_slot_valid  (gvt_task_slot_valid ),
   .gvt_task_slot        (gvt_task_slot       ),

   .arvalid    (rw_l2.arvalid),
   .arready    (rw_l2.arready),
   .araddr     (rw_l2.araddr[31:0] ),
   .arid       (rw_l2.arid   ),

   .rvalid     (rw_l2.rvalid ),
   .rready     (rw_l2.rready ),
   .rid        (rw_l2.rid    ),
   .rdata      (rw_l2.rdata  ),
   .rindex     (rw_l2_rindex ),

   .task_out_valid(rw_read_out_valid),
   .task_out_ready(rw_read_out_ready),
   .task_out      (rw_read_out_data ),  
   .task_out_fifo_occ (rw_read_out_fifo_occ),
   
   .reg_bus( reg_bus[ID_RW_READ]),
   .pci_debug(pci_debug[ID_RW_READ])
);

assign rw_l2.araddr[63:32] = '0;
assign rw_l2.bready = 1'b1;

recirculating_fifo #(
      .WIDTH( $bits(rw_read_out_data)),
      .LOG_DEPTH(LOG_STAGE_FIFO_SIZE)
   ) RW_READ_OUT_FIFO (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),
      .wr_en(rw_read_out_valid & !rw_read_out_fifo_full),
      .wr_data( rw_read_out_data ),

      .full(  rw_read_out_fifo_full ),
      .empty( rw_read_out_fifo_empty),

      .rd_en( rw_write_in_ready ),
      .rd_data( rw_write_in_data ),

      .size(rw_read_out_fifo_occ)

   );

logic rw_write_out_fifo_full;
logic rw_write_out_fifo_empty;
fifo_size_t rw_write_out_fifo_occ;

logic rw_write_out_valid;
logic rw_write_out_ready;
task_t rw_write_out_data;
cq_slice_slot_t rw_write_out_cq_slot;

assign rw_write_out_ready = !rw_write_out_fifo_full;

logic           [N_SUB_TYPES-1:0]  fifo_wr_en;
logic           [N_SUB_TYPES-1:0]  fifo_rd_en;
task_t          [N_SUB_TYPES-1:0]  fifo_in_task;
data_t          [N_SUB_TYPES-1:0]  fifo_in_data; 
cq_slice_slot_t [N_SUB_TYPES-1:0]  fifo_in_cq_slot;
byte_t          [N_SUB_TYPES-1:0]  fifo_in_word_id;

task_t          [N_SUB_TYPES-1:0]  fifo_out_task; 
data_t          [N_SUB_TYPES-1:0]  fifo_out_data; 
cq_slice_slot_t [N_SUB_TYPES-1:0]  fifo_out_cq_slot;
byte_t          [N_SUB_TYPES-1:0]  fifo_out_word_id;
                 
logic           [N_SUB_TYPES-1:0]  fifo_full;
logic           [N_SUB_TYPES-1:0]  fifo_empty;

fifo_size_t     [N_SUB_TYPES-1:0]  fifo_occ;

logic rw_finish_task_valid, rw_finish_task_ready;
logic ro_finish_task_valid, ro_finish_task_ready;
cq_slice_slot_t rw_finish_task_slot, ro_finish_task_slot;
child_id_t ro_finish_task_num_children;
logic rw_finish_task_is_undo_log_restore;


write_rw 
#(
) WRITE_RW (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .task_in_valid (rw_write_in_valid),
   .task_in_ready (rw_write_in_ready),

   .task_in (rw_write_in_data), 
   .gvt_task_slot_valid  (gvt_task_slot_valid ),
   .gvt_task_slot        (gvt_task_slot       ),

   .wvalid (rw_l2.awvalid),
   .wready (rw_l2.awready),
   .waddr  (rw_l2.awaddr[31:0] ), 
   .wdata  (rw_l2.wdata  ),
   .wstrb  (rw_l2.wstrb  ),

   .task_out_valid(rw_write_out_valid),
   .task_out_ready(rw_write_out_ready),
   .task_out(rw_write_out_data),  
   .task_out_cq_slot(rw_write_out_cq_slot),  
   .task_out_fifo_occ (fifo_occ[0]),

   .unlock_locale (unlock_thread_valid),
   .unlock_thread(unlock_thread),
   
   .finish_task_valid (rw_finish_task_valid),
   .finish_task_ready (rw_finish_task_ready),
   .finish_task_slot(rw_finish_task_slot),
   .finish_task_is_undo_log_restore(rw_finish_task_is_undo_log_restore),
   
   .reg_bus(reg_bus[ID_RW_WRITE])
);


assign rw_l2.wvalid = rw_l2.awvalid;
assign rw_l2.awaddr[63:32] = '0;
assign rw_l2.bready = 1'b1;



logic ro_out_task_valid;
logic ro_out_task_ready;
subtype_t ro_out_task_subtype;
task_t ro_out_task;
data_t ro_out_data;
cq_slice_slot_t ro_out_cq_slot;
byte_t ro_out_word_id;

logic ro_idle;

generate 
for (i=0;i<N_SUB_TYPES;i++) begin
   recirculating_fifo #(
         .WIDTH( $bits(fifo_in_task[0]) + $bits(fifo_in_data[0])+ $bits(fifo_in_cq_slot[0]) + 8),
         .LOG_DEPTH(LOG_STAGE_FIFO_SIZE)
      ) TASK_TYPE_FIFO (
         .clk(clk_main_a0),
         .rstn(rst_main_n_sync),
         .wr_en(fifo_wr_en[i] & !fifo_full[i]),
         .wr_data( {fifo_in_task[i], fifo_in_data[i], fifo_in_cq_slot[i], fifo_in_word_id[i]} ),

         .full(  fifo_full[i] ),
         .empty( fifo_empty[i] ),

         .rd_en( fifo_rd_en[i] ),
         .rd_data( {fifo_out_task[i], fifo_out_data[i], fifo_out_cq_slot[i], fifo_out_word_id[i]} ),

         .size( fifo_occ[i])
      );

   if (i==0) begin
      assign fifo_wr_en[i] = rw_write_out_valid;
      assign fifo_in_task[i] = rw_write_out_data;
      assign fifo_in_data[i] = 0;
      assign fifo_in_cq_slot[i] = rw_write_out_cq_slot;
      assign fifo_in_word_id[i] = 0;
   end else begin
      assign fifo_wr_en[i] = ro_out_task_valid & (ro_out_task_subtype == i);
      assign fifo_in_task[i] = ro_out_task;
      assign fifo_in_data[i] = ro_out_data;
      assign fifo_in_cq_slot[i] = ro_out_cq_slot;
      assign fifo_in_word_id[i] = ro_out_word_id;
   end
   
end
assign rw_write_out_fifo_full = fifo_full[0];
assign rw_write_out_fifo_empty = fifo_empty[0];
always_comb begin
   ro_out_task_ready = ro_out_task_valid & !fifo_full[ro_out_task_subtype];
end

endgenerate

read_only_stage
#(
   .TILE_ID(TILE_ID)
) RO_STAGE (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .task_in_valid (~fifo_empty),
   .task_in_ready (fifo_rd_en),
   .in_task       (fifo_out_task), 
   .in_data       (fifo_out_data), 
   .in_cq_slot    (fifo_out_cq_slot),
   .in_word_id    (fifo_out_word_id),
   
   .in_fifo_occ    (fifo_occ),

   .task_aborted(task_aborted),
   .gvt_task_slot_valid  (gvt_task_slot_valid ),
   .gvt_task_slot        (gvt_task_slot       ),
   .tsb_almost_full (tsb_almost_full),
   
   .arvalid(l1_arb[0].arvalid),
   .arready(l1_arb[0].arready),
   .araddr (l1_arb[0].araddr[31:0] ),
   .arid   (l1_arb[0].arid   ),

   .rvalid(l1_arb[0].rvalid),
   .rready(l1_arb[0].rready),
   .rdata (l1_arb[0].rdata ),
   .rid   (l1_arb[0].rid   ),

   .out_valid   (ro_out_task_valid),
   .out_ready   (ro_out_task_ready),
   .out_task    (ro_out_task),
   .out_subtype (ro_out_task_subtype),
   .out_cq_slot (ro_out_cq_slot),
   .out_data    (ro_out_data),
   .out_word_id (ro_out_word_id),
   
   .child_valid (cores_cm_wvalid[1]),
   .child_ready (cores_cm_wready[1]),
   .child_task  (cores_cm_wdata [1]),
   .child_untied(cores_cm_enq_untied[1]),
   .child_cq_slot( cores_cm_cq_slot[1]),
   .child_id    (cores_cm_child_id[1]),
  
   .finish_task_valid (ro_finish_task_valid),
   .finish_task_ready (ro_finish_task_ready),
   .finish_task_slot(ro_finish_task_slot),
   .finish_task_num_children(ro_finish_task_num_children),

   .idle(ro_idle),
   
   .reg_bus( reg_bus[ID_RO_STAGE]),
   .pci_debug(pci_debug[ID_RO_STAGE])
);

assign l1_arb[0].araddr[63:32] = 0;
assign l1_arb[0].awvalid = 0;
assign l1_arb[0].wvalid = 0;
assign l1_arb[0].bready = 1;

always_comb begin
   finish_task_valid = 1'b0;
   rw_finish_task_ready = 1'b0;
   ro_finish_task_ready = 1'b0;
   finish_task_slot = 'x;
   finish_task_num_children = 'x;
   finish_task_is_undo_log_restore = 1'b0;
   if (rw_finish_task_valid) begin
      finish_task_valid = 1'b1;
      finish_task_slot = rw_finish_task_slot;
      finish_task_num_children = 0;
      finish_task_is_undo_log_restore = rw_finish_task_is_undo_log_restore;
      if (finish_task_ready) begin
         rw_finish_task_ready = 1'b1;
      end
   end else if (ro_finish_task_valid) begin
      finish_task_valid = 1'b1;
      finish_task_slot = ro_finish_task_slot;
      finish_task_num_children = ro_finish_task_num_children;
      if (finish_task_ready) begin
         ro_finish_task_ready = 1'b1;
      end
   end
end


logic             cm_tsb_valid;
logic             cm_tsb_ready;
task_t            cm_tsb_data;
logic             cm_tsb_tied;
cq_slice_slot_t   cm_tsb_cq_slot;
child_id_t        cm_tsb_child_id;


logic             cm_tsb_retry_valid;
logic             cm_tsb_retry_ready;
tsb_entry_id_t    cm_tsb_retry_tsb_id;
logic             cm_tsb_retry_abort;
logic             cm_tsb_retry_tied;

   
logic             tsb_cm_valid;
logic             tsb_cm_ready;
logic             tsb_cm_ack;
tsb_entry_id_t    tsb_cm_tsb_slot;
cq_slice_slot_t   tsb_cm_cq_slot;
child_id_t        tsb_cm_child_id;
epoch_t           tsb_cm_epoch;
tq_slot_t         tsb_cm_tq_slot;
tile_id_t         tsb_cm_tile_id;

child_manager #(
      .NUM_SI(CM_PORTS)
   ) CHILD_MANAGER (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .s_wvalid      (cores_cm_wvalid),
   .s_wdata       (cores_cm_wdata),
   .s_wready      (cores_cm_wready),
   .s_enq_untied  (cores_cm_enq_untied),
   .s_cq_slot     (cores_cm_cq_slot),
   .s_child_id    (cores_cm_child_id),
   
   .task_enq_valid         (cm_tsb_valid),
   .task_enq_ready         (cm_tsb_ready),
   .task_enq_data          (cm_tsb_data),
   .task_enq_tied          (cm_tsb_tied),
   .task_enq_resp_cq_slot  (cm_tsb_cq_slot),
   .task_enq_resp_child_id (cm_tsb_child_id),

   .tsb_almost_full   (tsb_almost_full),

   .task_retry_valid    (cm_tsb_retry_valid),
   .task_retry_ready    (cm_tsb_retry_ready),
   .task_retry_tsb_id   (cm_tsb_retry_tsb_id),
   .task_retry_abort    (cm_tsb_retry_abort),
   .task_retry_tied     (cm_tsb_retry_tied),
   
   .task_resp_valid     (tsb_cm_valid),
   .task_resp_ready     (tsb_cm_ready),
   .task_resp_ack       (tsb_cm_ack),
   .task_resp_tsb_slot  (tsb_cm_tsb_slot),
   .task_resp_cq_slot   (tsb_cm_cq_slot),
   .task_resp_child_id  (tsb_cm_child_id),
   .task_resp_epoch     (tsb_cm_epoch),
   .task_resp_tq_slot   (tsb_cm_tq_slot),
   .task_resp_tile_id   (tsb_cm_tile_id),
   
   .cq_abort_children_valid   (abort_children_valid),
   .cq_abort_children_ready   (abort_children_ready),
   .cq_abort_children_cq_slot (abort_children_cq_slot),
   .cq_abort_children_count   (abort_children_count),
   
   .cq_cut_ties_valid   (cut_ties_valid),
   .cq_cut_ties_ready   (cut_ties_ready),
   .cq_cut_ties_cq_slot (cut_ties_cq_slot),
   .cq_cut_ties_count   (cut_ties_num_children),
   
   .abort_child_valid        (abort_child_out.valid),
   .abort_child_ready        (abort_child_out.ready),
   .abort_child_epoch        (abort_child_out.child_epoch),
   .abort_child_tq_slot      (abort_child_out.tq_slot),
   .abort_child_tile_id      (abort_child_out.dest_tile),
   .abort_child_resp_child_id(abort_child_out.resp_child_id),
   .abort_child_resp_cq_slot (abort_child_out.resp_cq_slot),

   .cut_ties_valid      (cut_ties_out.valid),
   .cut_ties_ready      (cut_ties_out.ready),
   .cut_ties_epoch      (cut_ties_out.child_epoch),
   .cut_ties_tq_slot    (cut_ties_out.tq_slot),
   .cut_ties_tile_id    (cut_ties_out.dest_tile),
   
   .abort_resp_valid    (abort_resp_in.valid),
   .abort_resp_ready    (abort_resp_in.ready),
   .abort_resp_cq_slot  (abort_resp_in.cq_slot),
   .abort_resp_child_id (abort_resp_in.child_id),
   
   .abort_children_ack_valid     (abort_ack_valid),
   .abort_children_ack_ready     (abort_ack_ready),
   .abort_children_ack_cq_slot   (abort_ack_cq_slot),
   
   .cut_ties_ack_valid     (cut_ties_ack_valid),
   .cut_ties_ack_ready     (cut_ties_ack_ready),
   .cut_ties_ack_cq_slot   (cut_ties_ack_cq_slot),

   .reg_bus(reg_bus[ID_CM]),
   .lvt(lvt_cm_out)
);
   

tsb TSB (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),
   
   .s_wvalid   (cm_tsb_valid),
   .s_wdata    (cm_tsb_data),
   .s_tied     (cm_tsb_tied),
   .s_wready   (cm_tsb_ready),
   .s_cq_slot  (cm_tsb_cq_slot),
   .s_child_id (cm_tsb_child_id),

   .almost_full (tsb_almost_full),

   .retry_valid   (cm_tsb_retry_valid),
   .retry_ready   (cm_tsb_retry_ready),
   .retry_tsb_id  (cm_tsb_retry_tsb_id),
   .retry_abort   (cm_tsb_retry_abort),
   .retry_tied    (cm_tsb_retry_tied),

   .task_enq_valid      (task_enq_out.valid),
   .task_enq_data       (task_enq_out.task_data),
   .task_enq_tied       (task_enq_out.task_tied),
   .task_enq_dest_tile  (task_enq_out.dest_tile),
   .task_enq_ready      (task_enq_out.ready),
   .task_enq_tsb_id     (task_enq_out.resp_tsb_id),

   .task_resp_valid     (task_resp_in.valid),
   .task_resp_ready     (task_resp_in.ready),
   .task_resp_ack       (task_resp_in.task_ack),
   .task_resp_tsb_id    (task_resp_in.tsb_id),
   .task_resp_epoch     (task_resp_in.task_epoch),
   .task_resp_tq_slot   (task_resp_in.tq_slot),
   
   .m_resp_valid   (tsb_cm_valid),  
   .m_resp_ready   (tsb_cm_ready),
   .m_resp_ack     (tsb_cm_ack),
   .m_tsb_slot     (tsb_cm_tsb_slot),
   .m_epoch        (tsb_cm_epoch),
   .m_tq_slot      (tsb_cm_tq_slot),
   .m_tile_id      (tsb_cm_tile_id),
   .m_cq_slot      (tsb_cm_cq_slot),
   .m_child_id     (tsb_cm_child_id),

   .lvt(lvt_tsb_out.ts),
   .empty(tsb_empty),
  
   .reg_bus(reg_bus[ID_TSB])
);

assign task_enq_out.resp_tile = TILE_ID;
assign abort_child_out.resp_tile = TILE_ID;

always @(posedge clk_main_a0) begin
   if (!rst_main_n_sync) begin
      done <= 0;
   end else begin
      done <= { {27{1'b1}}, tq_empty, tsb_empty, all_cores_idle, out_task_fifo_empty, ro_idle};
   end

end


endmodule

