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

module module_task_unit();

parameter num_tests = 100;
parameter max_q_size = (1<<TQ_STAGES) -1;

integer queue[$];

integer expected, actual, min_index;

logic clk, rstn;
logic s_wvalid;
logic s_wready;
tq_elem_s s_wdata;

logic [0: N_TASK_TYPES-1] m_rvalid;
task_t [0: N_TASK_TYPES-1] m_rdata;
logic [0: N_TASK_TYPES-1] m_rready;

task_unit DUT(
   .clk(clk),
   .rstn(rstn),

   .s_wvalid(s_wvalid),
   .s_wready(s_wready),
   .s_wdata(s_wdata),
   
   .m_rvalid(m_rvalid),
   .m_rready(m_rready),
   .m_rdata(m_rdata)
);

always 
   #5 clk = ~clk;

initial begin
   $srandom(10);

   clk = 0;
   rstn = 0;

   s_wvalid = 1'b0;
   s_wdata = 'x;

   # 1000;
   rstn = 1;

   for (integer i=0;i < num_tests; i=i+1) begin
      #10
      // start at a negedge
      s_wvalid = $urandom_range(0,3) > 0;

      if (s_wvalid) begin
         s_wdata.ttype = 0;
         s_wdata.object = i;
         s_wdata.ts = $urandom_range(0,255);
         $display ("Writing %d (0x%x) %d : occ:%d", s_wdata.ts, s_wdata.ts, 
            s_wdata.object, queue.size() + 1);
         queue.push_back(s_wdata.ts);
         // sample at posedge
         #5 while(!s_wready) #10;
         #5;
      end
      s_wvalid = 1'b0;
      s_wdata = 'x;
   end
end

initial begin

   m_rready[0] = 0;
   # 1000;
   #1; // avoid races
   for (integer i=0;i < num_tests; i=i+1) begin
      
      while(!m_rvalid[0]) #10;
      
      m_rready[0] = 1'b1; #1
      if (m_rready[0]) begin
         min_index = queue_getmin();
         expected = queue[min_index];
         actual = m_rdata[0].ts;
         queue.delete(min_index);
         $display ("Reading %3d Expected %3d object:%3d ", actual, expected, m_rdata[0].object);
      end
      #9
      m_rready[0] = 1'b0;
      #70;
   end
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


