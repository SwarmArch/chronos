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


parameter SILO_TX_ENQUEUER_TASK = 0;
   // [31:0] - enq_start
parameter SILO_NEW_ORDER_UPDATE_DISTRICT = 1;
   // [31:0] tx-id
   // [63:32] tx_info
   // [95:64] next_o_id
parameter SILO_NEW_ORDER_UPDATE_WR_PTR = 2;
   // [31:0] unused
   // [63:32] tx_info
   // [95:64] next_o_id
parameter SILO_NEW_ORDER_INSERT_NEW_ORDER = 3;
   // [31:0] wr_ptr
   // [63:32] tx_info
   // [95:64] next_o_id
parameter SILO_NEW_ORDER_INSERT_ORDER = 4;
parameter SILO_NEW_ORDER_ENQ_OL_CNT = 5;
parameter SILO_NEW_ORDER_UPDATE_STOCK = 6;
parameter SILO_NEW_ORDER_INSERT_ORDER_LINE = 7;

parameter OBJECT_DISTRICT = (1<<20);
parameter OBJECT_NEW_ORDER = (2<<20);
parameter OBJECT_ORDER = (3<<20);

typedef struct packed {
   logic [15:0] c_id;
   logic [3:0] num_items;
   logic [3:0] d_id;
   logic [3:0] w_id;
   logic [3:0] tx_type;
} silo_tx_info_new_order;

typedef struct packed {
   logic [3:0]  i_s_wid;
   logic [3:0]  i_qty;
   logic [23:0] i_id;
} silo_tx_info_order_item;

typedef struct packed {
   logic [8*24-1:0] __padding__;
   logic [31:0] d_ytd;
   logic [31:0] d_next_o_id;
} silo_district_rw;

module silo_read ( 
   input clk,
   input rstn,

   input task_t        task_in, 
   
   output logic [31:0] araddr,

   reg_bus_t         reg_bus
);

logic [31:0] base_district_rw;
logic [31:0] tbl_new_order_ptrs;
   
always_comb begin
   araddr = 'x;
   case (task_in.ttype)
      SILO_TX_ENQUEUER_TASK : araddr = 0;
      SILO_NEW_ORDER_UPDATE_DISTRICT : araddr = base_district_rw + (task_in.object[7:4] * 32);
      SILO_NEW_ORDER_UPDATE_WR_PTR : araddr = tbl_new_order_ptrs;  
      SILO_NEW_ORDER_INSERT_ORDER : araddr = 0;  
      SILO_NEW_ORDER_ENQ_OL_CNT : araddr = 0;  
   endcase
end



always_ff @(posedge clk) begin
   if (!rstn) begin
      base_district_rw <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            44 : base_district_rw <= {reg_bus.wdata[29:0], 2'b00};
           104 : tbl_new_order_ptrs <= {reg_bus.wdata[29:0], 2'b00};
         endcase
      end
   end
end
endmodule

module silo_write
#(
   parameter TILE_ID=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input rw_data_t         in_data,
   input cq_slice_slot_t   in_cq_slot,
   output logic [2:0]      wsize,
   
   output logic            wvalid,
   output logic [31:0]     waddr,
   output rw_data_t        wdata,

   output logic            out_valid,
   output task_t           out_task,
   output ro_data_t        out_data,
   output logic            out_task_rw,

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   reg_bus_t               reg_bus

);

logic [31:0] base_district_rw;
logic [31:0] tbl_new_order_ptrs;

assign task_in_ready = sched_task_valid & sched_task_ready;
assign sched_task_valid = task_in_valid;

silo_district_rw district_rw;

always_comb begin 
   wvalid = 1'b0;
   out_valid = 1'b0;
   out_task_rw = 1'b0;

   waddr = 'x;
   wdata = in_data;

   out_task = in_task;

   district_rw = in_data;

   if (task_in_valid) begin
      case (in_task.ttype)
         SILO_TX_ENQUEUER_TASK: begin
            wvalid = 1'b0;
            out_valid = 1'b1;
         end
         SILO_NEW_ORDER_UPDATE_DISTRICT: begin
            out_valid = 1'b1;
            out_task.args[95:64] = district_rw.d_next_o_id;
            district_rw.d_next_o_id += 1;
            waddr = base_district_rw + (in_task.object[7:4] * 32);
            wdata = district_rw;
            wvalid = 1'b1;
         end
         SILO_NEW_ORDER_UPDATE_WR_PTR : begin
            out_valid = 1'b1;
            out_task.args[31:0] = in_data[31:0];
            
            wvalid = 1'b1;
            waddr = tbl_new_order_ptrs;
            wdata[31:0] = in_data[31:0] + 1; // wr_ptr++
         end
         SILO_NEW_ORDER_INSERT_ORDER : begin
            out_valid = 1'b0;
            wvalid = 1'b0;
         end
         SILO_NEW_ORDER_ENQ_OL_CNT : begin
            out_valid = 1'b0;
            wvalid = 1'b0;
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            44 : base_district_rw <= {reg_bus.wdata[29:0], 2'b00};
           104 : tbl_new_order_ptrs <= {reg_bus.wdata[29:0], 2'b00};
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
         case (in_task.ttype)
         SILO_TX_ENQUEUER_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] TX_ENQUEUER ts:%8x object:%4x |enq_start:%d",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object, in_task.args[31:0]);
         end
         SILO_NEW_ORDER_UPDATE_DISTRICT: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] UPDATE_DIST ts:%8x object:%4x | args:%8x next_o_id:%d",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object, in_task.args[31:0], district_rw.d_next_o_id);
         end
         SILO_NEW_ORDER_UPDATE_WR_PTR: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] UPDATE_PTR  ts:%8x object:%4x | wr_ptr:%8x rd_ptr:%8x",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object,
                  in_data[31:0], in_data[63:32]);
         end

         endcase
      end
   end
`endif
endmodule

module silo_ro
#(
   parameter TILE_ID=0,
   parameter SUBTYPE=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input ro_data_t         in_data,
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
logic [31:0] num_tx;
logic [31:0] tx_offset;
logic [31:0] tx_data;
logic [3:0] order_n_buckets;

logic [31:0] pkey_in;
logic [3:0] n_buckets;
logic [7:0] offset;
logic [15:0] bucket;


pkey_hash hash (
   .key(pkey_in),
   .n_buckets(n_buckets),
   .offset(offset),
   .bucket(bucket)
);


/* TX_ENQUEUE */
logic [31:0] enq_start; 
assign enq_start = in_task.args[31:0];
silo_tx_info_new_order tx_info;
always_comb begin
   tx_info = 'x;
   if (task_in_valid) begin
      if ((in_task.ttype == SILO_TX_ENQUEUER_TASK) && (SUBTYPE==2)) begin
         tx_info = in_data;
      end else if (in_task.ttype == SILO_NEW_ORDER_UPDATE_DISTRICT) begin
         tx_info = in_task.args[63:32];
      end
   end
end

/* UPDATE_DISTRICT */
logic [23:0] next_o_id;
assign next_o_id = in_task.args[95:64];




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

   pkey_in = 'x;
   n_buckets = 8;
   
   if (task_in_valid) begin
      case (in_task.ttype) 
         SILO_TX_ENQUEUER_TASK: begin
            case (SUBTYPE) 
               0: begin
                  arvalid = 1'b1;
                  araddr = tx_offset + enq_start * 4;
                  arlen = 8;
                  if (num_tx <= enq_start + 7) begin
                     arlen = (num_tx - enq_start) - 1;
                  end
                  resp_subtype = 1;
               end
               1: begin
                  if (in_word_id == 7) begin
                     // enq continuation task
                     //out_valid = 1'b1;
                     out_task.args[31:0] += 7;
                     out_task.ts = ((enq_start + 7) << 8);
                  end else begin
                     arvalid = 1'b1;
                     araddr = tx_data + in_data * 4;
                     arlen = 0;
                     resp_subtype = 2;
                     resp_task.args[31:0] = in_task.args[31:0] + in_word_id;
                  end
               end
               2: begin
                  out_valid = 1'b1;
                  out_task.ttype = SILO_NEW_ORDER_UPDATE_DISTRICT;
                  out_task.ts = resp_task.args << 8;
                  out_task.object = OBJECT_DISTRICT | (tx_info.d_id << 4);
                  out_task.args[63:32] = in_data;
               end
            endcase
         end
         SILO_NEW_ORDER_UPDATE_DISTRICT: begin
            case (SUBTYPE) 
               0: begin
                  arvalid = 1'b1;
                  araddr = 0;
                  arlen = 1 + (tx_info.num_items >> 2) + 
                     ((tx_info.num_items[1:0] == 0) ? 0 : 1); // 2 + floor(num_items/4)
                  resp_subtype = 1;
               end
               1: begin
                  if (in_word_id == 0) begin
                     out_valid = 1'b1;
                     out_task.ttype = SILO_NEW_ORDER_UPDATE_WR_PTR;
                     out_task.args[31:0] = 'x;
                     out_task.object = OBJECT_NEW_ORDER;
                     // other args, same as incoming: 1-tx_info, 2-o_id
                  end else if (in_word_id == 1) begin
                     pkey_in[23:0] = next_o_id;
                     pkey_in[28:24] = tx_info.d_id;
                     pkey_in[31:29] = tx_info.w_id;

                     out_valid = 1'b1;
                     out_task.ttype = SILO_NEW_ORDER_INSERT_ORDER;
                     out_task.object = OBJECT_ORDER | (bucket << 4);
                     out_task.args[31:0] = pkey_in;
                     out_task.args[47:32] = tx_info.c_id;
                     out_task.args[63:48] = offset;
                     out_task.args[95:64] = tx_info.num_items;
                  end else begin
                     out_valid = 1'b1;
                     out_task.ttype = SILO_NEW_ORDER_ENQ_OL_CNT;
                     // arg0 - tx_id, arg1 - index, arg2 - o_id
                     out_task.args[63:32] = (in_word_id -2) * 4;
                  end   
               end
            endcase
         end
         SILO_NEW_ORDER_UPDATE_WR_PTR: begin
            out_valid = 1'b1;
            out_task.ttype = SILO_NEW_ORDER_INSERT_NEW_ORDER;
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
             4 : num_tx <= reg_bus.wdata;
             8 : tx_offset <= {reg_bus.wdata[29:0], 2'b00};
             12 : tx_data <= {reg_bus.wdata[29:0], 2'b00};
             64 : order_n_buckets = reg_bus.wdata[19:16];
             /*
             8 : numE <= reg_bus.wdata;
            16 : base_neighbors <= {reg_bus.wdata[29:0], 2'b00};
            20 : base_data <= {reg_bus.wdata[29:0], 2'b00};
            36 : enq_limit <= reg_bus.wdata;
            */
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
         case (in_task.ttype) 
         SILO_TX_ENQUEUER_TASK: begin
            if (SUBTYPE == 0) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t TX_ENQUEUER 0 ts:%8x object:%4x | enq_start:%4d ",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, enq_start) ;
            end
            if (SUBTYPE == 1) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t TX_ENQUEUER 1 ts:%8x object:%4x | word_id:%d offset %d ",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_word_id, in_data) ;
            end
            if (SUBTYPE == 2) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t TX_ENQUEUER 2 ts:%8x object:%4x | tx_id:%3d district: %d",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_task.args[31:0], tx_info.d_id) ;
            end
         end
         SILO_NEW_ORDER_UPDATE_DISTRICT: begin
            if (SUBTYPE == 0) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t UPDATE_DIST 0 ts:%8x object:%4x | tx_id:%4x ",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_task.args[31:0]) ;
            end
            if (SUBTYPE == 1) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t UPDATE_DIST 1 ts:%8x object:%4x | word_id:%d",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_word_id) ;
            end
         end
         endcase
      end
   end 
`endif

endmodule


module pkey_hash(
   input [31:0] key,
   input [3:0] n_buckets,
   output logic [7:0] offset,
   output logic [15:0] bucket
);

localparam logic [0:31] [31:0] hash_keys = {
      32'hc4252fd6,
      32'hfefae102,
      32'h0893b429,
      32'h6c6c8792,
      32'hf48f4329,
      32'he507f162,
      32'h53b8d2ce,
      32'hfd90b3aa,
      32'hc12fd5f1,
      32'h01b1aea4,
      32'ha12054b1,
      32'hb6c529dc,
      32'h6f84e59e,
      32'h90b2164e,
      32'ha19b2cfe,
      32'h34600bf4,
      32'h94f792e4,
      32'h10f09caa,
      32'h14671d06,
      32'ha7516124,
      32'he02b122c,
      32'h245254ca,
      32'h452fa591,
      32'h190a4e54,
      32'h4c50401e,
      32'h87a1574d,
      32'h780e947e,
      32'h3b613b60,
      32'h2b0404f3,
      32'h8c103276,
      32'h615735a1,
      32'h925e0a83
};

logic [31:0] hashed;
generate genvar i;
for (i=0;i<32;i++) begin
   assign hashed[i] = ^(key & hash_keys[i]);
end
endgenerate

assign offset = hashed[7:0];
always_comb begin
   case (n_buckets) 
      8: bucket = hashed[15:8];
      9: bucket = hashed[16:8];
     10: bucket = hashed[17:8];
     11: bucket = hashed[18:8];
     12: bucket = hashed[19:8];
     13: bucket = hashed[20:8];
     14: bucket = hashed[21:8];
     15: bucket = hashed[22:8];
     default: bucket = hashed[23:8];
   endcase
end
endmodule
