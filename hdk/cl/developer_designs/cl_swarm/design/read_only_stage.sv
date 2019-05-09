import swarm::*;

module read_only_stage
#(
   parameter STAGE_ID,
   parameter IN_WIDTH,
   parameter OUT_WIDTH,
   parameter DATA_WIDTH=64
) (
   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input logic [IN_WIDTH-1:0]     in_task, 
   input cq_slice_slot_t          in_cq_slot,
   input                          in_last,

   output logic        arvalid,
   input               arready,
   output logic [31:0] araddr,
   output id_t         arid,

   input               rvalid,
   output logic        rready,
   input id_t          rid,
   input logic [511:0] rdata,

   output logic                  out_valid,
   input                         out_ready,

   output logic [OUT_WIDTH-1:0]  out_task,
   output cq_slice_slot_t        out_cq_slot,
   output logic [DATA_WIDTH-1:0] out_data,
   output logic                  out_last,

   output logic                  idle, // all threads accounted for
   
   reg_bus_t         reg_bus
);

localparam FREE_LIST_SIZE = 5;

logic [FREE_LIST_SIZE-1:0] arid_free_list_add;
logic [FREE_LIST_SIZE-1:0] arid_free_list_next;
logic arid_free_list_add_valid;
logic arid_free_list_remove_valid;
logic arid_free_list_empty;

thread_id_t thread_free_list_add;
thread_id_t thread_free_list_next;
logic thread_free_list_add_valid;
logic thread_free_list_remove_valid;
logic thread_free_list_empty;
   
typedef struct packed {
   thread_id_t       thread;
   logic [15:0]      valid_words;
   logic [2:0]       arsize;
} ro_stage_mshr_t;

ro_stage_mshr_t ro_mshr [0:2**FREE_LIST_SIZE-1];

logic [OUT_WIDTH-1:0] mem_task [0:N_THREADS-1];
cq_slice_slot_t       mem_cq_slot [0:N_THREADS-1];

logic [31:0] mem_last_word[0:N_THREADS-1];

logic [7:0] remaining_words [0:N_THREADS-1] ;

logic reg_rvalid, reg_rready;
logic [511:0] reg_rdata;
id_t  reg_rid;
ro_stage_mshr_t rid_mshr;

logic [15:0] next_valid_words;

logic s_arvalid, reg_arvalid;
logic s_arready;
logic [31:0] s_araddr, reg_araddr;
thread_id_t           reg_thread;
logic [2:0] s_arsize, reg_arsize; 
logic [7:0] s_arlen,  reg_n_words;
ro_stage_mshr_t write_mshr; 
logic last_read_in_burst;
logic [OUT_WIDTH-1:0] s_task;
logic s_out_valid;

// TODO sizes other than 64
logic [31:0] out_data_word_0;
logic [31:0] out_data_word_1;
logic out_data_word_0_valid;
logic out_data_word_1_valid;

logic [31:0] out_data_word_from_mem;

always_comb begin
   next_valid_words = rid_mshr.valid_words;
   for (int j=0;j<16;j++) begin
      if (out_data_word_0_valid & (j == out_data_word_id)) begin
         next_valid_words[j] = 1'b0;
      end else if (out_data_word_1_valid & (j== (out_data_word_id + 1))) begin
         next_valid_words[j] = 1'b0;
      end
   end
end

assign rready = !reg_rvalid;
always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_rvalid <= 1'b0;
   end else begin
      if (rvalid & rready) begin
         rid_mshr <= ro_mshr[rid[7:0]];
         reg_rid <= rid;
         reg_rvalid <= rvalid;
         reg_rdata <= rdata;
      end else begin
         if (reg_rvalid) begin
            if ( (out_valid & out_ready) | (!out_valid & next_valid_words == 0)) begin
               rid_mshr.valid_words <= next_valid_words;
               if (next_valid_words == 0) begin
                  reg_rvalid <= 1'b0;
               end
            end
         end
      end
   end
end

assign arid_free_list_add_valid = rvalid & rready;
assign arid_free_list_add = rid[7:0];
assign thread_free_list_add_valid = out_last & (out_valid & out_ready);
assign thread_free_list_add = rid_mshr.thread;

logic [3:0] out_data_word_id;
   lowbit #(
      .OUT_WIDTH(4),
      .IN_WIDTH(16)   
   ) VALID_WORD  (
      .in(rid_mshr.valid_words),
      .out(out_data_word_id)
   );

always_comb begin 
   out_data_word_0 = reg_rdata[ out_data_word_id * 32 +: 32]; 
   out_data_word_1 = reg_rdata[ (out_data_word_id + 1) * 32 +: 32]; 
   out_data_word_0_valid = rid_mshr.valid_words[out_data_word_id];
   out_data_word_1_valid = (out_data_word_id < 15) & rid_mshr.valid_words[out_data_word_id + 1];
   out_data_word_from_mem = mem_last_word[rid_mshr.thread];
end

always_comb begin
   out_task = mem_task[rid_mshr.thread]; 
   out_cq_slot = mem_cq_slot[rid_mshr.thread]; 
   out_data = 'x;
   out_valid = 1'b0;
   out_last = 1'b0;
   if (reg_rvalid) begin
      if (out_data_word_0_valid && out_data_word_1_valid) begin
         out_data[31: 0] = out_data_word_0;
         out_data[63:32] = out_data_word_1;
         out_valid = 1'b1;
         out_last = (remaining_words[rid_mshr.thread] == 2);
      end else if (out_data_word_id == 0) begin
         out_data[31: 0] = out_data_word_0; 
         out_data[63:32] = out_data_word_from_mem ;
         out_valid = (remaining_words[rid_mshr.thread] == 1);
         out_last = (remaining_words[rid_mshr.thread] == 1);
      end else if (out_data_word_id == 15) begin
         out_data[31: 0] = out_data_word_from_mem ;
         out_data[63:32] = out_data_word_0; 
         out_valid = (remaining_words[rid_mshr.thread] == 1);
         out_last = (remaining_words[rid_mshr.thread] == 1);
      end 
   end
end

genvar i;
generate
   for (i=0;i<N_THREADS;i++) begin
      always_ff @(posedge clk) begin
         if (!rstn) begin
            remaining_words[i] <= 0;
         end else begin
            if (s_arvalid & s_arready & (i==in_thread)) begin
               case (s_arsize) 
                 2: remaining_words[i] <= (s_arlen + 1);
                 3: remaining_words[i] <= (s_arlen + 1) << 1;
                 // TODO
               endcase
            end else if (reg_rvalid & ( i == rid_mshr.thread)) begin
               if (out_valid) begin
                  if (out_ready & out_data_word_0_valid & out_data_word_1_valid) begin
                     remaining_words[i] <= remaining_words[i] -2;
                  end
               end else if (out_data_word_0_valid | out_data_word_1_valid) begin
                  remaining_words[i] <= remaining_words[i] -1;
               end
            end
         end

      end
   end

endgenerate


always_ff @(posedge clk) begin
   if (reg_rvalid) begin
      mem_last_word[rid_mshr.thread] <= out_data_word_0; 
   end
end


free_list #(
   .LOG_DEPTH(FREE_LIST_SIZE)
) FREE_LIST_ARID  (
   .clk(clk),
   .rstn(rstn),

   .wr_en(arid_free_list_add_valid),
   .rd_en(arid_free_list_remove_valid),
   .wr_data(arid_free_list_add),

   .full(), 
   .empty(arid_free_list_empty),
   .rd_data(arid_free_list_next),

   .size()
);

free_list #(
   .LOG_DEPTH($clog2(N_THREADS))
) FREE_LIST_THREAD_ID  (
   .clk(clk),
   .rstn(rstn),

   .wr_en(thread_free_list_add_valid),
   .rd_en(thread_free_list_remove_valid),
   .wr_data(thread_free_list_add),

   .full(idle), 
   .empty(thread_free_list_empty),
   .rd_data(thread_free_list_next),

   .size()
);

thread_id_t in_thread;
assign in_thread = thread_free_list_next;

assign thread_free_list_remove_valid = task_in_ready & s_out_valid;


logic [3:0] ar_read_words; // number of set bits in valid_words[]

generate 
   for (i=0;i<16;i++) begin
      assign write_mshr.valid_words[i] = (i >= reg_araddr[5:2]) & (i <  (reg_araddr[5:2] + reg_n_words));
   end
endgenerate
assign write_mshr.thread = reg_thread;
assign write_mshr.arsize = reg_arsize;

assign araddr = reg_araddr;
assign arvalid = reg_arvalid & !arid_free_list_empty;
assign arid = (STAGE_ID -1) << 8 | arid_free_list_next;
assign s_arready = s_arvalid & !thread_free_list_empty & ( !reg_arvalid | (arvalid & arready & last_read_in_burst) );
assign last_read_in_burst = ((reg_araddr[5:2] + reg_n_words) <= 16);
// if the number of words remaining in the cache line is greater than number of
// words requested..
assign ar_read_words = ( (16- reg_araddr[5:2])  > reg_n_words) ? reg_n_words : (16 - reg_araddr[5:2]);

always_ff @(posedge clk) begin
   if (arvalid & arready) begin
     ro_mshr[arid_free_list_next] <= write_mshr;
   end
end
assign arid_free_list_remove_valid = (arvalid & arready);

always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_arvalid <= 1'b0;
      reg_araddr <= 'x;
      reg_arsize <= 'x;
   end else begin
      if (s_arvalid & s_arready) begin
         reg_arvalid <= 1'b1;
         reg_araddr <= s_araddr;
         reg_arsize <= s_arsize;
         reg_thread <= in_thread;
         mem_task[in_thread] <= s_task;
         mem_cq_slot[in_thread] <= in_cq_slot;
         case (s_arsize) 
           2: reg_n_words <= (s_arlen + 1);
           3: reg_n_words <= (s_arlen + 1) << 1;
           // TODO
         endcase
      end else if (reg_arvalid) begin
         if (arvalid & arready) begin
            if (!last_read_in_burst) begin
               reg_araddr <= reg_araddr + (ar_read_words * 4); 
               reg_n_words <= reg_n_words - ar_read_words;
            end else begin
               reg_arvalid <= 1'b0;
            end
         end
      end

   end
end

generate 
if (STAGE_ID == 1) begin

sssp_stage_1 STAGE 
(
   .clk  (clk),
   .rstn (rstn),

   .task_in_valid (task_in_valid),
   .task_in_ready (task_in_ready),

   .in_task       (in_task), 

   .arvalid      (s_arvalid),
   .arready      (s_arready),
   .araddr       (s_araddr),
   .arsize       (s_arsize),
   .arlen        (s_arlen),


   .out_valid    (s_out_valid),
   .out_task     (s_task), // multicycle user functions not supported yet
   
   .reg_bus      (reg_bus)


);

end else if (STAGE_ID == 2) begin

sssp_stage_2 STAGE 
(
   .clk  (clk),
   .rstn (rstn),

   .task_in_valid (task_in_valid),
   .task_in_ready (task_in_ready),

   .in_task       (in_task), 

   .arvalid      (s_arvalid),
   .arready      (s_arready),
   .araddr       (s_araddr),
   .arsize       (s_arsize),
   .arlen        (s_arlen),


   .out_valid    (s_out_valid), 
   .out_task     (s_task),
   
   .reg_bus      (reg_bus)


);

end
endgenerate





endmodule

module sssp_stage_1
(

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t       in_task, 

   output logic        arvalid,
   input               arready,
   output logic [31:0] araddr,
   output logic [2:0]  arsize,
   output logic [7:0]  arlen,

   output logic                  out_valid,
   output task_t                 out_task,
   
   reg_bus_t         reg_bus


);

logic [31:0] offset_base_addr;

assign araddr = offset_base_addr + (in_task.locale <<  2);
assign arsize = 3;
assign arlen = 0;
assign out_task = in_task;
always_comb begin
   arvalid = 1'b0;
   out_valid = 1'b0;
   task_in_ready = 1'b0;
   if (task_in_valid) begin
      arvalid = 1'b1;
      out_valid = 1'b1;
      if (arready) begin
         task_in_ready = 1'b1;
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      offset_base_addr <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            OFFSET_BASE_ADDR : offset_base_addr <= (reg_bus.wdata << 2);
         endcase
      end
   end
end
always_ff @(posedge clk) begin
   reg_bus.rvalid <= reg_bus.arvalid;
end
assign reg_bus.rdata = 0;

`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [ro %2d] ts:%8d locale:%4d",
            cycle, 0 /*TILE_ID*/, 1, 
            in_task.ts, in_task.locale) ;
      end
   end 
`endif

endmodule

module sssp_stage_2
(

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input ro2_in_t       in_task, 

   output logic        arvalid,
   input               arready,
   output logic [31:0] araddr,
   output logic [2:0]  arsize,
   output logic [7:0]  arlen,

   output logic                  out_valid,
   output task_t                 out_task,
   
   reg_bus_t         reg_bus


);

logic [31:0] neigbors_base_addr;
         
assign araddr = neigbors_base_addr + (in_task.eo_begin <<  3);
assign arsize = 3;
assign arlen = (in_task.eo_end - in_task.eo_begin) -1;
assign out_task = in_task.task_desc;

always_comb begin
   arvalid = 1'b0;
   out_valid = 1'b0;
   task_in_ready = 1'b0;
   if (task_in_valid) begin
      if (in_task.eo_end == in_task.eo_begin) begin
         task_in_ready = 1'b1;
      end else begin
         arvalid = 1'b1;
         out_valid = 1'b1;
         if (arready) begin
            task_in_ready = 1'b1;
         end
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      neigbors_base_addr <= 0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            NEIGHBOR_BASE_ADDR : neigbors_base_addr <= (reg_bus.wdata << 2);
         endcase
      end
   end
end
always_ff @(posedge clk) begin
   reg_bus.rvalid <= reg_bus.arvalid;
end
assign reg_bus.rdata = 0;

`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [ro %2d] ts:%8d locale:%4d eo:(%4d %4d)",
            cycle, 0 /*TILE_ID*/, 2, 
            in_task.task_desc.ts, in_task.task_desc.locale, in_task.eo_begin, in_task.eo_end) ;
      end
   end 
`endif

endmodule


module sssp_gen_child
(

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t       in_task, 
   input logic [63:0] in_data,

   output logic                  out_valid,
   input                         out_ready,
   output task_t                 out_task
   

);

always_ff @(posedge clk) begin
   if (!rstn) begin
      out_valid <= 1'b0;
   end else begin
      if (task_in_valid & task_in_ready) begin
         out_valid <= 1'b1; 
         out_task.ts <= in_task.ts + in_data[63:32];
         out_task.locale <= in_data[31:0];
         out_task.ttype <= 0;
         out_task.producer <= 1'b0;
         out_task.no_write <= 1'b0;
         out_task.no_read <= 1'b0;
         out_task.args <= 0;
      end else if (out_valid & out_ready) begin
         out_valid <= 1'b0;
      end
   end

end

assign task_in_ready = task_in_valid & (!out_valid | out_ready);

`ifdef XILINX_SIMULATOR
   logic [63:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle + 1;
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [ro %2d] ts:%8d locale:%4d neighbor:(%4d %4d)",
            cycle, 0 /*TILE_ID*/, 3, 
            in_task.ts, in_task.locale, in_data[31:0], in_data[63:32]) ;
      end
   end 
`endif

endmodule

