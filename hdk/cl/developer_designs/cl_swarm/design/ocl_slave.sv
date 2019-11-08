import swarm::*;

module ocl_slave 
#(
   parameter TILE_ID=0
) (
   input clk,
   input rstn,

   axi_bus_t.master ocl,
   
   // Interface to other componenets.
   output logic [15:0] reg_bus_waddr,
   output logic [31:0] reg_bus_wdata,
   output logic [ID_LAST-1:0] reg_bus_wvalid,

   output logic [ID_LAST-1:0] reg_bus_arvalid,
   output logic [15:0] reg_bus_araddr,
   input [ID_LAST-1:0] reg_bus_rvalid,
   input reg_data_t [ID_LAST-1:0] reg_bus_rdata,

   output logic task_arvalid,
   output task_type_t task_araddr,
   input task_rvalid,
   input task_t task_rdata,

   output logic task_wvalid,
   output task_t task_wdata, 
   input task_wready,

   axi_bus_t.slave l1,

   input [31:0] done,
   output logic [63:0] cur_cycle,

   input [31:0] l2_debug

   
);

   localparam OCL_ON = (ALL_OCL || (TILE_ID == 0));

   typedef enum logic [3:0] { OCL_IDLE, OCL_SEND_AW, OCL_WAIT_W, OCL_SEND_W,
                              OCL_WAIT_B, OCL_SEND_B,
                              OCL_SEND_AR, OCL_WAIT_R, OCL_SEND_R
                              } ocl_state;

   logic [31:0] last_mem_latency;
   logic [31:0] task_locale;
   logic [ARG_WIDTH-1:0] task_args;
   logic [31:0] task_ts;
   logic [1:0] task_ttype;
   logic [3:0] task_param; // {producer, no_write, no_read, non_spec}
   logic [63:0] mem_addr;

   logic [31:0] task_args_word;
   
   logic [ID_LAST-1:0] wr_comp_bit_vector;

   ocl_state state;

   logic [15:0] id;

   logic [31:0] addr;
   logic [31:0] data;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         state <= OCL_IDLE;
         wr_comp_bit_vector <= 0;
         task_args_word <= 0;
         task_args <= 0;
         task_param <= 0;
      end else begin 
         case (state) 
            OCL_IDLE: begin
               if (ocl.awvalid) begin
                  state <= OCL_WAIT_W;
                  addr <= ocl.awaddr;
                  case (ocl.awaddr[15:8])
                     ID_ALL_CORES: begin
                        `ifdef USE_PIPELINED_TEMPLATE
                           wr_comp_bit_vector[4:1] <= '1;
                        `else 
                           wr_comp_bit_vector [ID_CORE_BEGIN +: N_CORES] <= '1;
                        `endif
                        wr_comp_bit_vector[ID_COAL    ] <= 1;
                        wr_comp_bit_vector[ID_SPLITTER    ] <= 1;
                     end
                     ID_ALL_APP_CORES : begin
                        `ifdef USE_PIPELINED_TEMPLATE
                           wr_comp_bit_vector[3:1] <= '1;
                        `else 
                           wr_comp_bit_vector [ID_CORE_BEGIN +: N_CORES] <= '1;
                        `endif
                     end
                     ID_COAL_AND_SPLITTER : begin 
                        wr_comp_bit_vector[ID_SPLITTER] <= 1;
                        wr_comp_bit_vector[ID_COAL    ] <= 1;
                     end
                     ID_GLOBAL : wr_comp_bit_vector <= 0;
                     default : wr_comp_bit_vector[ ocl.awaddr[15:8]] <= 1;
                  endcase

               end else if (ocl.arvalid) begin
                  state <= OCL_SEND_AR;
                  addr <= ocl.araddr;
               end
            end
            OCL_WAIT_W: begin
               if (ocl.wvalid) begin
                  state <= OCL_SEND_W;
                  data <= ocl.wdata;
               end
            end
            OCL_SEND_W: begin
               if ( (addr[15:8] != 0) || (!OCL_ON)) begin
                  state <= OCL_SEND_B;
               end else begin
                  case (addr[7:0]) 
                     OCL_TASK_ENQ: begin
                        if (task_wready) begin
                           state <= OCL_SEND_B;
                        end 
                     end
                     OCL_ACCESS_MEM: begin
                        if (l1.awready) begin
                           state <= OCL_WAIT_B;
                           last_mem_latency <= cur_cycle;
                        end 
                     end
                     default: state <= OCL_SEND_B;
                  endcase

                  case (addr[7:0]) 
                     OCL_TASK_ENQ_ARGS: task_args[task_args_word*32 +: 32] <= data;
                     OCL_TASK_ENQ_LOCALE: task_locale <= data;
                     OCL_TASK_ENQ_TTYPE: task_ttype <= data;
                     OCL_TASK_ENQ_NON_SPEC : task_param[0] <= data[0];
                     OCL_ACCESS_MEM_SET_MSB : mem_addr[63:0] <= data;
                     OCL_ACCESS_MEM_SET_LSB : mem_addr[31:0] <= data;
                     OCL_TASK_ENQ_ARG_WORD : task_args_word <= data;
                  endcase
               end
            end
            OCL_WAIT_B: begin
               if (l1.bvalid) begin
                  state <= OCL_SEND_B;
                  last_mem_latency <= cur_cycle - last_mem_latency;
               end
            end
            OCL_SEND_B: begin
               if (ocl.bready) begin
                  state <= OCL_IDLE;
                  wr_comp_bit_vector <= 0;
               end
            end
            OCL_SEND_AR: begin
               if (addr[15:8] != 0) begin
                  state <= OCL_WAIT_R;
               end else begin
                  case (addr[7:0]) 
                     OCL_ACCESS_MEM: begin
                        if (l1.arready) begin
                           state <= OCL_WAIT_R;
                           last_mem_latency <= cur_cycle;
                        end 
                     end
                     default: state <= OCL_WAIT_R;
                  endcase
               end
            end
            OCL_WAIT_R: begin
               if (!OCL_ON) begin
                  state <= OCL_SEND_R;
               end else if (addr [15:8] != 0 ) begin
                  if (reg_bus_rvalid[addr[15:8]]) begin
                     state <= OCL_SEND_R;
                     data <= reg_bus_rdata[addr[15:8]];
                  end
               end else begin
                  case (addr[7:0]) 
                     OCL_TASK_ENQ: begin
                        if (task_rvalid) begin
                           state <= OCL_SEND_R;
                           data <= task_rdata.ts;
                           task_locale <= task_rdata.locale;
                           task_args <= task_rdata.args;
                        end
                     end
                     OCL_TASK_ENQ_LOCALE: begin
                        state <= OCL_SEND_R;
                        data <= task_locale;
                     end
                     OCL_TASK_ENQ_ARGS: begin
                        state <= OCL_SEND_R;
                        data <= task_args;
                     end
                     OCL_ACCESS_MEM: begin
                        if (l1.rvalid) begin
                           state <= OCL_SEND_R;
                           data <= l1.rdata;
                           last_mem_latency <= cur_cycle - last_mem_latency;
                        end
                     end
                     OCL_CUR_CYCLE_MSB: begin
                        state <= OCL_SEND_R;
                        data <= cur_cycle[63:32];
                     end
                     OCL_CUR_CYCLE_LSB: begin
                        state <= OCL_SEND_R;
                        data <= cur_cycle[31:0];
                     end
                     OCL_LAST_MEM_LATENCY: begin
                        state <= OCL_SEND_R;
                        data <= last_mem_latency;
                     end
                     OCL_L2_DEBUG: begin
                        state <= OCL_SEND_R;
                        data <= l2_debug;
                     end
                     OCL_PARAM_N_TILES : begin
                        state <= OCL_SEND_R;
                        data <= N_TILES;
                     end
                     OCL_PARAM_N_CORES : begin
                        state <= OCL_SEND_R;
                        `ifdef USE_PIPELINED_TEMPLATE
                           data <= 0;
                        `else 
                           data <= N_CORES;
                        `endif
                     end
                     OCL_PARAM_LOG_TQ_HEAP_STAGES : begin
                        state <= OCL_SEND_R;
                        data <= TQ_STAGES;
                     end
                     OCL_PARAM_LOG_TQ_SIZE : begin
                        state <= OCL_SEND_R;
                        data <= LOG_TQ_SIZE;
                     end
                     OCL_PARAM_LOG_CQ_SIZE : begin
                        state <= OCL_SEND_R;
                        data <= LOG_CQ_SLICE_SIZE;
                     end
                     OCL_PARAM_LOG_READY_LIST_SIZE : begin
                        state <= OCL_SEND_R;
                        data <= LOG_READY_LIST_SIZE;
                     end
                     OCL_PARAM_LOG_SPILL_Q_SIZE: begin
                        state <= OCL_SEND_R;
                        data <= LOG_TQ_SPILL_SIZE;
                     end
                     OCL_PARAM_NON_SPEC: begin
                        state <= OCL_SEND_R;
                        data <= UNORDERED + NON_SPEC;
                     end
                     OCL_PARAM_LOG_L2_BANKS: begin
                        state <= OCL_SEND_R;
                        data <= LOG_L2_BANKS;
                     end
                     OCL_PARAM_APP_ID : begin
                        state <= OCL_SEND_R;
                        `ifdef USE_PIPELINED_TEMPLATE 
                           data <= APP_ID | (1<<16);
                        `else 
                           data <= APP_ID;
                        `endif
                     end
                     OCL_DONE: begin
                        state <= OCL_SEND_R;
                        data <= done;
                     end
                  endcase
               end
            end
            OCL_SEND_R: begin
               if (ocl.rready) begin
                  state <= OCL_IDLE;
               end
            end
         endcase
      end
   end


   always_ff @(posedge clk) begin
      if (!rstn) begin
         cur_cycle <= 0;
      end else begin
         cur_cycle <= cur_cycle + 1;
      end
   end

generate 
   assign l1.rready = (state == OCL_WAIT_R);
   assign l1.bready = 1'b1;
   
if (OCL_ON) begin
   assign l1.awvalid = (state == OCL_SEND_W) & (addr[15:0] == {8'b0, OCL_ACCESS_MEM});
   assign l1.wvalid = (state == OCL_SEND_W) & (addr[15:0] == {8'b0, OCL_ACCESS_MEM});
   assign l1.arvalid = (state == OCL_SEND_AR) & (addr[15:0] == {8'b0, OCL_ACCESS_MEM});
   assign task_wvalid = (state == OCL_SEND_W) & (addr[15:0] == {8'b0, OCL_TASK_ENQ});
   assign task_arvalid = (state == OCL_SEND_AR | state == OCL_WAIT_R) & (addr[15:0] == {8'b0, OCL_TASK_ENQ});
end else begin
   assign l1.awvalid = 0;
   assign l1.wvalid = 0;
   assign l1.arvalid = 0;
   assign task_wvalid = 0;
   assign task_arvalid = 0;
end
   assign l1.awaddr = mem_addr;
   assign l1.awlen = 0;
   assign l1.awsize = 2;
   assign l1.awid = 0;
   assign l1.wid = 0;
   assign l1.wdata = data;
   assign l1.wstrb = 4'b1111;
   assign l1.wlast = 1;

   assign l1.araddr = mem_addr;
   assign l1.arlen = 0;
   assign l1.arsize = 2;
   assign l1.arid = 0;
  
   assign ocl.awready = (state == OCL_IDLE);
   assign ocl.wready = (state == OCL_WAIT_W);
   assign ocl.arready = (state == OCL_IDLE);
   assign ocl.bvalid = (state == OCL_SEND_B);
   assign ocl.bresp = 2'b00;
   assign ocl.rvalid = (state == OCL_SEND_R);
   assign ocl.rdata = OCL_ON ? data : 0;
   assign ocl.rresp = 2'b00;
   
   assign task_wdata.ttype = task_ttype;
   assign task_wdata.locale  = task_locale;
   assign task_wdata.args  = task_args;
   assign task_wdata.ts    = data;
   assign task_wdata.producer = 1'b0;
   assign task_wdata.no_write = 1'b0;
   assign task_wdata.no_read = 1'b0;
   assign task_wdata.non_spec = task_param[0];

   assign task_araddr = task_ttype;

   genvar i;
      for (i=0;i<ID_LAST;i++) begin
         assign reg_bus_wvalid[i] = wr_comp_bit_vector[i] & (state == OCL_SEND_W);
         if (OCL_ON) begin
            assign reg_bus_arvalid[i] = (i==addr[15:8]) & (state == OCL_SEND_AR);
         end else begin
            assign reg_bus_arvalid[i] = 0;
         end
      end
   endgenerate
   assign reg_bus_waddr = addr[7:0];
   assign reg_bus_wdata = data;
   assign reg_bus_araddr = addr[7:0];
   
endmodule
