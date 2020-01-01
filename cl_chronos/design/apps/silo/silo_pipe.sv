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
   // [31:0] tx_id
   // [63:32] start_index
   // [95:64] ol_cnt
parameter SILO_NEW_ORDER_UPDATE_STOCK = 6;
parameter SILO_NEW_ORDER_INSERT_ORDER_LINE = 7;

parameter OBJECT_DISTRICT = (1<<20);
parameter OBJECT_NEW_ORDER = (2<<20);
parameter OBJECT_ORDER = (3<<20);
parameter OBJECT_STOCK = (4<<20);
parameter OBJECT_OL = (5<<20);
parameter OBJECT_OL_CNT = (8<<20);

parameter SILO_BUCKET_SIZE = 32 * 256;
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

typedef struct packed {
   logic [8*12-1:0] __padding__ ; // to fit into 32 B
   logic [31:0] s_ytd;
   logic [31:0] s_remote_cnt;
   logic [31:0] s_order_cnt;
   logic [31:0] s_quantity;
   logic [3:0] s_w_id;
   logic [27:0] s_i_id;
} silo_stock;

module silo_read ( 
   input clk,
   input rstn,

   input task_t        task_in, 
   
   output logic [31:0] araddr,

   reg_bus_t         reg_bus
);

logic [1:0] header_top;
logic [31:0] base_district_rw;
logic [31:0] tbl_new_order_ptrs;
logic [31:0] base_new_order;
logic [31:0] base_order;
logic [31:0] base_stock;
logic [31:0] base_ol;

logic [15:0] bucket_id;
logic [7:0] offset;
assign bucket_id = task_in.object[19:4];

   
always_comb begin
   araddr = 'x;
   offset = 'x;
   case (task_in.ttype)
      SILO_TX_ENQUEUER_TASK : araddr = 0;
      SILO_NEW_ORDER_UPDATE_DISTRICT : araddr = base_district_rw + (task_in.object[7:4] * 32);
      SILO_NEW_ORDER_UPDATE_WR_PTR : araddr = tbl_new_order_ptrs;  
      SILO_NEW_ORDER_INSERT_NEW_ORDER: araddr = base_new_order + (task_in.args[31:0] * 32);
      SILO_NEW_ORDER_INSERT_ORDER : begin
         offset = task_in.args[63:48];
         araddr = base_order + bucket_id * SILO_BUCKET_SIZE + offset * 32;  
      end
      SILO_NEW_ORDER_ENQ_OL_CNT : araddr = 0;  
      SILO_NEW_ORDER_UPDATE_STOCK : begin
         offset = task_in.args[63:48];
         araddr = base_stock + bucket_id * SILO_BUCKET_SIZE + offset * 32;  
      end
      SILO_NEW_ORDER_INSERT_ORDER_LINE : begin
         offset = task_in.args[63:56];
         araddr = base_ol + bucket_id * SILO_BUCKET_SIZE + offset * 32;  
      end
   endcase
end



always_ff @(posedge clk) begin
   if (!rstn) begin
      header_top <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         if (reg_bus.waddr == CORE_HEADER_TOP) begin
            header_top <= reg_bus.wdata[1:0];
         end else if (reg_bus.waddr[15:6] == 0) begin
            case ( {header_top, reg_bus.waddr[5:0]}) 
               44 : base_district_rw <= {reg_bus.wdata[29:0], 2'b00};
               68 : base_order <= {reg_bus.wdata[29:0], 2'b00};
               76 : base_ol <= {reg_bus.wdata[29:0], 2'b00};
               92 : base_stock <= {reg_bus.wdata[29:0], 2'b00};
               96 : base_new_order <= {reg_bus.wdata[29:0], 2'b00};
              104 : tbl_new_order_ptrs <= {reg_bus.wdata[29:0], 2'b00};
            endcase
         end
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

logic [1:0] header_top;
logic [31:0] base_district_rw;
logic [31:0] tbl_new_order_ptrs;
logic [31:0] base_new_order;
logic [31:0] base_order;
logic [31:0] base_stock;
logic [31:0] base_ol;

assign task_in_ready = sched_task_valid & sched_task_ready;
assign sched_task_valid = task_in_valid;

silo_tx_info_new_order tx_info;
always_comb begin
   tx_info = 'x;
   if (task_in_valid) begin
      if (in_task.ttype == SILO_NEW_ORDER_INSERT_NEW_ORDER) begin
         tx_info = in_task.args[63:32];
      end
   end
end

logic [31:0] in_key;
logic [31:0] ref_key;
logic [7:0] offset;

silo_district_rw district_rw;

logic [15:0] bucket_id;
assign bucket_id = in_task.object[19:4];

logic [15:0] s_update_qty;
assign s_update_qty = in_task.args[47:32];


always_comb begin 
   wvalid = 1'b0;
   out_valid = 1'b0;
   out_task_rw = 1'b0;

   waddr = 'x;
   wdata = in_data;

   out_task = in_task;

   district_rw = in_data;

   in_key = 'x;
   ref_key = 'x;
   offset = 'x;

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
         SILO_NEW_ORDER_INSERT_NEW_ORDER: begin
            out_valid = 1'b0;
            wvalid = 1'b1;
            waddr = base_new_order + (in_task.args[31:0]* 32);
            wdata = 0;
            wdata[23:0] = in_task.args[95:64];
            wdata[28:24] = tx_info.d_id;
            wdata[31:29] = tx_info.w_id; 
         end
         SILO_NEW_ORDER_INSERT_ORDER : begin
            in_key = in_task.args[31:0];
            ref_key = in_data[31:0];
            offset = in_task.args[63:48];
            
            if (ref_key == '1) begin
               out_valid = 1'b0;      
               wvalid = 1'b1;
               waddr = base_order + bucket_id * SILO_BUCKET_SIZE + offset * 32;  
               wdata[31:0] = in_key;
               wdata[63:32] = in_task.args[47:32]; //  cid;
               wdata[111:104] = in_task.args[95:64]; // ol_cnt;
            end else begin
               out_task_rw = 1'b1;
               out_task.args[63:48] = offset+1;
               out_valid = 1'b1;

               wvalid = 1'b0;
            end
         end
         SILO_NEW_ORDER_ENQ_OL_CNT : begin
            out_valid = 1'b1;
            wvalid = 1'b0;
         end
         SILO_NEW_ORDER_UPDATE_STOCK : begin
            in_key = in_task.args[31:0];
            ref_key = in_data[31:0];
            offset = in_task.args[63:48];
            if (ref_key == in_key) begin
               out_valid = 1'b0;      
               wvalid = 1'b1;
               waddr = base_stock + bucket_id * SILO_BUCKET_SIZE + offset * 32;  
               wdata[31:0] = in_key;
               wdata[63:32] = in_data[63:32] - s_update_qty; //  qty;
               if (wdata[63:32] < 10) begin
                  wdata[63:32] += 91;
               end
               wdata[128 :+ 32] +=1 ; // s_ytd;
            end else begin
               out_task_rw = 1'b1;
               out_task.args[63:48] = offset+1;
               out_valid = 1'b1;

               wvalid = 1'b0;
            end
         end
         SILO_NEW_ORDER_INSERT_ORDER_LINE : begin
            in_key = in_task.args[31:0];
            ref_key = in_data[31:0];
            offset = in_task.args[63:56];
            
            if (ref_key == '1) begin
               out_valid = 1'b0;      
               wvalid = 1'b1;
               waddr = base_ol + bucket_id * SILO_BUCKET_SIZE + offset * 32;  
               wdata[31:0] = in_key;
               wdata[63:32] = in_task.args[55:32]; //  ol_i_id;
               wdata[95:64] = in_task.args[95:64]; // qty, amt, s_wid;
            end else begin
               out_task_rw = 1'b1;
               out_task.args[63:56] = offset+1;
               out_valid = 1'b1;

               wvalid = 1'b0;
            end
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      header_top <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         if (reg_bus.waddr == CORE_HEADER_TOP) begin
            header_top <= reg_bus.wdata[1:0];
         end else if (reg_bus.waddr[15:6] == 0) begin
            case ( {header_top, reg_bus.waddr[5:0]}) 
               44 : base_district_rw <= {reg_bus.wdata[29:0], 2'b00};
               68 : base_order <= {reg_bus.wdata[29:0], 2'b00};
               76 : base_ol <= {reg_bus.wdata[29:0], 2'b00};
               92 : base_stock <= {reg_bus.wdata[29:0], 2'b00};
               96 : base_new_order <= {reg_bus.wdata[29:0], 2'b00};
              104 : tbl_new_order_ptrs <= {reg_bus.wdata[29:0], 2'b00};
            endcase
         end
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
         SILO_NEW_ORDER_INSERT_NEW_ORDER: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] INSERT_NEW_ORDER  ts:%8x object:%4x | wr_ptr:%8x o_id",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object,
                  in_task.args[31:0], in_task.args[95:64]);
         end
         SILO_NEW_ORDER_INSERT_ORDER: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] INSERT_ORDER  ts:%8x object:%4x | offset:%2x in_key:%8x cur_key:%8x",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object,
                  offset, in_key, ref_key);
         end
         SILO_NEW_ORDER_ENQ_OL_CNT: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] ENQ_OL_CNT  ts:%8x object:%4x | tx_id:%3d  start_index:%2d",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object,
                  in_task.args[31:0], in_task.args[63:32]);
         end
         SILO_NEW_ORDER_UPDATE_STOCK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] UPDATE_STOCK  ts:%8x object:%4x | id:%6x offset:%2d keys:(%8x %8x) ",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object,
                  in_task.args[27:0], 
                  offset, in_key, ref_key);
         end
         SILO_NEW_ORDER_INSERT_ORDER_LINE: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] INSERT_OL  ts:%8x object:%4x | offset:%2x in_key:%8x cur_key:%8x",
               cycle, TILE_ID, in_cq_slot, in_task.ts, in_task.object,
                  offset, in_key, ref_key);
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
logic [1:0] header_top;
logic [31:0] num_tx;
logic [31:0] tx_offset;
logic [31:0] tx_data;
logic [3:0] order_n_buckets;
logic [3:0] stock_n_buckets;
logic [3:0] item_n_buckets;
logic [3:0] ol_n_buckets;
logic [31:0] base_item;

logic [31:0] pkey_in;
logic [3:0] n_buckets;
logic [7:0] offset;
logic [15:0] bucket;

logic [7:0] new_offset;
assign new_offset = offset + in_task.args[23:16];

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
silo_tx_info_order_item tx_item;
always_comb begin
   tx_info = 'x;
   tx_item = 'x;
   if (task_in_valid) begin
      if ((in_task.ttype == SILO_TX_ENQUEUER_TASK) && (SUBTYPE==2)) begin
         tx_info = in_data;
      end else if (in_task.ttype == SILO_NEW_ORDER_UPDATE_DISTRICT) begin
         tx_info = in_task.args[63:32];
      end else if (in_task.ttype == SILO_NEW_ORDER_ENQ_OL_CNT)  begin
         if (SUBTYPE==2) tx_info = in_data;
         else tx_info = in_task.args[31:0];
         tx_item = in_task.args[63:32];
      end
   end
end

/* UPDATE_DISTRICT */
logic [23:0] next_o_id;
assign next_o_id = in_task.args[95:64];

/* ENQ_OL_CNT */
logic [31:0] ol_cnt_tx_id;
logic [3:0] ol_cnt_start_index;
logic [31:0] ol_cnt_o_id; 
assign ol_cnt_tx_id = in_task.args[31:0];
assign ol_cnt_start_index = in_task.args[63:32];
assign ol_cnt_o_id = in_task.args[95:64];

/* UPDATE_STOCK */
silo_stock stock;
assign stock.s_i_id = tx_item.i_id;
assign stock.s_w_id = tx_item.i_s_wid;

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
                     n_buckets = order_n_buckets;

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
                     out_task.object = OBJECT_OL_CNT | ( in_task.args[11:0] << 8)
                           | (((in_word_id)-2) << 4) ;
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
         SILO_NEW_ORDER_ENQ_OL_CNT: begin
            // TODO: NOT TESTED AND INCOMPLETE
            case (SUBTYPE)
               0: begin
                  // Read tx_offset[tx_id]
                  arvalid = 1'b1;
                  araddr = tx_offset + ol_cnt_tx_id;
                  arlen = 0;
                  resp_subtype = 1;
               end
               1: begin
                  arvalid = 1'b1;
                  araddr = tx_data + in_data *4;
                  arlen = 0;
                  resp_subtype = 2;
                  resp_task.args[31:0] = in_data; // offset
               end
               2: begin 
                  // Read tx_item entries
                  arvalid = 1'b1;
                  araddr = tx_data + (in_task.args[31:0]+1+ ol_cnt_start_index) *4;
                  arlen = 3;
                  if (tx_info.num_items < ol_cnt_start_index + 3) begin
                     arlen = tx_info.num_items - ol_cnt_start_index - 1;
                  end
                  resp_task.args[31:0] = tx_info;
                  resp_subtype = 3;
               end
               3: begin
                  // At this point, we need to both enq a new task and to launch
                  // a mem request. Since, a subtask with both these things have
                  // not been tested, serialize things.
                  arvalid = 1'b1;
                  araddr = 0;
                  arlen = 1;
                  resp_subtype = 4;
                  resp_task.args[15: 0] = resp_task.args[15:0]; // tx_item without c_id
                  resp_task.args[31:16] = 0; // number of hash collisions for tbl_item reads
                  resp_task.args[63:32] = in_data; // tx_item
                  resp_task.args[95:92] = ol_cnt_start_index + in_word_id;
                  // 91:64 - o_id
               end
               4: begin
                  if (in_word_id == 0) begin
                     // read item
                     pkey_in = tx_item.i_id;
                     n_buckets = item_n_buckets;

                     arvalid = 1'b1;
                     araddr = base_item + bucket * SILO_BUCKET_SIZE + 
                           offset * 32;  
                     arlen = 0;
                     resp_subtype = 5;
                  end else begin
                     // enq stock update
                     pkey_in[27:0] = stock.s_i_id;
                     pkey_in[31:28] = stock.s_w_id;
                     n_buckets = stock_n_buckets;
                     
                     out_valid = 1'b1;
                     out_task.ttype = SILO_NEW_ORDER_UPDATE_STOCK;
                     out_task.object = OBJECT_STOCK | (bucket << 4);
                     out_task.ts = in_task.ts + in_task.args[95:92];
                     out_task.args[31:0] = pkey_in;
                     out_task.args[47:32] = tx_item.i_qty;
                     out_task.args[63:48] = offset;
                     out_task.args[95:64] = 0;
                  end
               end
               5: begin
                  // req item / req item price
                  pkey_in = tx_item.i_id;
                  n_buckets = item_n_buckets;
                  if (tx_item.i_id == in_data) begin
                     // req item price
                     arvalid = 1'b1;
                     araddr = base_item + bucket * SILO_BUCKET_SIZE + 
                           new_offset * 32 + 8;  
                     arlen = 0;
                     resp_subtype = 6;
                  end else begin
                     arvalid = 1'b1;
                     araddr = base_item + bucket * SILO_BUCKET_SIZE + 
                           new_offset * 32;  
                     arlen = 0;
                     resp_subtype = 5;
                     resp_task.args[23:16] = in_task.args[23:16]+1;
                  end
               end
               6: begin
                  // enq order line
                  pkey_in[19:0] = in_task.args[91:64]; // o_id
                  pkey_in[24:20] = tx_info.d_id; 
                  pkey_in[27:25] = tx_info.w_id; 
                  pkey_in[31:28] = in_task.args[95:92]; // ol_number
                  n_buckets = ol_n_buckets;
                  
                  out_valid = 1'b1;
                  out_task.ttype = SILO_NEW_ORDER_INSERT_ORDER_LINE;
                  out_task.object = OBJECT_STOCK | (bucket << 4);
                  out_task.ts = in_task.ts + in_task.args[95:92];
                  out_task.args[31:0] = pkey_in;
                  out_task.args[55:32] = tx_item.i_id;
                  out_task.args[63:56] = offset;
                  out_task.args[87:64] = in_data * tx_item.i_qty;
                  out_task.args[91:88] = tx_item.i_qty;
                  out_task.args[95:92] = tx_item.i_s_wid;
               end
            endcase
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      header_top <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         if (reg_bus.waddr == CORE_HEADER_TOP) begin
            header_top <= reg_bus.wdata[1:0];
         end else if (reg_bus.waddr[15:6] == 0) begin
            case ( {header_top, reg_bus.waddr[5:0]}) 
                4 : num_tx <= reg_bus.wdata;
                8 : tx_offset <= {reg_bus.wdata[29:0], 2'b00};
                12 : tx_data <= {reg_bus.wdata[29:0], 2'b00};
                64 : order_n_buckets <= reg_bus.wdata[19:16];
                72 : ol_n_buckets <= reg_bus.wdata[19:16];
                80 : item_n_buckets <= reg_bus.wdata[19:16];
                84 : base_item <= {reg_bus.wdata[29:0], 2'b00};
                88 : stock_n_buckets <= reg_bus.wdata[19:16];
            endcase
         end
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
         SILO_NEW_ORDER_ENQ_OL_CNT: begin
            if (SUBTYPE == 4) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t ENQ_OL_CNT %1d ts:%8x object:%4x | ol:%2d word_id:%d in_data:%4x ",
               cycle, TILE_ID, in_cq_slot, SUBTYPE,
               in_task.ts, in_task.object, 
               in_task.args[95:92], in_word_id, in_data) ;
            end
            if (SUBTYPE == 5) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t ENQ_OL_CNT 5 ts:%8x object:%4x | i_id:%4x in_data:%4x ",
               cycle, TILE_ID, in_cq_slot, 
               in_task.ts, in_task.object, tx_item.i_id, in_data) ;
            end
            if (SUBTYPE == 6) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t ENQ_OL_CNT 6 ts:%8x object:%4x | ol:%2d i_price:%4d ",
               cycle, TILE_ID, in_cq_slot, 
               in_task.ts, in_task.object, in_task.args[95:92], in_data) ;
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
      1: bucket = hashed[   8];
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
