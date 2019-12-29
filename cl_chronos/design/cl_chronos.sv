/** $lic$
 * Copyright (C) 2014-2019 by Massachusetts Institute of Technology
 *
 * This file is part of the Chronos FPGA Acceleration Framework.
 *
 * Chronos is free software; you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, version 2.
 *
 * If you use this framework in your research, we request that you reference
 * the Chronos paper ("Chronos: Efficient Speculative Parallelism for
 * Accelerators", Abeydeera and Sanchez, ASPLOS-25, March 2020), and that
 * you send us a citation of your work.
 *
 * Chronos is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */

module cl_chronos 

(
   `include "cl_ports.vh" // Fixed port definition

);

`include "cl_id_defines.vh"          // Defines for ID0 and ID1 (PCI ID's)
`include "cl_chronos_defines.vh" // CL Defines for cl_hello_world

logic rst_main_n_sync_p;
logic rst_main_n_sync;


//--------------------------------------------0
// Start with Tie-Off of Unused Interfaces
//---------------------------------------------
// the developer should use the next set of `include
// to properly tie-off any unused interface
// The list is put in the top of the module
// to avoid cases where developer may forget to
// remove it from the end of the file

`include "unused_flr_template.inc"
`ifdef SIMPLE_MEMORY
`include "unused_ddr_a_b_d_template.inc"
`include "unused_ddr_c_template.inc"
`endif
`include "unused_pcim_template.inc"
//`include "unused_dma_pcis_template.inc"
`include "unused_cl_sda_template.inc"
`include "unused_sh_bar1_template.inc"
`include "unused_apppf_irq_template.inc"


import chronos::*;

//-------------------------------------------------
// Reset Synchronization
//-------------------------------------------------
logic pre_sync_rst_n;

always_ff @(negedge rst_main_n or posedge clk_main_a0)
   if (!rst_main_n)
   begin
      pre_sync_rst_n  <= 0;
      rst_main_n_sync_p <= 0;
   end
   else
   begin
      pre_sync_rst_n  <= 1;
      rst_main_n_sync_p <= pre_sync_rst_n;
   end


   lib_pipe #(
      .WIDTH(1),
      .STAGES(3)
   ) RST_PIPE (
      .clk(clk_main_a0), 
      .rst_n(1'b1),
      
      .in_bus ( rst_main_n_sync_p ),
      .out_bus( rst_main_n_sync )
   ); 

assign sh_ocl_bus.awvalid = sh_ocl_awvalid;
assign sh_ocl_bus.awaddr[31:0] = sh_ocl_awaddr;
assign ocl_sh_awready = sh_ocl_bus.awready;
assign sh_ocl_bus.wvalid = sh_ocl_wvalid;
assign sh_ocl_bus.wdata[31:0] = sh_ocl_wdata;
assign sh_ocl_bus.wstrb[3:0] = sh_ocl_wstrb;
assign ocl_sh_wready = sh_ocl_bus.wready;
assign ocl_sh_bvalid = sh_ocl_bus.bvalid;
assign ocl_sh_bresp = sh_ocl_bus.bresp;
assign sh_ocl_bus.bready = sh_ocl_bready;
assign sh_ocl_bus.arvalid = sh_ocl_arvalid;
assign sh_ocl_bus.araddr[31:0] = sh_ocl_araddr;
assign ocl_sh_arready = sh_ocl_bus.arready;
assign ocl_sh_rvalid = sh_ocl_bus.rvalid;
assign ocl_sh_rresp = sh_ocl_bus.rresp;
assign ocl_sh_rdata = sh_ocl_bus.rdata[31:0];
assign sh_ocl_bus.rready = sh_ocl_rready;

assign sh_cl_dma_pcis_bus.awvalid = sh_cl_dma_pcis_awvalid;
assign sh_cl_dma_pcis_bus.awaddr = sh_cl_dma_pcis_awaddr;
assign sh_cl_dma_pcis_bus.awid[5:0] = sh_cl_dma_pcis_awid;
assign sh_cl_dma_pcis_bus.awlen = sh_cl_dma_pcis_awlen;
assign sh_cl_dma_pcis_bus.awsize = sh_cl_dma_pcis_awsize;
assign cl_sh_dma_pcis_awready = sh_cl_dma_pcis_bus.awready;
assign sh_cl_dma_pcis_bus.wvalid = sh_cl_dma_pcis_wvalid;
assign sh_cl_dma_pcis_bus.wdata = sh_cl_dma_pcis_wdata;
assign sh_cl_dma_pcis_bus.wstrb = sh_cl_dma_pcis_wstrb;
assign sh_cl_dma_pcis_bus.wlast = sh_cl_dma_pcis_wlast;
assign cl_sh_dma_pcis_wready = sh_cl_dma_pcis_bus.wready;
assign cl_sh_dma_pcis_bvalid = sh_cl_dma_pcis_bus.bvalid;
assign cl_sh_dma_pcis_bresp = sh_cl_dma_pcis_bus.bresp;
assign sh_cl_dma_pcis_bus.bready = sh_cl_dma_pcis_bready;
assign cl_sh_dma_pcis_bid = sh_cl_dma_pcis_bus.bid[5:0];
assign sh_cl_dma_pcis_bus.arvalid = sh_cl_dma_pcis_arvalid;
assign sh_cl_dma_pcis_bus.araddr = sh_cl_dma_pcis_araddr;
assign sh_cl_dma_pcis_bus.arid[5:0] = sh_cl_dma_pcis_arid;
assign sh_cl_dma_pcis_bus.arlen = sh_cl_dma_pcis_arlen;
assign sh_cl_dma_pcis_bus.arsize = sh_cl_dma_pcis_arsize;
assign cl_sh_dma_pcis_arready = sh_cl_dma_pcis_bus.arready;
assign cl_sh_dma_pcis_rvalid = sh_cl_dma_pcis_bus.rvalid;
assign cl_sh_dma_pcis_rid = sh_cl_dma_pcis_bus.rid[5:0];
assign cl_sh_dma_pcis_rlast = sh_cl_dma_pcis_bus.rlast;
assign cl_sh_dma_pcis_rresp = sh_cl_dma_pcis_bus.rresp;
assign cl_sh_dma_pcis_rdata = sh_cl_dma_pcis_bus.rdata;
assign sh_cl_dma_pcis_bus.rready = sh_cl_dma_pcis_rready;

genvar i,j;
// axi_bus_t core_cache_bus[0:0]();
// axi_bus_t cache_bus();
axi_bus_t sh_ocl_bus();
axi_bus_t sh_ocl_bus_q();
axi_bus_t sh_cl_dma_pcis_bus();
axi_bus_t sh_cl_dma_pcis_bus_q();
axi_bus_t pci_arb_mem_arb_bus();
axi_bus_t axi_tree_0_p();

axi_pipe 
#(
   .STAGES(1),
   .WRITE_TOGETHER(0)
) OCL_PIPE (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .in(sh_ocl_bus),
   .out(sh_ocl_bus_q)
);

axi_pipe 
#(
   .STAGES(1),
   .WRITE_TOGETHER(0)
) PCIS_PIPE (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .in(sh_cl_dma_pcis_bus),
   .out(sh_cl_dma_pcis_bus_q)
);

axi_bus_t ocl[N_TILES]();
axi_bus_t ocl_q[N_TILES]();
logic [N_TILES-1:0] ocl_awvalid;
logic [N_TILES-1:0] ocl_awready;
logic [31:0] ocl_awaddr;

logic [N_TILES-1:0] ocl_wvalid;
logic [N_TILES-1:0] ocl_wready;
logic [31:0] ocl_wdata;

logic [N_TILES-1:0] ocl_bvalid;
logic ocl_bready;

logic [N_TILES-1:0] ocl_arvalid;
logic [N_TILES-1:0] ocl_arready;
logic [31:0] ocl_araddr;

logic [N_TILES-1:0] ocl_rvalid;
reg_data_t [N_TILES-1:0] ocl_rdata;
logic ocl_rready;


pci_debug_bus_t pci_debug[N_TILES]();
logic [N_TILES-1:0] pci_debug_arvalid;
logic [7:0] pci_debug_arlen;
logic [7:0] pci_debug_comp;

logic pci_debug_rready;
cache_line_t [N_TILES-1:0] pci_debug_rdata;
logic [N_TILES-1:0] pci_debug_rvalid;
logic [N_TILES-1:0] pci_debug_rlast;

logic [N_TILES-1:0] pci_debug_arvalid_q;
logic [7:0] pci_debug_arlen_q;
logic [7:0] pci_debug_comp_q;

task_enq_req_t task_enq_req_in[N_TILES](); // in/out relative to the xbar
task_enq_req_t task_enq_req_out[N_TILES]();
logic       [N_TILES-1:0] task_enq_req_in_wvalid;
logic       [N_TILES-1:0] task_enq_req_in_wready;
logic [N_TILES-1:0]  [TASK_ENQ_DATA_WIDTH-1:0] task_enq_req_in_wdata;
tile_id_t [N_TILES-1:0] task_enq_req_in_port;
logic       [N_TILES-1:0] task_enq_req_out_wvalid;
logic       [N_TILES-1:0] task_enq_req_out_wready;
logic [N_TILES-1:0] [TASK_ENQ_DATA_WIDTH-1:0] task_enq_req_out_wdata;

logic [2:0] num_mem_ctrl;
logic [15:0] rate_ctrl_r;
logic [15:0] rate_ctrl_n;
logic [15:0] pci_log_size;
logic [N_TILES-1:0] [$clog2(N_TILES):0] task_in_port;


generate 
for (i=0;i<N_TILES;i++) begin : task_enq_xbar
   assign task_enq_req_in_wvalid    [i]  = task_enq_req_in[i].valid;
   assign task_enq_req_in_wdata     [i]  = { task_enq_req_in[i].task_data,
                                             task_enq_req_in[i].task_tied,
                                             task_enq_req_in[i].resp_tsb_id,
                                             task_enq_req_in[i].resp_tile };
   assign task_enq_req_in_port      [i]  = task_enq_req_in[i].dest_tile;
   assign task_enq_req_in[i].ready  = task_enq_req_in_wready[i];

   assign task_enq_req_out[i].valid = task_enq_req_out_wvalid[i];
   assign { task_enq_req_out[i].task_data,
            task_enq_req_out[i].task_tied,
            task_enq_req_out[i].resp_tsb_id,
            task_enq_req_out[i].resp_tile }  = task_enq_req_out_wdata [i];
   assign task_enq_req_out_wready   [i]  = task_enq_req_out[i].ready;
/*
   always_comb begin
      case (log_n_tiles) 
         0: task_in_port[i] = 0; 
         1: task_in_port[i] = task_in_wdata[i].object[4]; 
         2: task_in_port[i] = task_in_wdata[i].object[5:4]; 
         3: task_in_port[i] = task_in_wdata[i].object[6:4];
         4: task_in_port[i] = task_in_wdata[i].object[7:4];
         default: task_in_port[i] = task_in_wdata[i].object[8:4];
      endcase
   end
*/
end
endgenerate

tile_xbar 
#(
   .DATA_WIDTH(TASK_ENQ_DATA_WIDTH)
) TASK_XBAR (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .s_wdata       (  task_enq_req_in_wdata     ),
   .s_wvalid      (  task_enq_req_in_wvalid    ),
   .s_wready      (  task_enq_req_in_wready    ),
   
   .s_port        (  task_enq_req_in_port      ),
  
   .m_wdata       (  task_enq_req_out_wdata     ),
   .m_wvalid      (  task_enq_req_out_wvalid    ),
   .m_wready      (  task_enq_req_out_wready    )
);

task_enq_resp_t task_enq_resp_in [N_TILES](); // in/out relative to the xbar
task_enq_resp_t task_enq_resp_out[N_TILES]();
logic       [N_TILES-1:0] task_enq_resp_in_wvalid;
logic       [N_TILES-1:0] task_enq_resp_in_wready;
logic [N_TILES-1:0]  [TASK_RESP_DATA_WIDTH-1:0] task_enq_resp_in_wdata;
tile_id_t [N_TILES-1:0] task_enq_resp_in_port;
logic       [N_TILES-1:0] task_enq_resp_out_wvalid;
logic       [N_TILES-1:0] task_enq_resp_out_wready;
logic [N_TILES-1:0] [TASK_RESP_DATA_WIDTH-1:0] task_enq_resp_out_wdata;
generate 
for (i=0;i<N_TILES;i++) begin : task_resp_xbar
   assign task_enq_resp_in_wvalid    [i]  = task_enq_resp_in[i].valid;
   assign task_enq_resp_in_wdata     [i]  = { 
                     task_enq_resp_in[i].tsb_id,
                     task_enq_resp_in[i].task_ack,
                     task_enq_resp_in[i].task_epoch,
                     task_enq_resp_in[i].tq_slot};
   assign task_enq_resp_in_port      [i]  = task_enq_resp_in[i].dest_tile;
   assign task_enq_resp_in[i].ready  = task_enq_resp_in_wready[i];

   assign task_enq_resp_out[i].valid = task_enq_resp_out_wvalid[i];
   assign {
      task_enq_resp_out[i].tsb_id,
      task_enq_resp_out[i].task_ack,
      task_enq_resp_out[i].task_epoch,
      task_enq_resp_out[i].tq_slot }   
         = task_enq_resp_out_wdata [i];
   assign task_enq_resp_out_wready   [i]  = task_enq_resp_out[i].ready;
end
endgenerate

tile_xbar 
#(
   .DATA_WIDTH(TASK_RESP_DATA_WIDTH)
) RESP_XBAR (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .s_wdata       (  task_enq_resp_in_wdata     ),
   .s_wvalid      (  task_enq_resp_in_wvalid    ),
   .s_wready      (  task_enq_resp_in_wready    ),
   
   .s_port        (  task_enq_resp_in_port      ),
  
   .m_wdata       (  task_enq_resp_out_wdata     ),
   .m_wvalid      (  task_enq_resp_out_wvalid    ),
   .m_wready      (  task_enq_resp_out_wready    )
);


abort_child_req_t abort_child_req_in[N_TILES](); // in/out relative to the xbar
abort_child_req_t abort_child_req_out[N_TILES]();
logic       [N_TILES-1:0] abort_child_req_in_wvalid;
logic       [N_TILES-1:0] abort_child_req_in_wready;
logic [N_TILES-1:0]  [ABORT_CHILD_DATA_WIDTH-1:0] abort_child_req_in_wdata;
tile_id_t [N_TILES-1:0]   abort_child_req_in_port;
logic       [N_TILES-1:0] abort_child_req_out_wvalid;
logic       [N_TILES-1:0] abort_child_req_out_wready;
logic [N_TILES-1:0] [ABORT_CHILD_DATA_WIDTH-1:0] abort_child_req_out_wdata;



generate 
for (i=0;i<N_TILES;i++) begin : abort_child_xbar
   assign abort_child_req_in_wvalid [i]  = abort_child_req_in[i].valid;
   assign abort_child_req_in_wdata  [i]  = { abort_child_req_in[i].tq_slot,
                                             abort_child_req_in[i].child_epoch,
                                             abort_child_req_in[i].resp_tile,
                                             abort_child_req_in[i].resp_cq_slot,
                                             abort_child_req_in[i].resp_child_id };
   assign abort_child_req_in_port      [i]  = abort_child_req_in[i].dest_tile;
   assign abort_child_req_in[i].ready  = abort_child_req_in_wready[i];

   assign abort_child_req_out[i].valid = abort_child_req_out_wvalid[i];
   assign { abort_child_req_out[i].tq_slot,
            abort_child_req_out[i].child_epoch,
            abort_child_req_out[i].resp_tile,
            abort_child_req_out[i].resp_cq_slot,
            abort_child_req_out[i].resp_child_id }   = abort_child_req_out_wdata [i];
   assign abort_child_req_out_wready   [i]  = abort_child_req_out[i].ready;
end
endgenerate

tile_xbar 
#(
   .DATA_WIDTH(ABORT_CHILD_DATA_WIDTH)
) ABORT_CHILD_XBAR (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .s_wdata       (  abort_child_req_in_wdata     ),
   .s_wvalid      (  abort_child_req_in_wvalid    ),
   .s_wready      (  abort_child_req_in_wready    ),
   
   .s_port        (  abort_child_req_in_port      ),
  
   .m_wdata       (  abort_child_req_out_wdata     ),
   .m_wvalid      (  abort_child_req_out_wvalid    ),
   .m_wready      (  abort_child_req_out_wready    )
);

abort_child_resp_t abort_child_resp_in [N_TILES](); // in/out relative to the xbar
abort_child_resp_t abort_child_resp_out[N_TILES](); 
logic       [N_TILES-1:0] abort_child_resp_in_wvalid;
logic       [N_TILES-1:0] abort_child_resp_in_wready;
logic [N_TILES-1:0]  [ABORT_RESP_DATA_WIDTH-1:0] abort_child_resp_in_wdata;
tile_id_t [N_TILES-1:0] abort_child_resp_in_port;
logic       [N_TILES-1:0] abort_child_resp_out_wvalid;
logic       [N_TILES-1:0] abort_child_resp_out_wready;
logic [N_TILES-1:0] [ABORT_RESP_DATA_WIDTH-1:0] abort_child_resp_out_wdata;
generate 
for (i=0;i<N_TILES;i++) begin : abort_resp_xbar
   assign abort_child_resp_in_wvalid    [i]  = abort_child_resp_in[i].valid;
   assign abort_child_resp_in_wdata     [i]  = { 
                     abort_child_resp_in[i].cq_slot,
                     abort_child_resp_in[i].child_id };
   assign abort_child_resp_in_port      [i]  = abort_child_resp_in[i].dest_tile;
   assign abort_child_resp_in[i].ready  = abort_child_resp_in_wready[i];

   assign abort_child_resp_out[i].valid = abort_child_resp_out_wvalid[i];
   assign {
      abort_child_resp_out[i].cq_slot,
      abort_child_resp_out[i].child_id }
         = abort_child_resp_out_wdata [i];
   assign abort_child_resp_out_wready   [i]  = abort_child_resp_out[i].ready;
end
endgenerate

tile_xbar 
#(
   .DATA_WIDTH(ABORT_RESP_DATA_WIDTH)
) ABORT_RESP_XBAR (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .s_wdata       (  abort_child_resp_in_wdata     ),
   .s_wvalid      (  abort_child_resp_in_wvalid    ),
   .s_wready      (  abort_child_resp_in_wready    ),
   
   .s_port        (  abort_child_resp_in_port      ),
  
   .m_wdata       (  abort_child_resp_out_wdata     ),
   .m_wvalid      (  abort_child_resp_out_wvalid    ),
   .m_wready      (  abort_child_resp_out_wready    )
);

cut_ties_req_t cut_ties_req_in [N_TILES](); // in/out relative to the xbar
cut_ties_req_t cut_ties_req_out[N_TILES](); 
logic       [N_TILES-1:0] cut_ties_req_in_wvalid;
logic       [N_TILES-1:0] cut_ties_req_in_wready;
logic [N_TILES-1:0]  [CUT_TIES_DATA_WIDTH-1:0] cut_ties_req_in_wdata;
tile_id_t [N_TILES-1:0]   cut_ties_req_in_port;
logic       [N_TILES-1:0] cut_ties_req_out_wvalid;
logic       [N_TILES-1:0] cut_ties_req_out_wready;
logic [N_TILES-1:0] [CUT_TIES_DATA_WIDTH-1:0] cut_ties_req_out_wdata;



generate 
for (i=0;i<N_TILES;i++) begin : cut_ties_xbar
   assign cut_ties_req_in_wvalid [i]  = cut_ties_req_in[i].valid;
   assign cut_ties_req_in_wdata  [i]  = { cut_ties_req_in[i].tq_slot,
                                          cut_ties_req_in[i].child_epoch };
   assign cut_ties_req_in_port      [i]  = cut_ties_req_in[i].dest_tile;
   assign cut_ties_req_in[i].ready  = cut_ties_req_in_wready[i];

   assign cut_ties_req_out[i].valid = cut_ties_req_out_wvalid[i];
   assign { cut_ties_req_out[i].tq_slot,
            cut_ties_req_out[i].child_epoch}   = cut_ties_req_out_wdata [i];
   assign cut_ties_req_out_wready   [i]  = cut_ties_req_out[i].ready;
end
endgenerate

tile_xbar 
#(
   .DATA_WIDTH(CUT_TIES_DATA_WIDTH)
) CUT_TIES_XBAR (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .s_wdata       (  cut_ties_req_in_wdata     ),
   .s_wvalid      (  cut_ties_req_in_wvalid    ),
   .s_wready      (  cut_ties_req_in_wready    ),
   
   .s_port        (  cut_ties_req_in_port      ),
  
   .m_wdata       (  cut_ties_req_out_wdata     ),
   .m_wvalid      (  cut_ties_req_out_wvalid    ),
   .m_wready      (  cut_ties_req_out_wready    )
);





// -- Memory --
axi_bus_t axi_tree[2*C_N_TILES](); // 0 is for pci_decoder
axi_bus_t tile_mem[N_TILES](); // 0 is for pci_decoder
axi_bus_t xbar_ddr_bus[4](); 
axi_bus_t xbar_ddr_bus_p[4](); 




axi_id_t    [XBAR_IN_TILES:0] mem_xbar_in_awid;
axi_addr_t  [XBAR_IN_TILES:0] mem_xbar_in_awaddr;
axi_len_t   [XBAR_IN_TILES:0] mem_xbar_in_awlen;
axi_size_t  [XBAR_IN_TILES:0] mem_xbar_in_awsize;
logic       [XBAR_IN_TILES:0] mem_xbar_in_awvalid;
logic       [XBAR_IN_TILES:0] mem_xbar_in_awready;

axi_id_t    [XBAR_IN_TILES:0] mem_xbar_in_wid;
axi_data_t  [XBAR_IN_TILES:0] mem_xbar_in_wdata;
axi_strb_t  [XBAR_IN_TILES:0] mem_xbar_in_wstrb;
logic       [XBAR_IN_TILES:0] mem_xbar_in_wlast;
logic       [XBAR_IN_TILES:0] mem_xbar_in_wvalid;
logic       [XBAR_IN_TILES:0] mem_xbar_in_wready;

axi_id_t    [XBAR_IN_TILES:0] mem_xbar_in_bid;
axi_resp_t  [XBAR_IN_TILES:0] mem_xbar_in_bresp;
logic       [XBAR_IN_TILES:0] mem_xbar_in_bvalid;
logic       [XBAR_IN_TILES:0] mem_xbar_in_bready;

axi_id_t    [XBAR_IN_TILES:0] mem_xbar_in_arid;
axi_addr_t  [XBAR_IN_TILES:0] mem_xbar_in_araddr;
axi_len_t   [XBAR_IN_TILES:0] mem_xbar_in_arlen;
axi_size_t  [XBAR_IN_TILES:0] mem_xbar_in_arsize;
logic       [XBAR_IN_TILES:0] mem_xbar_in_arvalid;
logic       [XBAR_IN_TILES:0] mem_xbar_in_arready;

axi_id_t    [XBAR_IN_TILES:0] mem_xbar_in_rid;
axi_data_t  [XBAR_IN_TILES:0] mem_xbar_in_rdata;
axi_resp_t  [XBAR_IN_TILES:0] mem_xbar_in_rresp;
logic       [XBAR_IN_TILES:0] mem_xbar_in_rlast;
logic       [XBAR_IN_TILES:0] mem_xbar_in_rvalid;
logic       [XBAR_IN_TILES:0] mem_xbar_in_rready;

generate 
for (i=XBAR_IN_TILES;i<C_N_TILES;i++) begin : axi_mux

      axi_mux
      #( 
         .ID_BIT(10 + $clog2(C_N_TILES) -  $clog2(i+1))
      ) AXI_MUX (
         .clk(clk_main_a0),
         .rstn(rst_main_n_sync),

         .a(axi_tree[i*2]),
         .b(axi_tree[i*2+1]),
         .out_q(axi_tree[i])
      );
end
for (i=0;i<N_TILES;i++) begin
   axi_pipe 
   #(
      .STAGES(1)
   ) AXI_PIPE (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),

      .in(tile_mem[i]),
      .out(axi_tree[C_N_TILES+i])
   );
end

for (i=C_N_TILES+N_TILES; i<2*C_N_TILES;i++) begin
  assign axi_tree[i].awvalid = 1'b0;
  assign axi_tree[i].arvalid = 1'b0;
  assign axi_tree[i].wvalid = 1'b0;
  assign axi_tree[i].rready = 1'b1;
  assign axi_tree[i].bready = 1'b1;
  assign axi_tree[i].arlen = 10;
end

for (i=0;i<1;i++) begin : xbar_in_pci

      assign mem_xbar_in_awid    [i] = axi_tree[i].awid;
      assign mem_xbar_in_awaddr  [i] = axi_tree[i].awaddr;
      assign mem_xbar_in_awsize  [i] = axi_tree[i].awsize;
      assign mem_xbar_in_awlen   [i] = axi_tree[i].awlen;
      assign mem_xbar_in_awvalid [i] = axi_tree[i].awvalid;
      assign axi_tree[i].awready = mem_xbar_in_awready [i];

      assign mem_xbar_in_wid     [i] = axi_tree[i].wid;
      assign mem_xbar_in_wdata   [i] = axi_tree[i].wdata;
      assign mem_xbar_in_wlast   [i] = axi_tree[i].wlast;
      assign mem_xbar_in_wstrb   [i] = axi_tree[i].wstrb;
      assign mem_xbar_in_wvalid  [i] = axi_tree[i].wvalid;
      assign axi_tree[i].wready  = mem_xbar_in_wready [i];

      assign axi_tree[i].bid    = mem_xbar_in_bid    [i];
      assign axi_tree[i].bresp  = mem_xbar_in_bresp  [i];
      assign axi_tree[i].bvalid = mem_xbar_in_bvalid [i];
      assign mem_xbar_in_bready  [i] = axi_tree[i].bready;
      
      assign mem_xbar_in_arid    [i] = axi_tree[i].arid;
      assign mem_xbar_in_araddr  [i] = axi_tree[i].araddr;
      assign mem_xbar_in_arsize  [i] = axi_tree[i].arsize;
      assign mem_xbar_in_arlen   [i] = axi_tree[i].arlen;
      assign mem_xbar_in_arvalid [i] = axi_tree[i].arvalid;
      assign axi_tree[i].arready = mem_xbar_in_arready [i];

      assign axi_tree[i].rid     = mem_xbar_in_rid    [i];
      assign axi_tree[i].rresp   = mem_xbar_in_rresp  [i];
      assign axi_tree[i].rvalid  = mem_xbar_in_rvalid [i];
      assign axi_tree[i].rdata   = mem_xbar_in_rdata  [i];
      assign axi_tree[i].rlast   = mem_xbar_in_rlast  [i];
      assign mem_xbar_in_rready  [i] = axi_tree[i].rready;
end

for (i=1;i<=XBAR_IN_TILES;i++) begin : xbar_in_tile

      assign mem_xbar_in_awid    [i] = axi_tree[i+XBAR_IN_TILES-1].awid;
      assign mem_xbar_in_awaddr  [i] = axi_tree[i+XBAR_IN_TILES-1].awaddr;
      assign mem_xbar_in_awsize  [i] = axi_tree[i+XBAR_IN_TILES-1].awsize;
      assign mem_xbar_in_awlen   [i] = axi_tree[i+XBAR_IN_TILES-1].awlen;
      assign mem_xbar_in_awvalid [i] = axi_tree[i+XBAR_IN_TILES-1].awvalid;
      assign axi_tree[i+XBAR_IN_TILES-1].awready = mem_xbar_in_awready [i];

      assign mem_xbar_in_wid     [i] = axi_tree[i+XBAR_IN_TILES-1].wid;
      assign mem_xbar_in_wdata   [i] = axi_tree[i+XBAR_IN_TILES-1].wdata;
      assign mem_xbar_in_wlast   [i] = axi_tree[i+XBAR_IN_TILES-1].wlast;
      assign mem_xbar_in_wstrb   [i] = axi_tree[i+XBAR_IN_TILES-1].wstrb;
      assign mem_xbar_in_wvalid  [i] = axi_tree[i+XBAR_IN_TILES-1].wvalid;
      assign axi_tree[i+XBAR_IN_TILES-1].wready  = mem_xbar_in_wready [i];

      assign axi_tree[i+XBAR_IN_TILES-1].bid    = mem_xbar_in_bid    [i];
      assign axi_tree[i+XBAR_IN_TILES-1].bresp  = mem_xbar_in_bresp  [i];
      assign axi_tree[i+XBAR_IN_TILES-1].bvalid = mem_xbar_in_bvalid [i];
      assign mem_xbar_in_bready  [i] = axi_tree[i+XBAR_IN_TILES-1].bready;
      
      assign mem_xbar_in_arid    [i] = axi_tree[i+XBAR_IN_TILES-1].arid;
      assign mem_xbar_in_araddr  [i] = axi_tree[i+XBAR_IN_TILES-1].araddr;
      assign mem_xbar_in_arsize  [i] = axi_tree[i+XBAR_IN_TILES-1].arsize;
      assign mem_xbar_in_arlen   [i] = axi_tree[i+XBAR_IN_TILES-1].arlen;
      assign mem_xbar_in_arvalid [i] = axi_tree[i+XBAR_IN_TILES-1].arvalid;
      assign axi_tree[i+XBAR_IN_TILES-1].arready = mem_xbar_in_arready [i];

      assign axi_tree[i+XBAR_IN_TILES-1].rid     = mem_xbar_in_rid    [i];
      assign axi_tree[i+XBAR_IN_TILES-1].rresp   = mem_xbar_in_rresp  [i];
      assign axi_tree[i+XBAR_IN_TILES-1].rvalid  = mem_xbar_in_rvalid [i];
      assign axi_tree[i+XBAR_IN_TILES-1].rdata   = mem_xbar_in_rdata  [i];
      assign axi_tree[i+XBAR_IN_TILES-1].rlast   = mem_xbar_in_rlast  [i];
      assign mem_xbar_in_rready  [i] = axi_tree[i+XBAR_IN_TILES-1].rready;
end

endgenerate

axi_id_t    [3:0] xbar_ddr_awid;
axi_addr_t  [3:0] xbar_ddr_awaddr;
axi_len_t   [3:0] xbar_ddr_awlen;
axi_size_t  [3:0] xbar_ddr_awsize;
logic       [3:0] xbar_ddr_awvalid;
logic       [3:0] xbar_ddr_awready;

axi_id_t    [3:0] xbar_ddr_wid;
axi_data_t  [3:0] xbar_ddr_wdata;
axi_strb_t  [3:0] xbar_ddr_wstrb;
logic       [3:0] xbar_ddr_wlast;
logic       [3:0] xbar_ddr_wvalid;
logic       [3:0] xbar_ddr_wready;

axi_id_t    [3:0] xbar_ddr_bid;
axi_resp_t  [3:0] xbar_ddr_bresp;
logic       [3:0] xbar_ddr_bvalid;
logic       [3:0] xbar_ddr_bready;

axi_id_t    [3:0] xbar_ddr_arid;
axi_addr_t  [3:0] xbar_ddr_araddr;
axi_len_t   [3:0] xbar_ddr_arlen;
axi_size_t  [3:0] xbar_ddr_arsize;
logic       [3:0] xbar_ddr_arvalid;
logic       [3:0] xbar_ddr_arready;

axi_id_t    [3:0] xbar_ddr_rid;
axi_data_t  [3:0] xbar_ddr_rdata;
axi_resp_t  [3:0] xbar_ddr_rresp;
logic       [3:0] xbar_ddr_rlast;
logic       [3:0] xbar_ddr_rvalid;
logic       [3:0] xbar_ddr_rready;

generate;
   for (i=0;i<4;i=i+1) begin
      axi_pipe 
      #(
         .STAGES(1),
         .WRITE_TOGETHER(0)
      ) DDR_PIPE (
         .clk(clk_main_a0),
         .rstn(rst_main_n_sync),

         .in(xbar_ddr_bus_p[i]),
         .out(xbar_ddr_bus[i])
      );

      assign xbar_ddr_bus_p[i].awid     = xbar_ddr_awid   [i];
      assign xbar_ddr_bus_p[i].awaddr   = xbar_ddr_awaddr [i];
      assign xbar_ddr_bus_p[i].awsize   = xbar_ddr_awsize [i];
      assign xbar_ddr_bus_p[i].awlen    = xbar_ddr_awlen  [i];
      assign xbar_ddr_bus_p[i].awvalid  = xbar_ddr_awvalid[i];
      assign xbar_ddr_awready[i] = xbar_ddr_bus_p[i].awready;

      assign xbar_ddr_bus_p[i].wid      = xbar_ddr_wid    [i];
      assign xbar_ddr_bus_p[i].wdata    = xbar_ddr_wdata  [i];
      assign xbar_ddr_bus_p[i].wlast    = xbar_ddr_wlast  [i];
      assign xbar_ddr_bus_p[i].wstrb    = xbar_ddr_wstrb  [i];
      assign xbar_ddr_bus_p[i].wvalid   = xbar_ddr_wvalid [i];
      assign xbar_ddr_wready[i]  = xbar_ddr_bus_p[i].wready;

      assign xbar_ddr_bid    [i] = xbar_ddr_bus_p[i].bid    ;
      assign xbar_ddr_bresp  [i] = xbar_ddr_bus_p[i].bresp  ;
      assign xbar_ddr_bvalid [i] = xbar_ddr_bus_p[i].bvalid ;
      assign xbar_ddr_bus_p[i].bready   = xbar_ddr_bready [i];
      
      assign xbar_ddr_bus_p[i].arid     = xbar_ddr_arid   [i];
      assign xbar_ddr_bus_p[i].araddr   = xbar_ddr_araddr [i];
      assign xbar_ddr_bus_p[i].arsize   = xbar_ddr_arsize [i];
      assign xbar_ddr_bus_p[i].arlen    = xbar_ddr_arlen  [i];
      assign xbar_ddr_bus_p[i].arvalid  = xbar_ddr_arvalid[i];
      assign xbar_ddr_arready[i] = xbar_ddr_bus_p[i].arready;

      assign xbar_ddr_rid    [i] = xbar_ddr_bus_p[i].rid    ;
      assign xbar_ddr_rresp  [i] = xbar_ddr_bus_p[i].rresp  ;
      assign xbar_ddr_rvalid [i] = xbar_ddr_bus_p[i].rvalid ;
      assign xbar_ddr_rdata  [i] = xbar_ddr_bus_p[i].rdata  ;
      assign xbar_ddr_rlast  [i] = xbar_ddr_bus_p[i].rlast  ;
      assign xbar_ddr_bus_p[i].rready   = xbar_ddr_rready [i];
   end
endgenerate

axi_xbar 
#(
   .NUM_SI(XBAR_IN_TILES + 1),
   .NUM_MI(4),
   .RESP_ID_START(10),
   .RESP_ID_PCI(15)
) MEM_XBAR (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

   .s_awid        (  mem_xbar_in_awid      ),  
   .s_awaddr      (  mem_xbar_in_awaddr    ),
   .s_awlen       (  mem_xbar_in_awlen     ),
   .s_awsize      (  mem_xbar_in_awsize    ),
   .s_awvalid     (  mem_xbar_in_awvalid   ),
   .s_awready     (  mem_xbar_in_awready   ),
   
   .s_wid         (  mem_xbar_in_wid       ),
   .s_wdata       (  mem_xbar_in_wdata     ),
   .s_wstrb       (  mem_xbar_in_wstrb     ),
   .s_wlast       (  mem_xbar_in_wlast     ),   
   .s_wvalid      (  mem_xbar_in_wvalid    ),
   .s_wready      (  mem_xbar_in_wready    ),
                             
   .s_bid         (  mem_xbar_in_bid       ),
   .s_bresp       (  mem_xbar_in_bresp     ),
   .s_bvalid      (  mem_xbar_in_bvalid    ),
   .s_bready      (  mem_xbar_in_bready    ),
                              
   .s_arid        (  mem_xbar_in_arid      ),
   .s_araddr      (  mem_xbar_in_araddr    ),   
   .s_arlen       (  mem_xbar_in_arlen     ),
   .s_arsize      (  mem_xbar_in_arsize    ),
   .s_arvalid     (  mem_xbar_in_arvalid   ),
   .s_arready     (  mem_xbar_in_arready   ),
                             
   .s_rid         (  mem_xbar_in_rid       ),
   .s_rdata       (  mem_xbar_in_rdata     ),
   .s_rresp       (  mem_xbar_in_rresp     ),
   .s_rlast       (  mem_xbar_in_rlast     ),
   .s_rvalid      (  mem_xbar_in_rvalid    ),   
   .s_rready      (  mem_xbar_in_rready    ),      

   .m_awid        (  xbar_ddr_awid      ),  
   .m_awaddr      (  xbar_ddr_awaddr    ),
   .m_awlen       (  xbar_ddr_awlen     ),
   .m_awsize      (  xbar_ddr_awsize    ),
   .m_awvalid     (  xbar_ddr_awvalid   ),
   .m_awready     (  xbar_ddr_awready   ),
   
   .m_wid         (  xbar_ddr_wid       ),
   .m_wdata       (  xbar_ddr_wdata     ),
   .m_wstrb       (  xbar_ddr_wstrb     ),
   .m_wlast       (  xbar_ddr_wlast     ),   
   .m_wvalid      (  xbar_ddr_wvalid    ),
   .m_wready      (  xbar_ddr_wready    ),
   
   .m_bid         (  xbar_ddr_bid       ),
   .m_bresp       (  xbar_ddr_bresp     ),
   .m_bvalid      (  xbar_ddr_bvalid    ),
   .m_bready      (  xbar_ddr_bready    ),
   
   .m_arid        (  xbar_ddr_arid      ),
   .m_araddr      (  xbar_ddr_araddr    ),   
   .m_arlen       (  xbar_ddr_arlen     ),
   .m_arsize      (  xbar_ddr_arsize    ),
   .m_arvalid     (  xbar_ddr_arvalid   ),
   .m_arready     (  xbar_ddr_arready   ),
   
   .m_rid         (  xbar_ddr_rid       ),
   .m_rdata       (  xbar_ddr_rdata     ),
   .m_rresp       (  xbar_ddr_rresp     ),
   .m_rlast       (  xbar_ddr_rlast     ),
   .m_rvalid      (  xbar_ddr_rvalid    ),   
   .m_rready      (  xbar_ddr_rready    ),

   .num_mem_ctrl  (  num_mem_ctrl       ),
   .rate_ctrl_r   (  rate_ctrl_r        ),
   .rate_ctrl_n   (  rate_ctrl_n        )

);

logic [31:0] ocl_global_rdata;
logic [7:0] ocl_global_raddr;

logic [31:0] axi_tree_debug_aw, axi_tree_debug_aw_d;
logic [31:0] axi_tree_debug_ar, axi_tree_debug_ar_d;
logic [31:0] axi_tree_debug_w,  axi_tree_debug_w_d;
logic [31:0] axi_tree_debug_r,  axi_tree_debug_r_d;
logic [31:0] axi_tree_debug_b,  axi_tree_debug_b_d;
logic [31:0] ddr_debug, ddr_debug_d;

logic [31:0] awcount[4];
logic [31:0] wcount[4];
logic [31:0] arcount[4];
logic [31:0] rcount[4];
logic [31:0] bcount[4];

generate
   for (i=0;i<(C_N_TILES >= 8 ? 16 : C_N_TILES*2);i++) begin
      assign axi_tree_debug_aw[i] = axi_tree[i].awvalid;
      assign axi_tree_debug_aw[i+16] = axi_tree[i].awready;
      assign axi_tree_debug_ar[i] = axi_tree[i].arvalid;
      assign axi_tree_debug_ar[i+16] = axi_tree[i].arready;
      assign axi_tree_debug_w[i] = axi_tree[i].wvalid;
      assign axi_tree_debug_w[i+16] = axi_tree[i].wready;
      assign axi_tree_debug_r[i] = axi_tree[i].rvalid;
      assign axi_tree_debug_r[i+16] = axi_tree[i].rready;
      assign axi_tree_debug_b[i] = axi_tree[i].bvalid;
      assign axi_tree_debug_b[i+16] = axi_tree[i].bready;
   end
   assign ddr_debug = {xbar_ddr_awvalid, xbar_ddr_awready, xbar_ddr_arvalid, xbar_ddr_arready, xbar_ddr_wvalid,
                        xbar_ddr_wready, xbar_ddr_rvalid, xbar_ddr_rready};

   for (i=0;i<4;i++) begin
      always_ff @(posedge clk_main_a0) begin
         if (!rst_main_n_sync) begin
            awcount[i] <= 0; arcount[i] <= 0; 
            wcount[i] <= 0; rcount[i] <= 0; bcount[i] <= 0;
         end else begin
            if (xbar_ddr_awvalid[i] & xbar_ddr_awready[i]) awcount[i] <= awcount[i] + 1;
            if (xbar_ddr_arvalid[i] & xbar_ddr_arready[i]) arcount[i] <= arcount[i] + 1;
            if (xbar_ddr_wvalid[i] & xbar_ddr_wready[i]) wcount[i] <= wcount[i] + 1;
            if (xbar_ddr_rvalid[i] & xbar_ddr_rready[i]) rcount[i] <= rcount[i] + 1;
            if (xbar_ddr_bvalid[i] & xbar_ddr_bready[i]) bcount[i] <= bcount[i] + 1;
         end
      end
   end
endgenerate
   
   lib_pipe #(
      .WIDTH(32*6),
      .STAGES(2)
   ) OCL_DEBUG_PIPE (
      .clk(clk_main_a0), 
      .rst_n(rst_main_n_sync),
      
      .in_bus ( {axi_tree_debug_aw, axi_tree_debug_ar, axi_tree_debug_w, axi_tree_debug_r, axi_tree_debug_b, ddr_debug }),
      .out_bus ({axi_tree_debug_aw_d, axi_tree_debug_ar_d, axi_tree_debug_w_d, axi_tree_debug_r_d, axi_tree_debug_b_d, ddr_debug_d})
   ); 

ocl_arbiter OCL_ARBITER (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .ocl(sh_ocl_bus_q), // from SH
   
   .ocl_awvalid   (ocl_awvalid),
   .ocl_awready   (ocl_awready),
   .ocl_awaddr    (ocl_awaddr ),
   
   .ocl_wvalid    (ocl_wvalid ),
   .ocl_wready    (ocl_wready ),
   .ocl_wdata     (ocl_wdata  ),

   .ocl_bvalid    (ocl_bvalid ),
   .ocl_bready    (ocl_bready ),

   .ocl_arvalid   (ocl_arvalid),
   .ocl_arready   (ocl_arready),
   .ocl_araddr    (ocl_araddr ),

   .ocl_rvalid    (ocl_rvalid ),
   .ocl_rdata     (ocl_rdata  ),
   .ocl_rready    (ocl_rready ),

   .num_mem_ctrl   (num_mem_ctrl),
   .rate_ctrl_r    (rate_ctrl_r ),
   .rate_ctrl_n    (rate_ctrl_n ),

   .ocl_global_raddr (ocl_global_raddr),
   .ocl_global_rdata (ocl_global_rdata)
);

always_ff @(posedge clk_main_a0) begin
   case (ocl_global_raddr) 
      DEBUG_CAPACITY : ocl_global_rdata <= pci_log_size;
      8'h0 : ocl_global_rdata <= axi_tree_debug_aw_d; 
      8'h4 : ocl_global_rdata <= axi_tree_debug_ar_d; 
      8'h8 : ocl_global_rdata <= axi_tree_debug_w_d; 
      8'hc : ocl_global_rdata <= axi_tree_debug_r_d; 
      8'h10 : ocl_global_rdata <= axi_tree_debug_b_d; 
      8'h14 : ocl_global_rdata <= ddr_debug_d; 
      8'h20, 8'h24, 8'h28, 8'h2c : ocl_global_rdata <= awcount[ocl_global_raddr[3:2]];
      8'h30, 8'h34, 8'h38, 8'h3c : ocl_global_rdata <= arcount[ocl_global_raddr[3:2]];
      8'h40, 8'h44, 8'h48, 8'h4c : ocl_global_rdata <= wcount[ocl_global_raddr[3:2]];
      8'h50, 8'h54, 8'h58, 8'h5c : ocl_global_rdata <= rcount[ocl_global_raddr[3:2]];
      8'h60, 8'h64, 8'h68, 8'h6c : ocl_global_rdata <= bcount[ocl_global_raddr[3:2]];
   endcase
end

   lib_pipe #(
      .WIDTH(N_TILES+8+8),
      .STAGES(2)
   ) PCI_DEBUG_AR_PIPE (
      .clk(clk_main_a0), 
      .rst_n(rst_main_n_sync),
      
      .in_bus ( {pci_debug_arvalid  , pci_debug_arlen  , pci_debug_comp  } ),
      .out_bus( {pci_debug_arvalid_q, pci_debug_arlen_q, pci_debug_comp_q} )
   ); 

generate;
for (i=0;i<N_TILES;i=i+1) begin
   assign pci_debug[i].arvalid = pci_debug_arvalid_q[i];
   assign pci_debug[i].arlen  = pci_debug_arlen_q;

   register_slice
   #(
      .WIDTH(512+1),
      .STAGES(2)
   )
   R_SLICE (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),
      // slave at the tile, master at the Arbiter
      .s_valid(pci_debug[i].rvalid),
      .s_ready(pci_debug[i].rready),
      
      .m_valid(pci_debug_rvalid[i]),
      .m_ready(pci_debug_rready),

      .s_data( {pci_debug[i].rdata, pci_debug[i].rlast}),
      .m_data( {pci_debug_rdata[i], pci_debug_rlast[i]})

   );
   
   assign ocl[i].awvalid = ocl_awvalid[i];
   assign ocl_awready[i] = ocl[i].awready;
   assign ocl[i].awaddr = ocl_awaddr;
   assign ocl[i].awlen = 0;
   assign ocl[i].awsize = 2;
   
   assign ocl[i].wvalid = ocl_wvalid[i];
   assign ocl_wready[i] = ocl[i].wready;
   assign ocl[i].wdata = ocl_wdata;

   assign ocl_bvalid[i] = ocl[i].bvalid;
   assign ocl[i].bready = ocl_bready;

   assign ocl[i].arvalid = ocl_arvalid[i];
   assign ocl_arready[i] = ocl[i].arready;
   assign ocl[i].araddr = ocl_araddr;
   assign ocl[i].arlen = 0;
   assign ocl[i].arsize = 2;

   assign ocl_rvalid[i] = ocl[i].rvalid;
   assign ocl_rdata[i] = ocl[i].rdata;
   assign ocl[i].rready = ocl_rready;
      
   axi_pipe 
   #(
      .STAGES(2),
      .WRITE_TOGETHER(0)
   ) OCL_PIPE (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),

      .in(ocl[i]),
      .out(ocl_q[i])
   );
end
endgenerate

vt_t [C_N_TILES-1:0] lvt;
vt_t gvt;

gvt_arbiter GVT_ARBITER (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .lvt(lvt),
   .gvt(gvt)
);

generate 
for (i=0;i<N_TILES;i++) begin : tile
   tile
   #( 
      .TILE_ID(i)
   ) TILE (
      .clk_main_a0(clk_main_a0),
      .rst_main_n_sync_p(rst_main_n_sync),

      .mem_bus(tile_mem[i]),

      .ocl_bus(ocl_q[i]),

      .task_enq_in (task_enq_req_out[i]),
      .task_enq_out(task_enq_req_in [i]),
      
      .task_resp_in (task_enq_resp_out[i]),
      .task_resp_out(task_enq_resp_in [i]),
      
      .abort_child_in (abort_child_req_out[i]),
      .abort_child_out(abort_child_req_in [i]),

      .abort_resp_in (abort_child_resp_out[i]),
      .abort_resp_out(abort_child_resp_in [i]),
      
      .cut_ties_in (cut_ties_req_out[i]),
      .cut_ties_out(cut_ties_req_in [i]),
      
      .pci_debug_in(pci_debug[i]),
      .pci_debug_comp(pci_debug_comp),

      .lvt(lvt[i]),
      .gvt(gvt)
   );
end
for (i=N_TILES; i<C_N_TILES;i++) begin
  assign lvt[i] = '1;
end
endgenerate


pci_arbiter PCI_ARBITER (
   .clk(clk_main_a0),
   .rstn(rst_main_n_sync),

   .pci(sh_cl_dma_pcis_bus_q),

   .pci_debug_arvalid   (pci_debug_arvalid),
   .pci_debug_arlen     (pci_debug_arlen),
   .pci_debug_rready    (pci_debug_rready),
   .pci_debug_rdata     (pci_debug_rdata),
   .pci_debug_rvalid    (pci_debug_rvalid),
   .pci_debug_rlast     (pci_debug_rlast),

   .pci_debug_comp(pci_debug_comp),

   .mem(pci_arb_mem_arb_bus),
   .ddr_snoop      (xbar_ddr_bus[2]),

   .pci_log_size(pci_log_size)
);

axi_decoder #(
   .ID_BASE(0),
   .IN_TILE(0)
) pci_decoder (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

  .core(pci_arb_mem_arb_bus),
  .l2(axi_tree_0_p)
);
   
axi_pipe 
#(
  .STAGES(1)
) PCI_OUT_PIPE (
  .clk(clk_main_a0),
  .rstn(rst_main_n_sync),

  .in(axi_tree_0_p),
  .out(axi_tree[0])
);


`ifdef SIMPLE_MEMORY
generate 
for (i=0;i<4;i++) begin : mem_ctrl
   mem_ctrl MEM_CTRL (
      .clk(clk_main_a0),
      .rstn(rst_main_n_sync),

      .axi(xbar_ddr_bus[i])
   );
end
endgenerate
`else 
  assign cl_sh_ddr_awid     = xbar_ddr_bus[2].awid;
  assign cl_sh_ddr_awaddr   = xbar_ddr_bus[2].awaddr;
  assign cl_sh_ddr_awlen    = xbar_ddr_bus[2].awlen;
  assign cl_sh_ddr_awsize   = xbar_ddr_bus[2].awsize;
  assign cl_sh_ddr_awvalid  = xbar_ddr_bus[2].awvalid;
  assign xbar_ddr_bus[2].awready= sh_cl_ddr_awready;

  assign cl_sh_ddr_wid      = xbar_ddr_bus[2].wid;
  assign cl_sh_ddr_wdata    = xbar_ddr_bus[2].wdata;
  assign cl_sh_ddr_wstrb    = xbar_ddr_bus[2].wstrb;
  assign cl_sh_ddr_wlast    = xbar_ddr_bus[2].wlast;
  assign cl_sh_ddr_wvalid   = xbar_ddr_bus[2].wvalid;
  assign xbar_ddr_bus[2].wready = sh_cl_ddr_wready;
   
  assign cl_sh_ddr_bready   = xbar_ddr_bus[2].bready;
  assign xbar_ddr_bus[2].bid    = sh_cl_ddr_bid;
  assign xbar_ddr_bus[2].bvalid = sh_cl_ddr_bvalid;
  assign xbar_ddr_bus[2].bresp  = sh_cl_ddr_bresp;

  assign cl_sh_ddr_arid     = xbar_ddr_bus[2].arid;
  assign cl_sh_ddr_araddr   = xbar_ddr_bus[2].araddr;
  assign cl_sh_ddr_arlen    = xbar_ddr_bus[2].arlen;
  assign cl_sh_ddr_arsize   = xbar_ddr_bus[2].arsize;
  assign cl_sh_ddr_arvalid  = xbar_ddr_bus[2].arvalid;
  assign xbar_ddr_bus[2].arready= sh_cl_ddr_arready;

  assign cl_sh_ddr_rready   = xbar_ddr_bus[2].rready;
  assign xbar_ddr_bus[2].rid    = sh_cl_ddr_rid;
  assign xbar_ddr_bus[2].rresp  = sh_cl_ddr_rresp;
  assign xbar_ddr_bus[2].rdata  = sh_cl_ddr_rdata;
  assign xbar_ddr_bus[2].rlast  = sh_cl_ddr_rlast;
  assign xbar_ddr_bus[2].rvalid = sh_cl_ddr_rvalid;

//----------------------------------------- 
// DDR controller instantiation   
//-----------------------------------------
logic clk;

logic [2:0] lcl_sh_cl_ddr_is_ready;

//---------------------------- 
// End Internal signals
//----------------------------

assign clk = clk_main_a0;
   
logic [7:0] sh_ddr_stat_addr_q[2:0];
logic[2:0] sh_ddr_stat_wr_q;
logic[2:0] sh_ddr_stat_rd_q; 
logic[31:0] sh_ddr_stat_wdata_q[2:0];
logic[2:0] ddr_sh_stat_ack_q;
logic[31:0] ddr_sh_stat_rdata_q[2:0];
logic[7:0] ddr_sh_stat_int_q[2:0];

localparam NUM_CFG_STGS_CL_DDR_ATG=8;
lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT0 (.clk(clk), .rst_n(rst_main_n_sync),
                                               .in_bus({sh_ddr_stat_wr0, sh_ddr_stat_rd0, sh_ddr_stat_addr0, sh_ddr_stat_wdata0}),
                                               .out_bus({sh_ddr_stat_wr_q[0], sh_ddr_stat_rd_q[0], sh_ddr_stat_addr_q[0], sh_ddr_stat_wdata_q[0]})
                                               );


lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK0 (.clk(clk), .rst_n(rst_main_n_sync),
                                               .in_bus({ddr_sh_stat_ack_q[0], ddr_sh_stat_int_q[0], ddr_sh_stat_rdata_q[0]}),
                                               .out_bus({ddr_sh_stat_ack0, ddr_sh_stat_int0, ddr_sh_stat_rdata0})
                                               );


lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT1 (.clk(clk), .rst_n(rst_main_n_sync),
                                               .in_bus({sh_ddr_stat_wr1, sh_ddr_stat_rd1, sh_ddr_stat_addr1, sh_ddr_stat_wdata1}),
                                               .out_bus({sh_ddr_stat_wr_q[1], sh_ddr_stat_rd_q[1], sh_ddr_stat_addr_q[1], sh_ddr_stat_wdata_q[1]})
                                               );


lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK1 (.clk(clk), .rst_n(rst_main_n_sync),
                                               .in_bus({ddr_sh_stat_ack_q[1], ddr_sh_stat_int_q[1], ddr_sh_stat_rdata_q[1]}),
                                               .out_bus({ddr_sh_stat_ack1, ddr_sh_stat_int1, ddr_sh_stat_rdata1})
                                               );

lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT2 (.clk(clk), .rst_n(rst_main_n_sync),
                                               .in_bus({sh_ddr_stat_wr2, sh_ddr_stat_rd2, sh_ddr_stat_addr2, sh_ddr_stat_wdata2}),
                                               .out_bus({sh_ddr_stat_wr_q[2], sh_ddr_stat_rd_q[2], sh_ddr_stat_addr_q[2], sh_ddr_stat_wdata_q[2]})
                                               );


lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK2 (.clk(clk), .rst_n(rst_main_n_sync),
                                               .in_bus({ddr_sh_stat_ack_q[2], ddr_sh_stat_int_q[2], ddr_sh_stat_rdata_q[2]}),
                                               .out_bus({ddr_sh_stat_ack2, ddr_sh_stat_int2, ddr_sh_stat_rdata2})
                                               ); 

//convert to 2D 
logic[15:0] cl_sh_ddr_awid_2d[2:0];
logic[63:0] cl_sh_ddr_awaddr_2d[2:0];
logic[7:0] cl_sh_ddr_awlen_2d[2:0];
logic[2:0] cl_sh_ddr_awsize_2d[2:0];
logic cl_sh_ddr_awvalid_2d [2:0];
logic[2:0] sh_cl_ddr_awready_2d;

logic[15:0] cl_sh_ddr_wid_2d[2:0];
logic[511:0] cl_sh_ddr_wdata_2d[2:0];
logic[63:0] cl_sh_ddr_wstrb_2d[2:0];
logic[2:0] cl_sh_ddr_wlast_2d;
logic[2:0] cl_sh_ddr_wvalid_2d;
logic[2:0] sh_cl_ddr_wready_2d;

logic[15:0] sh_cl_ddr_bid_2d[2:0];
logic[1:0] sh_cl_ddr_bresp_2d[2:0];
logic[2:0] sh_cl_ddr_bvalid_2d;
logic[2:0] cl_sh_ddr_bready_2d;

logic[15:0] cl_sh_ddr_arid_2d[2:0];
logic[63:0] cl_sh_ddr_araddr_2d[2:0];
logic[7:0] cl_sh_ddr_arlen_2d[2:0];
logic[2:0] cl_sh_ddr_arsize_2d[2:0];
logic[2:0] cl_sh_ddr_arvalid_2d;
logic[2:0] sh_cl_ddr_arready_2d;

logic[15:0] sh_cl_ddr_rid_2d[2:0];
logic[511:0] sh_cl_ddr_rdata_2d[2:0];
logic[1:0] sh_cl_ddr_rresp_2d[2:0];
logic[2:0] sh_cl_ddr_rlast_2d;
logic[2:0] sh_cl_ddr_rvalid_2d;
logic[2:0] cl_sh_ddr_rready_2d;

assign cl_sh_ddr_awid_2d = '{xbar_ddr_bus[3].awid, xbar_ddr_bus[1].awid, xbar_ddr_bus[0].awid};
assign cl_sh_ddr_awaddr_2d = '{xbar_ddr_bus[3].awaddr, xbar_ddr_bus[1].awaddr, xbar_ddr_bus[0].awaddr};
assign cl_sh_ddr_awlen_2d = '{xbar_ddr_bus[3].awlen, xbar_ddr_bus[1].awlen, xbar_ddr_bus[0].awlen};
assign cl_sh_ddr_awsize_2d = '{xbar_ddr_bus[3].awsize, xbar_ddr_bus[1].awsize, xbar_ddr_bus[0].awsize};
assign cl_sh_ddr_awvalid_2d = '{xbar_ddr_bus[3].awvalid, xbar_ddr_bus[1].awvalid, xbar_ddr_bus[0].awvalid};
assign {xbar_ddr_bus[3].awready, xbar_ddr_bus[1].awready, xbar_ddr_bus[0].awready} = sh_cl_ddr_awready_2d;

assign cl_sh_ddr_wid_2d = '{xbar_ddr_bus[3].wid, xbar_ddr_bus[1].wid, xbar_ddr_bus[0].wid};
assign cl_sh_ddr_wdata_2d = '{xbar_ddr_bus[3].wdata, xbar_ddr_bus[1].wdata, xbar_ddr_bus[0].wdata};
assign cl_sh_ddr_wstrb_2d = '{xbar_ddr_bus[3].wstrb, xbar_ddr_bus[1].wstrb, xbar_ddr_bus[0].wstrb};
assign cl_sh_ddr_wlast_2d = {xbar_ddr_bus[3].wlast, xbar_ddr_bus[1].wlast, xbar_ddr_bus[0].wlast};
assign cl_sh_ddr_wvalid_2d = {xbar_ddr_bus[3].wvalid, xbar_ddr_bus[1].wvalid, xbar_ddr_bus[0].wvalid};
assign {xbar_ddr_bus[3].wready, xbar_ddr_bus[1].wready, xbar_ddr_bus[0].wready} = sh_cl_ddr_wready_2d;

assign {xbar_ddr_bus[3].bid, xbar_ddr_bus[1].bid, xbar_ddr_bus[0].bid} = {sh_cl_ddr_bid_2d[2], sh_cl_ddr_bid_2d[1], sh_cl_ddr_bid_2d[0]};
assign {xbar_ddr_bus[3].bresp, xbar_ddr_bus[1].bresp, xbar_ddr_bus[0].bresp} = {sh_cl_ddr_bresp_2d[2], sh_cl_ddr_bresp_2d[1], sh_cl_ddr_bresp_2d[0]};
assign {xbar_ddr_bus[3].bvalid, xbar_ddr_bus[1].bvalid, xbar_ddr_bus[0].bvalid} = sh_cl_ddr_bvalid_2d;
assign cl_sh_ddr_bready_2d = {xbar_ddr_bus[3].bready, xbar_ddr_bus[1].bready, xbar_ddr_bus[0].bready};

assign cl_sh_ddr_arid_2d = '{xbar_ddr_bus[3].arid, xbar_ddr_bus[1].arid, xbar_ddr_bus[0].arid};
assign cl_sh_ddr_araddr_2d = '{xbar_ddr_bus[3].araddr, xbar_ddr_bus[1].araddr, xbar_ddr_bus[0].araddr};
assign cl_sh_ddr_arlen_2d = '{xbar_ddr_bus[3].arlen, xbar_ddr_bus[1].arlen, xbar_ddr_bus[0].arlen};
assign cl_sh_ddr_arsize_2d = '{xbar_ddr_bus[3].arsize, xbar_ddr_bus[1].arsize, xbar_ddr_bus[0].arsize};
assign cl_sh_ddr_arvalid_2d = {xbar_ddr_bus[3].arvalid, xbar_ddr_bus[1].arvalid, xbar_ddr_bus[0].arvalid};
assign {xbar_ddr_bus[3].arready, xbar_ddr_bus[1].arready, xbar_ddr_bus[0].arready} = sh_cl_ddr_arready_2d;

assign {xbar_ddr_bus[3].rid, xbar_ddr_bus[1].rid, xbar_ddr_bus[0].rid} = {sh_cl_ddr_rid_2d[2], sh_cl_ddr_rid_2d[1], sh_cl_ddr_rid_2d[0]};
assign {xbar_ddr_bus[3].rresp, xbar_ddr_bus[1].rresp, xbar_ddr_bus[0].rresp} = {sh_cl_ddr_rresp_2d[2], sh_cl_ddr_rresp_2d[1], sh_cl_ddr_rresp_2d[0]};
assign {xbar_ddr_bus[3].rdata, xbar_ddr_bus[1].rdata, xbar_ddr_bus[0].rdata} = {sh_cl_ddr_rdata_2d[2], sh_cl_ddr_rdata_2d[1], sh_cl_ddr_rdata_2d[0]};
assign {xbar_ddr_bus[3].rlast, xbar_ddr_bus[1].rlast, xbar_ddr_bus[0].rlast} = sh_cl_ddr_rlast_2d;
assign {xbar_ddr_bus[3].rvalid, xbar_ddr_bus[1].rvalid, xbar_ddr_bus[0].rvalid} = sh_cl_ddr_rvalid_2d;
assign cl_sh_ddr_rready_2d = {xbar_ddr_bus[3].rready, xbar_ddr_bus[1].rready, xbar_ddr_bus[0].rready};

(* dont_touch = "true" *) logic sh_ddr_sync_rst_n;
lib_pipe #(.WIDTH(1), .STAGES(4)) SH_DDR_SLC_RST_N (.clk(clk_main_a0), .rst_n(1'b1), .in_bus(rst_main_n_sync), .out_bus(sh_ddr_sync_rst_n));
sh_ddr #(
         .DDR_A_PRESENT( (N_DDR_CTRL > 2) ? 1 : 0),
         .DDR_A_IO(1),
         .DDR_B_PRESENT( (N_DDR_CTRL > 2) ? 1 : 0),
         .DDR_D_PRESENT( (N_DDR_CTRL > 1) ? 1 : 0)
   ) SH_DDR
   (
   .clk(clk_main_a0),
   .rst_n(sh_ddr_sync_rst_n),

   .stat_clk(clk),
   .stat_rst_n(sh_ddr_sync_rst_n),


   .CLK_300M_DIMM0_DP(CLK_300M_DIMM0_DP),
   .CLK_300M_DIMM0_DN(CLK_300M_DIMM0_DN),
   .M_A_ACT_N(M_A_ACT_N),
   .M_A_MA(M_A_MA),
   .M_A_BA(M_A_BA),
   .M_A_BG(M_A_BG),
   .M_A_CKE(M_A_CKE),
   .M_A_ODT(M_A_ODT),
   .M_A_CS_N(M_A_CS_N),
   .M_A_CLK_DN(M_A_CLK_DN),
   .M_A_CLK_DP(M_A_CLK_DP),
   .M_A_PAR(M_A_PAR),
   .M_A_DQ(M_A_DQ),
   .M_A_ECC(M_A_ECC),
   .M_A_DQS_DP(M_A_DQS_DP),
   .M_A_DQS_DN(M_A_DQS_DN),
   .cl_RST_DIMM_A_N(cl_RST_DIMM_A_N),
   
   
   .CLK_300M_DIMM1_DP(CLK_300M_DIMM1_DP),
   .CLK_300M_DIMM1_DN(CLK_300M_DIMM1_DN),
   .M_B_ACT_N(M_B_ACT_N),
   .M_B_MA(M_B_MA),
   .M_B_BA(M_B_BA),
   .M_B_BG(M_B_BG),
   .M_B_CKE(M_B_CKE),
   .M_B_ODT(M_B_ODT),
   .M_B_CS_N(M_B_CS_N),
   .M_B_CLK_DN(M_B_CLK_DN),
   .M_B_CLK_DP(M_B_CLK_DP),
   .M_B_PAR(M_B_PAR),
   .M_B_DQ(M_B_DQ),
   .M_B_ECC(M_B_ECC),
   .M_B_DQS_DP(M_B_DQS_DP),
   .M_B_DQS_DN(M_B_DQS_DN),
   .cl_RST_DIMM_B_N(cl_RST_DIMM_B_N),

   .CLK_300M_DIMM3_DP(CLK_300M_DIMM3_DP),
   .CLK_300M_DIMM3_DN(CLK_300M_DIMM3_DN),
   .M_D_ACT_N(M_D_ACT_N),
   .M_D_MA(M_D_MA),
   .M_D_BA(M_D_BA),
   .M_D_BG(M_D_BG),
   .M_D_CKE(M_D_CKE),
   .M_D_ODT(M_D_ODT),
   .M_D_CS_N(M_D_CS_N),
   .M_D_CLK_DN(M_D_CLK_DN),
   .M_D_CLK_DP(M_D_CLK_DP),
   .M_D_PAR(M_D_PAR),
   .M_D_DQ(M_D_DQ),
   .M_D_ECC(M_D_ECC),
   .M_D_DQS_DP(M_D_DQS_DP),
   .M_D_DQS_DN(M_D_DQS_DN),
   .cl_RST_DIMM_D_N(cl_RST_DIMM_D_N),

   //------------------------------------------------------
   // DDR-4 Interface from CL (AXI-4)
   //------------------------------------------------------
   .cl_sh_ddr_awid(cl_sh_ddr_awid_2d),
   .cl_sh_ddr_awaddr(cl_sh_ddr_awaddr_2d),
   .cl_sh_ddr_awlen(cl_sh_ddr_awlen_2d),
   .cl_sh_ddr_awsize(cl_sh_ddr_awsize_2d),
   .cl_sh_ddr_awvalid(cl_sh_ddr_awvalid_2d),
   .sh_cl_ddr_awready(sh_cl_ddr_awready_2d),

   .cl_sh_ddr_wid(cl_sh_ddr_wid_2d),
   .cl_sh_ddr_wdata(cl_sh_ddr_wdata_2d),
   .cl_sh_ddr_wstrb(cl_sh_ddr_wstrb_2d),
   .cl_sh_ddr_wlast(cl_sh_ddr_wlast_2d),
   .cl_sh_ddr_wvalid(cl_sh_ddr_wvalid_2d),
   .sh_cl_ddr_wready(sh_cl_ddr_wready_2d),

   .sh_cl_ddr_bid(sh_cl_ddr_bid_2d),
   .sh_cl_ddr_bresp(sh_cl_ddr_bresp_2d),
   .sh_cl_ddr_bvalid(sh_cl_ddr_bvalid_2d),
   .cl_sh_ddr_bready(cl_sh_ddr_bready_2d),

   .cl_sh_ddr_arid(cl_sh_ddr_arid_2d),
   .cl_sh_ddr_araddr(cl_sh_ddr_araddr_2d),
   .cl_sh_ddr_arlen(cl_sh_ddr_arlen_2d),
   .cl_sh_ddr_arsize(cl_sh_ddr_arsize_2d),
   .cl_sh_ddr_arvalid(cl_sh_ddr_arvalid_2d),
   .sh_cl_ddr_arready(sh_cl_ddr_arready_2d),

   .sh_cl_ddr_rid(sh_cl_ddr_rid_2d),
   .sh_cl_ddr_rdata(sh_cl_ddr_rdata_2d),
   .sh_cl_ddr_rresp(sh_cl_ddr_rresp_2d),
   .sh_cl_ddr_rlast(sh_cl_ddr_rlast_2d),
   .sh_cl_ddr_rvalid(sh_cl_ddr_rvalid_2d),
   .cl_sh_ddr_rready(cl_sh_ddr_rready_2d),

   .sh_cl_ddr_is_ready(lcl_sh_cl_ddr_is_ready),

   .sh_ddr_stat_addr0  (sh_ddr_stat_addr_q[0]) ,
   .sh_ddr_stat_wr0    (sh_ddr_stat_wr_q[0]     ) , 
   .sh_ddr_stat_rd0    (sh_ddr_stat_rd_q[0]     ) , 
   .sh_ddr_stat_wdata0 (sh_ddr_stat_wdata_q[0]  ) , 
   .ddr_sh_stat_ack0   (ddr_sh_stat_ack_q[0]    ) ,
   .ddr_sh_stat_rdata0 (ddr_sh_stat_rdata_q[0]  ),
   .ddr_sh_stat_int0   (ddr_sh_stat_int_q[0]    ),

   .sh_ddr_stat_addr1  (sh_ddr_stat_addr_q[1]) ,
   .sh_ddr_stat_wr1    (sh_ddr_stat_wr_q[1]     ) , 
   .sh_ddr_stat_rd1    (sh_ddr_stat_rd_q[1]     ) , 
   .sh_ddr_stat_wdata1 (sh_ddr_stat_wdata_q[1]  ) , 
   .ddr_sh_stat_ack1   (ddr_sh_stat_ack_q[1]    ) ,
   .ddr_sh_stat_rdata1 (ddr_sh_stat_rdata_q[1]  ),
   .ddr_sh_stat_int1   (ddr_sh_stat_int_q[1]    ),

   .sh_ddr_stat_addr2  (sh_ddr_stat_addr_q[2]) ,
   .sh_ddr_stat_wr2    (sh_ddr_stat_wr_q[2]     ) , 
   .sh_ddr_stat_rd2    (sh_ddr_stat_rd_q[2]     ) , 
   .sh_ddr_stat_wdata2 (sh_ddr_stat_wdata_q[2]  ) , 
   .ddr_sh_stat_ack2   (ddr_sh_stat_ack_q[2]    ) ,
   .ddr_sh_stat_rdata2 (ddr_sh_stat_rdata_q[2]  ),
   .ddr_sh_stat_int2   (ddr_sh_stat_int_q[2]    ) 
   );
`endif

assign cl_sh_status_vled = 0;


//-------------------------------------------
// Tie-Off Global Signals
//-------------------------------------------
`ifndef CL_VERSION
   `define CL_VERSION 32'hee_ee_ee_00
`endif  


  assign cl_sh_status0[31:0] =  32'h0000_0FF0;
  assign cl_sh_status1[31:0] = `CL_VERSION;
//-------------------------------------------------
// ID Values (cl_hello_world_defines.vh)
//-------------------------------------------------
  assign cl_sh_id0[31:0] = `CL_SH_ID0;
  assign cl_sh_id1[31:0] = `CL_SH_ID1;




endmodule





