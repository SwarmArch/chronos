import swarm::*;

module write_rw
#(
   parameter TILE_ID=0
) (
   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input rw_write_t        task_in, 

   output logic        wvalid,
   input               wready,
   output logic [31:0] waddr, // directly index into the data_array bypassing tags
   output logic [511:0] wdata,
   output logic [63:0] wstrb,
   output id_t         wid,

   input               bvalid,
   output logic        bready,
   input id_t          bid,

   output logic            task_out_valid,
   input                   task_out_ready,
   output task_t           task_out,  
   output cq_slice_slot_t  task_out_cq_slot,  
   
   input fifo_size_t   task_out_fifo_occ, 
   
   input logic         gvt_task_slot_valid,
   cq_slice_slot_t     gvt_task_slot,

   output logic        unlock_locale,
   output thread_id_t  unlock_thread,
   
   output logic        finish_task_valid,
   input               finish_task_ready,
   output cq_slice_slot_t finish_task_slot,
   output logic        finish_task_is_undo_log_restore,
   
   reg_bus_t         reg_bus
);

fifo_size_t fifo_out_almost_full_thresh;

logic s_finish_task_valid, s_finish_task_ready, s_finish_task_is_undo_log_restore;
logic s_task_out_valid;

logic s_valid, s_ready;
logic s_wvalid;
logic [31:0] s_waddr;
object_t s_wdata;

logic s_out_valid, s_out_ready;
task_t s_out_task;

logic s_sched_valid, s_sched_ready;


always_ff @(posedge clk) begin
   if (s_task_out_valid) begin
      task_out <= s_out_task;
      task_out_cq_slot <= task_in.cq_slot;
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      task_out_valid <= 1'b0;
   end else begin
      if (s_task_out_valid) begin
         task_out_valid <= 1'b1;
      end else if (task_out_valid & task_out_ready) begin
         task_out_valid <= 1'b0;
      end
   end
end

assign s_out_ready = (!task_out_valid | task_out_ready);

logic [31:0] base_rw_addr;

assign s_valid = task_in_valid & (task_in.task_desc.ttype != TASK_TYPE_UNDO_LOG_RESTORE) & 
    (  (task_out_fifo_occ < fifo_out_almost_full_thresh) |
       (gvt_task_slot_valid & (gvt_task_slot == task_in.cq_slot)) );

always_comb begin
   if (task_in_valid & (task_in.task_desc.ttype != TASK_TYPE_UNDO_LOG_RESTORE)) begin
      if ( (s_out_valid & !s_out_ready) | 
           (!s_out_valid & !s_finish_task_ready) |
           (s_write_wvalid & !s_write_wready) ) begin
         s_sched_ready = 1'b0;
      end else begin
         s_sched_ready = 1'b1;
      end
   end else begin
      s_sched_ready = 1'b0;
   end
end

logic s_write_wvalid;
object_t s_write_data;
logic s_write_wready;
locale_t s_write_locale;
thread_id_t s_thread_id, write_thread_id;

logic wdata_fifo_full, wdata_fifo_empty;

locale_t write_locale;
object_t write_data;

fifo #(
      .WIDTH($bits(s_write_locale) + $bits(s_thread_id) + $bits(s_write_data)),
      .LOG_DEPTH(1)
   ) WDATA_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(s_write_wvalid & s_write_wready),
      .wr_data({s_thread_id, s_write_locale,  s_write_data}),

      .full(wdata_fifo_full),
      .empty(wdata_fifo_empty),

      .rd_en(wvalid & wready),
      .rd_data({write_thread_id, write_locale, write_data})

   );

assign s_thread_id = task_in.thread;
assign wvalid = !wdata_fifo_empty;
assign wid = write_thread_id;
assign s_write_wready = !wdata_fifo_full;
assign s_write_locale = task_in.task_desc.locale;

assign  waddr = base_rw_addr + ( write_locale << (LOG_RW_WIDTH) ) ;
always_comb begin
   wdata = 'x;
   case (LOG_RW_WIDTH) 
      2: wdata [ write_locale[3:0]* 32 +: 32 ] = write_data;
      3: wdata [ write_locale[2:0]* 64 +: 64 ] = write_data;
      4: wdata [ write_locale[1:0]* 128 +: 128 ] = write_data;
      5: wdata [ write_locale[0]* 256 +: 256 ] = write_data;
      6: wdata  = write_data;
   endcase
end
always_comb begin
   wstrb = 0;
   case (LOG_RW_WIDTH) 
      2: wstrb[ write_locale[3:0] * 4 +: 4]  = '1;
      3: wstrb[ write_locale[2:0] * 8 +: 8]  = '1;
      4: wstrb[ write_locale[1:0] * 16 +: 16]  = '1;
      5: wstrb[ write_locale[0] * 32 +: 32]  = '1;
      6: wstrb  = '1;
   endcase
end

always_comb begin 
   s_write_wvalid = 0;
   s_write_data = 'x;
   task_in_ready = 1'b0;
   s_finish_task_valid = 1'b0; 
   s_finish_task_is_undo_log_restore = 1'b0;
   s_task_out_valid = 1'b0;

   if (task_in_valid) begin
      if (task_in.task_desc.ttype == TASK_TYPE_UNDO_LOG_RESTORE) begin
         if (s_finish_task_ready) begin
            s_write_wvalid = 1'b1;
            s_write_data = task_in.object;
            s_finish_task_is_undo_log_restore = 1'b1;
            if (s_write_wvalid & s_write_wready) begin
               task_in_ready = 1'b1;
               s_finish_task_valid = 1'b1;
            end
         end
      end else if (s_sched_valid) begin 
         task_in_ready = s_ready;
         s_write_wvalid = s_wvalid;
         s_write_data = s_wdata;
         s_task_out_valid = s_sched_ready & s_out_valid;
         s_finish_task_valid = s_sched_ready & !s_out_valid;
             
      end
   end
end

`RW_WORKER #(
  .TILE_ID(TILE_ID) 
) WORKER (

   .clk(clk),
   .rstn(rstn),

   .task_in_valid(s_valid),
   .task_in_ready(s_ready),

   .in_task(task_in.task_desc), 
   .in_data(task_in.object),
   .in_cq_slot(task_in.cq_slot),
   
   .wvalid (s_wvalid),
   .waddr  (),
   .wdata  (s_wdata),

   .out_valid (s_out_valid),
   .out_task  (s_out_task),

   .sched_task_valid (s_sched_valid),
   .sched_task_ready (s_sched_ready),

   .reg_bus(reg_bus)

);

always_comb begin
   unlock_locale = 1'b0;
   unlock_thread = 'x;
   bready = 1'b0;
   if (task_in_ready & !s_write_wvalid) begin
      unlock_locale = 1'b1;
      unlock_thread = task_in.thread;
   end else if (bvalid) begin
      bready = 1'b1;
      unlock_locale = 1'b1;
      unlock_thread = bid;
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      base_rw_addr <= 0;
      fifo_out_almost_full_thresh <= '1;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
            RW_BASE_ADDR : base_rw_addr <= {reg_bus.wdata[29:0], 2'b00};
            CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD : fifo_out_almost_full_thresh <= reg_bus.wdata;
         endcase
      end
   end
end

always_ff @(posedge clk) begin
   reg_bus.rvalid <= reg_bus.arvalid;
end
assign reg_bus.rdata = 0;

logic finish_task_fifo_empty, finish_task_fifo_full;

fifo #(
      .WIDTH( $bits(finish_task_slot) + 1),
      .LOG_DEPTH(1)
   ) FINISHED_TASK_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(s_finish_task_valid & s_finish_task_ready),
      .wr_data({task_in.cq_slot, s_finish_task_is_undo_log_restore}),

      .full(finish_task_fifo_full),
      .empty(finish_task_fifo_empty),

      .rd_en(finish_task_valid & finish_task_ready),
      .rd_data({finish_task_slot, finish_task_is_undo_log_restore})

   );

assign finish_task_valid = !finish_task_fifo_empty;
assign s_finish_task_ready = !finish_task_fifo_full;

endmodule

