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


module test_chronos();

import tb_type_defines_pkg::*;
import chronos::*;

// AXI ID
parameter [5:0] AXI_ID = 6'h0;

logic [31:0] rdata;

integer fid, status, timeout_count;
integer line;
integer n_lines;

logic [31:0] file[*];

logic [63:0] log_start_addr;
logic [511:0] log_entry;

logic [31:0] ocl_addr, ocl_data; 
integer dist_actual, dist_ref;
integer num_errors;

localparam HOST_SPILL_AREA = 32'h1000000;
localparam CL_SPILL_AREA = (1<<30);
   
logic [31:0] addr, data;
logic [511:0] cache_line;

logic [31:0] enq_ts;
logic [31:0] enq_object;
logic [31:0] enq_args;

logic binary_file;

integer BASE_END;

string input_file;

initial begin
  
   tb.power_up();
   
   // If using proper DDR models, wait for them to initialize
   `ifndef SIMPLE_MEMORY
       tb.nsec_delay(1000);
       tb.poke_stat(.addr(8'h0c), .ddr_idx(0), .data(32'h0000_0000));
       tb.poke_stat(.addr(8'h0c), .ddr_idx(1), .data(32'h0000_0000));
       tb.poke_stat(.addr(8'h0c), .ddr_idx(2), .data(32'h0000_0000));
      #25us;
   `endif
   
   if (RISCV) begin
      load_riscv_program();      
   end

   
   case (APP_NAME) 
      "des"     : input_file = "input_net";
      "sssp"    : input_file = "input_graph";
      "sssp_hls": input_file = "input_graph";
      "astar"   : input_file = "input_astar";
      "color"   : input_file = "input_color";
      "maxflow" : input_file = "input_maxflow";
      "silo"    : input_file = "silo_tx";
   endcase

   read_and_transfer_input_file();

   initialize_spilling_structures();
   
   for (int i=0;i<N_TILES;i++) begin
      for (int j=0;j< ((APP_NAME == "silo") ? 32 : 16 );j++) begin
         ocl_poke(i, ID_ALL_APP_CORES, j*4, file[j]);
      end
      ocl_poke(i, ID_TSB, TSB_HASH_KEY, 32'h4b56917f);
      ocl_poke(i, ID_ALL_APP_CORES, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, 10);
      ocl_poke(i, ID_SERIALIZER, SERIALIZER_N_THREADS, 16);
   end


   // Application specific initialization
   if (APP_NAME == "des") begin
      for (int i=0;i<file[11];i++) begin // numI
         enq_ts = 0;
         enq_object = file[ file[7] + i] ; 
         enq_args = 0 ; 
         // task_enq(ttype, object, ts, num_args, arg_0, arg_1)
         task_enq(1, enq_object, enq_ts, 1, enq_args, 0);
      end
   end
   if (APP_NAME == "sssp" | APP_NAME == "sssp_hls") begin
      task_enq(0, file[7], 0, 0, 0, 0);
   end      
   if (APP_NAME == "color") begin
      task_enq(0, 0, 0, 1 /*n_args*/, 0, 0);
   end      
   if (APP_NAME == "astar") begin
      // initial task: queue_vertex 0
      task_enq(1, file[7], 0, 2 /*n_args*/, 0, 32'hffffffff);
   end
   if (APP_NAME == "maxflow") begin
      for (int i=0;i<N_TILES;i++) begin
         ocl_poke(i, ID_TASK_UNIT, TASK_UNIT_IS_TRANSACTIONAL, 1);
         ocl_poke(i, ID_TASK_UNIT, TASK_UNIT_GLOBAL_RELABEL_START_MASK, (1<< file[10]) - 1);
         ocl_poke(i, ID_TASK_UNIT, TASK_UNIT_GLOBAL_RELABEL_START_INC, 32'h10);
      end
      task_enq(0, file[7], 0, 1 /*n_args*/, 0, 0);
   end
   if (APP_NAME == "silo") begin
      task_enq(0, 0, 0, 0, 0, 0);
   end      

   
   // GO !!
   for (int i=0;i<N_TILES;i++) begin 
      ocl_poke(i, ID_TASK_UNIT, TASK_UNIT_START, 1);
      ocl_poke(i, ID_ALL_CORES, CORE_START, '1);
   end
   $display("Cores started"); 
   #4us;
   //check_log(0, ID_COAL);
   
   // Wait until application completes
   do begin
      // If non-spec, need to query each tile individually and see if it finished.
      // If spec, we are done when gvt == '1 
      #300ns;
      if (NO_ROLLBACK) begin
         for (int i=0;i<N_TILES;i++) begin
            ocl_peek(i, 0, OCL_DONE, ocl_data); 
            if (ocl_data != '1) begin
               break;
            end
         end
      end else begin
         ocl_peek(0, ID_CQ, CQ_GVT_TS, ocl_data); 
      end
      #300ns;
   end while (ocl_data!='1);

   $display("Run Complete. Flushing Cache ...");
   
   flush_caches();
   
   #1us;
   //check_log(0, ID_UNDO_LOG+1);
   
   // Application-specific verification code
   
   num_errors = 0;
   if (APP_NAME == "des") begin
      BASE_END = file[10]; // unused host memory
      read_cl_memory( .host_addr(BASE_END*4), .cl_addr(file[5]*4), .len(file[1]*4));
      for (int i=0;i<file[12];i++) begin  // numOutputs
         dist_ref = file[file[6]+i]; // [31:16] - vid, [1:0] val 
         dist_actual[31:24] = tb.hm_get_byte( (BASE_END + dist_ref[31:16] )* 4 + 3);
         if (dist_ref[1:0] != dist_actual[25:24]) num_errors++;
         $display("vid:%3d dist:%3d, ref:%3d, %s, num_errors%2d", dist_ref[31:16],
               dist_actual[25:24], dist_ref[15:0],
               dist_actual[25:24] == dist_ref[1:0] ? "MATCH" : "FAIL", num_errors); 
      end
   end

   if (APP_NAME == "sssp" | APP_NAME == "sssp_hls") begin
      BASE_END = file[8];
      read_cl_memory( .host_addr(BASE_END*4), .cl_addr(file[5]*4), .len(file[1]*4));
      for (int i=0;i<file[1];i++) begin
         dist_actual[ 7: 0] = tb.hm_get_byte( (BASE_END + i)* 4);
         dist_actual[15: 8] = tb.hm_get_byte( (BASE_END + i)* 4+ 1);
         dist_actual[23:16] = tb.hm_get_byte( (BASE_END + i)* 4+ 2);
         dist_actual[31:24] = tb.hm_get_byte( (BASE_END + i)* 4+ 3);
         dist_ref = file [file[6]+i];
         if (dist_actual != dist_ref) num_errors++;
         $display("vid:%3d dist:%3d, ref:%3d, %s, num_errors%2d", i, dist_actual, dist_ref,
               dist_actual == dist_ref ? "MATCH" : "FAIL", num_errors); 
      end
   end
   if (APP_NAME == "astar") begin
      BASE_END = file[10];
      read_cl_memory( .host_addr(BASE_END*4), .cl_addr(file[5]*4), .len(file[1]*4));
      for (int i=0;i<file[1];i++) begin
         dist_actual[ 7: 0] = tb.hm_get_byte( (BASE_END + i)* 4);
         dist_actual[15: 8] = tb.hm_get_byte( (BASE_END + i)* 4+ 1);
         dist_actual[23:16] = tb.hm_get_byte( (BASE_END + i)* 4+ 2);
         dist_actual[31:24] = tb.hm_get_byte( (BASE_END + i)* 4+ 3);
         dist_ref = file [file[9]+i];
         if (dist_ref == '1) continue;
         if (dist_actual != dist_ref) num_errors++;
         $display("vid:%3d dist:%5d, ref:%5d, %s, num_errors%2d", i, dist_actual, dist_ref,
               dist_actual == dist_ref ? "MATCH" : "FAIL", num_errors); 
      end
   end
   if (APP_NAME == "maxflow") begin
      BASE_END = file[8];
      // Read flow into destination node
      read_cl_memory( .host_addr(BASE_END*4), .cl_addr(file[5]*4), .len(file[1]*64));
         dist_actual[ 7: 0] = tb.hm_get_byte( BASE_END*4 + file[9]*64);
         dist_actual[15: 8] = tb.hm_get_byte( BASE_END*4 + file[9]*64+ 1);
         dist_actual[23:16] = tb.hm_get_byte( BASE_END*4 + file[9]*64+ 2);
         dist_actual[31:24] = tb.hm_get_byte( BASE_END*4 + file[9]*64+ 3);
      $display("vid:%3d flow:%d", file[9], dist_actual);
   end
   if (APP_NAME == "color" ) begin
      BASE_END = file[8];
      read_cl_memory( .host_addr(BASE_END*4), .cl_addr(file[5]*4), .len(file[1]*16));
      for (int i=0;i<file[1];i++) begin
         dist_actual[ 7: 0] = tb.hm_get_byte( BASE_END*4 + i* 16);
         dist_actual[15: 8] = tb.hm_get_byte( BASE_END*4 + i* 16+ 1);
         dist_actual[31:16] = 0;
         dist_ref = file [file[6]+i];
         if (dist_actual != dist_ref) num_errors++;
         $display("vid:%3d dist:%3d, ref:%3d, %s, num_errors%2d", i, dist_actual, dist_ref,
               dist_actual == dist_ref ? "MATCH" : "FAIL", num_errors); 
      end
   end

   // Uncomment to Test DEBUG interfaces
   //check_log(ID_L2);
   
   tb.kernel_reset();
   tb.power_down();

   $finish;

end  // initial begin 

// ----------------------------------------------------------------------------------------//
// Helper tasks



task read_cl_memory;
   input [63:0] host_addr;
   input [31:0] cl_addr;
   input [31:0] len;
begin
    logic [511:0] cache_line_data;
   `ifdef FAST_VERIFY
     `ifdef CACHE_LINE_SIZED_SIMPLE_MEMORY 
      for (int i=0;i<len;i+=64) begin
         addr = cl_addr + i;
         cache_line_data = tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ {addr[31:6], 6'b0} ];
         for (int j=0;j<64;j++) begin
            tb.hm_put_byte(.addr(host_addr + i + j), .d(cache_line_data[8*j+:8] ));
         end
      end
     `else
      for (int i=0;i<len;i++) begin
         addr = cl_addr + i;
         data = tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ {addr[31:6], addr[5:0]} ];
         if (N_DDR_CTRL == 1) begin
            data = tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ {addr[31:6], addr[5:0]} ];
         end else if (N_DDR_CTRL == 2) begin
            case (addr[6])
               0: data = tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ {addr[31:7], addr[5:0]} ];
               1: data = tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ {addr[31:7], addr[5:0]} ];
            endcase
         end else begin
            case (addr[7:6])
               0: data = tb.card.fpga.CL.\mem_ctrl[0].MEM_CTRL .memory[ {addr[31:8], addr[5:0]} ];
               1: data = tb.card.fpga.CL.\mem_ctrl[1].MEM_CTRL .memory[ {addr[31:8], addr[5:0]} ];
               2: data = tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ {addr[31:8], addr[5:0]} ];
               3: data = tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ {addr[31:8], addr[5:0]} ];
            endcase
         end
         tb.hm_put_byte(.addr(host_addr + i), .d(data));
      end
     `endif
   `else
      // NOTE (This branch has not been verified thouroughly)
      tb.que_cl_to_buffer(.chan(0), .dst_addr(host_addr), .cl_addr(cl_addr), .len(len) );  
      tb.start_que_to_buffer(.chan(0));   
      timeout_count = 0;       
      do begin
         status = tb.is_dma_to_buffer_done(.chan(0));
         #10ns;
         timeout_count++;          
      end while ((status == 0) && (timeout_count < 3000));
      
      if (timeout_count >= 1000000) begin
         $display("[%t] : *** ERROR *** Timeout waiting for dma transfers from cl", $realtime);
      end
   `endif
end

endtask

task task_enq;
   input [31:0] ttype;
   input [31:0] object;
   input [31:0] ts;
   input [1:0] n_args ;
   input [31:0] arg_0 ;
   input [31:0] arg_1 ;
   begin
      ocl_poke(0, 0, OCL_TASK_ENQ_TTYPE, ttype);
      ocl_poke(0, 0, OCL_TASK_ENQ_OBJECT, object);
      if (n_args >0) begin
         ocl_poke(0, 0, OCL_TASK_ENQ_ARG_WORD, 0);
         ocl_poke(0, 0, OCL_TASK_ENQ_ARGS, arg_0);
      end
      if (n_args >1) begin
         ocl_poke(0, 0, OCL_TASK_ENQ_ARG_WORD, 1);
         ocl_poke(0, 0, OCL_TASK_ENQ_ARGS, arg_1);
      end
      ocl_poke(0, 0, OCL_TASK_ENQ, ts);

      $display("Enqueued initial task ttype:%2s ts:%3d, object:%3d", ttype, ts, object);
   end
endtask

task ocl_poke;
   input [7:0] tile;
   input [7:0] component;
   input [7:0] addr;
   input [31:0] ocl_data;
   begin
      ocl_addr[31:24] = 0;
      ocl_addr[23:16] = tile;
      ocl_addr[15:8] = component;
      ocl_addr[7:0] = addr;
      tb.poke(.addr(ocl_addr), .data(ocl_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

   end
endtask

logic [31:0] ocl_read_data;
task ocl_peek;
   input [7:0] tile;
   input [7:0] component;
   input [7:0] addr;
   output [31:0] ret_val;
   begin
      ocl_addr[31:24] = 0;
      ocl_addr[23:16] = tile;
      ocl_addr[15:8] = component;
      ocl_addr[7:0] = addr;
      tb.peek(.addr(ocl_addr), .data(ocl_read_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      ret_val = ocl_read_data;
   end
endtask

logic [63:0] cl_addr;
task check_log;
input [7:0] tile;
input [7:0] id;
begin
   ocl_addr[23:16] = tile;
   ocl_addr[15:8] = id;
   ocl_addr[7:0] = DEBUG_CAPACITY;
   tb.peek(.addr(ocl_addr), .data(ocl_data),
          .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   $display("Log %d has %d records",id, ocl_data);
   if (ocl_data == 0) begin
      return;
   end
   log_start_addr = 64'h8000_0000;
   cl_addr = (1<<36);
   cl_addr[35:28] = tile; 
   cl_addr[27:20] = id; 
   tb.que_cl_to_buffer(.chan(0), .dst_addr(log_start_addr), .cl_addr(cl_addr), .len(ocl_data*64) );  
   tb.start_que_to_buffer(.chan(0));   
   timeout_count = 0;
   do begin
      status = tb.is_dma_to_buffer_done(.chan(0));
      #10ns;
      timeout_count++;          
   end while ((status == 0) && (timeout_count < 1000));
   for (int i=0;i<ocl_data;i++) begin
      for (int j=0;j<64;j++) begin
         log_entry[j*8 +: 8] = tb.hm_get_byte(log_start_addr + i*64 + j);
      end
      $display("log %2d  (%8x, %8x), (%8x %8x)(%8x, %8x) %8x, %8x %8x", i,
         log_entry[31:0], log_entry[63:32],
         log_entry[95:64], log_entry[127:96],
         log_entry[159:128], log_entry[191:160],
         log_entry[223:192], log_entry[255:224],
         log_entry[287:256]
      );

   end
   
   ocl_addr[15:8] = id;
   ocl_addr[7:0] = DEBUG_CAPACITY;
   tb.peek(.addr(ocl_addr), .data(ocl_data),
          .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   $display("Log End %d has %d records",id, ocl_data);


end
endtask

//https://github.com/SpinalHDL/VexRiscv/blob/master/src/test/cpp/regression/main.cpp
task load_riscv_program;
   integer status;
   logic [31:0] offset, byteCount, nextAddr, key;
   logic [31:0] addr, data, mem_ctrl_addr;
   string line; 
   logic [31:0] _main;
   logic [31:0] boot_code [0:3];
   offset = 0;
   fid = $fopen("input_code.hex", "r");
`ifdef CACHE_LINE_SIZED_SIMPLE_MEMORY
    $display("Cache line sized memory not supported for RISCV");
    $finish();
`endif
   while (!$feof(fid)) begin
      status = $fgets(line, fid);
      if (line.getc(0) == ":") begin
         status = $sscanf( line.substr(1,2), "%x", byteCount);
         status = $sscanf( line.substr(3,6), "%x", nextAddr);
         nextAddr += offset;
         status = $sscanf( line.substr(7,8), "%x", key);
         if (key ==0 ) begin
            for (integer i=0;i<byteCount; i+=1) begin
               addr = nextAddr + i;
               status = $sscanf( line.substr(9+i*2,9+i*2+1), "%x", data);
               //$display("addr %x data %x", addr, data);
                `ifdef SIMPLE_MEMORY
                  if (N_DDR_CTRL == 1) begin
                     mem_ctrl_addr = {addr[31:6], addr[5:0]};
                     tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ mem_ctrl_addr ] = data;
                  end else if (N_DDR_CTRL == 2) begin
                     mem_ctrl_addr = {addr[31:7], addr[5:0]};
                     case (addr[6])
                        0: tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ mem_ctrl_addr ] = data;
                        1: tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ mem_ctrl_addr ] = data;
                     endcase
                  end else begin
                     mem_ctrl_addr = {addr[31:8], addr[5:0]};
                     case (addr[7:6])
                        0: tb.card.fpga.CL.\mem_ctrl[0].MEM_CTRL .memory[ mem_ctrl_addr ] = data;
                        1: tb.card.fpga.CL.\mem_ctrl[1].MEM_CTRL .memory[ mem_ctrl_addr ] = data;
                        2: tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ mem_ctrl_addr ] = data;
                        3: tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ mem_ctrl_addr ] = data;
                     endcase
                  end
               `else
                  // TODO 

               `endif

               
            end
         end
         if (key == 2) begin
            status = $sscanf( line.substr(9,12), "%x", offset);
            offset = offset << 4;
         end
         if (key == 4) begin
            status = $sscanf( line.substr(9,12), "%x", offset);
            offset = offset << 16;
         end
         //$display("%d %d %d", byteCount, nextAddr, key); 
      end
   end

   //assign _main = 32'h800000bc; 
   assign _main = 32'h80000074; 
   boot_code[0] = {_main[31:12], 5'd1, 7'b0110111};    // lui x1, _main[31:12]
   boot_code[1] = {_main[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011};  // addi x1, x1,  _main[11:0]
   boot_code[2] = 32'h80000137; // li sp, 0x80000
   boot_code[3] = {12'b0, 5'd1, 3'b000, 5'd0, 7'b1100111};  // jalr x1, 0
`ifdef SIMPLE_MEMORY
   for (integer i=0;i<4; i+=1) begin
      addr = 32'h80000000 + (i*4);
      //$display("addr %x data %x", addr, data);
      for (integer j=0;j<4;j++) begin
         data = boot_code[i][j*8 +: 8];
         if (N_DDR_CTRL == 1) begin
            mem_ctrl_addr = {addr[31:6], addr[5:0]};
            tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ mem_ctrl_addr +j] = data;
         end else if (N_DDR_CTRL == 2) begin
            mem_ctrl_addr = {addr[31:7], addr[5:0]};
            case (addr[6])
               0: tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ mem_ctrl_addr +j] = data;
               1: tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ mem_ctrl_addr +j] = data;
            endcase
         end else begin
            mem_ctrl_addr = {addr[31:8], addr[5:0]};
            case (addr[7:6])
               0: tb.card.fpga.CL.\mem_ctrl[0].MEM_CTRL .memory[ mem_ctrl_addr +j] = data;
               1: tb.card.fpga.CL.\mem_ctrl[1].MEM_CTRL .memory[ mem_ctrl_addr +j] = data; 
               2: tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ mem_ctrl_addr +j] = data;
               3: tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ mem_ctrl_addr +j] = data;
            endcase
         end
      end
   end
`endif
endtask


task read_and_transfer_input_file;
   
   fid = $fopen(input_file, "rb");
   if (fid==0) begin
      $display("File %s not found", input_file);
      $finish();
   end
   line[7:0] = $fgetc(fid);
   line[15:8] = $fgetc(fid);
   line[23:16] = $fgetc(fid);
   line[31:24] = $fgetc(fid);
   $display("Magic op %x %d %d",line, status, fid);  
   $fclose(fid);
   binary_file = (line == 32'hdead);
   if (binary_file) begin
      fid = $fopen(input_file, "rb");
   end else begin
      fid = $fopen(input_file, "r");
   end
`ifdef CACHE_LINE_SIZED_SIMPLE_MEMORY
   assert(N_DDR_CTRL == 1) else begin
       $error("Not supported for N_DDR_CTRL > 1");
       $finish();
   end
   if (binary_file) begin
        addr = 0;
        while (!$feof(fid)) begin
            cache_line[addr[5:0] * 8 +:8] = $fgetc(fid);
            if (addr[5:0] == '1) begin
                tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ {addr[31:6], 6'b0} ] = cache_line;
                //$display ("addr %x data %x", addr[31:6], cache_line);
            end
            if (addr[1:0] == '1 && addr[31:8] == 0) begin
                file[addr[7:2]] = cache_line[ addr[5:2]*32 +: 32];
            end
            addr = addr + 1;
            if (addr[21:0]  == 0) begin
               $display("%d Bytes transferred from input file", addr);  
            end
        end
        tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ addr[31:6] ] = cache_line;
   end else begin
        $display("non binary files not supported");
        $finish();
   end
   return;
`endif

   line = 0;
   n_lines = 0;
   while (!$feof(fid)) begin
      if (!binary_file) begin
         status = $fscanf(fid, "%8x\n", line);
      end else begin
         line[7:0] = $fgetc(fid);
         line[15:8] = $fgetc(fid);
         line[23:16] = $fgetc(fid);
         line[31:24] = $fgetc(fid);
      end
      file[n_lines] = line;
      if (n_lines %1000000 == 0) begin
         $display("Read %d lines from input file", n_lines);  
      end
      n_lines = n_lines + 1;
   end
   $display("Read %d lines from input file", n_lines);  

   // Put file in host memory       
   
   for (int i = 0 ; i < n_lines ; i++) begin
      tb.hm_put_byte(.addr(i*4  ), .d(file[i][ 7: 0]));
      tb.hm_put_byte(.addr(i*4+1), .d(file[i][15: 8]));
      tb.hm_put_byte(.addr(i*4+2), .d(file[i][23:16]));
      tb.hm_put_byte(.addr(i*4+3), .d(file[i][31:24]));
   end
   
   
   // Transfer to CL Memory
   `ifdef FAST_MEM_INIT   
      for (int i=0;i< n_lines*4; i++) begin
         data = {24'b0, tb.hm_get_byte(i)};
         //data = file[i/4][i*8 +:8];
         if (N_DDR_CTRL == 1) begin
            addr = {i[31:6], i[5:0]};
            tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ addr ] = data;
         end else if (N_DDR_CTRL == 2) begin
            addr = {i[31:7], i[5:0]};
            case (i[6])
               0: tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ addr ] = data;
               1: tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ addr ] = data;
            endcase
         end else begin
            addr = {i[31:8], i[5:0]};
            case (i[7:6])
               0: tb.card.fpga.CL.\mem_ctrl[0].MEM_CTRL .memory[ addr ] = data;
               1: tb.card.fpga.CL.\mem_ctrl[1].MEM_CTRL .memory[ addr ] = data;
               2: tb.card.fpga.CL.\mem_ctrl[2].MEM_CTRL .memory[ addr ] = data;
               3: tb.card.fpga.CL.\mem_ctrl[3].MEM_CTRL .memory[ addr ] = data;
            endcase
         end
         if (i %4000000 == 0) begin
            $display("Transferred %d bytes to CL", i);  
         end
      end
   `else
      
      // Let the CL know of the number of DDR controllers available.
      // This is actually redundant unless you want to disable some controllers
      /*
      ocl_addr[31:24] = 0;
      ocl_addr[23:16] = N_TILES;
      ocl_addr[15:8] = ID_GLOBAL;
      ocl_addr[7:0] = MEM_XBAR_NUM_CTRL; 
      tb.poke(.addr(ocl_addr), .data(N_DDR_CTRL),
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      */

      // Begin DMA transfer
      tb.que_buffer_to_cl(.chan(0), .src_addr(0),
         .cl_addr(64'h0000_0000_0000), .len(n_lines*4) );  // move buffer to DDR 

      //$display("[%t] : starting H2C DMA channels ", $realtime);
      //Start transfers of data to CL DDR
      tb.start_que_to_cl(.chan(0));   

      // wait for dma transfers to complete
      timeout_count = 0;       
      do begin
         status = tb.is_dma_to_cl_done(.chan(0));
         #10ns;
         timeout_count++;
      end while ((status == 0) && (timeout_count < 2000));

      if (timeout_count >= 2000000) begin
         $display("[%t] : *** ERROR *** Timeout waiting for dma transfers from cl", $realtime);
      end
   `endif

endtask


task initialize_spilling_structures;

   // Initialize Splitter Stack and scratchpad
   integer i;
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
   end
   $display("Stack initialized"); 
   // END DMA
   
   for (i=0;i<N_TILES;i++) begin
      
      ocl_addr[31:16] = i;
      // set splitter base addresses
      ocl_addr[15:8] = ID_COAL_AND_SPLITTER;
      ocl_addr[7:0] = SPILL_ADDR_STACK_PTR;
      tb.poke(.addr(ocl_addr), .data(  (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION) >> 6  ),
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

      ocl_addr[7:0] = SPILL_BASE_STACK;
      tb.poke(.addr(ocl_addr), .data(
         (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION + STACK_BASE_OFFSET) >> 6 ) ,
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

      ocl_addr[7:0] = SPILL_BASE_SCRATCHPAD;
      tb.poke(.addr(ocl_addr), .data(
         (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION + SCRATCHPAD_BASE_OFFSET) >> 6 ) ,
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      
      ocl_addr[7:0] = SPILL_BASE_TASKS;
      tb.poke(.addr(ocl_addr), .data(
         (CL_SPILL_AREA + i*TOTAL_SPILL_ALLOCATION + SPILL_TASK_BASE_OFFSET) >> 6 ) ,
         .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

// Uncomment selectively to test task_spilling. 
/*
      ocl_addr[15:8] = ID_TASK_UNIT;
      ocl_addr[7:0] = TASK_UNIT_SPILL_THRESHOLD;
      ocl_data = 64;
      tb.poke(.addr(ocl_addr), .data(ocl_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      ocl_addr[7:0] = TASK_UNIT_SPILL_SIZE;
      ocl_data = 16;
      tb.poke(.addr(ocl_addr), .data(ocl_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 

      ocl_addr[15:8] = ID_CQ;
      ocl_addr [7:0] = CQ_SIZE;
      ocl_data = 16;
      tb.poke(.addr(ocl_addr), .data(ocl_data),
                .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      ocl_addr[15:8] = ID_TASK_UNIT;
      ocl_addr[7:0] = TASK_UNIT_TIED_CAPACITY;
      ocl_data = 32;
*/
/*
      tb.poke(.addr(ocl_addr), .data(ocl_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL));
      ocl_addr[15:8] = ID_TASK_UNIT;
      ocl_addr[7:0] = TASK_UNIT_SPILL_THRESHOLD;
      // has to be greater than (TIED_CAPACITY + CQ_SIZE + SPILL_SIZE)
      // why: n_untied_tasks = n_tasks - n_tied_tasks
      // however upto CQ_SIZE tasks could have been dequeued
      // and the coalescer needs at least SPILL_SIZE tasks to proceed 
      ocl_data = 66;
      tb.poke(.addr(ocl_addr), .data(ocl_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      ocl_addr[15:8] = ID_TASK_UNIT;
      ocl_addr[7:0] = TASK_UNIT_CLEAN_THRESHOLD;
      ocl_data = 4070;
      tb.poke(.addr(ocl_addr), .data(ocl_data),
             .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   
   // TODO: sanity checks
   // SPILL_THRESHOLD > (TIED_CAP + CQ_SIZE + SPILL_SIZE)
   // SPILL_SIZE % 8 ==0
   // SPILL_SIZE < 2**LOG_TQ_SPILL_SIZE
   // TIED_CAPACITY < 2**LOG_TQ_SIZE
   // CLEAN_THRESH < 2**TQ_STAGES-1
*/

    
      // Start coalesecer early
      ocl_addr[15:8] = ID_COAL;
      ocl_addr [7:0] = CORE_START;
      ocl_data = '1;
      tb.poke(.addr(ocl_addr), .data(ocl_data),
                .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 


      // 
      ocl_addr[15:8] = ID_TASK_UNIT;
      ocl_addr [7:0] = TASK_UNIT_PRE_ENQ_BUFFER_CONFIG;
      ocl_data = {16'd10, 16'd10};
      tb.poke(.addr(ocl_addr), .data(ocl_data),
                .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
   end

endtask
   
task flush_caches; 
   // Faster simulation by capping flushing to read-write data (BIG HACK)
   tb.card.fpga.CL.\tile[0].TILE .\l2[0].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   tb.card.fpga.CL.\tile[0].TILE .\l2[1].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   //tb.card.fpga.CL.\tile[1].TILE .\l2[0].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   //tb.card.fpga.CL.\tile[1].TILE .\l2[1].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   //tb.card.fpga.CL.\tile[2].TILE .\l2[0].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   //tb.card.fpga.CL.\tile[2].TILE .\l2[1].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   //tb.card.fpga.CL.\tile[3].TILE .\l2[0].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   //tb.card.fpga.CL.\tile[3].TILE .\l2[1].L2 .L2_STAGE_1.flush_addr_last = (file[3] >> 4);
   
   for (int i=0;i<N_TILES;i++) begin
      for (int j=0;j<L2_BANKS;j++) begin
         ocl_addr[23:16] = i;
         ocl_addr[15:8] = ID_L2 + j;
         ocl_addr[ 7:0] = L2_FLUSH;
         tb.poke(.addr(ocl_addr), .data(1),
                   .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
      end
   end
   do begin
      for (int i=0;i<N_TILES;i++) begin
         ocl_addr[23:16] = i;
         ocl_addr[15:8] = ID_L2;
         ocl_addr[ 7:0] = L2_FLUSH;
         tb.peek(.addr(ocl_addr), .data(ocl_data),
                .id(AXI_ID), .size(DataSize::UINT16), .intf(AxiPort::PORT_OCL)); 
         if (ocl_data ==1) break;

      end
      #300ns;
   end while (ocl_data==1);
endtask

endmodule

