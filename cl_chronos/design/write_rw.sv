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

module write_rw
#(
   parameter TILE_ID=0
) (
   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input rw_write_t        task_in, 

   output logic        wvalid,
   input               wready,
   output logic [31:0] waddr, // directly index into the data_array bypassing tags
   output logic [511:0] wdata,
   output logic [63:0] wstrb,
   output id_t         wid,

   input               bvalid,
   output logic        bready,
   input id_t          bid,
   
   input logic [2**LOG_CQ_SLICE_SIZE-1:0]    task_aborted,

   output logic            task_out_valid,
   input                   task_out_ready,
   output task_t           task_out,  
   output rw_data_t        data_out,  
   output logic            task_out_is_rw,
   output cq_slice_slot_t  task_out_cq_slot,  
   output thread_id_t      task_out_thread_id,  
   
   input fifo_size_t   task_out_fifo_occ, 
   
   input logic         gvt_task_slot_valid,
   cq_slice_slot_t     gvt_task_slot,

   output logic        unlock_object,
   output thread_id_t  unlock_thread,
   
   output logic        finish_task_valid,
   input               finish_task_ready,
   output cq_slice_slot_t finish_task_slot,
   output logic        finish_task_is_undo_log_restore,
   
   reg_bus_t         reg_bus
);

logic started;

fifo_size_t fifo_out_almost_full_thresh;

logic s_finish_task_valid, s_finish_task_ready, s_finish_task_is_undo_log_restore;
logic s_task_out_valid;

logic s_valid, s_ready;
logic s_wvalid;
logic [31:0] s_waddr;
rw_data_t s_wdata;

logic s_out_valid, s_out_ready;
task_t s_out_task;
rw_data_t s_out_data;
logic s_out_task_rw;

logic s_sched_valid, s_sched_ready;

always_ff @(posedge clk) begin
   if (s_task_out_valid) begin
      task_out <= s_out_task;
      data_out <= s_out_data;
      task_out_is_rw <= s_out_task_rw;
      task_out_cq_slot <= task_in.cq_slot;
      task_out_thread_id <= task_in.thread;
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      task_out_valid <= 1'b0;
   end else begin
      if (s_task_out_valid) begin
         task_out_valid <= 1'b1;
      end else if (task_out_valid & task_out_ready) begin
         task_out_valid <= 1'b0;
      end
   end
end

assign s_out_ready = (!task_out_valid | task_out_ready);

logic [31:0] base_rw_addr;

assign s_valid = task_in_valid & (task_in.task_desc.ttype != TASK_TYPE_UNDO_LOG_RESTORE) & 
    (  (task_out_fifo_occ < fifo_out_almost_full_thresh) |
       (gvt_task_slot_valid & (gvt_task_slot == task_in.cq_slot)) );

always_comb begin
   if (task_in_valid & (task_in.task_desc.ttype != TASK_TYPE_UNDO_LOG_RESTORE)) begin
      if ( (s_out_valid & !s_out_ready) | 
           (!s_out_valid & !s_finish_task_ready) |
           (task_aborted[task_in.cq_slot] & !s_finish_task_ready) |
           (s_wvalid & !s_write_wready) ) begin
         s_sched_ready = 1'b0;
      end else begin
         s_sched_ready = 1'b1;
      end
   end else begin
      s_sched_ready = 1'b0;
   end
end

logic s_write_wvalid;
rw_data_t s_write_data;
logic s_write_wready;
logic [31:0] s_write_addr;
thread_id_t s_thread_id, write_thread_id;

logic wdata_fifo_full, wdata_fifo_empty;

logic [31:0] write_addr;
rw_data_t write_data;

fifo #(
      .WIDTH($bits(s_write_addr) + $bits(s_thread_id) + $bits(s_write_data)),
      .LOG_DEPTH(1)
   ) WDATA_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(s_write_wvalid & s_write_wready),
      .wr_data({s_thread_id, s_write_addr,  s_write_data}),

      .full(wdata_fifo_full),
      .empty(wdata_fifo_empty),

      .rd_en(wvalid & wready),
      .rd_data({write_thread_id, write_addr, write_data})

   );

logic c_bvalid, c_bready, bvalid_fifo_full, bvalid_fifo_empty;
id_t c_bid; 

fifo #(
      .WIDTH($bits(bid)),
      .LOG_DEPTH(1)
   ) BVALID_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(bvalid & bready),
      .wr_data(bid),

      .full(bvalid_fifo_full),
      .empty(bvalid_fifo_empty),

      .rd_en(c_bvalid & c_bready),
      .rd_data(c_bid)

   );

assign c_bvalid = !bvalid_fifo_empty;
assign bready = !bvalid_fifo_full;

assign s_thread_id = task_in.thread;
assign wvalid = !wdata_fifo_empty;
assign wid = write_thread_id;
assign s_write_wready = !wdata_fifo_full;

assign  waddr = write_addr; // base_rw_addr + ( write_object << (LOG_RW_WIDTH) ) ;
always_comb begin
   wdata = 'x;
   case (LOG_RW_WIDTH) 
      2: wdata [ write_addr[5:2]* 32 +: 32 ] = write_data;
      3: wdata [ write_addr[5:3]* 64 +: 64 ] = write_data;
      4: wdata [ write_addr[5:4]* 128 +: 128 ] = write_data;
      5: wdata [ write_addr[5]* 256 +: 256 ] = write_data;
      6: wdata  = write_data;
   endcase
end
always_comb begin
   wstrb = 0;
   case (LOG_RW_WIDTH) 
      2: wstrb[ write_addr[5:2] * 4 +: 4]  = '1;
      3: wstrb[ write_addr[5:3] * 8 +: 8]  = '1;
      4: wstrb[ write_addr[5:4] * 16 +: 16]  = '1;
      5: wstrb[ write_addr[5] * 32 +: 32]  = '1;
      6: wstrb  = '1;
   endcase
end

always_comb begin 
   s_write_wvalid = 0;
   s_write_data = 'x;
   task_in_ready = 1'b0;
   s_finish_task_valid = 1'b0; 
   s_finish_task_is_undo_log_restore = 1'b0;
   s_task_out_valid = 1'b0;
   s_write_addr = 'x;

   if (task_in_valid) begin
      if (task_in.task_desc.ttype == TASK_TYPE_UNDO_LOG_RESTORE) begin
         if (s_finish_task_ready) begin
            s_write_wvalid = 1'b1;
            s_write_data = task_in.object;
            s_write_addr = task_in.task_desc.object;
            s_finish_task_is_undo_log_restore = 1'b1;
            if (s_write_wvalid & s_write_wready) begin
               task_in_ready = 1'b1;
               s_finish_task_valid = 1'b1;
            end
         end
      end else if (s_sched_valid & s_sched_ready) begin 
         task_in_ready = s_ready;
         s_write_wvalid = s_wvalid;
         s_write_data = s_wdata;
         s_write_addr = s_waddr;
         s_task_out_valid = s_out_valid & !task_aborted[task_in.cq_slot];
         s_finish_task_valid = !s_task_out_valid;
             
      end
   end
end

`RW_WORKER #(
  .TILE_ID(TILE_ID) 
) WORKER (

   .clk(clk),
   .rstn(rstn),

   .task_in_valid(s_valid),
   .task_in_ready(s_ready),

   .in_task(task_in.task_desc), 
   .in_data(task_in.object),
   .in_cq_slot(task_in.cq_slot),
   
   .wvalid (s_wvalid),
   .waddr  (s_waddr),
   .wdata  (s_wdata),
   .wsize  (),

   .out_valid (s_out_valid),
   .out_task  (s_out_task),
   .out_data  (s_out_data),
   .out_task_rw (s_out_task_rw), 

   .sched_task_valid (s_sched_valid),
   .sched_task_ready (s_sched_ready),

   .reg_bus(reg_bus)

);

always_comb begin
   c_bready = 1'b0;
   if (task_in_ready & !s_write_wvalid 
       & (!s_out_task_rw | task_aborted[task_in.cq_slot]) ) begin
   end else if (c_bvalid) begin
      c_bready = 1'b1;
   end
end
always_ff @(posedge clk) begin
   if (!rstn) begin
      unlock_object <= 1'b0;
      unlock_thread <= 'x;
   end else begin
      if (task_in_ready & !s_write_wvalid 
          & (!s_out_task_rw | task_aborted[task_in.cq_slot])  ) begin
         unlock_object <= 1'b1;
         unlock_thread <= task_in.thread;
      end else if (c_bvalid) begin
         unlock_object <= 1'b1;
         unlock_thread <= c_bid;
      end else begin
         unlock_object <= 1'b0;
         unlock_thread <= 'x;
      end
   end
end

logic [31:0] cycles_task_processed;
logic [31:0] cycles_no_task;
logic [31:0] cycles_stall_fifo_full;
logic [31:0] cycles_stall_mem;
logic [31:0] cycles_stall_finish;
logic [31:0] cycles_unassigned;

always_ff @(posedge clk) begin
   if (!rstn) begin
      cycles_task_processed <= 0;
      cycles_no_task <= 0;
      cycles_stall_fifo_full <= 0;
      cycles_stall_mem <= 0;
      cycles_stall_finish <= 0;
      cycles_unassigned <= 0;
   end else begin
      if (started) begin
         if (!task_in_valid) cycles_no_task <= cycles_no_task + 1;
         else if (task_in_ready) cycles_task_processed <= cycles_task_processed + 1;
         else begin
            if (task_out_fifo_occ >= fifo_out_almost_full_thresh) begin
               cycles_stall_fifo_full <= cycles_stall_fifo_full + 1;
            end else if (s_write_wvalid & !s_write_wready) begin
               cycles_stall_mem <= cycles_stall_mem + 1;
            end else if (!s_out_valid & !s_finish_task_ready) begin
               cycles_stall_finish <= cycles_stall_finish + 1;
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
      started <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            RW_BASE_ADDR : base_rw_addr <= {reg_bus.wdata[29:0], 2'b00};
            CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD : fifo_out_almost_full_thresh <= reg_bus.wdata;
            CORE_START : started <= reg_bus.wdata[0];
         endcase
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
         8'h90: reg_bus.rdata <= cycles_stall_finish;
         8'ha0: reg_bus.rdata <= cycles_unassigned;
         CORE_DEBUG_WORD: reg_bus.rdata = {
            18'b0,
            s_write_wvalid, s_write_wready,
            finish_task_valid, finish_task_ready, s_sched_valid, s_sched_ready,
            wvalid, wready, bvalid, bready,
            task_in_valid, task_in_ready, task_out_valid, task_out_ready
         };


      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end

logic finish_task_fifo_empty, finish_task_fifo_full;

fifo #(
      .WIDTH( $bits(finish_task_slot) + 1),
      .LOG_DEPTH(2)
   ) FINISHED_TASK_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(s_finish_task_valid & s_finish_task_ready),
      .wr_data({task_in.cq_slot, s_finish_task_is_undo_log_restore}),

      .full(finish_task_fifo_full),
      .empty(finish_task_fifo_empty),

      .rd_en(finish_task_valid & finish_task_ready),
      .rd_data({finish_task_slot, finish_task_is_undo_log_restore})

   );

assign finish_task_valid = !finish_task_fifo_empty;
assign s_finish_task_ready = !finish_task_fifo_full;

endmodule

