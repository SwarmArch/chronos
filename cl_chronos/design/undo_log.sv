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

module undo_log 
 #(
    parameter ID_BASE = 0,
    parameter TILE_ID = 0,
    parameter N_CORES = 1,
    parameter UNDO_LOG_THREADS = 1
 )
(
   input clk,
   input rstn,

   // Log interface
   input                   [N_CORES-1:0] undo_log_valid,
   output logic            [N_CORES-1:0] undo_log_ready,
   input undo_id_t         [N_CORES-1:0] undo_log_id,
   input undo_log_addr_t   [N_CORES-1:0] undo_log_addr,
   input undo_log_data_t   [N_CORES-1:0] undo_log_data,
   input cq_slice_slot_t   [N_CORES-1:0] undo_log_slot,

   input                   finish_task_valid,
   input cq_slice_slot_t   finish_task_slot,
   input logic             finish_task_undo_log_write,
  

   // Restore interface - Connects to conflict serializer
   output logic          [UNDO_LOG_THREADS-1:0] restore_arvalid,
   output task_type_t    [UNDO_LOG_THREADS-1:0] restore_araddr,
   input                 [UNDO_LOG_THREADS-1:0] restore_rvalid,
   input cq_slice_slot_t                        restore_cq_slot, 
   input thread_id_t                            restore_thread_id,

   output logic          [UNDO_LOG_THREADS-1:0] restore_done_valid,
   input                 [UNDO_LOG_THREADS-1:0] restore_done_ready,
   output cq_slice_slot_t[UNDO_LOG_THREADS-1:0] restore_done_cq_slot,
   output thread_id_t    [UNDO_LOG_THREADS-1:0] restore_done_thread_id,
   
   // L2
   axi_bus_t.slave      l2, 
   pci_debug_bus_t.master                 pci_debug,
   reg_bus_t.master                       reg_bus

);

localparam ENTRIES_PER_TASK = 2**LOG_UNDO_LOG_ENTRIES_PER_TASK;

generate 
if (NO_ROLLBACK) begin
   assign undo_log_ready = '1;
   assign restore_arvalid = 0;
   assign restore_araddr = 'x;
   assign restore_done_valid = 0;
   assign restore_done_cq_slot = 'x;
   assign l2.awvalid = 0;
   assign l2.wvalid = 0;
   assign l2.awsize = 2;
   assign l2.awlen = 0;
   assign l2.awaddr = 'x;  
   assign l2.wdata = 'x;
   assign l2.awid = ID_BASE ;
   assign l2.wid = ID_BASE ;
   assign l2.wstrb = '1;
   assign l2.bready = 1;
   assign l2.arvalid = 1'b0;
   assign l2.rready = 1'b1;
end else begin

logic [$clog2(N_CORES)-1:0] undo_log_select_core;

lowbit #(
   .OUT_WIDTH($clog2(N_CORES)),
   .IN_WIDTH(N_CORES)
) UNDO_LOG_SELECT (
   .in(undo_log_valid),
   .out(undo_log_select_core)
);
logic undo_log_select_valid;
logic undo_log_select_ready;
cq_slice_slot_t undo_log_select_cq_slot;
always_comb begin
   undo_log_select_valid       = undo_log_valid       [undo_log_select_core];
   undo_log_select_cq_slot     = undo_log_slot        [undo_log_select_core];
end

genvar i;
   for (i=0;i<N_CORES;i++) begin
      assign undo_log_ready[i] = undo_log_select_valid & undo_log_select_ready & 
         (undo_log_select_core ==i);
   end
assign undo_log_select_ready = undo_log_select_valid;
cq_slice_slot_t next_cq_slot;
undo_id_t       next_id;

undo_log_addr_t addr_log [0: ENTRIES_PER_TASK * 2**LOG_CQ_SLICE_SIZE-1];
undo_log_data_t data_log [0: ENTRIES_PER_TASK * 2**LOG_CQ_SLICE_SIZE-1];

undo_id_t last_word_id[0: 2**LOG_CQ_SLICE_SIZE - 1];
   
   logic undo_log_written[0:2**LOG_CQ_SLICE_SIZE-1];
   always_ff @(posedge clk) begin
      if (finish_task_valid) begin
         undo_log_written[finish_task_slot] <= finish_task_undo_log_write;
      end
   end

undo_log_addr_t addr_read;
undo_log_data_t data_read;


always_ff @(posedge clk) begin
   if (undo_log_select_valid & undo_log_select_ready) begin
      addr_log[undo_log_select_cq_slot * ENTRIES_PER_TASK + undo_log_id[undo_log_select_core]]
         <= undo_log_addr[undo_log_select_core];
   end
   addr_read <= addr_log[next_cq_slot * ENTRIES_PER_TASK + next_id];
end
always_ff @(posedge clk) begin
   if (undo_log_select_valid & undo_log_select_ready) begin
      data_log[undo_log_select_cq_slot * ENTRIES_PER_TASK + undo_log_id[undo_log_select_core]]
        <= undo_log_data[undo_log_select_core];
   end
   data_read <= data_log[next_cq_slot * ENTRIES_PER_TASK + next_id];
end
always_ff @(posedge clk) begin
   if (undo_log_select_valid & undo_log_select_ready) begin
      last_word_id[undo_log_select_cq_slot] <= undo_log_id[undo_log_select_core];
   end
end


// -- RESTORE LOGIC

logic [UNDO_LOG_THREADS-1:0] thread_in_use;
cq_slice_slot_t [UNDO_LOG_THREADS-1:0] thread_cq_slot;
thread_id_t [UNDO_LOG_THREADS-1:0] thread_thread_id; 
// BEWARE: different notions of thread here <undo_log>thread_<serializer>thread_id

typedef logic [$clog2(UNDO_LOG_THREADS)-1:0] undo_log_thread_id;
undo_log_thread_id arthread, reg_rthread, bthread;

lowbit #(
   .OUT_WIDTH($clog2(UNDO_LOG_THREADS)),
   .IN_WIDTH(UNDO_LOG_THREADS)
) UNDO_LOG_THREAD_SELECT (
   .in(~thread_in_use),
   .out(arthread)
);

typedef enum logic[1:0] {RESTORE_IDLE, RESTORE_READ_LOG, RESTORE_WRITE_MEM, RESTORE_NO_UNDO_LOG_WRITE } restore_state_t;
restore_state_t restore_state;

typedef enum logic {RESTORE_ACK_IDLE, RESTORE_ACK_RECEIVED} restore_ack_state_t;
undo_log_thread_id restore_ack_thread;
restore_ack_state_t restore_ack_state;

id_t [UNDO_LOG_THREADS-1:0] restore_bvalid_remaining;
assign bthread = l2.bid[UNDO_LOG_THREADS-1:0];

for (i=0;i<UNDO_LOG_THREADS;i++) begin
   assign restore_arvalid[i] = (arthread == i) & !thread_in_use[i] 
         & (restore_state == RESTORE_IDLE);
   assign restore_araddr[i] = TASK_TYPE_UNDO_LOG_RESTORE;
   
   always_comb begin
      restore_done_valid[i] = 0;
      if (restore_ack_state == RESTORE_ACK_RECEIVED) begin
         restore_done_valid[i] = (restore_ack_thread == i);
      end else if (restore_state == RESTORE_NO_UNDO_LOG_WRITE) begin
         restore_done_valid[i] = (reg_rthread == i);
      end
   end
   assign restore_done_cq_slot[i] = thread_cq_slot[i];
   assign restore_done_thread_id[i] = thread_thread_id[i];

   always_ff @(posedge clk) begin
      if (!rstn) begin
         thread_in_use[i] <= 1'b0;
      end else begin
         if ((restore_state == RESTORE_READ_LOG) & (reg_rthread==i)) begin
            thread_in_use[i] <= 1'b1;
         end else if ((restore_ack_state == RESTORE_ACK_RECEIVED) & (restore_done_ready[i])) begin
            thread_in_use[i] <= 1'b0;
         end else if ((restore_state == RESTORE_NO_UNDO_LOG_WRITE) 
                  & restore_done_valid[i] & restore_done_ready[i]) begin
            thread_in_use[i] <= 1'b0;
         end
      end
   end
   always_ff @(posedge clk) begin
      if ((restore_state == RESTORE_IDLE) & (i==arthread) & restore_rvalid[i]) begin
         restore_bvalid_remaining[i] <= last_word_id[restore_cq_slot] + 1;
      end else if ((restore_ack_state == RESTORE_ACK_IDLE) & l2.bvalid & (i==bthread)) begin
        restore_bvalid_remaining[i] <=  restore_bvalid_remaining[i] - 1;
     end
   end
end


always_ff @(posedge clk) begin
   if (!rstn) begin
      restore_state <= RESTORE_IDLE;
   end else begin
      case (restore_state) 
         RESTORE_IDLE: begin
            if (restore_rvalid[arthread]) begin
               restore_state <= (undo_log_written[restore_cq_slot]) ?
                                 RESTORE_READ_LOG : RESTORE_NO_UNDO_LOG_WRITE;
               next_cq_slot <= restore_cq_slot;
               next_id <= 0;
               reg_rthread <= arthread;
               thread_cq_slot[arthread] <= restore_cq_slot;
               thread_thread_id[arthread] <= restore_thread_id;
            end
         end
         RESTORE_READ_LOG: begin
            restore_state <= RESTORE_WRITE_MEM;
         end
         RESTORE_WRITE_MEM: begin
            if (l2.awready & l2.wready) begin
               if (next_id < last_word_id[next_cq_slot]) begin
                  restore_state <= RESTORE_READ_LOG;
                  next_id <= next_id + 1;
               end else begin
                  restore_state <= RESTORE_IDLE;
               end
            end
         end
         RESTORE_NO_UNDO_LOG_WRITE: begin
            if (restore_done_ready[reg_rthread]) begin
               restore_state <= RESTORE_IDLE;
            end
         end
      endcase
   end
end


always_ff @(posedge clk) begin
   if (!rstn) begin
      restore_ack_state <= RESTORE_ACK_IDLE;
   end else begin
      case (restore_ack_state) 
         RESTORE_ACK_IDLE : begin
            if (l2.bvalid) begin

               if (restore_bvalid_remaining[bthread] == 1) begin
                  restore_ack_state <= RESTORE_ACK_RECEIVED;
                  restore_ack_thread <= l2.bid[UNDO_LOG_THREADS-1:0];
               end
            end
         end
         RESTORE_ACK_RECEIVED: begin
            if (restore_done_ready[restore_ack_thread] ) begin
               restore_ack_state <= RESTORE_ACK_IDLE;
            end
         end
      endcase
   end
end

assign l2.awvalid = (restore_state == RESTORE_WRITE_MEM);
assign l2.wvalid = (restore_state == RESTORE_WRITE_MEM);
assign l2.awsize = 2;
assign l2.awlen = 0;
assign l2.awaddr = addr_read;  
assign l2.wdata = data_read;
assign l2.awid = ID_BASE | reg_rthread;
assign l2.wid = ID_BASE | reg_rthread;
assign l2.wlast = 1'b1;
assign l2.wstrb = '1;
assign l2.bready = (restore_ack_state == RESTORE_ACK_IDLE);



// No L2 reads/ only writes
assign l2.arvalid = 1'b0;
assign l2.rready = 1'b1;

logic [LOG_LOG_DEPTH:0] log_size; 
always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_bus.rvalid <= 1'b0;
   end
   if (reg_bus.arvalid) begin
      reg_bus.rvalid <= 1'b1;
      case (reg_bus.araddr) 
         DEBUG_CAPACITY : reg_bus.rdata <= log_size;
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end  

if (UNDO_LOG_LOGGING[TILE_ID]) begin
   logic log_valid;
   typedef struct packed {

      logic [31:0] undo_log_addr;
      logic [31:0] undo_log_data;

      logic [3:0] undo_log_id;
      logic [6:0] undo_log_cq_slot;
      logic undo_log_select_valid;
      logic [19:0] unused_1;
      

      logic [31:0] awaddr;
      logic [31:0] wdata;


      // 32
      logic [3:0] restore_arvalid;
      logic [3:0] restore_rvalid;
      logic [7:0] restore_cq_slot;
      logic awvalid;
      logic awready; 
      logic [13:0] awid;

      // 32
      logic [15:0] bid;
      logic bvalid;
      logic bready;
      logic [5:0] restore_ack_thread;
      logic [3:0] restore_done_valid;
      logic [3:0] restore_done_ready;
      
   } undo_log_t;
   undo_log_t log_word;
   always_comb begin

      log_word = '0;

      log_word.undo_log_addr = undo_log_addr[undo_log_select_core];
      log_word.undo_log_data = undo_log_data[undo_log_select_core];
      log_word.undo_log_id   = undo_log_id  [undo_log_select_core];
      log_word.undo_log_cq_slot   = undo_log_slot[undo_log_select_core];
      log_word.undo_log_select_valid = undo_log_select_valid;

      log_word.awaddr = l2.awaddr;
      log_word.wdata = l2.wdata;

      log_word.bid = l2.bid;
      log_word.bvalid = l2.bvalid;
      log_word.bready = l2.bready;
      log_word.restore_ack_thread = restore_ack_thread;
      log_word.restore_done_valid = restore_done_valid;
      log_word.restore_done_ready = restore_done_ready;
      
      log_word.restore_arvalid = restore_arvalid;
      log_word.restore_rvalid = restore_rvalid;
      log_word.restore_cq_slot = restore_cq_slot;
      
      log_word.awvalid = l2.awvalid;
      log_word.awready = l2.awready;
      log_word.awid = l2.awid;
   
      log_valid = (l2.bvalid | (restore_done_valid != 0) | restore_arvalid[3] | (restore_rvalid !=0) | l2.awvalid | undo_log_select_valid );
   end

   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) TASK_UNIT_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid(log_valid),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end

`ifdef XILINX_SIMULATOR
   if (1) begin
      logic [63:0] cycle;
      integer file,r;
      string file_name;
      initial begin
         $sformat(file_name, "undo_log_%0d.log", TILE_ID);
         file = $fopen(file_name,"w");
      end
      always_ff @(posedge clk) begin
         if (!rstn) cycle <=0;
         else cycle <= cycle + 1;
      end

      always_ff @(posedge clk) begin
         if (undo_log_select_valid) begin
            $fwrite(file,"[%5d] [rob-%2d] addr:%8x, data:%8x, id:%1x, cq_slot:%2d, core:%1d \n", 
               cycle, TILE_ID,
               undo_log_addr[undo_log_select_core],
               undo_log_data[undo_log_select_core],
               undo_log_id[undo_log_select_core],
               undo_log_slot[undo_log_select_core],
               undo_log_select_core,


            ) ;
         end
         $fflush(file);
      end
   end
`endif

end
endgenerate
endmodule
