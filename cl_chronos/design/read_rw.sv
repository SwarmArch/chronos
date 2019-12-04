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

module read_rw
#(
   parameter TILE_ID
) (
   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            task_in, 
   input cq_slice_slot_t   cq_slot_in,
   input thread_id_t       thread_id_in,
   
   input logic         gvt_task_slot_valid,
   cq_slice_slot_t     gvt_task_slot,

   output logic        arvalid,
   input               arready,
   output logic [31:0] araddr,
   output id_t         arid,

   input               rvalid,
   output logic        rready,
   input id_t          rid,
   input logic [511:0] rdata,

   output logic        task_out_valid,
   input               task_out_ready,
   output rw_write_t   task_out,  

   input fifo_size_t   task_out_fifo_occ, 
   
   reg_bus_t         reg_bus,
   pci_debug_bus_t   pci_debug
);

logic started; // cycle counting;

task_t task_desc [0:N_THREADS-1];
cq_slice_slot_t task_cq_slot [0:N_THREADS-1];

logic [31:0] base_rw_addr;

fifo_size_t fifo_out_almost_full_thresh;
logic [31:0] dequeues_remaining;


logic can_dequeue; 
assign can_dequeue = (dequeues_remaining > 0) & 
   ( (task_out_fifo_occ < fifo_out_almost_full_thresh) 
    | (gvt_task_slot_valid & (gvt_task_slot == cq_slot_in)));

logic s_arvalid, s_arready;
logic [31:0] s_araddr;
id_t s_arid;
logic ar_fifo_empty;
logic ar_fifo_full;

assign s_arid = thread_id_in;
assign s_araddr = base_rw_addr + (task_in.object << (LOG_RW_WIDTH) );

assign arvalid = !ar_fifo_empty;
assign s_arready = !ar_fifo_full;

   fifo #(
      .WIDTH($bits(s_araddr) + $bits(s_arid)),
      .LOG_DEPTH(3)
   ) WDATA_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(s_arvalid & s_arready),
      .wr_data({s_araddr, s_arid}),

      .full(ar_fifo_full),
      .empty(ar_fifo_empty),

      .rd_en(arvalid & arready),
      .rd_data({araddr, arid})

   );

always_comb begin
   s_arvalid = 1'b0;
   task_in_ready = 1'b0;
   if (task_in_valid & can_dequeue) begin
      if (task_in.no_read) begin
         task_in_ready = 1'b1;
      end else begin
         s_arvalid = 1'b1;
         if (s_arready) begin
            task_in_ready = 1'b1;
         end
      end
   end
end

always_ff @(posedge clk) begin
   if (task_in_valid & task_in_ready) begin
      task_desc[thread_id_in] <= task_in;
      task_cq_slot[thread_id_in] <= cq_slot_in;
   end
end

rw_data_t undo_log [0:2**LOG_CQ_SLICE_SIZE-1];
rw_data_t undo_log_read_word;

logic             reg_task_valid;
task_t            reg_task;
cq_slice_slot_t   reg_slot;
thread_id_t       reg_thread;

always_ff @(posedge clk) begin
   if (task_out_valid & task_out_ready) begin
      undo_log[task_out.cq_slot] <= task_out.object;
   end
   undo_log_read_word <= undo_log[cq_slot_in];
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_task_valid <= 1'b0;
   end
   if (task_in_valid & task_in_ready) begin
      reg_task <= task_in;
      reg_slot <= cq_slot_in;
      reg_thread <= thread_id_in;
      reg_task_valid <= 1'b1;
   end else if (task_out_valid & task_out_ready) begin
      reg_task_valid <= 1'b0;
   end

end


always_comb begin
   task_out.task_desc = task_desc[rid];
   task_out.cq_slot = task_cq_slot[rid];
   task_out.thread = rid;
   case (LOG_RW_WIDTH)
      2: task_out.object = rdata[ task_out.task_desc.object[ 3:0] * 32  +: 32 ]; 
      3: task_out.object = rdata[ task_out.task_desc.object[ 2:0] * 64  +: 64 ]; 
      4: task_out.object = rdata[ task_out.task_desc.object[ 1:0] * 128  +: 128 ]; 
      5: task_out.object = rdata[ task_out.task_desc.object[ 0] * 256  +: 256 ]; 
      default: task_out.object = rdata; 
   endcase
   task_out_valid = 1'b0;
   rready = 1'b0;
   
     
   if (reg_task_valid & (reg_task.ttype == TASK_TYPE_UNDO_LOG_RESTORE)) begin
      task_out.task_desc = reg_task;
      task_out.cq_slot = reg_slot;
      task_out.thread = reg_thread;
      task_out.object = undo_log_read_word;
      task_out_valid = 1'b1;
   end else if (reg_task_valid & reg_task.no_read) begin
      task_out.task_desc = reg_task;
      task_out.cq_slot = reg_slot;
      task_out.thread = reg_thread;
      task_out.object = 'x;
      task_out_valid = 1'b1;
   end else if (rvalid) begin
      task_out_valid = 1'b1;
      if (task_out_ready) begin
         rready = 1'b1;
      end
   end
end

logic [31:0] cycles_task_processed;
logic [31:0] cycles_no_task;
logic [31:0] cycles_stall_fifo_full;
logic [31:0] cycles_stall_mem;
logic [31:0] cycles_unassigned;

always_ff @(posedge clk) begin
   if (!rstn) begin
      cycles_task_processed <= 0;
      cycles_no_task <= 0;
      cycles_stall_fifo_full <= 0;
      cycles_stall_mem <= 0;
      cycles_unassigned <= 0;
   end else begin
      if (started) begin
         if (!task_in_valid) cycles_no_task <= cycles_no_task + 1;
         else if (task_in_ready) cycles_task_processed <= cycles_task_processed + 1;
         else begin
            if (task_out_fifo_occ >= fifo_out_almost_full_thresh) begin
               cycles_stall_fifo_full <= cycles_stall_fifo_full + 1;
            end else if (arvalid & !arready) begin
               cycles_stall_mem <= cycles_stall_mem + 1;
            end else begin
               cycles_unassigned <= cycles_unassigned + 1;
            end
         end
      end

   end
   
end

logic [LOG_LOG_DEPTH:0] log_size; 
always_ff @(posedge clk) begin
   if (!rstn) begin
      base_rw_addr <= 0;
      fifo_out_almost_full_thresh <= '1;
      dequeues_remaining <= '1;
      started <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            RW_BASE_ADDR : base_rw_addr <= {reg_bus.wdata[29:0], 2'b00};
            CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD : fifo_out_almost_full_thresh <= reg_bus.wdata;
            CORE_N_DEQUEUES: dequeues_remaining <= reg_bus.wdata;
            CORE_START : started <= reg_bus.wdata[0];
         endcase
      end else begin
         if (task_in_valid & task_in_ready) begin
            dequeues_remaining <= dequeues_remaining - 1;
         end
      end
   end
end
always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_bus.rvalid <= 1'b0;
      reg_bus.rdata <= 'x;
   end else
   if (reg_bus.arvalid) begin
      reg_bus.rvalid <= 1'b1;
      casex (reg_bus.araddr) 
         DEBUG_CAPACITY : reg_bus.rdata <= log_size;
         CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD : reg_bus.rdata <= task_out_fifo_occ;
         8'h80: reg_bus.rdata <= cycles_no_task;
         8'h84: reg_bus.rdata <= cycles_task_processed;
         8'h88: reg_bus.rdata <= cycles_stall_fifo_full;
         8'h8c: reg_bus.rdata <= cycles_stall_mem;
         8'ha0: reg_bus.rdata <= cycles_unassigned;
         CORE_DEBUG_WORD: reg_bus.rdata = {
            24'b0,
            arvalid, arready, rvalid, rready,
            task_in_valid, task_in_ready, task_out_valid, task_out_ready
         };


      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end
/*         
`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [read_rw] [%2d] [thread-%2d] ts:%8d object:%4d type:%1x",
            cycle, TILE_ID, cq_slot_in, thread_id_in,
            task_in.ts, task_in.object, task_in.ttype) ;
      end
   end 
`endif
*/


if (READ_RW_LOGGING[TILE_ID]) begin
   logic log_valid;
   typedef struct packed {

      logic [191:0] out_data_rest;
      
      logic task_in_valid;
      logic task_in_ready;
      logic task_out_valid;
      logic task_out_ready;
      logic arvalid;
      logic arready;
      logic rvalid;
      logic rready;
      logic [7:0] out_fifo_occ;
      logic [15:0] out_thread;
      
      logic [7:0] in_cq_slot;
      logic [7:0] in_thread;
      logic [11:0] rid;
      logic [3:0]  task_in_ttype;

      logic [31:0] task_in_ts;
      logic [31:0] task_in_object;

      logic [31:0] araddr;

      logic [31:0] out_data;
      logic [31:0] out_ts;
      logic [31:0] out_object;
      
   } rw_read_log_t;
   rw_read_log_t log_word;
   always_comb begin
      log_valid = (task_in_valid & task_in_ready) | (task_out_valid & task_out_ready) ;

      log_word = '0;

      log_word.task_in_valid = task_in_valid;
      log_word.task_in_ready = task_in_ready;
      log_word.task_out_valid = task_out_valid;
      log_word.task_out_ready = task_out_ready;
      log_word.arvalid = arvalid;
      log_word.arready = arready;
      log_word.rvalid = rvalid;
      log_word.rready = rready;
      log_word.out_fifo_occ = task_out_fifo_occ;

      log_word.in_cq_slot = cq_slot_in;
      log_word.in_thread = thread_id_in;

      log_word.rid = rid;
      log_word.task_in_ttype = task_in.ttype; 
      log_word.task_in_ts = task_in.ts; 
      log_word.task_in_object = task_in.object; 
      log_word.araddr = araddr; 
      if (APP_NAME == "maxflow") begin
         log_word.out_data = task_out.object[511-:32] ;
      end else begin
         log_word.out_data = task_out.object;
      end
      log_word.out_thread = task_out.thread; 
      log_word.out_ts = task_out.task_desc.ts;
      log_word.out_object = task_out.task_desc.object;

      log_word.out_data_rest = task_out.object;

   end

   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) RW_READ_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid(log_valid),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end

endmodule
