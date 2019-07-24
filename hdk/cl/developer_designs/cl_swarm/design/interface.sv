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

`ifndef CL_INTERFACE
`define CL_INTERFACE
import swarm::*;
   
   interface axi_bus_t #(parameter WIDTH=64); // width in bytes
      logic[15:0] awid;
      logic[63:0] awaddr;
      logic[7:0] awlen;
      logic [2:0] awsize;
      logic awvalid;
      logic awready;
   
      logic[15:0] wid;
      logic[WIDTH*8-1:0] wdata;
      logic[WIDTH-1:0] wstrb;
      logic wlast;
      logic wvalid;
      logic wready;
         
      logic[15:0] bid;
      logic[1:0] bresp;
      logic bvalid;
      logic bready;
         
      logic[15:0] arid;
      logic[63:0] araddr;
      logic[7:0] arlen;
      logic [2:0] arsize;
      logic arvalid;
      logic arready;
         
      logic[15:0] rid;
      logic[WIDTH*8-1:0] rdata;
      logic[1:0] rresp;
      logic rlast;
      logic rvalid;
      logic rready;

      modport master (input awid, awaddr, awlen, awsize, awvalid, output awready,
                      input wid, wdata, wstrb, wlast, wvalid, output wready,
                      output bid, bresp, bvalid, input bready,
                      input arid, araddr, arlen, arsize, arvalid, output arready,
                      output rid, rdata, rresp, rlast, rvalid, input rready);

      modport slave (output awid, awaddr, awlen, awsize, awvalid, input awready,
                     output wid, wdata, wstrb, wlast, wvalid, input wready,
                     input bid, bresp, bvalid, output bready,
                     output arid, araddr, arlen, arsize, arvalid, input arready,
                     input rid, rdata, rresp, rlast, rvalid, output rready);
      modport snoop (input awid, awaddr, awlen, awsize, awvalid, awready,
                     wid, wdata, wstrb, wlast, wvalid, wready,
                     bid, bresp, bvalid, bready,
                     arid, araddr, arlen, arsize, arvalid, arready,
                     rid, rdata, rresp, rlast, rvalid, rready);
   endinterface
  
   interface task_enq_req_t; 
      logic          valid;
      logic          ready;
      tile_id_t      dest_tile;
      task_t         task_data;
      logic          task_tied;
      tsb_entry_id_t resp_tsb_id;
      tile_id_t      resp_tile;

      modport master (input valid, task_data, task_tied, resp_tile, resp_tsb_id, dest_tile, output ready);
      modport slave (output valid, task_data, task_tied, resp_tile, resp_tsb_id, dest_tile,  input ready);

   endinterface

   interface task_enq_resp_t;
      logic          valid;
      logic          ready;
      tile_id_t      dest_tile;
      tsb_entry_id_t tsb_id;
      logic          task_ack;
      epoch_t        task_epoch;
      tq_slot_t      tq_slot;

      modport master (input valid, tsb_id, dest_tile, task_ack, task_epoch, tq_slot, output ready);
      modport slave (output valid, tsb_id, dest_tile, task_ack, task_epoch, tq_slot,  input ready);

   endinterface

   interface abort_child_req_t;
      logic          valid;
      logic          ready;
      tile_id_t      dest_tile;
      tq_slot_t      tq_slot;
      epoch_t        child_epoch;
      tile_id_t      resp_tile;
      cq_slice_slot_t resp_cq_slot;
      child_id_t     resp_child_id;

      modport master (input valid, dest_tile, tq_slot, child_epoch, resp_tile, resp_cq_slot, resp_child_id,
            output ready);
      modport slave (output valid, dest_tile, tq_slot, child_epoch, resp_tile, resp_cq_slot, resp_child_id,
            input ready);

   endinterface

   interface abort_child_resp_t;
      logic          valid;
      logic          ready;
      tile_id_t      dest_tile;
      cq_slice_slot_t cq_slot;
      child_id_t     child_id;

      modport master (input valid, dest_tile, cq_slot, child_id, output ready);
      modport slave (output valid, dest_tile, cq_slot, child_id, input ready);

   endinterface

   interface cut_ties_req_t;
      logic       valid;
      logic       ready;
      tile_id_t   dest_tile;
      tq_slot_t   tq_slot;
      epoch_t     child_epoch;

      modport master (input valid, dest_tile, tq_slot, child_epoch, output ready);
      modport slave (output valid, dest_tile, tq_slot, child_epoch, input ready);

   endinterface
   
   
   // An extremely lite version of AXI for register accesses
   // Used for both configuration writes and debug reads
   interface reg_bus_t #(parameter WIDTH=32); // Width in bits
      logic [15:0] waddr;
      logic [WIDTH-1:0] wdata;
      logic wvalid;

      logic [15:0] araddr;
      logic arvalid;
      logic [WIDTH-1:0] rdata;
      logic rvalid;

      modport master (input araddr, arvalid, waddr, wvalid, wdata, output rdata, rvalid);
      modport slave  (output araddr, arvalid, waddr, wvalid, wdata, input rdata, rvalid);
   endinterface

   // Fixed Addr, Read only AXI bus
   interface pci_debug_bus_t;
      logic arvalid;
      logic [7:0] arlen;
      logic [511:0] rdata;
      logic rvalid;
      logic rlast;
      logic rready;

      modport master (input arvalid, arlen, rready, output rdata, rvalid, rlast);
      modport slave  (output arvalid, arlen, rready, input rdata, rvalid, rlast);

   endinterface
/*
   interface cfg_bus_t;
      logic [31:0] addr;
      logic [31:0] wdata;
      logic wr;
      logic rd;
      logic ack;
      logic[31:0] rdata;

      modport master (input addr, wdata, wr, rd, output ack, rdata);

      modport slave (output addr, wdata, wr, rd, input ack, rdata);
   endinterface
*/
   interface scrb_bus_t;
      logic [63:0] addr;
      logic [2:0] state;
      logic enable;
      logic done;

      modport master (input enable, output addr, state, done);

      modport slave (output enable, input addr, state, done);
   endinterface
   
   interface heap_entry_t 
   #(
      parameter PRIORITY_WIDTH = 32,
      parameter DATA_WIDTH = 33,
      parameter CAPACITY_WIDTH = TQ_STAGES
   ); 
      logic                       active;
      logic [CAPACITY_WIDTH-1:0]  capacity;
      logic [PRIORITY_WIDTH-1:0]  ts;
      logic [DATA_WIDTH-1:0]      data;
      
      modport in  ( input active, capacity, ts, data);
      modport out (output active, capacity, ts, data);
   endinterface

`endif //CL_INTERFACE
