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

import chronos::*;


module ocl_arbiter(
   input clk,
   input rstn,

   axi_bus_t.master ocl, // from SH
   
   output logic [N_TILES-1:0] ocl_awvalid,
   input [N_TILES-1:0] ocl_awready,
   output logic [31:0] ocl_awaddr,
   
   output logic [N_TILES-1:0] ocl_wvalid,
   input [N_TILES-1:0] ocl_wready,
   output logic [31:0] ocl_wdata,

   input [N_TILES-1:0] ocl_bvalid,
   output logic ocl_bready,

   output logic [N_TILES-1:0] ocl_arvalid,
   input [N_TILES-1:0] ocl_arready,
   output logic [31:0] ocl_araddr,

   input [N_TILES-1:0] ocl_rvalid,
   input reg_data_t [N_TILES-1:0] ocl_rdata,
   output logic ocl_rready,

   output logic [2:0] num_mem_ctrl,

   output [7:0] ocl_global_raddr,
   input [31:0] ocl_global_rdata,

   input [15:0] pci_log_size

);

   logic [7:0] tile;

   typedef enum logic [3:0] { OCL_IDLE, OCL_SEND_AW, OCL_WAIT_W, OCL_SEND_W,
                              OCL_WAIT_B, OCL_SEND_B,
                              OCL_SEND_AR, OCL_WAIT_R, OCL_SEND_R
                              } ocl_state;

   
   assign ocl_global_raddr = ocl_araddr[7:0];

   ocl_state state;
   
   logic [2:0] log_n_tiles_p; 

   logic [15:0] id;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         state <= OCL_IDLE;
         num_mem_ctrl <= N_DDR_CTRL;
      end else begin 
         case (state) 
            OCL_IDLE: begin
               if (ocl.awvalid) begin
                  state <= OCL_SEND_AW;
                  ocl.bid <= ocl.awid;
                  ocl_awaddr <= ocl.awaddr;
                  tile <= ocl.awaddr[23:16];
               end else if (ocl.arvalid) begin
                  state <= OCL_SEND_AR;
                  ocl.rid <= ocl.arid;
                  ocl_araddr <= ocl.araddr;
                  tile <= ocl.araddr[23:16];
               end
            end
            OCL_SEND_AW: begin
               if (tile == N_TILES) begin
                  state <= OCL_WAIT_W;
               end else begin
                  if (ocl_awready[tile]) begin
                     state <= OCL_WAIT_W;
                  end
               end
            end
            OCL_WAIT_W: begin
               if (ocl.wvalid) begin
                  state <= OCL_SEND_W;
                  ocl_wdata <= ocl.wdata;
               end
            end
            OCL_SEND_W: begin
               if (tile == N_TILES) begin
                  if (ocl_awaddr[15:8] == ID_GLOBAL) begin
                     if (ocl_awaddr[7:0] == MEM_XBAR_NUM_CTRL) begin
                        num_mem_ctrl <= ocl_wdata; 
                        state <= OCL_SEND_B; 
                     end
                  end
               end else begin
                  if (ocl_wready[tile]) begin
                     state <= OCL_WAIT_B;
                  end 
               end
            end
            OCL_WAIT_B: begin
               if (ocl_bvalid[tile]) begin
                  state <= OCL_SEND_B;
               end
            end
            OCL_SEND_B: begin
               if (ocl.bready) begin
                  state <= OCL_IDLE;
               end
            end
            OCL_SEND_AR: begin
               if (tile == N_TILES) begin
                  state <= OCL_WAIT_R;
               end else begin
                  if (ocl_arready[tile]) begin
                     state <= OCL_WAIT_R;
                  end
               end
            end
            OCL_WAIT_R: begin
               if (tile == N_TILES) begin
                  if (ocl_araddr[15:8] == ID_GLOBAL) begin
                     ocl.rdata <= ocl_global_rdata; 
                     state <= OCL_SEND_R;
                  end
               end else begin
                  if (ocl_rvalid[tile]) begin
                     state <= OCL_SEND_R;
                     ocl.rdata <= ocl_rdata[tile];
                  end
               end
            end
            OCL_SEND_R: begin
               if (ocl.rready) begin
                  state <= OCL_IDLE;
               end
            end
         endcase
      end
   end
   
   lib_pipe #(
      .WIDTH(3),
      .STAGES(3)
   ) N_TILES_PIPE (
      .clk(clk), 
      .rst_n(1'b1),
      
      .in_bus ( log_n_tiles_p ),
      .out_bus( log_n_tiles)
   ); 

   genvar i;
   generate 
      for (i=0;i<N_TILES;i++) begin
         assign ocl_awvalid[i] = (state==OCL_SEND_AW) & (i==tile);
         assign ocl_wvalid[i] = (state==OCL_SEND_W) & (i==tile);
         assign ocl_arvalid[i] = (state==OCL_SEND_AR) & (i==tile);
      end
   endgenerate
   
   assign ocl_bready = (state==OCL_WAIT_B);
   assign ocl_rready = (state==OCL_WAIT_R);


   // Assumes both awvalid and arvalid wouldnt be set at the same cycle.
   // Reasonable because the software is synchronous.
   assign ocl.awready = (state==OCL_IDLE);
   assign ocl.arready = (state==OCL_IDLE);
   assign ocl.wready = (state==OCL_WAIT_W);
   assign ocl.bvalid = (state==OCL_SEND_B);
   assign ocl.rvalid = (state==OCL_SEND_R);

   assign ocl.bid = id;
   assign ocl.rid = id;
   assign ocl.bresp = 0;
   assign ocl.rresp = 0;
   assign ocl.rlast = 1;

endmodule

