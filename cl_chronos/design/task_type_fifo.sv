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

// MODULE NOT USED ANY MORE
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
            DEQ_FIFO_NEXT_TASK_OBJECT : reg_bus.rdata <= s_rdata.object;
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
