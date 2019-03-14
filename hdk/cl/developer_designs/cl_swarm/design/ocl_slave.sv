import swarm::*;

module ocl_slave 
(
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

   input done,
   output logic [63:0] cur_cycle

   
);

   typedef enum logic [3:0] { OCL_IDLE, OCL_SEND_AW, OCL_WAIT_W, OCL_SEND_W,
                              OCL_WAIT_B, OCL_SEND_B,
                              OCL_SEND_AR, OCL_WAIT_R, OCL_SEND_R
                              } ocl_state;

   logic [31:0] last_mem_latency;
   logic [31:0] task_hint;
   logic [ARG_WIDTH-1:0] task_args;
   logic [31:0] task_ts;
   logic [1:0] task_ttype;
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
      end else begin 
         case (state) 
            OCL_IDLE: begin
               if (ocl.awvalid) begin
                  state <= OCL_WAIT_W;
                  addr <= ocl.awaddr;
                  case (ocl.awaddr[15:8])
                     ID_ALL_CORES: begin
                        wr_comp_bit_vector[N_CORES:1] <= '1;
                        wr_comp_bit_vector[ID_COAL    ] <= 1;
                     end
                     ID_ALL_APP_CORES : wr_comp_bit_vector[N_APP_CORES:1] <= '1;
                     ID_COAL_AND_SPLITTER : begin 
                        wr_comp_bit_vector[ID_SPLITTER] <= 1;
                        wr_comp_bit_vector[ID_COAL    ] <= 1;
                     end
                     ID_TASK_XBAR : wr_comp_bit_vector <= 0;
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
               if (addr[15:8] != 0 ) begin
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
                     OCL_TASK_ENQ_HINT: task_hint <= data;
                     OCL_TASK_ENQ_TTYPE: task_ttype <= data;
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
               if (addr [15:8] != 0) begin
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
                           task_hint <= task_rdata.hint;
                           task_args <= task_rdata.args;
                        end
                     end
                     OCL_TASK_ENQ_HINT: begin
                        state <= OCL_SEND_R;
                        data <= task_hint;
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
                     OCL_PARAM_N_TILES : begin
                        state <= OCL_SEND_R;
                        data <= N_TILES;
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
                     OCL_PARAM_N_APP_CORES : begin
                        state <= OCL_SEND_R;
                        data <= N_APP_CORES;
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
                     OCL_DONE: begin
                        state <= OCL_SEND_R;
                        data <= {31'b0, done};
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
   
   assign l1.rready = (state == OCL_WAIT_R);
   assign l1.bready = 1'b1;
   
   assign l1.awvalid = (state == OCL_SEND_W) & (addr[15:0] == {8'b0, OCL_ACCESS_MEM});
   assign l1.wvalid = (state == OCL_SEND_W) & (addr[15:0] == {8'b0, OCL_ACCESS_MEM});
   assign l1.awaddr = mem_addr;
   assign l1.awlen = 0;
   assign l1.awsize = 2;
   assign l1.awid = 0;
   assign l1.wid = 0;
   assign l1.wdata = data;
   assign l1.wstrb = 4'b1111;
   assign l1.wlast = 1;

   assign l1.arvalid = (state == OCL_SEND_AR) & (addr[15:0] == {8'b0, OCL_ACCESS_MEM});
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
   assign ocl.rdata = data;
   assign ocl.rresp = 2'b00;
   
   assign task_wvalid = (state == OCL_SEND_W) & (addr[15:0] == {8'b0, OCL_TASK_ENQ});
   assign task_wdata.ttype = task_ttype;
   assign task_wdata.hint  = task_hint;
   assign task_wdata.args  = task_args;
   assign task_wdata.ts    = data;

   assign task_arvalid = (state == OCL_SEND_AR | state == OCL_WAIT_R) & (addr[15:0] == {8'b0, OCL_TASK_ENQ});
   assign task_araddr = task_ttype;

   genvar i;
   generate
      for (i=0;i<ID_LAST;i++) begin
         assign reg_bus_wvalid[i] = wr_comp_bit_vector[i] & (state == OCL_SEND_W);

         assign reg_bus_arvalid[i] = (i==addr[15:8]) & (state == OCL_SEND_AR);
      end
   endgenerate
   assign reg_bus_waddr = addr[7:0];
   assign reg_bus_wdata = data;
   assign reg_bus_araddr = addr[7:0];
   
endmodule
