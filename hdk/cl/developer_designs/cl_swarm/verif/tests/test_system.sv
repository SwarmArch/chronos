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


module test_system();

import tb_type_defines_pkg::*;
import swarm::*;
// AXI ID
parameter [5:0] AXI_ID = 6'h0;

logic [31:0] rdata;

integer fid;
byte  op;
integer ts, line;

parameter num_tests = 100;
parameter max_q_size = (1<<TQ_STAGES) -1;

integer queue[$];
typedef enum logic {DEQUEUE, INSERT} op_t;

integer expected, actual, min_index;
logic [31:0] task_enq_addr;
logic [31:0] cur_cycle;

localparam DMA_TEST = 0;

// mem access list
typedef struct {
   logic is_read;
   logic [47:0] addr;
   logic [31:0] wdata;
} mem_request_t;
mem_request_t req_queue[$];

logic [31:0] mem_addr;
logic [31:0] mem_msb;
logic [31:0] mem_rdata;

logic [63:0] host_memory_buffer_address;
integer len0;
integer timeout_count;
logic status;

initial begin
   tb.power_up();

   $srandom(10);
   line = 0;
   task_enq_addr = ADDR_TASK_ENQ;
   task_enq_addr [15:0] = 0;

   tb.peek(.addr(ADDR_CUR_CYCLE), .data(cur_cycle),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   $display("Starting at Cycle %d", cur_cycle);
   
   tb.peek(.addr(ADDR_CUR_CYCLE+1), .data(cur_cycle),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   $display("Incorrect addr reads %d", cur_cycle);

if (DMA_TEST) begin
// DMA write
   
    // allow memory to initialize
    tb.nsec_delay(23000);

    $display("[%t] : Initializing buffers", $realtime);
    host_memory_buffer_address = 64'h0;
    len0 = 128;

    //Queue data to be transfered to CL DDR
    tb.que_buffer_to_cl(.chan(0), .src_addr(host_memory_buffer_address),
       .cl_addr(64'h0000_0000_1100), .len(len0) );  // move buffer to DDR 

    // Put test pattern in host memory       
    for (int i = 0 ; i < len0 ; i++) begin
       tb.hm_put_byte(.addr(host_memory_buffer_address), .d(8'hAA));
       host_memory_buffer_address++;
    end

    $display("[%t] : starting H2C DMA channels ", $realtime);
    //Start transfers of data to CL DDR
    tb.start_que_to_cl(.chan(0));   

    // wait for dma transfers to complete
    timeout_count = 0;       
    do begin
       status = tb.is_dma_to_cl_done(.chan(0));
       #10ns;
       timeout_count++;
    end while ((status == 0) && (timeout_count < 2000));
    
    if (timeout_count >= 2000) begin
       $display("[%t] : *** ERROR *** Timeout waiting for dma transfers from cl", $realtime);
    end

   $display("[%t] : H2C DMA channels complete ", $realtime);
// End DMA Write
end
   // Setting ROI = 1
   mem_addr = ADDR_CONFIG_SPACE;
   mem_addr[15:0] = CONFIG_ROI;
   tb.poke(.addr(mem_addr), .data(32'b1),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL));
   $display("addr: %x writes %d", mem_addr, 32'b1);
   mem_msb = 0;
   req_queue[0] = '{1'b1, 48'h0000_1100, 32'd0} ;
   req_queue[1] = '{1'b1, 48'h0000_1100, 32'd0} ;
   req_queue[2] = '{1'b1, 48'h0000_1104, 32'd0} ;
   req_queue[3] = '{1'b1, 48'h0000_1114, 32'd0} ;
   req_queue[4] = '{1'b0, 48'h0000_1104, 32'd110} ;
   req_queue[5] = '{1'b1, 48'h0000_1104, 32'd0} ;
   req_queue[6] = '{1'b1, 48'h0000_1100, 32'd0} ;
   req_queue[7] = '{1'b0, 48'h0010_1100, 32'd200} ; // cache miss
   req_queue[8] = '{1'b1, 48'h0000_1104, 32'd0} ;
   mem_addr = ADDR_ACCESS_MEM;
   for (integer i=0;i<req_queue.size(); i=i+1) begin
      if (mem_msb != req_queue[i].addr[47:16]) begin
         mem_msb = req_queue[i].addr[47:16];
         tb.poke(.addr(ADDR_SET_MEM_MSB), .data(req_queue[i].addr[47:16]),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
         $display("setting mem_msb to %x", mem_msb);
      end
      mem_addr[15:0] = req_queue[i].addr[15:0];
      if (req_queue[i].is_read) begin
         tb.peek(.addr(mem_addr), .data(mem_rdata),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
         $display("addr: %x reads %d", req_queue[i].addr, mem_rdata);
      end else begin
         tb.poke(.addr(mem_addr), .data(req_queue[i].wdata),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
         $display("addr: %x writes %d", req_queue[i].addr, req_queue[i].wdata);
      end
   end

   tb.peek(.addr(ADDR_LAST_READ_LATENCY), .data(cur_cycle),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   $display("Last read latency:%d", cur_cycle);
   
   // Setting ROI = 0
   mem_addr = ADDR_CONFIG_SPACE;
   mem_addr[15:0] = CONFIG_ROI;
   tb.poke(.addr(mem_addr), .data(32'b0),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL));
   $display("addr: %x writes %d", mem_addr, 32'b0);
 
// DMA READ
if (DMA_TEST) begin
   $display("[%t] : starting C2H DMA channels ", $realtime);

    // read the data from cl and put it in the host memory 
    host_memory_buffer_address = 64'h0_0001_0800;
    tb.que_cl_to_buffer(.chan(0), .dst_addr(host_memory_buffer_address), 
       .cl_addr(64'h0000_0000_1100), .len(len0) );  // move DDR0 to buffer
 
    //Start transfers of data from CL DDR
    tb.start_que_to_buffer(.chan(0));   

    // wait for dma transfers to complete
    timeout_count = 0;    
    status = 0;
    do begin
       status = tb.is_dma_to_buffer_done(.chan(0));
       #10ns;
       timeout_count++;          
    end while ((status == 0) && (timeout_count < 1000));
   
   #2us;
      
    if (timeout_count >= 1000) begin
       $display("[%t] : *** ERROR *** Timeout waiting for dma transfers from cl", $realtime);
    end
// End DMA Read
    // Compare the data in host memory with the expected data
    $display("[%t] : DMA buffer from DDR 0", $realtime);

    host_memory_buffer_address = 64'h0_0001_0800;
    for (int i = 0 ; i<len0 ; i++) begin
      if (tb.hm_get_byte(.addr(host_memory_buffer_address + i)) !== 8'hAA) begin
        $display("[%t] : *** ERROR *** DDR0 Data mismatch, addr:%0x read data is: %0x", 
                         $realtime, (host_memory_buffer_address + i), 
                         tb.hm_get_byte(.addr(host_memory_buffer_address + i)));
      end    
    end
  $finish(); 

end
   while (line < num_tests) begin
      op_t op;
      if (queue.size() ==0) begin
         op = INSERT;
      end else if (queue.size() == max_q_size) begin
         op = DEQUEUE;
      end else begin
         op = $urandom_range(0,1) == 0 ? DEQUEUE : INSERT;
         if (line < 10) begin
            op = INSERT;
         end
      end

      if (op==INSERT) begin
         ts = $urandom_range(0,255);
         $display ("Writing %d (0x%x) %d : occ:%d", ts[TS_WIDTH-1:0],ts[TS_WIDTH-1:0], 
            line[HINT_WIDTH-1:0], queue.size() + 1);
         tb.poke(.addr(task_enq_addr), .data({ts[TS_WIDTH-1:0], line[HINT_WIDTH-1:0]}),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
         queue.push_back(ts);
      end else begin
         $display("Starting Read");
         tb.peek(.addr(task_enq_addr), .data(rdata),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
         min_index = queue_getmin();
         expected = queue[min_index];
         actual = rdata[31 -: TS_WIDTH];
         queue.delete(min_index);
         $display ("Reading %3d  %3d ", actual, rdata[HINT_WIDTH-1:0]);
               
         //if(actual != expected) $finish;
      end
      line=line+1;
   end
    
   tb.peek(.addr(ADDR_CUR_CYCLE), .data(cur_cycle),
       .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   $display("Finishing at Cycle %d", cur_cycle);

   tb.kernel_reset();

   tb.power_down();

   $finish;
end

function integer queue_getmin;
   integer i,min, min_index;
   min = 65535;
   for (i=0;i<queue.size();i++) begin
      //$display(" val %d", queue[i]);
      if (queue[i] < min) begin
         min = queue[i];
         min_index = i;
      end
   end
   return min_index;
endfunction

endmodule


