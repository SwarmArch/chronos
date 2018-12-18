//---------------------------------------------------------------------------------------
// Amazon FPGA Hardware Development Kit
//
// Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.
//---------------------------------------------------------------------------------------

//-----------------------------------------------------------------------------------------------------
// Note please see the Shell Interface Specification for more details on the interfaces:
//
//  https://github.com/aws/aws-fpga/blob/master/hdk/docs/AWS_Shell_Interface_Specification.md
//
//-----------------------------------------------------------------------------------------------------

   //--------------------------------
   // Globals
   //--------------------------------
   output logic clk_main_a0,                           //Main clock.  This is the clock for all of the interfaces to the SH
   output logic clk_extra_a1,                          //Extra clock A1 (phase aligned to "A" clock group)
   output logic clk_extra_a2,                          //Extra clock A2 (phase aligned to "A" clock group)
   output logic clk_extra_a3,                          //Extra clock A3 (phase aligned to "A" clock group)
   
   output logic clk_extra_b0,                          //Extra clock B0 (phase aligned to "B" clock group)
   output logic clk_extra_b1,                          //Extra clock B1 (phase aligned to "B" clock group)
   
   output logic clk_extra_c0,                          //Extra clock C0 (phase aligned to "B" clock group)
   output logic clk_extra_c1,                          //Extra clock C1 (phase aligned to "B" clock group)
   
   output logic kernel_rst_n,                          //Kernel reset (for SDA platform)
     
   output logic rst_main_n,                            //Reset sync'ed to main clock.

   output logic sh_cl_flr_assert,                      //Function level reset assertion.  Level signal that indicates PCIe function level reset is asserted 
   input logic  cl_sh_flr_done,                 //Function level reset done indication.  Must be asserted by CL when done processing function level reset.
         
   input logic [31:0] cl_sh_status0,            //Functionality TBD
   input logic [31:0] cl_sh_status1,            //Functionality TBD
   input logic [31:0] cl_sh_id0,                //15:0 - PCI Vendor ID
                                                //31:16 - PCI Device ID

   input logic [31:0] cl_sh_id1,                //15:0 - PCI Subsystem Vendor ID
                                                //31:16 - PCI Subsystem ID

   output logic[31:0] sh_cl_ctl0,                      //Functionality TBD
   output logic[31:0] sh_cl_ctl1,                      //Functionality TBD

   output logic[15:0] sh_cl_status_vdip,               //Virtual DIP switches.  Controlled through FPGA management PF and tools.
   input logic [15:0] cl_sh_status_vled,        //Virtual LEDs, monitored through FPGA management PF and tools

   output logic[1:0] sh_cl_pwr_state,               	  //Power state, 2'b00: Normal, 2'b11: Critical
  
   // These signals relate to the dma_pcis interface (BAR4). They should be
   // asserted when the CL is running out of resources and will not be able
   // to accept certain types of transactions.
   input logic    cl_sh_dma_wr_full,              // Resources low for dma writes  (DMA_PCIS AXI ID: 0x00-0x03)
   input logic    cl_sh_dma_rd_full,              // Resources low for dma reads   (DMA_PCIS AXI ID: 0x00-0x03)

   //-------------------------------------------------------------------------------------------
   // PCIe Master interface from CL
   //
   //    AXI-4 master interface per PCIe interface.  This is for PCIe transactions mastered
   //    from the SH targetting the host (DMA access to host).  Standard AXI-4 interface.
   //-------------------------------------------------------------------------------------------
   input logic [15:0] cl_sh_pcim_awid,
   input logic [63:0] cl_sh_pcim_awaddr,
   input logic [7:0] cl_sh_pcim_awlen,
   input logic [2:0] cl_sh_pcim_awsize,
   input logic [18:0] cl_sh_pcim_awuser,                             //RESERVED (not used)
								
   input logic  cl_sh_pcim_awvalid,
   output logic sh_cl_pcim_awready,
   
   input logic [511:0] cl_sh_pcim_wdata,
   input logic [63:0] cl_sh_pcim_wstrb,
   input logic  cl_sh_pcim_wlast,
   input logic  cl_sh_pcim_wvalid,
   output logic sh_cl_pcim_wready,
   
   output logic [15:0] sh_cl_pcim_bid,
   output logic [1:0] sh_cl_pcim_bresp,
   output logic  sh_cl_pcim_bvalid,
   input logic  cl_sh_pcim_bready,
  
   input logic [15:0] cl_sh_pcim_arid,		                           //Note max 32 outstanding txns are supported, width is larger to allow bits for AXI fabrics
   input logic [63:0] cl_sh_pcim_araddr,
   input logic [7:0] cl_sh_pcim_arlen,
   input logic [2:0] cl_sh_pcim_arsize,
   input logic [18:0] cl_sh_pcim_aruser,                             // RESERVED (not used)

   input logic  cl_sh_pcim_arvalid,
   output logic sh_cl_pcim_arready,
   
   output logic[15:0] sh_cl_pcim_rid,
   output logic[511:0] sh_cl_pcim_rdata,
   output logic[1:0] sh_cl_pcim_rresp,
   output logic sh_cl_pcim_rlast,
   output logic sh_cl_pcim_rvalid,
   input logic  cl_sh_pcim_rready,

   output logic[1:0] cfg_max_payload,                                    //Max payload size - 00:128B, 01:256B, 10:512B
   output logic[2:0] cfg_max_read_req                                    //Max read requst size - 000b:128B, 001b:256B, 010b:512B, 011b:1024B
                                                                  // 100b-2048B, 101b:4096B
   
   //-----------------------------------------------------------------------------------------------
   // DDR-4 Interface 
   //
   //    x3 DDR is instantiated in CL.  This is the physical interface (fourth DDR is in SH)
   //    These interfaces must be connected to an instantiated sh_ddr in the CL logic.
   //    Note even if DDR interfaces are not used, sh_ddr must be instantiated and connected
   //    to these interface ports. The sh_ddr block has parameters to control which DDR 
   //    controllers are instantiated.  If a DDR controller is not instantiated it will not
   //    take up FPGA resources.
   //-----------------------------------------------------------------------------------------------
`ifndef NO_CL_DDR
  ,
// ------------------- DDR4 x72 RDIMM 2100 Interface A ----------------------------------
   output logic                CLK_300M_DIMM0_DP,
   output logic                CLK_300M_DIMM0_DN,
   input logic               M_A_ACT_N,
   input logic [16:0]        M_A_MA,
   input logic [1:0]         M_A_BA,
   input logic [1:0]         M_A_BG,
   input logic [0:0]         M_A_CKE,
   input logic [0:0]         M_A_ODT,
   input logic [0:0]         M_A_CS_N,
   input logic [0:0]         M_A_CLK_DN,
   input logic [0:0]         M_A_CLK_DP,
   input logic               M_A_PAR,
   inout  [63:0]        M_A_DQ,
   inout  [7:0]         M_A_ECC,
   inout  [17:0]        M_A_DQS_DP,
   inout  [17:0]        M_A_DQS_DN,
   input logic               cl_RST_DIMM_A_N,

// ------------------- DDR4 x72 RDIMM 2100 Interface B ----------------------------------
   output logic                CLK_300M_DIMM1_DP,
   output logic                CLK_300M_DIMM1_DN,
   input logic               M_B_ACT_N,
   input logic [16:0]        M_B_MA,
   input logic [1:0]         M_B_BA,
   input logic [1:0]         M_B_BG,
   input logic [0:0]         M_B_CKE,
   input logic [0:0]         M_B_ODT,
   input logic [0:0]         M_B_CS_N,
   input logic [0:0]         M_B_CLK_DN,
   input logic [0:0]         M_B_CLK_DP,
   input logic               M_B_PAR,
   inout  [63:0]        M_B_DQ,
   inout  [7:0]         M_B_ECC,
   inout  [17:0]        M_B_DQS_DP,
   inout  [17:0]        M_B_DQS_DN,
   input logic               cl_RST_DIMM_B_N,


// ------------------- DDR4 x72 RDIMM 2100 Interface D ----------------------------------
   output logic                CLK_300M_DIMM3_DP,
   output logic                CLK_300M_DIMM3_DN,
   input logic               M_D_ACT_N,
   input logic [16:0]        M_D_MA,
   input logic [1:0]         M_D_BA,
   input logic [1:0]         M_D_BG,
   input logic [0:0]         M_D_CKE,
   input logic [0:0]         M_D_ODT,
   input logic [0:0]         M_D_CS_N,
   input logic [0:0]         M_D_CLK_DN,
   input logic [0:0]         M_D_CLK_DP,
   input logic               M_D_PAR,
   inout  [63:0]        M_D_DQ,
   inout  [7:0]         M_D_ECC,
   inout  [17:0]        M_D_DQS_DP,
   inout  [17:0]        M_D_DQS_DN,
   input logic               cl_RST_DIMM_D_N

`endif

   //-----------------------------------------------------------------------------
   // DDR Stats interfaces for DDR controllers in the CL.  This must be hooked up
   // to the sh_ddr.sv for the DDR interfaces to function.  If the DDR controller is
   // not used (removed through parameter on the sh_ddr instantiated), then the 
   // associated stats interface should not be hooked up and the ddr_sh_stat_ackX signal
   // should be tied high.
   //-----------------------------------------------------------------------------
   ,
   output logic [7:0] sh_ddr_stat_addr0,               //Stats address
   output logic sh_ddr_stat_wr0,                       //Stats write strobe
   output logic sh_ddr_stat_rd0,                       //Stats read strobe
   output logic [31:0] sh_ddr_stat_wdata0,             //Stats write data
   input logic  ddr_sh_stat_ack0,               //Stats cycle ack
   input logic [31:0] ddr_sh_stat_rdata0,       //Stats cycle read data
   input logic [7:0] ddr_sh_stat_int0,          //Stats interrupt

   output logic [7:0] sh_ddr_stat_addr1,
   output logic sh_ddr_stat_wr1, 
   output logic sh_ddr_stat_rd1, 
   output logic [31:0] sh_ddr_stat_wdata1,
   input logic  ddr_sh_stat_ack1,
   input logic [31:0] ddr_sh_stat_rdata1,
   input logic [7:0] ddr_sh_stat_int1,

   output logic [7:0] sh_ddr_stat_addr2,
   output logic sh_ddr_stat_wr2, 
   output logic sh_ddr_stat_rd2, 
   output logic [31:0] sh_ddr_stat_wdata2,
   input logic  ddr_sh_stat_ack2,
   input logic [31:0] ddr_sh_stat_rdata2,
   input logic [7:0] ddr_sh_stat_int2,

   //-----------------------------------------------------------------------------------
   // AXI4 Interface for DDR_C 
   //    This is the DDR controller that is instantiated in the SH.  CL is the AXI-4
   //    master, and the DDR_C controller in the SH is the slave.
   //-----------------------------------------------------------------------------------
   input logic [15:0] cl_sh_ddr_awid,
   input logic [63:0] cl_sh_ddr_awaddr,
   input logic [7:0] cl_sh_ddr_awlen,
   input logic [2:0] cl_sh_ddr_awsize,
   input logic [1:0] cl_sh_ddr_awburst,              //Burst mode, only INCR is supported, must be tied to 2'b01
   input logic  cl_sh_ddr_awvalid,
   output logic sh_cl_ddr_awready,
      
   input logic [15:0] cl_sh_ddr_wid,
   input logic [511:0] cl_sh_ddr_wdata,
   input logic [63:0] cl_sh_ddr_wstrb,
   input logic  cl_sh_ddr_wlast,
   input logic  cl_sh_ddr_wvalid,
   output logic sh_cl_ddr_wready,
      
   output logic[15:0] sh_cl_ddr_bid,
   output logic[1:0] sh_cl_ddr_bresp,
   output logic sh_cl_ddr_bvalid,
   input logic  cl_sh_ddr_bready,
      
   input logic [15:0] cl_sh_ddr_arid,
   input logic [63:0] cl_sh_ddr_araddr,
   input logic [7:0] cl_sh_ddr_arlen,
   input logic [2:0] cl_sh_ddr_arsize,
   input logic [1:0] cl_sh_ddr_arburst,              //Burst mode, only INCR is supported, must be tied to 2'b01
   input logic  cl_sh_ddr_arvalid,
   output logic sh_cl_ddr_arready,
      
   output logic[15:0] sh_cl_ddr_rid,
   output logic[511:0] sh_cl_ddr_rdata,
   output logic[1:0] sh_cl_ddr_rresp,
   output logic sh_cl_ddr_rlast,
   output logic sh_cl_ddr_rvalid,
   input logic  cl_sh_ddr_rready,
      
   output logic sh_cl_ddr_is_ready

                                                                                                    
   //---------------------------------------------------------------------------------------
   // The user-defined interrupts.  These map to MSI-X vectors through mapping in the SH.
   //---------------------------------------------------------------------------------------
    ,
    input logic [15:0] cl_sh_apppf_irq_req,        //Interrupt request.  The request (cl_sh_apppf_irq_req[n]) should be pulsed (single clock) to generate
                                                   // an interrupt request.  Another request should not be generated until ack'ed by the SH

    output logic [15:0] sh_cl_apppf_irq_ack               //Interrupt ack.  SH asserts sh_cl_apppf_irq_ack[n] (single clock pulse) to acknowledge the corresponding
                                                   // interrupt request (cl_sh_apppf_irq_req[n]) from the CL

   //----------------------------------------------------
   // PCIS AXI-4 interface to master cycles to CL
   //----------------------------------------------------
`ifndef SH_NO_PCIS
   ,
   output logic[5:0] sh_cl_dma_pcis_awid,
   output logic[63:0] sh_cl_dma_pcis_awaddr,
   output logic[7:0] sh_cl_dma_pcis_awlen,
   output logic[2:0] sh_cl_dma_pcis_awsize,
   output logic sh_cl_dma_pcis_awvalid,
   input logic  cl_sh_dma_pcis_awready,

   output logic[511:0] sh_cl_dma_pcis_wdata,
   output logic[63:0] sh_cl_dma_pcis_wstrb,
   output logic sh_cl_dma_pcis_wlast,
   output logic sh_cl_dma_pcis_wvalid,
   input logic  cl_sh_dma_pcis_wready,

   input logic [5:0] cl_sh_dma_pcis_bid,
   input logic [1:0] cl_sh_dma_pcis_bresp,
   input logic  cl_sh_dma_pcis_bvalid,
   output logic sh_cl_dma_pcis_bready,

   output logic[5:0] sh_cl_dma_pcis_arid,
   output logic[63:0] sh_cl_dma_pcis_araddr,
   output logic[7:0] sh_cl_dma_pcis_arlen,
   output logic[2:0] sh_cl_dma_pcis_arsize,
   output logic sh_cl_dma_pcis_arvalid,
   input logic  cl_sh_dma_pcis_arready,

   input logic [5:0] cl_sh_dma_pcis_rid,
   input logic [511:0] cl_sh_dma_pcis_rdata,
   input logic [1:0] cl_sh_dma_pcis_rresp,
   input logic  cl_sh_dma_pcis_rlast,
   input logic  cl_sh_dma_pcis_rvalid,
   output logic sh_cl_dma_pcis_rready
`endif

   //------------------------------------------------------------------------------------------
   // AXI-L maps to any inbound PCIe access through ManagementPF BAR4 for developer's use
   // If the CL is created through  Xilinx’s SDAccel, then this configuration bus
   // would be connected automatically to SDAccel generic logic (SmartConnect, APM etc)
   //------------------------------------------------------------------------------------------
`ifndef SH_NO_SDA
    ,
   output logic sda_cl_awvalid,
   output logic[31:0] sda_cl_awaddr, 
   input logic  cl_sda_awready,

   //Write data
   output logic sda_cl_wvalid,
   output logic[31:0] sda_cl_wdata,
   output logic[3:0] sda_cl_wstrb,
   input logic  cl_sda_wready,

   //Write response
   input logic  cl_sda_bvalid,
   input logic [1:0] cl_sda_bresp,
   output logic sda_cl_bready,

   //Read address
   output logic sda_cl_arvalid,
   output logic[31:0] sda_cl_araddr,
   input logic  cl_sda_arready,

   //Read data/response
   input logic  cl_sda_rvalid,
   input logic [31:0] cl_sda_rdata,
   input logic [1:0] cl_sda_rresp,

   output logic sda_cl_rready
`endif

   //------------------------------------------------------------------------------------------
   // AXI-L maps to any inbound PCIe access through AppPF BAR0
   // For example, this AXI-L interface can connect to OpenCL Kernels
   // This would connect automatically to the required logic 
   // if the CL is created through SDAccel flow   
   //------------------------------------------------------------------------------------------
   ,
   output logic sh_ocl_awvalid,
   output logic[31:0] sh_ocl_awaddr,
   input logic  ocl_sh_awready,
                                                                                                                               
   //Write data                                                                                                                
   output logic sh_ocl_wvalid,
   output logic[31:0] sh_ocl_wdata,
   output logic[3:0] sh_ocl_wstrb,
   input logic  ocl_sh_wready,
                                                                                                                               
   //Write response                                                                                                            
   input logic  ocl_sh_bvalid,
   input logic [1:0] ocl_sh_bresp,
   output logic sh_ocl_bready,
                                                                                                                               
   //Read address                                                                                                              
   output logic sh_ocl_arvalid,
   output logic[31:0] sh_ocl_araddr,
   input logic  ocl_sh_arready,
                                                                                                                               
   //Read data/response                                                                                                        
   input logic  ocl_sh_rvalid,
   input logic [31:0] ocl_sh_rdata,
   input logic [1:0] ocl_sh_rresp,
                                                                                                                               
   output logic sh_ocl_rready

   //------------------------------------------------------------------------------------------
   // AXI-L maps to any inbound PCIe access through AppPF BAR1
   // For example,
   //------------------------------------------------------------------------------------------
`ifndef SH_NO_BAR1
   ,
   output logic sh_bar1_awvalid,
   output logic[31:0] sh_bar1_awaddr,
   input logic  bar1_sh_awready,
                                                                                                                               
   //Write data                                                                                                                
   output logic sh_bar1_wvalid,
   output logic[31:0] sh_bar1_wdata,
   output logic[3:0] sh_bar1_wstrb,
   input logic  bar1_sh_wready,
                                                                                                                               
   //Write response                                                                                                            
   input logic  bar1_sh_bvalid,
   input logic [1:0] bar1_sh_bresp,
   output logic sh_bar1_bready,
                                                                                                                               
   //Read address                                                                                                              
   output logic sh_bar1_arvalid,
   output logic[31:0] sh_bar1_araddr,
   input logic  bar1_sh_arready,
                                                                                                                               
   //Read data/response                                                                                                        
   input logic  bar1_sh_rvalid,
   input logic [31:0] bar1_sh_rdata,
   input logic [1:0] bar1_sh_rresp,
                                                                                                                               
   output logic sh_bar1_rready           
`endif

   //-------------------------------------------------------------------------------------------
   // Debug bridge -- This is for Virtual JTAG.   If enabling the CL for
   // Virtual JTAG (chipcope) debug, connect this interface to the debug bridge in the CL
   //-------------------------------------------------------------------------------------------
   ,
   output logic drck,
   output logic shift,
   output logic tdi,
   output logic update,
   output logic sel,
   input logic  tdo,
   output logic tms,
   output logic tck,
   output logic runtest,
   output logic reset,
   output logic capture,
   output logic bscanid_en

   //-------------------------------------------------------------
   // These are global counters that increment every 4ns.  They
   // are synchronized to clk_main_a0.  Note if clk_main_a0 is
   // slower than 250MHz, the CL will see skips in the counts
   //-------------------------------------------------------------
   ,
   output logic[63:0] sh_cl_glcount0,                  //Global counter 0
   output logic[63:0] sh_cl_glcount1                   //Global counter 1

   //-------------------------------------------------------------------------------------
   // Serial GTY interface
   //    AXI-Stream interface to send/receive packets to/from Serial interfaces.
   //    This interface TBD.
   //-------------------------------------------------------------------------------------
   //
   //------------------------------------------------------
   // Aurora Interface from CL (AXI-S)
   //------------------------------------------------------
`ifdef AURORA
    ,
   //-------------------------------
   // GTY
   //-------------------------------
   input logic [NUM_GTY-1:0]        cl_sh_aurora_channel_up,
   output logic [NUM_GTY-1:0]         gty_refclk_p,
   output logic [NUM_GTY-1:0]         gty_refclk_n,
   
   output logic [(NUM_GTY*4)-1:0]     gty_txp,
   output logic [(NUM_GTY*4)-1:0]     gty_txn,

   output logic [(NUM_GTY*4)-1:0]     gty_rxp,
   output logic [(NUM_GTY*4)-1:0]     gty_rxn

   ,
   output logic [7:0] sh_aurora_stat_addr,
   output logic sh_aurora_stat_wr, 
   output logic sh_aurora_stat_rd, 
   output logic [31:0] sh_aurora_stat_wdata, 
   input logic  aurora_sh_stat_ack,
   input logic [31:0] aurora_sh_stat_rdata,
   input logic [7:0] aurora_sh_stat_int
`endif //  `ifdef AURORA

`ifdef HMC_PRESENT
   //-----------------------------------------------------------------
   // HMC Interface -- this is not currently used
   //-----------------------------------------------------------------
   ,
   output logic                       dev01_refclk_p ,
   output logic                       dev01_refclk_n ,
   output logic                       dev23_refclk_p ,
   output logic                       dev23_refclk_n ,
                               
                               /* HMC0 interface */ 
   input logic wire                 hmc0_dev_p_rst_n ,
   output logic wire                  hmc0_rxps ,
   input logic wire                 hmc0_txps ,
   input logic wire [7 : 0]         hmc0_txp ,
   input logic wire [7 : 0]         hmc0_txn ,
   output logic wire [7 : 0]          hmc0_rxp ,
   output logic wire [7 : 0]          hmc0_rxn ,
                               /* HMC1 interface */ 
   input logic wire                 hmc1_dev_p_rst_n ,
   output logic wire                  hmc1_rxps ,
   input logic wire                 hmc1_txps ,
   input logic wire [7 : 0]         hmc1_txp ,
   input logic wire [7 : 0]         hmc1_txn ,
   output logic wire [7 : 0]          hmc1_rxp ,
   output logic wire [7 : 0]          hmc1_rxn ,
                               /* HMC2 interface */ 
   input logic wire                 hmc2_dev_p_rst_n ,
   output logic wire                  hmc2_rxps ,
   input logic wire                 hmc2_txps ,
   input logic wire [7 : 0]         hmc2_txp ,
   input logic wire [7 : 0]         hmc2_txn ,
   output logic wire [7 : 0]          hmc2_rxp ,
   output logic wire [7 : 0]          hmc2_rxn ,
                               /* HMC3 interface */ 
   input logic wire                 hmc3_dev_p_rst_n ,
   output logic wire                  hmc3_rxps ,
   input logic wire                 hmc3_txps ,
   input logic wire [7 : 0]         hmc3_txp ,
   input logic wire [7 : 0]         hmc3_txn ,
   output logic wire [7 : 0]          hmc3_rxp ,
   output logic wire [7 : 0]          hmc3_rxn

   ,
   output logic                      hmc_iic_scl_i,
   input logic                hmc_iic_scl_o,
   input logic                hmc_iic_scl_t,
   output logic                      hmc_iic_sda_i,
   input logic                hmc_iic_sda_o,
   input logic                hmc_iic_sda_t,

   output logic[7:0]                 sh_hmc_stat_addr,
   output logic                      sh_hmc_stat_wr,
   output logic                      sh_hmc_stat_rd,
   output logic[31:0]                sh_hmc_stat_wdata,

   input logic                hmc_sh_stat_ack,
   input logic  [31:0]        hmc_sh_stat_rdata,

   input logic [7:0]          hmc_sh_stat_int

`endif
