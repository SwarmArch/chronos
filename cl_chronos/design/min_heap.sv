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

// Amazon FPGA Hardware Development Kit
//
// Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.

import chronos::*;


// Ideally the size of addr_t should be based on the instantiation parameter N_STAGES.
// But I cant figure out a way to do this in SV. Hence size for the largest
typedef logic [TQ_STAGES-1:0] addr_t;
   

module min_heap #(
   parameter N_STAGES = 10,
   parameter PRIORITY_WIDTH = 32,
   parameter DATA_WIDTH = 33,
   parameter DETERMINISTIC = 0 
) (
   input clk,
   input rstn,

   input [PRIORITY_WIDTH-1:0] in_ts,
   input [DATA_WIDTH-1:0] in_data,
   heap_op_t in_op,
   output logic ready,

   output logic [PRIORITY_WIDTH-1:0] out_ts,
   output logic [DATA_WIDTH-1:0] out_data,
   output logic out_valid,
   
   output logic [N_STAGES-1:0] capacity,

   output logic [PRIORITY_WIDTH-1:0] max_out_ts,
   output logic [DATA_WIDTH-1:0] max_out_data,
   output logic max_out_valid,

   output addr_t max_out_pos
);
   
   //allocate in excess so as to make indexing easier
   heap_op_t pipe_op[0:N_STAGES]; // N_STAGES has no sink for all three
   addr_t pipe_pos[0:N_STAGES];
   logic[PRIORITY_WIDTH-1:0] pipe_ts[0:N_STAGES];
   logic[DATA_WIDTH-1:0] pipe_data[0:N_STAGES];

   heap_op_t cur_op[0:N_STAGES-1];

   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  rdata_c[0:N_STAGES-1]();
   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  rdata_0_n[0:N_STAGES-1](); // STAGE-1 has no source. Hence set below.
   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  rdata_1_n[0:N_STAGES-1]();

   addr_t waddr_c[0:N_STAGES-1];
   addr_t waddr_n[0:N_STAGES-1]; // N_STAGES-1 has no sink
   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  wdata_c[0:N_STAGES-1]();
   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  wdata_n[0:N_STAGES-1](); // N_STAGES-1 has no sink

   logic wr_en_c[0:N_STAGES-1];
   logic wr_en_n[0:N_STAGES-1]; // N_STAGES-1 has no sink


   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  min_entry(); 
   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  next_heap_entry(); 

   assign pipe_op[0] = in_op;
   assign pipe_pos[0] = 1;
   assign pipe_ts[0] = in_ts;
   assign pipe_data[0] = in_data;
   
   assign out_ts = min_entry.ts;
   assign out_valid = min_entry.active;
   assign out_data = min_entry.data;

   assign capacity = min_entry.capacity;

   assign ready = (cur_op[0] == NOP);

   logic stage_0_wr_en;
   always_comb begin
      stage_0_wr_en = 1'b0;
      next_heap_entry.active   = 1'b0;
      next_heap_entry.ts       = 'x;
      next_heap_entry.data     = 'x;
      next_heap_entry.capacity = min_entry.capacity;

      if (pipe_op[0] == REPLACE) begin
         stage_0_wr_en = 1'b1;
         next_heap_entry.active = 1'b1;
         next_heap_entry.ts = in_ts;
         next_heap_entry.data = in_data;
      end else if (pipe_op[0] == DEQ_MAX_REPLACE) begin
         stage_0_wr_en = 1'b1;
         next_heap_entry.active = 1'b1;
         next_heap_entry.ts = in_ts;
         next_heap_entry.data = in_data;
         next_heap_entry.capacity = min_entry.capacity + 1;
      end else if (pipe_op[0] == DEQ_MIN) begin
         stage_0_wr_en = 1'b1;
         next_heap_entry.capacity = min_entry.capacity + 1;
      end
   end

   // edge cases
   assign rdata_0_n[N_STAGES-1].active = 1'b0;
   assign rdata_1_n[N_STAGES-1].active = 1'b0;
   assign rdata_0_n[N_STAGES-1].capacity = 0;
   assign rdata_1_n[N_STAGES-1].capacity = 0;

   // output from last pipe stage of the token array
   assign max_out_valid = (pipe_op[N_STAGES] == DEQ_MAX);
   assign max_out_ts  = pipe_ts[N_STAGES];
   assign max_out_data  = pipe_data[N_STAGES];
   assign max_out_pos = pipe_pos[N_STAGES];

   generate genvar i;
   for (i=0;i <N_STAGES; i=i+1)
      heap_stage #(
         .N_STAGES(N_STAGES),
         .STAGE_ID(i),
         .PRIORITY_WIDTH(PRIORITY_WIDTH),
         .DATA_WIDTH(DATA_WIDTH),
         .DETERMINISTIC(DETERMINISTIC)
      ) HEAP_STAGE (
         .clk(clk),
         .rstn(rstn),

         .in_op(pipe_op[i]),
         .in_pos(pipe_pos[i]),
         .in_ts(pipe_ts[i]),
         .in_data(pipe_data[i]),

         .cur_op(cur_op[i]),

         .rdata_c(rdata_c[i]),
         .rdata_0_n(rdata_0_n[i]),
         .rdata_1_n(rdata_1_n[i]),
         
         .out_op(pipe_op[i+1]),
         .out_pos(pipe_pos[i+1]),
         .out_ts(pipe_ts[i+1]),
         .out_data(pipe_data[i+1]),
         
         .waddr_c(waddr_c[i]),
         .waddr_n(waddr_n[i]),

         .wdata_c(wdata_c[i]),
         .wdata_n(wdata_n[i]),

         .wr_en_c(wr_en_c[i]),
         .wr_en_n(wr_en_n[i])

      );
   endgenerate
   
   stage_mem_0 #(
      .N_STAGES(N_STAGES),
      .PRIORITY_WIDTH(PRIORITY_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
   ) STAGE_MEM_0 (
      .clk(clk),
      .rstn(rstn),
      
      .op_c(pipe_op[0]),
      .op_n(cur_op[0]),

      .rdata_p(min_entry),
      .rdata_c(rdata_c[0]),

      .wdata_p(next_heap_entry),
      .wdata_c(wdata_c[0]),

      .wr_en_p(stage_0_wr_en),
      .wr_en_c(wr_en_c[0])
   );

   stage_mem_1 #(
      .N_STAGES(N_STAGES),
      .PRIORITY_WIDTH(PRIORITY_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
   ) STAGE_MEM_1 (
      .clk(clk),
      .rstn(rstn),
      
      .op_p(pipe_op[0]),
      .op_c(pipe_op[1]),
      .op_n(cur_op[1]),

      .raddr_p(pipe_pos[0] * 2),
      .raddr_c(pipe_pos[1]),
      
      .rdata_0_p(rdata_0_n[0]),
      .rdata_1_p(rdata_1_n[0]),
      .rdata_c(rdata_c[1]),

      .waddr_p(waddr_n[0]),
      .waddr_c(waddr_c[1]),

      .wdata_p(wdata_n[0]),
      .wdata_c(wdata_c[1]),

      .wr_en_p(wr_en_n[0]),
      .wr_en_c(wr_en_c[1])
   );

   generate genvar j;
   for (j=2; j<N_STAGES; j=j+1) 
      stage_mem #(
         .N_STAGES(N_STAGES),
         .STAGE_ID(j),
         .PRIORITY_WIDTH(PRIORITY_WIDTH),
         .DATA_WIDTH(DATA_WIDTH)
      ) STAGE_MEM (
         .clk(clk),
         .rstn(rstn),
         
         .op_p(pipe_op[j-1]),
         .op_c(pipe_op[j]), 
         .op_n(cur_op[j]),

         .raddr_p(pipe_pos[j-1]*2),
         .raddr_c(pipe_pos[j]),
         
         .rdata_0_p(rdata_0_n[j-1]),
         .rdata_1_p(rdata_1_n[j-1]),
         .rdata_c(rdata_c[j]),

         .waddr_p(waddr_n[j-1]),
         .waddr_c(waddr_c[j]),
   
         .wdata_p(wdata_n[j-1]),
         .wdata_c(wdata_c[j]),

         .wr_en_p(wr_en_n[j-1]),
         .wr_en_c(wr_en_c[j])
      );
   endgenerate
   
endmodule

module heap_stage
#(
   parameter STAGE_ID,
   parameter N_STAGES,
   parameter PRIORITY_WIDTH,
   parameter DATA_WIDTH,
   parameter DETERMINISTIC
) (
   input clk,
   input rstn,

   input heap_op_t in_op,
   input addr_t in_pos,
   input logic [PRIORITY_WIDTH-1:0] in_ts,
   input logic [DATA_WIDTH-1:0] in_data,
   
   heap_entry_t.in rdata_c,
   heap_entry_t.in rdata_0_n,
   heap_entry_t.in rdata_1_n,
   
   output heap_op_t out_op,
   output addr_t out_pos,
   output logic [PRIORITY_WIDTH-1:0] out_ts,
   output logic [DATA_WIDTH-1:0] out_data,

   output heap_op_t cur_op,
  
   output addr_t waddr_c,
   output addr_t waddr_n,

   heap_entry_t.out wdata_c,
   heap_entry_t.out wdata_n,

   output logic wr_en_c,
   output logic wr_en_n
);

   addr_t cur_pos;
   logic [PRIORITY_WIDTH-1:0] cur_ts;
   logic [DATA_WIDTH-1:0] cur_data;

   logic [7:0] lfsr;
   logic lfsr_new_bit;
   assign lfsr_new_bit = ^(lfsr & ((STAGE_ID * 7)));
   always_ff @(posedge clk) begin
      if (!rstn) begin
         lfsr <= STAGE_ID;
      end else begin
         lfsr <= { lfsr[6:0], lfsr_new_bit };
      end
   end

   always_ff @(posedge clk) begin
       cur_op <= in_op;
       cur_pos <= in_pos;
       cur_ts <= in_ts;
       cur_data <= in_data;
   end

   always_comb begin
      waddr_c = 'x;
      waddr_n = 'x;

      wdata_c.active = rdata_c.active;
      wdata_c.capacity = rdata_c.capacity;
      wdata_c.ts = rdata_c.ts;
      wdata_c.data = rdata_c.data;
      {wdata_n.active, wdata_n.capacity, wdata_n.ts, wdata_n.data} = 'x;

      out_op = cur_op;
      out_pos = cur_pos * 2;
      out_ts = 'x;
      out_data = 'x;

      wr_en_c = 1'b0;
      wr_en_n = 1'b0;

      case(cur_op)
         ENQ, DEQ_MAX_ENQ: begin
            if (!rdata_c.active) begin
               wdata_c.active = (cur_op == ENQ);
               wdata_c.ts = cur_ts;
               wdata_c.data = cur_data;
               wdata_c.capacity = rdata_c.capacity -1 + ((cur_op==DEQ_MAX_ENQ) ? 1 :0);
               out_op = (cur_op == ENQ) ? NOP : DEQ_MAX;
               out_ts = cur_ts;
               out_data = cur_data;
               wr_en_c = 1'b1;
               waddr_c = cur_pos;
            end else if (cur_ts < rdata_c.ts) begin
               // swap cur_task with rdata_c.vtask
               out_ts = rdata_c.ts;
               out_data = rdata_c.data;
               wdata_c.ts = cur_ts;
               wdata_c.data = cur_data;
               wdata_c.active = 1'b1;
               wdata_c.capacity = rdata_c.capacity -1 + ((cur_op==DEQ_MAX_ENQ) ? 1 :0);
               wr_en_c = 1'b1;
               waddr_c = cur_pos;
            end else begin
               out_ts = cur_ts;
               out_data = cur_data;
               wdata_c.capacity = rdata_c.capacity -1 + ((cur_op==DEQ_MAX_ENQ) ? 1 :0);
               wr_en_c = 1'b1;
               waddr_c = cur_pos;
            end
            if (DETERMINISTIC) begin
               if ((rdata_0_n.capacity ==0) | 
                     (rdata_1_n.active & (rdata_1_n.capacity > 0) & (cur_ts > rdata_1_n.ts) ) ) begin
                  out_pos = cur_pos * 2 + 1;
               end else begin
                  out_pos = cur_pos * 2; 
               end
            end else begin
               // if can both ways, randomize
               if ( (rdata_0_n.capacity > 0) & (rdata_1_n.capacity > 0)) begin
                  out_pos = cur_pos * 2 + lfsr[1]; // chose bit 1 because bit 0 may never change at full rate 
               end else if (rdata_0_n.capacity > 0) begin
                  out_pos = cur_pos * 2; 
               end else begin
                  out_pos = cur_pos * 2 + 1;
               end
            end
         end
         DEQ_MIN: begin
            if (!rdata_0_n.active & !rdata_1_n.active) begin
               out_op = NOP;
            end else begin
               wdata_c.active = 1'b1;
               wr_en_c = 1'b1;
               waddr_c = cur_pos;
               wr_en_n = 1'b1;
               if (
                  (rdata_0_n.active & rdata_1_n.active &
                     (rdata_0_n.ts <= rdata_1_n.ts)) |
                  (!rdata_1_n.active) )
               begin
                  // go left
                  wdata_c.ts = rdata_0_n.ts;
                  wdata_c.data = rdata_0_n.data;
                  wdata_n.active = 1'b0;
                  wdata_n.capacity = rdata_0_n.capacity + 1;
                  out_pos = cur_pos * 2;
                  waddr_n = cur_pos * 2;
               end else if (
                  (rdata_0_n.active & rdata_1_n.active &
                     (rdata_1_n.ts < rdata_0_n.ts)) |
                  (!rdata_0_n.active) )
               begin
                  // go right 
                  wdata_c.ts = rdata_1_n.ts;
                  wdata_c.data = rdata_1_n.data;
                  wdata_n.active = 1'b0;
                  wdata_n.capacity = rdata_1_n.capacity + 1;
                  out_pos = cur_pos * 2 + 1;
                  waddr_n = cur_pos * 2 + 1;
               end
            end
         end
         REPLACE, DEQ_MAX_REPLACE: begin
            if (
               // both children are inactive
               (!rdata_0_n.active & !rdata_1_n.active) |
               // or lower than both children
               ( rdata_0_n.active & rdata_1_n.active &
                     (rdata_c.ts < rdata_0_n.ts) &
                     (rdata_c.ts < rdata_1_n.ts)) |
               // or lower than the single active child
               ( !rdata_1_n.active & (rdata_c.ts < rdata_0_n.ts) ) |
               ( !rdata_0_n.active & (rdata_c.ts < rdata_1_n.ts) ) )
               
            begin
               if (cur_op == DEQ_MAX_REPLACE) begin
                  out_op = DEQ_MAX;
                  if ( (rdata_1_n.active & rdata_0_n.active) & !DETERMINISTIC) begin
                     out_pos = cur_pos * 2 + lfsr[1];
                  end else if (rdata_1_n.active) begin
                     out_pos = cur_pos * 2 + 1;
                  end else if (rdata_0_n.active) begin
                     out_pos = cur_pos * 2;
                  end else begin
                     out_ts = rdata_c.ts;
                     out_data = rdata_c.data;
                     wdata_c.active = 1'b0;
                     wr_en_c = 1'b1;
                     waddr_c = cur_pos;
                  end
               end else begin
                  out_op = NOP;
               end
            end else begin
               wdata_c.active = 1'b1;
               wr_en_c = 1'b1;
               waddr_c = cur_pos;
               wr_en_n = 1'b1;
               if (
                  (rdata_0_n.active & rdata_1_n.active & 
                     rdata_0_n.ts <= rdata_1_n.ts) |
                  (!rdata_1_n.active) )
               begin
                  // swap with left
                  wdata_c.ts = rdata_0_n.ts;
                  wdata_c.data = rdata_0_n.data;
                  wdata_n.ts = rdata_c.ts;
                  wdata_n.data = rdata_c.data;
                  wdata_n.active = 1'b1;
                  wdata_n.capacity = rdata_0_n.capacity + ((cur_op==DEQ_MAX_REPLACE) ? 1 :0);
                  out_pos = cur_pos * 2;
                  waddr_n = cur_pos * 2;
               end else if (
                  (rdata_0_n.active & rdata_1_n.active & 
                     rdata_1_n.ts < rdata_0_n.ts) |
                  (!rdata_0_n.active) )
               begin
                  wdata_c.ts = rdata_1_n.ts;
                  wdata_c.data = rdata_1_n.data;
                  wdata_n.ts = rdata_c.ts;
                  wdata_n.data = rdata_c.data;
                  wdata_n.active = 1'b1;
                  wdata_n.capacity = rdata_1_n.capacity + ((cur_op==DEQ_MAX_REPLACE) ? 1 :0);
                  out_pos = cur_pos * 2 + 1;
                  waddr_n = cur_pos * 2 + 1;
               end
            end

         end
         DEQ_MAX: begin
            // Can we do DEQ_MAX operations on successive cycles?
            // No. No bypass from wr_data of stage n to rd_data of stage n-1
            out_op = DEQ_MAX;
            if (!rdata_c.active) begin
               // pass it down on the token pipeline
               out_ts = cur_ts;
               out_data = cur_data;
            end else begin
               wr_en_c = 1'b1;
               waddr_c = cur_pos;
               wdata_c.capacity = rdata_c.capacity + 1;
               if ( (rdata_1_n.active & rdata_0_n.active) & !DETERMINISTIC) begin
                  out_pos = cur_pos * 2 + lfsr[1];
               end else if (rdata_1_n.active) begin
                  out_pos = cur_pos * 2 + 1;
               end else if (rdata_0_n.active) begin
                  out_pos = cur_pos * 2;
               end else begin
                  out_ts = rdata_c.ts;
                  out_data = rdata_c.data;
                  wdata_c.active = 1'b0;
               end
            end
            
         end
         default: begin

         end
      endcase
   end
endmodule

module stage_mem
#(
   parameter STAGE_ID,
   parameter N_STAGES,
   parameter PRIORITY_WIDTH,
   parameter DATA_WIDTH
) (
   input clk,
   input rstn,
   
   input heap_op_t op_p, // op coming in to the previous level in the next cycle
   input heap_op_t op_c, // op coming in to the current level in the next cycle
   input heap_op_t op_n, // op performed in the current level in this cycle
                    // (may not be the same as op going into next level) 
   
   input addr_t raddr_p, // address of data going out to previous level next cycle
   input addr_t raddr_c, // address of data going out to current level next cycle

   heap_entry_t.out rdata_0_p, // data going out to previous level from bank0
   heap_entry_t.out rdata_1_p,
   heap_entry_t.out rdata_c, // data going out current level this cycle

   input addr_t waddr_p, // address of data being written from previous level
   input addr_t waddr_c, // address of data being written from current level

   // 1 write from current level or 1 from prev level
   heap_entry_t.in wdata_p,
   heap_entry_t.in wdata_c,

   input wr_en_p,
   input wr_en_c

);
   // Force BRAM synthesis for all fields. heap_entry_s array[] does not do so.
   localparam MEM_WIDTH = 1+N_STAGES + PRIORITY_WIDTH + DATA_WIDTH;
   //(* ram_style = "block" *)
   logic [MEM_WIDTH-1:0] bank_0[0:2**(STAGE_ID-1)-1];
   //(* ram_style = "block" *)
   logic [MEM_WIDTH-1:0] bank_1[0:2**(STAGE_ID-1)-1];

   // raddr_c corresponds to the data provided to the current level. 
   // However this request has to come one cycle before. 
   // Hence the corresponding op is op_p,
   // For raddr_p, the op is op_2p.
   // at least one of the ops are guaranteed be a NOP. select from the other
   addr_t raddr;
   addr_t waddr;
   assign raddr = (op_c != NOP) ? raddr_c : raddr_p;
   assign waddr = (op_n != NOP) ? waddr_c : waddr_p;
   
   logic [MEM_WIDTH-1:0] wdata;
   assign wdata = (op_n != NOP) ? 
      {wdata_c.active, wdata_c.capacity, wdata_c.ts, wdata_c.data} : 
      {wdata_p.active, wdata_p.capacity, wdata_p.ts, wdata_p.data} ; 
   
   logic wr_en, wr_en_0, wr_en_1;
   assign wr_en  = (op_n != NOP) ? wr_en_c : wr_en_p;
   
   assign wr_en_0 = wr_en & ~waddr[0];
   assign wr_en_1 = wr_en & waddr[0];

   logic [MEM_WIDTH-1:0] rdata_0;
   logic [MEM_WIDTH-1:0] rdata_1;
   assign {rdata_0_p.active, rdata_0_p.capacity, rdata_0_p.ts, rdata_0_p.data} = rdata_0;
   assign {rdata_1_p.active, rdata_1_p.capacity, rdata_1_p.ts, rdata_1_p.data} = rdata_1;

   addr_t raddr_d1;
   assign {rdata_c.active, rdata_c.capacity, rdata_c.ts, rdata_c.data} = 
      raddr_d1[0] ? rdata_1 : rdata_0;

   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  init_data();
   initial begin 
      init_data.active = 1'b0;
      init_data.ts = 'x;
      init_data.data = 'x;
      init_data.capacity = 2**(N_STAGES-STAGE_ID) -1;
      for (integer i=0;i< 2**(STAGE_ID-1); i= i+1) begin
         bank_0[i] = {init_data.active, init_data.capacity, init_data.ts, init_data.data};
         bank_1[i] = {init_data.active, init_data.capacity, init_data.ts, init_data.data};
      end
   end
   
   always_ff @(posedge clk) begin
      raddr_d1 <= raddr;
   end
   
   // match BRAM template
   logic [MEM_WIDTH-1:0] bank_0_out;
   logic [MEM_WIDTH-1:0] bank_1_out;
   logic addr_collision_0, addr_collision_1;
   logic [MEM_WIDTH-1:0] wdata_d1_0;
   logic [MEM_WIDTH-1:0] wdata_d1_1;

   always_ff @(posedge clk) begin
      if (wr_en_0) begin
         bank_0[ waddr[STAGE_ID-1:1] ] <= wdata; 
      end
      bank_0_out <= bank_0[ raddr[STAGE_ID-1:1]];
   end
   always_ff @(posedge clk) begin
      if (!rstn) begin
         addr_collision_0 <= 1'b0;
         wdata_d1_0 <= 'x;
      end else begin
         addr_collision_0 <= (wr_en_0 && waddr[STAGE_ID-1:1] == raddr[STAGE_ID-1:1]);
         wdata_d1_0 <= wdata;
      end
   end
   always_comb begin
      rdata_0 = addr_collision_0 ? wdata_d1_0 : bank_0_out;
   end

   always_ff @(posedge clk) begin
      if (wr_en_1) begin
         bank_1[ waddr[STAGE_ID-1:1] ] <= wdata; 
      end
      bank_1_out <= bank_1[ raddr[STAGE_ID-1:1]];
   end
   always_ff @(posedge clk) begin
      if (!rstn) begin
         addr_collision_1 <= 1'b0;
         wdata_d1_1 <= 'x;
      end else begin
         addr_collision_1 <= (wr_en_1 && waddr[STAGE_ID-1:1] == raddr[STAGE_ID-1:1]);
         wdata_d1_1 <= wdata;
      end
   end
   always_comb begin
      rdata_1 = addr_collision_1 ? wdata_d1_1 : bank_1_out;
   end
endmodule

// specialized module is needed for stage 0 because 
// vivado would not infer BRAM even for the other memories
module stage_mem_1
#(
   parameter N_STAGES,
   parameter PRIORITY_WIDTH,
   parameter DATA_WIDTH
) (
   input clk,
   input rstn,
   
   input heap_op_t op_p, // op coming in to the previous level (L0) in the next cycle
   input heap_op_t op_c, // op coming in to the current level in the next cycle
   input heap_op_t op_n, // op performed in the current level in this cycle
   
   input addr_t raddr_p, // address of data going out to previous level next cycle
   input addr_t raddr_c, // address of data going out to current level next cycle

   heap_entry_t.out rdata_0_p, // data going out to previous level from bank0
   heap_entry_t.out rdata_1_p,
   heap_entry_t.out rdata_c, // data going out to current level this cycle

   input addr_t waddr_p, // address of data being written from previous level
   input addr_t waddr_c, // address of data being written from current level

   // 1 write from current level or 1 from prev level
   heap_entry_t.in wdata_p,
   heap_entry_t.in wdata_c,

   input wr_en_p,
   input wr_en_c
);
   
   localparam MEM_WIDTH = 1+N_STAGES + PRIORITY_WIDTH + DATA_WIDTH;
   logic [MEM_WIDTH-1:0] bank_0;
   logic [MEM_WIDTH-1:0] bank_1;

   // at least one of the ops are guaranteed be a NOP. select from the other
   addr_t raddr;
   addr_t waddr;
   assign raddr = (op_c != NOP) ? raddr_c : raddr_p;
   assign waddr = (op_n != NOP) ? waddr_c : waddr_p;
   
   logic [MEM_WIDTH-1:0] wdata;
   assign wdata = (op_n != NOP) ? 
      {wdata_c.active, wdata_c.capacity, wdata_c.ts, wdata_c.data} : 
      {wdata_p.active, wdata_p.capacity, wdata_p.ts, wdata_p.data} ; 
   
   logic wr_en, wr_en_0, wr_en_1;
   assign wr_en  = (op_n != NOP) ? wr_en_c : wr_en_p;
   
   assign wr_en_0 = wr_en & ~waddr[0];
   assign wr_en_1 = wr_en & waddr[0];

   logic [MEM_WIDTH-1:0] rdata_0;
   logic [MEM_WIDTH-1:0] rdata_1;
   assign {rdata_0_p.active, rdata_0_p.capacity, rdata_0_p.ts, rdata_0_p.data} = rdata_0;
   assign {rdata_1_p.active, rdata_1_p.capacity, rdata_1_p.ts, rdata_1_p.data} = rdata_1;

   addr_t raddr_d1; // raddr of last cycle;
   assign {rdata_c.active, rdata_c.capacity, rdata_c.ts, rdata_c.data} = 
      raddr_d1[0] ? rdata_1 : rdata_0;

   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  init_data();
   initial begin 
      init_data.active = 1'b0;
      init_data.ts = 'x;
      init_data.data = 'x;
      init_data.capacity = 2**(N_STAGES-1) -1;
   end

   always_ff @(posedge clk) begin
      raddr_d1 <= raddr;
      if (!rstn) begin
         bank_0 <= {init_data.active, init_data.capacity, init_data.ts, init_data.data};
      end else if (wr_en_0) begin
         bank_0 <= wdata; 
      end
      if (wr_en_0 && waddr[1] == raddr[1]) begin
         rdata_0 <= wdata;
      end else begin
         rdata_0 <= bank_0;
      end
      if (!rstn) begin
         bank_1 <= {init_data.active, init_data.capacity, init_data.ts, init_data.data};
      end else if (wr_en_1) begin
         bank_1 <= wdata; 
      end
      if (wr_en_1 && waddr[1] == raddr[1]) begin
         rdata_1 <= wdata;
      end else begin
         rdata_1 <= bank_1;
      end
   end
endmodule

module stage_mem_0
#(
   parameter N_STAGES,
   parameter PRIORITY_WIDTH,
   parameter DATA_WIDTH
) (
   input clk,
   input rstn,
   
   input heap_op_t op_c, // op coming in to the current level in the next cycle
   input heap_op_t op_n, // op performed in the current level in this cycle
   
   heap_entry_t.out rdata_p,
   heap_entry_t.out rdata_c,
   
   heap_entry_t.in wdata_p,
   heap_entry_t.in wdata_c,

   input wr_en_p,
   input wr_en_c

);
   localparam MEM_WIDTH = 1+N_STAGES + PRIORITY_WIDTH + DATA_WIDTH;
   logic [MEM_WIDTH-1:0] min_entry;

   heap_entry_t #(
      .PRIORITY_WIDTH( PRIORITY_WIDTH),
      .DATA_WIDTH( DATA_WIDTH ),
      .CAPACITY_WIDTH( N_STAGES )
   )  init_data();
   initial begin 
      init_data.active = 1'b0;
      init_data.ts = 'x;
      init_data.data = 'x;
      init_data.capacity = 2**(N_STAGES) -1;
   end
   
   logic [MEM_WIDTH-1:0] wdata;
   assign wdata = (op_n != NOP) ? 
      {wdata_c.active, wdata_c.capacity, wdata_c.ts, wdata_c.data} : 
      {wdata_p.active, wdata_p.capacity, wdata_p.ts, wdata_p.data} ; 

   logic wr_en; 
   assign wr_en  = (op_n != NOP) ? wr_en_c : wr_en_p;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         rdata_c.active <= 0;
         rdata_c.ts <= 'x;
         rdata_c.data <= 'x;
         rdata_c.capacity <= 2**(N_STAGES) -1;
         rdata_p.active <= 0;
         rdata_p.ts <= 'x;
         rdata_p.data <= 'x;
         rdata_p.capacity <= 2**(N_STAGES) -1;
         min_entry <= {init_data.active, init_data.capacity, init_data.ts, init_data.data};
      end else begin
         if (wr_en) begin
            min_entry <= wdata; 
         end
         if (wr_en) begin
            {rdata_c.active, rdata_c.capacity, rdata_c.ts, rdata_c.data} <= wdata;
            {rdata_p.active, rdata_p.capacity, rdata_p.ts, rdata_p.data} <= wdata;
         end else begin
            {rdata_c.active, rdata_c.capacity, rdata_c.ts, rdata_c.data} <= min_entry;
            {rdata_p.active, rdata_p.capacity, rdata_p.ts, rdata_p.data} <= min_entry;
         end
      end
   end
endmodule

