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

module test_cache();


logic wr_map[*];
logic rd_map[*];

logic clk, rstn;
axi_bus_t cbus();
axi_bus_t mem_bus();

integer cycle;

typedef struct {
   logic [33:0] addr;
   integer cycle; // doubles up as data
} req;

req write_list[$];
req read_list[$];

logic flush_valid, flush_ready;

initial begin
   write_list.push_back('{addr:{16'h0010, 12'h0, 6'h0}, cycle:100});
   write_list.push_back('{addr:{16'h0020, 12'h0, 6'h0}, cycle:100});
   write_list.push_back('{addr:{16'h0030, 12'h0, 6'h0}, cycle:100});
   write_list.push_back('{addr:{16'h0040, 12'h0, 6'h0}, cycle:100});
   write_list.push_back('{addr:{16'h0070, 12'h0, 6'h0}, cycle:145});
   write_list.push_back('{addr:{16'h0010, 12'h0, 6'h0}, cycle:145});
   write_list.push_back('{addr:{16'h0050, 12'h0, 6'h0}, cycle:240});
   
   read_list.push_back('{addr:{16'h0010, 12'h0, 6'h0}, cycle:200});
   read_list.push_back('{addr:{16'h0020, 12'h0, 6'h0}, cycle:200});
   read_list.push_back('{addr:{16'h0070, 12'h0, 6'h0}, cycle:200});
   
   write_list.push_back('{addr:{16'h0021, 12'h3, 6'h0}, cycle:300});
   write_list.push_back('{addr:{16'h0021, 12'h5, 6'h0}, cycle:300});
   write_list.push_back('{addr:{16'h0071, 12'h3, 6'h0}, cycle:300});
   write_list.push_back('{addr:{16'h0071, 12'h30, 6'h0}, cycle:300});
   
end

cfg_bus_t cfg();
ocl_debug_bus_t ocl();
pci_debug_bus_t pci();

l2 DUT(
   .clk(clk),
   .rstn(rstn),

   .l1(cbus),
   .mem_bus(mem_bus),

   .cfg(cfg),
   .ocl_debug(ocl),
   .pci_debug(pci)
);

mem_ctrl MEM_CTRL(
   .clk(clk),
   .rstn(rstn),
   .axi(mem_bus)
);

always 
   #5 clk = ~clk;

initial begin

   clk = 0;
   rstn = 0;
   cbus.wvalid = 1'b0;
   cbus.arvalid = 1'b0;
   cbus.rready = 1'b0;
   cbus.bready = 1'b0;

   flush_valid = 1'b0;

   cycle = 0;

   # 1000;
   rstn = 1;
   cbus.rready = 1'b1;
   cbus.bready = 1'b1;
   
   # 3000;
   flush_valid = 1'b1;
   #100;
   flush_valid = 1'b0;
   
   wait(flush_ready);
   $display("Simulation End, Outstanding TX: read-%2d, write-%2d", 
      rd_map.size(), wr_map.size());
   $finish();
end

always
   #10 cycle = cycle + 1;


always_ff @(posedge clk) begin
   if (!rstn) begin
      cbus.arid <= 0;
   end else begin
      if (!cbus.arvalid | (cbus.arvalid & cbus.arready)) begin
         if ( read_list.size()>0 && cycle >= read_list[0].cycle) begin 
            // new read tx on average every 3 cycles
            cbus.arvalid <= 1'b1;
            cbus.araddr <= read_list[0].addr;
            cbus.arid <= cbus.arid + 1;
            read_list.pop_front(); 
         end else begin
            cbus.arvalid <= 1'b0;
         end
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      cbus.wid <= 0;
   end else begin
      if (!cbus.wvalid | (cbus.wvalid & cbus.wready)) begin
         if ( write_list.size()>0 && cycle >= write_list[0].cycle) begin 
            // new write tx on average every 10 cycles
            cbus.awvalid <= 1'b1;
            cbus.wvalid <= 1'b1;
            cbus.wid <= cbus.wid + 1;
            cbus.awaddr <= write_list[0].addr;
            cbus.wstrb <= 64'd3; // two bytes/ four hex nibbles
            cbus.wdata <= cycle;
            write_list.pop_front(); 
         end else begin
            cbus.awvalid <= 1'b0;
            cbus.wvalid <= 1'b0;
         end
      end
   end
end

always @(posedge clk) begin
   if (cbus.wvalid & cbus.wready) begin
      $display("[%4d] WRITE REQ  id:%2d addr:%x index:%4d \t data:%8x",
         cycle, cbus.wid, cbus.awaddr, cbus.awaddr[17:6], cbus.wdata);
      wr_map[cbus.wid] = 1;
   end
   if (cbus.arvalid & cbus.arready) begin
      $display("[%4d] READ REQ   id:%2d addr:%x index:%4d",
         cycle, cbus.arid, cbus.araddr, cbus.araddr[17:6]);
      rd_map[cbus.arid] = 1;
   end
   if (cbus.rvalid &cbus.rready) begin
      $display("[%4d] READ RESP  id:%2d \t\t\t\t data:%8x", cycle, cbus.rid, cbus.rdata);
      if (!rd_map.exists(cbus.rid)) begin
         $error("No read req issued for this id");
      end
      rd_map.delete(cbus.rid);
   end
   if (cbus.bvalid & cbus.bready) begin
      $display("[%4d] WRITE_RESP id:%2d", cycle, cbus.bid);
      if (!wr_map.exists(cbus.bid)) begin
         $error("No write req issued for this id");
      end
      wr_map.delete(cbus.bid);
   end
end



endmodule


