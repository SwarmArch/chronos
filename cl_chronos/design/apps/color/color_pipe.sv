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

`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import chronos::*;

typedef struct packed {
   logic [31:0] eo_begin;
   logic [15:0] neighbor_degrees_pending;
   logic [15:0] neighbor_colors_pending;
   logic [31:0] scratch;
   logic [15:0] degree;
   logic [15:0] color;
} color_data_t;

parameter COLOR_ENQ_TASK = 0;
      // 31:0 enq_start
parameter COLOR_SEND_DEGREE_TASK = 1;
      // 15:0 enq_start
parameter COLOR_RECEIVE_DEGREE_TASK = 2;
      // [15:0] enq_start
      // [31:16] neighbor degree
      // [63:32] neighbor id
parameter COLOR_RECEIVE_COLOR_TASK = 3;
      // [15:0] enq_start
      // [63:32] neighbor id
      // [79:64] neighbor color

module color_rw
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
   output rw_data_t         wdata,

   output logic            out_valid,
   output task_t           out_task,
   output ro_data_t           out_data,

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   reg_bus_t               reg_bus

);

// headers
logic [31:0] numV, numE;
logic [31:0] base_neighbors;
logic [31:0] base_data;
logic [6:0]  enq_limit;

color_data_t read_word, write_word;
assign read_word = in_data;
assign wdata = write_word;

assign task_in_ready = sched_task_valid & sched_task_ready;
assign sched_task_valid = task_in_valid;

logic [31:0] neighbor_id; 
logic [15:0] neighbor_degree;
logic [15:0] enq_start;
assign neighbor_id = in_task.args[63:32];
assign enq_start = (in_task.ttype == COLOR_ENQ_TASK) ? in_task.args[31:0] : in_task.args[15:0];
assign neighbor_degree = in_task.args[31:16];

logic [4:0] assign_color, bitmap_color;
logic [31:0] bitmap;
assign bitmap = write_word.scratch;
lowbit #(
   .OUT_WIDTH(5),
   .IN_WIDTH(32)
) COLOR_SELECT (
   .in(~bitmap),
   .out(bitmap_color)
);

always_comb begin
   if (bitmap == 0) begin
      assign_color = 0;
   end else if (bitmap == '1) begin
      assign_color = 32;
   end else begin
      assign_color = bitmap_color;
   end
end
always_comb begin 
   wvalid = 0;
   waddr = base_data + ( in_task.object << 4) ;
   write_word = read_word;
   out_valid = 1'b0;

   out_task = in_task;

   if (task_in_valid) begin
      case (in_task.ttype)
         COLOR_ENQ_TASK: begin
            out_valid = 1'b1;
         end
         COLOR_SEND_DEGREE_TASK: begin
            if (enq_start == 0) begin
               //write_word.neighbor_degrees_pending += read_word.degree;
               //wvalid = 1'b1;
            end
            if (read_word.degree == 0) begin
               write_word.color = 0;
               wvalid = 1'b1;
            end else begin
               out_valid = 1'b1;
               out_task.args[15:0] = enq_start;
               out_task.args[31:16] = read_word.degree;
               out_task.args[63:32] = read_word.eo_begin;
            end
         end
         COLOR_RECEIVE_DEGREE_TASK: begin
            wvalid = 1'b1;
            write_word.neighbor_degrees_pending -= 1;
            if ( (neighbor_degree > read_word.degree) || ( 
               (neighbor_degree == read_word.degree) & (neighbor_id < in_task.object) )) begin
               write_word.neighbor_colors_pending += 1;
            end
            if ((write_word.neighbor_degrees_pending == 0) && (write_word.neighbor_colors_pending==0)) begin
               out_valid = 1'b1;
               out_task.args[63:32] = read_word.eo_begin;
               out_task.args[31:16] = read_word.degree;
               out_task.args[79:64]  = assign_color;
               write_word.color = assign_color;
            end
         end
         COLOR_RECEIVE_COLOR_TASK: begin
            if (enq_start == 0) begin
               if ( (neighbor_degree > read_word.degree) || ( 
                  (neighbor_degree == read_word.degree) & (neighbor_id < in_task.object) )) begin
                  wvalid = 1'b1;
                  write_word.neighbor_colors_pending -= 1;
                  write_word.scratch |= (1<<in_task.args[68:64]);
                  write_word.color = assign_color;
                  if ( (write_word.neighbor_degrees_pending == 0) && (write_word.neighbor_colors_pending==0)) begin
                     write_word.color = assign_color;
                     out_valid = 1'b1;
                     out_task.args[63:32] = read_word.eo_begin; 
                     out_task.args[31:16] = read_word.degree;
                     out_task.args[79:64]  = assign_color;
                  end
               end
            end else begin
               out_valid = 1'b1;
               out_task.args[63:32] = read_word.eo_begin; 
               out_task.args[31:16] = read_word.degree;
               out_task.args[79:64] = read_word.color;
            end
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
             4 : numV <= reg_bus.wdata;
             8 : numE <= reg_bus.wdata;
            16 : base_neighbors <= {reg_bus.wdata[29:0], 2'b00};
            20 : base_data <= {reg_bus.wdata[29:0], 2'b00};
            36 : enq_limit <= reg_bus.wdata;
         endcase
      end
   end
end

`ifdef XILINX_SIMULATOR
   logic [31:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle+1;
   end
   always_ff @(posedge clk) begin
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [rw] [%3d] type:%1d object:%4d | args: (%4d %4d %4d %4d) | ndp:%4d ncp:%d sc:%4x | eo:%4d d:%4d | out:%1d ",
         cycle, TILE_ID, in_cq_slot,
         in_task.ttype, in_task.object, 
         in_task.args[15:0], in_task.args[31:16], in_task.args[63:32], in_task.args[79:64],
         read_word.neighbor_degrees_pending, read_word.neighbor_colors_pending, read_word.scratch,
         read_word.eo_begin, read_word.degree, out_valid) ;
      end
   end
`endif
endmodule

module color_worker
#(
   parameter TILE_ID=0,
   parameter SUBTYPE=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input ro_data_t            in_data,
   input byte_t            in_word_id,
   input cq_slice_slot_t   in_cq_slot,

   output cq_slice_slot_t  out_cq_slot,
   
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

assign sched_task_valid = task_in_valid;
assign task_in_ready = sched_task_ready;
assign out_cq_slot = in_cq_slot;

// headers
logic [31:0] numV, numE;
logic [31:0] base_neighbors;
logic [31:0] base_data;
logic [6:0]  enq_limit;

logic [31:0] enq_start;
assign enq_start = (in_task.ttype == COLOR_ENQ_TASK) ? in_task.args[31:0] : {16'b0, in_task.args[15:0]};
logic [15:0] degree, n_rem_neighbors;
logic [31:0] eo_begin;
logic [15:0] color;
assign degree = in_task.args[31:16];
assign n_rem_neighbors = in_task.args[31:16];
assign color = in_task.args[79:64];
assign eo_begin = in_task.args[63:32];


always_comb begin
   araddr = 'x;
   arsize = 2;
   arlen = 0;
   arvalid = 1'b0;
   out_valid = 1'b0;
   resp_mark_last = 1'b0;
   out_task = in_task;
   out_task_is_child = 1'b1;
   resp_subtype = 1;
   resp_task = in_task;
   
   if (task_in_valid) begin
      case (in_task.ttype) 
         COLOR_ENQ_TASK: begin
            case (SUBTYPE) 
               0: begin
                  araddr = base_neighbors;
                  arvalid = 1'b1;
                  if (enq_start + enq_limit >= numV) begin
                     arlen = (numV - enq_start)-1;
                  end else begin
                     arlen = enq_limit;
                  end
               end
               1: begin
                  out_valid = 1'b1;
                  if (in_word_id == enq_limit) begin
                     out_task.ttype = COLOR_ENQ_TASK;
                     out_task.producer = 1'b1;
                     out_task.object = enq_start + enq_limit;
                     out_task.args[31:0] = enq_start + enq_limit;
                  end else begin
                     out_task.ttype = COLOR_SEND_DEGREE_TASK;
                     out_task.producer = 1'b1;
                     out_task.object = enq_start + in_word_id;
                     out_task.args[31:0] = 0; // enq_start
                  end
               end
            endcase
         end
         COLOR_SEND_DEGREE_TASK,
         COLOR_RECEIVE_DEGREE_TASK,
         COLOR_RECEIVE_COLOR_TASK         : begin
            case (SUBTYPE) 
               0: begin
                  araddr = base_neighbors + ( (eo_begin + enq_start) << 2);
                  arvalid = 1'b1;
                  if (enq_start + enq_limit >= degree) begin
                     arlen =  (degree - enq_start)-1;
                  end else begin
                     arlen = enq_limit;
                  end
               end
               1: begin
                  out_valid = 1'b1;
                  if (in_word_id == enq_limit) begin
                     out_task.ttype = (in_task.ttype == COLOR_SEND_DEGREE_TASK) ?
                                    COLOR_SEND_DEGREE_TASK : COLOR_RECEIVE_COLOR_TASK ;
                     out_task.producer = 1'b1;
                     out_task.args[15:0] = enq_start + enq_limit;
                  end else begin
                     if (in_task.ttype == COLOR_SEND_DEGREE_TASK) begin
                        out_task.ttype = COLOR_RECEIVE_DEGREE_TASK;
                        out_task.args[63:32] = in_task.object;
                        out_task.args[31:16] = degree;
                        out_task.args[15:0] = 0;
                     end else begin
                        out_task.ttype = COLOR_RECEIVE_COLOR_TASK;
                        out_task.args[63:32] = in_task.object;
                        out_task.args[79:64] = color;
                        out_task.args[15:0] = 0;

                     end
                     out_task.producer = 1'b0;
                     out_task.args[15: 0] = 0;
                     out_task.object = in_data;
                  end
               end
            endcase
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
             4 : numV <= reg_bus.wdata;
             8 : numE <= reg_bus.wdata;
            16 : base_neighbors <= {reg_bus.wdata[29:0], 2'b00};
            20 : base_data <= {reg_bus.wdata[29:0], 2'b00};
            36 : enq_limit <= reg_bus.wdata;
         endcase
      end
   end
end


endmodule

