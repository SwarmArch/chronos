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


module test_task_unit();

import tb_type_defines_pkg::*;
import swarm::*;

// AXI ID
parameter [5:0] AXI_ID = 6'h0;

logic [31:0] rdata;

integer fid, status, timeout_count;
integer line;
integer n_lines;

logic [31:0] file[*];

integer ts_remaining[ logic[31:0] ];

localparam HOST_SPILL_AREA = 32'h1000000;
localparam CL_SPILL_AREA = (1<<30);

logic [31:0] task_enq_addr, config_addr, config_data;
logic [31:0] return_ts;
integer i;
initial begin
   
   
   
   tb.power_up();
   
   // Initialize Splitter Stack and scratchpad
   for (i=0;i<4;i++) begin
      tb.hm_put_byte(.addr(HOST_SPILL_AREA + STACK_PTR_ADDR_OFFSET + i), .d(0));
   end
   for (i=0;i< (1<<LOG_SPLITTER_STACK_SIZE) ; i++) begin
      tb.hm_put_byte(.addr(HOST_SPILL_AREA + STACK_BASE_OFFSET +  i*2  ), .d(i[ 7:0]));
      tb.hm_put_byte(.addr(HOST_SPILL_AREA + STACK_BASE_OFFSET +  i*2+1), .d(i[15:8]));
   end
   for (i=SCRATCHPAD_BASE_OFFSET; i<SCRATCHPAD_END_OFFSET;i++) begin
      tb.hm_put_byte(.addr(HOST_SPILL_AREA + i), .d(0));
   end
   for (i=0;i<N_TILES;i++) begin
      $display("Initialing stack tile %d", i);
      tb.que_buffer_to_cl(.chan(0),
         .src_addr(HOST_SPILL_AREA),
         .cl_addr(CL_SPILL_AREA + i * TOTAL_SPILL_ALLOCATION ), 
         .len(SCRATCHPAD_END_OFFSET) );   

      tb.start_que_to_cl(.chan(0));

      do begin
         status = tb.is_dma_to_cl_done(.chan(0)); #10ns;
      end while (status == 0);
      
      // set splitter base addresses
      config_addr = 0;
      config_addr[15:8] = ID_COAL_AND_SPLITTER;
      config_addr[7:0] = SPILL_ADDR_STACK_PTR;
      tb.poke(.addr(config_addr), .data(  (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION) >> 6  ),
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

      config_addr[7:0] = SPILL_BASE_STACK;
      tb.poke(.addr(config_addr), .data(
         (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION + STACK_BASE_OFFSET) >> 6 ) ,
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

      config_addr[7:0] = SPILL_BASE_SCRATCHPAD;
      tb.poke(.addr(config_addr), .data(
         (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION + SCRATCHPAD_BASE_OFFSET) >> 6 ) ,
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      
      config_addr[7:0] = SPILL_BASE_TASKS;
      tb.poke(.addr(config_addr), .data(
         (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION + SPILL_TASK_BASE_OFFSET) >> 6 ) ,
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

   end
   $display("Stack initiaized"); 

   task_enq_addr = 0;
   task_enq_addr[7:0] = OCL_TASK_ENQ_HINT;
   tb.poke(.addr(task_enq_addr), .data(0),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   task_enq_addr[7:0] = OCL_TASK_ENQ_TTYPE;
   tb.poke(.addr(task_enq_addr), .data(0),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   config_addr = 0;
   config_addr [15:8] = ID_ALL_CORES;
   config_addr [ 7:0] = CORE_START;
   config_data = 7; 
   tb.poke(.addr(config_addr), .data(config_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
  
   for (int i=0;i<100;i=i+1) begin 
         
      task_enq_addr = OCL_TASK_ENQ;
      return_ts = (i%10)*10 + (i/10);
      tb.poke(.addr(task_enq_addr), .data(return_ts),
          .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      ts_remaining[ return_ts ] = 1; 
      $display( "[tb] [%3d] enq task %3d",i, return_ts);
   end

   for (int i=0;i<100;i=i+1) begin
      task_enq_addr = OCL_TASK_ENQ;
      tb.peek(.addr(task_enq_addr), .data(return_ts),
          .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
       $display( "[tb] [%3d] deque task %3d",i, return_ts);
       if(ts_remaining[return_ts]) begin
            ts_remaining[return_ts] = 0;
       end else begin
            $error(" [tb] ts:%2d returned twice", return_ts);
       end
   end
   /*
   for (int i=10;i<20;i=i+1) begin 
         
      task_enq_addr = OCL_TASK_ENQ;
      return_ts = (i%10)*10 + (i/10);
      tb.poke(.addr(task_enq_addr), .data(return_ts),
          .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      ts_remaining[ return_ts ] = 1; 
   end
   for (int i=0;i<10;i=i+1) begin
      task_enq_addr = OCL_TASK_ENQ;
      tb.peek(.addr(task_enq_addr), .data(return_ts),
          .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
       $display( "[tb] [%3d] deque task %3d",i, return_ts);
       if(ts_remaining[return_ts]) begin
            ts_remaining[return_ts] = 0;
       end else begin
            $error(" [tb] ts:%2d returned twice", return_ts);
       end
   end */
   $display( "[tb] %2d tasks not dequeued", ts_remaining.num());
   //wait (tb.card.fpga.CL.done);
   tb.kernel_reset();

   tb.power_down();



   $finish;
end


endmodule


