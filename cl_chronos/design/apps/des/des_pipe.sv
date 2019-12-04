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
import des::*;

module des_rw
#(
   parameter TILE_ID=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input rw_data_t          in_data,
   input cq_slice_slot_t   in_cq_slot,
   
   output logic            wvalid,
   output logic [31:0]     waddr,
   output ro_data_t           wdata,

   output logic            out_valid,
   output task_t           out_task,
   output ro_data_t           out_data,

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   reg_bus_t               reg_bus

);

assign task_in_ready = sched_task_valid & sched_task_ready;
assign sched_task_valid = task_in_valid;

logic        use_seq_number; 
// append a per-gate 8-bit sequence number to the timestamp. This is used to
// order the outgoing messages when a gate receives two messages at the same
// timestamp.

logic_val_t  input_logic_val;
logic        input_port;

gate_t       logic_gate;
logic_val_t  logic_val_0, logic_val_1;
logic [15:0] gate_delay;

logic gate_output_changed;
logic gate_input_changed;
logic_val_t current_gate_output, new_gate_output;

logic_val_t new_gate_in0;
logic_val_t new_gate_in1;

assign new_gate_in0 = (~input_port ? input_logic_val : logic_val_0);
assign new_gate_in1 = ( input_port ? input_logic_val : logic_val_1);

logic_eval GATE_EVAL (
   .p0(new_gate_in0),
   .p1(new_gate_in1),
   .gate(logic_gate),
   .o(new_gate_output)
);

assign gate_output_changed = (current_gate_output != new_gate_output);
assign gate_input_changed = (new_gate_in0 != logic_val_0) | (new_gate_in1 != logic_val_1);

always_comb begin 
   wvalid = 0;
   wdata = in_data;
   out_valid = 1'b0;

   out_task = in_task;
   if (task_in_valid) begin
      if (in_task.ttype == 0) begin
         wvalid = 1'b1;
         wdata[21:20] = new_gate_in1;
         wdata[23:22] = new_gate_in0;
         wdata[25:24] = new_gate_output;
         out_valid = gate_output_changed;
         if (use_seq_number) begin
            wdata[31:26] = in_data[31:26] + 1;
            if ( (wdata[31:26] < in_task.ts[5:0]) & (gate_delay == 0)) begin
               // prevent TS going back
               wdata[31:26] = in_task.ts[5:0];
            end
            out_task.ts = {in_task.ts[31:8] + gate_delay, 2'b0, wdata[31:26]};
         end else begin
            out_task.ts = in_task.ts + gate_delay;
            wdata[31:26] = 0;
         end
         out_task.args[1:0] = new_gate_output;
      end else begin
         out_valid = 1'b1;
      end
   end
end

always_comb begin
   case (in_task.args[1:0])
      0: input_logic_val = LOGIC_0;
      1: input_logic_val = LOGIC_1;
      2: input_logic_val = LOGIC_X;
      3: input_logic_val = LOGIC_Z;
   endcase
   input_port = in_task.args[2];
   case (in_data[25:24])
      0: current_gate_output = LOGIC_0;
      1: current_gate_output = LOGIC_1;
      2: current_gate_output = LOGIC_X;
      3: current_gate_output = LOGIC_Z;
   endcase
   case (in_data[23:22])
      0: logic_val_0 = LOGIC_0;
      1: logic_val_0 = LOGIC_1;
      2: logic_val_0 = LOGIC_X;
      3: logic_val_0 = LOGIC_Z;
   endcase
   case (in_data[21:20])
      0: logic_val_1 = LOGIC_0;
      1: logic_val_1 = LOGIC_1;
      2: logic_val_1 = LOGIC_X;
      3: logic_val_1 = LOGIC_Z;
   endcase
   case (in_data[18:16])
      0: logic_gate = BUF;
      1: logic_gate = INV;
      2: logic_gate = NAND2;
      3: logic_gate = NOR2;
      4: logic_gate = AND2;
      5: logic_gate = OR2;
      6: logic_gate = XOR2;
      7: logic_gate = XNOR2;
   endcase
   gate_delay = in_data[15:0];
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      use_seq_number <= 1;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr)
            8'd52 : use_seq_number <= reg_bus.wdata[0];
         endcase
      end
   end
end

         
`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         if (in_task.ttype == 0) begin
            $display("[%5d] [rob-%2d] [write_rw] [%2d] ts:%8x object:%4d (type:%d (%d %d) in:(%d on %d) ->%d old:%d type:%1x",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, 
               logic_gate, logic_val_0, logic_val_1, input_logic_val, input_port,
               new_gate_output, current_gate_output,
               in_task.ttype) ;
         end else begin
            $display("[%5d] [rob-%2d] [write_rw] [%2d] ts:%8x object:%4d args:%d type:%1x",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_task.args, in_task.ttype) ;

         end
      end
   end 
`endif


endmodule

module des_ro
#(
   parameter SUBTYPE=0,
   parameter TILE_ID=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input ro_data_t            in_data,
   input byte_t            in_word_id,
   input cq_slice_slot_t   in_cq_slot,
   
   output cq_slice_slot_t   out_cq_slot,
   
   output logic            arvalid,
   output logic [31:0]     araddr,
   output logic [2:0]      arsize,
   output logic [7:0]      arlen,
   output task_t           resp_task, //each mem resp will create a new task with this parameters
   output subtype_t        resp_subtype,
   output logic            resp_mark_last, // mark the last resp task as last

   output logic            out_valid,
   output task_t           out_task,
   output subtype_t        out_subtype,

   output logic            out_task_is_child, // if 0, out_task is re-enqueued back to a FIFO, else sent to CM

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   output logic [31:0]     log_output,

   reg_bus_t               reg_bus

);

logic [31:0] offset_base_addr;
logic [31:0] neighbors_base_addr;
logic [31:0] init_edge_offset;
logic [31:0] init_edge_neighbors;
logic use_seq_number;

assign sched_task_valid = task_in_valid;
assign task_in_ready = sched_task_ready;

assign out_cq_slot = in_cq_slot;

assign resp_task = in_task;

logic [31:0] init_eo_begin;
assign init_eo_begin = in_data[31:0] + in_task.args;

always_comb begin
   araddr = 'x;
   arsize = 2;
   arlen = 0;
   arvalid = 1'b0;
   out_valid = 1'b0;
   resp_mark_last = 1'b0;
   out_task = in_task;
   out_task_is_child = 1'b1;
   resp_subtype = 'x;
   
   if (task_in_valid) begin
      if (in_task.ttype == 0) begin
         case (SUBTYPE) 
            0: begin
               araddr = offset_base_addr + (in_task.object <<  2);
               arsize = 3;
               arvalid = 1'b1;
               arlen = 0;
               resp_subtype = 1;
            end
            1: begin
               araddr = neighbors_base_addr + (in_data[31:0] << 2);
               arvalid = (in_data[63:32] != in_data[31:0]);
               arsize = 2;
               arlen = (in_data[63:32] - in_data[31:0])-1;
               resp_subtype = 2;
               resp_mark_last = 1'b1;
            end
            2: begin
               out_valid = 1'b1;
               out_task.object = in_data[31:1];
               out_task.ts = in_task.ts;
               out_task.args[2] = in_data[0];
               out_task_is_child = 1'b1;
            end
         endcase
      end else begin
         case (SUBTYPE) 
            0: begin
               araddr = init_edge_offset + (in_task.object <<  2);
               arsize = 3;
               arvalid = 1'b1;
               arlen = 0;
               resp_subtype = 1;
            end
            1: begin
               araddr = init_edge_neighbors + ( init_eo_begin <<  2);
               arvalid = (in_data[63:32] != (init_eo_begin));
               arsize = 2;
               if (in_data[63:32] - init_eo_begin > 7) begin
                  arlen = 7;
               end else begin
                  arlen = (in_data[63:32] - init_eo_begin)-1;
               end
               resp_subtype = 2;
               resp_mark_last = 1'b1;
            end
            2: begin
               out_valid = 1'b1;
               if (in_word_id == 7) begin
                  out_task.ttype = 1;
                  out_task.args = in_task.args + 7;
                  out_task_is_child = 1'b1;
                  if (use_seq_number) begin
                     out_task.ts = {in_data[23:0], 8'b0};
                  end else begin
                     out_task.ts = in_data[23:0];
                  end
               end else begin
                  out_task.ttype = 0;
                  if (use_seq_number) begin
                     out_task.ts = {in_data[23:0], 8'b0};
                  end else begin
                     out_task.ts = in_data[23:0];
                  end
                  out_task.args = {28'b0 , 1'b0 /*port*/, in_data[25:24]};
                  out_task_is_child = 1'b1;
               end
            end
         endcase

      end

   end 
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      offset_base_addr <= 0;
      neighbors_base_addr <= 0;
      use_seq_number <= 1;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr)
            8'd12 : offset_base_addr <= (reg_bus.wdata << 2);
            8'd16 : neighbors_base_addr <= (reg_bus.wdata << 2);
            8'd32 : init_edge_offset <= (reg_bus.wdata << 2);
            8'd36 : init_edge_neighbors <= (reg_bus.wdata << 2);
            8'd52 : use_seq_number <= reg_bus.wdata[0];
         endcase
      end
   end
end

`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         if (in_task.ttype == 0 & SUBTYPE==2) begin
            $display("[%5d] [rob-%2d] [ro %2d] [%3d] ts:%8x object:%4d neighbor:%5d port:%5d)",
               cycle, TILE_ID, SUBTYPE, in_cq_slot,
               in_task.ts, in_task.object, in_data[31:1], in_data[0] ) ;
         end else begin
            $display("[%5d] [rob-%2d] [ro %2d] [%3d] ts:%8x object:%4d data:(%5x %5x)",
               cycle, TILE_ID, SUBTYPE, in_cq_slot,
               in_task.ts, in_task.object, in_data[63:32], in_data[31:0] ) ;
         end
      end
   end 
`endif


endmodule


