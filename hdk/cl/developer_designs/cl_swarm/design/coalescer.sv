`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif

import swarm::*;

module coalescer
#(
   parameter CORE_ID=2,
   parameter TILE_ID=0
) (
   input clk,
   input rstn,

   axi_bus_t.slave   l1,
   reg_bus_t.master  reg_bus,

   output logic   coal_child_valid,
   input          coal_child_ready,
   output task_t  coal_child_task,

   input          overflow_valid,
   output logic   overflow_ready,
   input task_t   overflow_task,

   output logic stack_lock_out,
   input stack_lock_in
    
);
   
logic spill_fifo_full;
logic spill_fifo_empty;

logic spill_fifo_wr_en;
logic spill_fifo_rd_en;

task_t spill_fifo_rd_data;
task_t spill_fifo_wr_data;

localparam LOG_TASK_WIDTH = $clog2(TQ_WIDTH); 
localparam C_TASK_WIDTH = 2**LOG_TASK_WIDTH; // in bits
localparam HEAP_N_STAGES = $clog2(TASKS_PER_SPLITTER + 1);

typedef enum logic [3:0] {
   COAL_INIT, COAL_GRAB_LOCK, COAL_CHECK_LOCK,
   COAL_READ_STACK_PTR, COAL_READ_STACK_PTR_WAIT,
   COAL_WRITE_STACK_PTR, COAL_WRITE_STACK_PTR_WAIT, 
   COAL_READ_STACK_TOP, COAL_READ_STACK_TOP_WAIT,
   COAL_RELEASE_LOCK,
   COAL_IDLE, 
   COAL_WRITE_TASK, COAL_WRITE_TASK_WAIT,
   COAL_ENQ_SPLITTER
} coal_state_t ;

logic start;

coal_state_t state, state_next;


reg [7:0] tasks_remaining, tasks_remaining_next;
logic [15:0] coal_id;
ts_t coal_ts;


logic [37:0] ADDR_BASE_SPILL;
logic [37:0] ADDR_BASE_SPLITTER_SCRATCHPAD; 
logic [37:0] ADDR_BASE_SPLITTER_STACK; 
logic [37:0] ADDR_SPLITTER_STACK_PTR; 

always_ff @(posedge clk) begin
   if (!rstn) begin
      stack_lock_out <= 1'b0; 
   end else begin
      // in case both the splitter and coalsecer tried to grab the lock on the
      // same cycle, splitter has priority.
      if (state == COAL_GRAB_LOCK & !stack_lock_in) begin
         stack_lock_out <= 1'b1;
      end else if (state == COAL_CHECK_LOCK) begin
         stack_lock_out <= !stack_lock_in;
      end else if (state == COAL_RELEASE_LOCK) begin
         stack_lock_out <= 1'b0;
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      state <= COAL_INIT;
      tasks_remaining <= 0;
   end else begin
      state <= state_next;
      tasks_remaining <= tasks_remaining_next;
   end
end

logic [15:0] stack_ptr;

localparam STACK_WIDTH = (1<< LOG_SPLITTER_STACK_ENTRY_WIDTH);

always_ff @(posedge clk) begin
   if (state == COAL_READ_STACK_PTR_WAIT & l1.rvalid) begin
      stack_ptr <= l1.rdata[15:0];
   end
   if (state == COAL_READ_STACK_TOP_WAIT & l1.rvalid ) begin
      coal_id <= (l1.rdata[STACK_WIDTH-1:0]) << LOG_SPLITTERS_PER_CHUNK;
   end else if (state == COAL_ENQ_SPLITTER & coal_child_valid & coal_child_ready) begin
      coal_id <= coal_id + 1;
   end
   if (state == COAL_WRITE_TASK & l1.wvalid & l1.wready) begin
      if (tasks_remaining == TASKS_PER_SPLITTER) begin
         coal_ts <= spill_fifo_rd_data.ts;
      end else if (NON_SPEC) begin
         if (coal_ts > spill_fifo_rd_data.ts) begin
            coal_ts <= spill_fifo_rd_data.ts;
         end
      end
   end
end

always_comb begin
   l1.rready = 1'b0;
   case (state) 
      COAL_READ_STACK_PTR_WAIT,
      COAL_READ_STACK_TOP_WAIT
         : l1.rready = 1'b1;
   endcase
end

always_comb begin
   l1.bready = 1'b0;
   case (state) 
      COAL_WRITE_STACK_PTR_WAIT,
      COAL_WRITE_TASK_WAIT
         : l1.bready = 1'b1;
   endcase
end

always_comb begin
   state_next = state;
   tasks_remaining_next = tasks_remaining;

   coal_child_valid = 1'b0;
   coal_child_task = 'x;

   spill_fifo_rd_en = 1'b0;

   l1.awid    = 0;
   l1.awlen   = 0; // TASKS_PER_COALSECER; 
   l1.awsize  = 1;  
   l1.awvalid = 0;
   l1.awaddr  = 0; 
   l1.wid  = 0;
   l1.wvalid  = 1'b0;
   l1.wlast   = 1'b0;
   l1.wdata   = 0;
   l1.wstrb   = '1;

   l1.arid    = 0;
   l1.arlen   = 0; 
   l1.arsize  = 3'b010; 
   l1.arvalid = 1'b0;
   l1.araddr  = 64'h0;

   case (state) 
      COAL_INIT: begin
         if (start & !spill_fifo_empty) state_next = COAL_GRAB_LOCK;
      end
      COAL_GRAB_LOCK: begin
         if (!stack_lock_in) state_next = COAL_CHECK_LOCK;
      end
      COAL_CHECK_LOCK: begin
         state_next = (stack_lock_in) ? COAL_GRAB_LOCK : COAL_READ_STACK_PTR;
      end
      COAL_READ_STACK_PTR: begin
         l1.araddr = ADDR_SPLITTER_STACK_PTR;
         l1.arsize = 1;
         l1.arlen = 0;
         l1.arvalid = 1;
         if (l1.arready) begin
            state_next = COAL_READ_STACK_PTR_WAIT;
         end
      end
      COAL_READ_STACK_PTR_WAIT: begin
         if (l1.rvalid) begin
            state_next = COAL_WRITE_STACK_PTR;
         end
      end
      COAL_WRITE_STACK_PTR: begin
         l1.awaddr = ADDR_SPLITTER_STACK_PTR;
         l1.awsize = 1;
         l1.awlen = 0;
         l1.awvalid = 1;
         l1.wvalid = 1;
         l1.wdata = stack_ptr + 1;
         l1.wlast = 1;
         if (l1.awready) begin
            state_next = COAL_WRITE_STACK_PTR_WAIT;
         end
      end
      COAL_WRITE_STACK_PTR_WAIT: begin
         if (l1.bvalid) state_next = COAL_READ_STACK_TOP;
      end
      COAL_READ_STACK_TOP: begin
         l1.araddr = ADDR_BASE_SPLITTER_STACK + 
               (stack_ptr << (LOG_SPLITTER_STACK_ENTRY_WIDTH -3));
         l1.arsize = LOG_SPLITTER_STACK_ENTRY_WIDTH - 3;
         l1.arlen = 0;
         l1.arvalid = 1;
         if (l1.arready) begin
            state_next = COAL_READ_STACK_TOP_WAIT;
         end
      end
      COAL_READ_STACK_TOP_WAIT: begin
         if (l1.rvalid) state_next = COAL_RELEASE_LOCK;
      end
      COAL_RELEASE_LOCK: begin
         state_next = COAL_IDLE;
      end
      COAL_IDLE: begin
         if (!start) begin
            // soft reset
            state_next = COAL_INIT;
         end else
         if (!spill_fifo_empty) begin
           state_next = COAL_WRITE_TASK;
           tasks_remaining_next = TASKS_PER_SPLITTER;
           l1.awaddr = ADDR_BASE_SPILL + (coal_id << LOG_SPLITTER_CHUNK_WIDTH);
           l1.awsize = LOG_TASK_WIDTH - 3;
           l1.awlen = TASKS_PER_SPLITTER - 1;
           l1.awvalid = 1;
           if (l1.awready) state_next = COAL_WRITE_TASK;
         end
      end
      COAL_WRITE_TASK: begin
         if (!spill_fifo_empty) begin
            l1.wvalid = 1'b1;
            l1.wdata[TQ_WIDTH-1:0] = spill_fifo_rd_data;  
            l1.wlast = (tasks_remaining == 1);
            if (l1.wready) begin
               spill_fifo_rd_en = 1'b1;
               tasks_remaining_next = tasks_remaining - 1;
               if (tasks_remaining == 1) begin
                  state_next = COAL_WRITE_TASK_WAIT; 
               end
            end
         end
      end
      COAL_WRITE_TASK_WAIT: begin
         if (l1.bvalid) begin
            state_next = COAL_ENQ_SPLITTER; 
         end
      end
      COAL_ENQ_SPLITTER: begin
         coal_child_valid = 1'b1;
         coal_child_task.ts = coal_ts;
         coal_child_task.locale = (coal_id<< 16) + ((TILE_ID)<<4); // route to same tile 
         coal_child_task.ttype = TASK_TYPE_SPLITTER;
         coal_child_task.args = 0;
         coal_child_task.producer = 1'b1;
         coal_child_task.no_write = 1'b1;
         coal_child_task.no_read = 1'b0;
         if (coal_child_ready) begin
            state_next = (coal_id[LOG_SPLITTERS_PER_CHUNK-1:0] == '1) ? COAL_INIT : COAL_IDLE;
         end
      end
   endcase
end

   
assign overflow_ready = !(spill_fifo_full);   
assign spill_fifo_wr_en = overflow_valid & overflow_ready;
assign spill_fifo_wr_data = overflow_task;

fifo #(
   .WIDTH( $bits(spill_fifo_wr_data)),
   .LOG_DEPTH(LOG_TQ_SPILL_SIZE)
) SPILL_FIFO (
   .clk(clk),
   .rstn(rstn),
   .wr_en(spill_fifo_wr_en),
   .wr_data(spill_fifo_wr_data),

   .full(spill_fifo_full),
   .empty(spill_fifo_empty),

   .rd_en(spill_fifo_rd_en),
   .rd_data(spill_fifo_rd_data)

);


always_ff @(posedge clk) begin
   if (!rstn) begin
      start <= 1'b0;
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr[7:0]) 
            CORE_START: start <= reg_bus.wdata[CORE_ID];
            SPILL_BASE_TASKS:  ADDR_BASE_SPILL <= {reg_bus.wdata , 6'b0};
            SPILL_BASE_STACK:  ADDR_BASE_SPLITTER_STACK  <= {reg_bus.wdata , 6'b0};
            SPILL_BASE_SCRATCHPAD:  ADDR_BASE_SPLITTER_SCRATCHPAD  <= {reg_bus.wdata , 6'b0};
            SPILL_ADDR_STACK_PTR :  ADDR_SPLITTER_STACK_PTR <= {reg_bus.wdata , 6'b0};
         endcase
      end
   end
   
end

logic [31:0] num_enqueues, num_dequeues;

always_ff @(posedge clk) begin
   if (!rstn) begin
      num_enqueues <= 0;
      num_dequeues <= 0;
   end else begin
      if (coal_child_valid & coal_child_ready) begin
         num_enqueues <= num_enqueues + 1;
      end
      if (overflow_valid) begin
         num_dequeues <= num_dequeues + 1;
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_bus.rvalid <= 1'b0;
   end
   if (reg_bus.arvalid) begin
      reg_bus.rvalid <= 1'b1;
      case (reg_bus.araddr) 
         CORE_NUM_ENQ  : reg_bus.rdata <= num_enqueues;
         CORE_NUM_DEQ  : reg_bus.rdata <= num_dequeues;
         CORE_STATE    : reg_bus.rdata <= state;
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end  

`ifdef XILINX_SIMULATOR
integer cycle;
always_ff @(posedge clk) begin
   if (!rstn) cycle <= 0;
   else cycle <= cycle + 1;
end
always_ff @(posedge clk) begin
   if (state == COAL_WRITE_TASK & l1.wvalid & l1.wready) begin
      $display("[%5d][coalescer-%2d] coalescing task (%3d,%2d) - (%2d, %3d %3d)",
         cycle, TILE_ID, coal_id, TASKS_PER_SPLITTER - tasks_remaining,
             spill_fifo_rd_data.ttype, spill_fifo_rd_data.ts, spill_fifo_rd_data.locale);
   end
   if (l1.awvalid & l1.awready & l1.wvalid & l1.wready) begin
      $display("[%5d][coalescer-%2d] write %10h : %10h",
            cycle, TILE_ID, l1.awaddr, l1.wdata);
   end
   if (l1.rvalid & l1.rready) begin
      case (state)
         COAL_READ_STACK_PTR_WAIT: 
            $display("[%5d][coalescer-%2d] read stack ptr %6d",
               cycle, TILE_ID, l1.rdata);
         COAL_READ_STACK_TOP_WAIT: 
            $display("[%5d][coalescer-%2d] read stack top %6d",
               cycle, TILE_ID, l1.rdata);

      endcase
   end

end

`endif

endmodule
