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

typedef struct packed {
   logic is_read;
   logic [15:0] id;
   logic [63:0] addr;
   cache_line_t data;
   logic [63:0] wstrb;
   logic [7:0] size;
   logic last;
   logic [63:0] cycle;
} mem_request_t;

module mem_ctrl(
   input clk,
   input rstn,
   axi_bus_t axi
);

localparam QUEUE_SIZE = 16;
localparam LATENCY = 30;

mem_request_t req_queue[$];
mem_request_t head;
logic [7:0] memory[*];

logic [63:0] cycle;

logic aw_taken; 

always_ff @(posedge clk) begin
   if (!rstn) begin
      cycle <= 0;
   end else begin
      cycle <= cycle + 1;
   end
end

//always_ff @(posedge clk) begin
//   if (!rstn) begin
//      axi.rready <= 1'b0;
//   end else begin
//      if (!axi.arvalid | req_queue.size() < 16) begin
//         axi.rready <= 1'b1;
//      end
//   end
//end

logic q_pop, q_push;
logic [31:0] q_size;

logic [63:0] awaddr;
logic [2:0] awsize;
logic [15:0] awid;

logic[7:0] size_map[8] = { 1, 2, 4, 8, 16, 32, 64, 128};
always_ff @(posedge clk) begin
   if (!rstn) begin
      aw_taken <= 1'b0;
   end else begin
      // take the writes first, since awvalid was originally asserted the
      // previous cycle
      if (axi.awvalid & axi.awready) begin
         awaddr <= axi.awaddr;
         awsize <= axi.awsize;
         awid <= axi.awid;
         aw_taken <= 1'b1;
      end else 
      if (axi.wvalid & axi.wready) begin
         req_queue.push_back({1'b0, awid, awaddr, 
            axi.wdata, axi.wstrb, size_map[awsize], axi.wlast, cycle+LATENCY});
         awaddr <= awaddr + size_map[awsize];
         if (axi.wlast) begin
            aw_taken <= 1'b0;
         end
      end
      if (axi.arvalid & axi.arready) begin
         for (integer i=0;i <= axi.arlen; i=i+1) begin
            req_queue.push_back({1'b1, axi.arid, axi.araddr + i * size_map[axi.arsize],
               512'b0, 64'b0, size_map[axi.arsize], (i==axi.arlen), cycle+LATENCY});
         end
      end
   end
end

assign axi.rid = head.id;
assign axi.rlast = head.last;
assign axi.rresp = 0;
assign axi.bid = head.id; 
assign axi.bresp = 0;
always_comb begin
   q_pop = 0;
   axi.rdata = 0;
   axi.rvalid = 0;
   
   axi.bvalid = 1'b0;
  
   head = req_queue[0];
   if (q_size >0 && head.cycle < cycle) begin
      if (head.is_read) begin
         axi.rvalid = 1'b1;
         for (integer i=0;i <head.size; i=i+1) begin
            if (memory.exists(head.addr + i)) begin
               axi.rdata[i*8 +: 8] = memory[head.addr+i];
            end else begin
               axi.rdata[i*8 +: 8] = 0;
            end
         end
         if (axi.rready) begin
            q_pop = 1;
         end
      end else begin
         for ( integer i=0; i<head.size; i=i+1) begin
            if (head.wstrb[i]) begin
               memory[head.addr+i] = head.data[i*8 +:8];
            end
         end
         if (head.last) begin
            axi.bvalid = 1'b1;
            if (axi.bready) begin
               q_pop = 1;
            end
         end else begin
            q_pop = 1;
         end
      end
   end
end 
always_comb begin
   
   if (q_size<QUEUE_SIZE-1) begin
      axi.awready = !aw_taken;
      axi.wready = aw_taken;
      axi.arready = 1'b1;
   end else begin
      axi.awready = 1'b0;
      axi.wready = 1'b0;
      axi.arready = 1'b0;
   end
end

always_ff @(posedge clk) begin
   if (q_pop) begin
      req_queue.pop_front();
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      q_size <= 0;
   end else begin
      q_size <= q_size + (axi.awvalid & axi.awready)  
                       + (axi.arvalid & axi.arready) 
                       - q_pop;
   end
end

endmodule
