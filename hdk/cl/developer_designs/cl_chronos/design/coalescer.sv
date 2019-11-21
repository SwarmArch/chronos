`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif

import chronos::*;

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
   input stack_lock_in,

   output ts_t    lvt,
   
   pci_debug_bus_t.master pci_debug
    
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
   COAL_WRITE_TASK, COAL_WRITE_TASK_WAIT
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

always_ff @(posedge clk) begin
   if (!rstn) begin
      lvt <= '1;
   end else begin
      if (!spill_fifo_empty & (lvt > spill_fifo_rd_data.ts)) begin
         lvt <= spill_fifo_rd_data.ts;
      end else if (spill_fifo_empty & free_list_full) begin
         // It is not possible to (cheaply) track the lowest ts coal_child
         // that hasn't completed yet. So be conservative and do not reset lvt
         // until coalescer becomes idle.
         lvt <= '1;
      end
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
   end else if (state == COAL_WRITE_TASK_WAIT) begin
      coal_id <= coal_id + 1;
   end
   if (state == COAL_WRITE_TASK & l1.wvalid & l1.wready) begin
      if (tasks_remaining == TASKS_PER_SPLITTER) begin
         coal_ts <= spill_fifo_rd_data.ts;
      end else begin
         if ( (coal_ts > spill_fifo_rd_data.ts) & !spill_fifo_empty) begin
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


ts_t pending_coal_child_ts [0:15];
logic[15:0] pending_coal_child_id [0:15];
logic free_list_empty, free_list_full;
logic [3:0] next_awid;

   free_list #(
      .LOG_DEPTH(4)
   ) FREE_LIST (
      .clk(clk),
      .rstn(rstn),

      .wr_en(l1.bvalid & l1.bready),
      .rd_en(l1.awvalid & l1.awready),
      .wr_data(l1.bid[3:0]),

      .full(free_list_full), 
      .empty(free_list_empty),
      .rd_data(next_awid)
   );

logic [3:0] reg_awid, write_stack_ptr_awid; 
always_ff @(posedge clk) begin
   if (l1.awvalid & l1.awready) begin
      if (state == COAL_WRITE_STACK_PTR) begin
         write_stack_ptr_awid <= next_awid;
      end
      reg_awid <= next_awid;
   end
end

always_ff @(posedge clk) begin
   if (state == COAL_WRITE_TASK_WAIT) begin
      pending_coal_child_ts[reg_awid] <= coal_ts;
      pending_coal_child_id[reg_awid] <= coal_id;
   end
end

ts_t fifo_out_ts;
logic[15:0] fifo_out_id;
assign l1.bready = ((state == COAL_WRITE_STACK_PTR_WAIT) & (l1.bid[3:0] == write_stack_ptr_awid)) 
               ? 1'b1 :!fifo_full;

logic [4:0] coal_child_fifo_size;
   fifo #(
      .LOG_DEPTH(4),
      .WIDTH(32+16)
   ) COAL_CHILD_FIFO (
      .clk(clk),
      .rstn(rstn),

      .wr_en(l1.bvalid & l1.bready & 
            !( (state==COAL_WRITE_STACK_PTR_WAIT) & (l1.bid[3:0] == write_stack_ptr_awid)) ),
      .rd_en(coal_child_valid & coal_child_ready),
      .wr_data( { pending_coal_child_ts[l1.bid[3:0]], pending_coal_child_id[l1.bid[3:0]]}  ),

      .full(fifo_full), 
      .empty(fifo_empty),
      .rd_data( {fifo_out_ts, fifo_out_id} ),
      .size (coal_child_fifo_size)
   );

assign coal_child_valid = !fifo_empty;
assign coal_child_task.ts = fifo_out_ts;
assign coal_child_task.locale = (fifo_out_id<< 16) + ((TILE_ID)<<4); // route to same tile 
assign coal_child_task.ttype = TASK_TYPE_SPLITTER;
assign coal_child_task.args = 0;
assign coal_child_task.producer = 1'b1;
assign coal_child_task.no_write = 1'b1;
assign coal_child_task.no_read = 1'b0;

logic [3:0] cycles_since_last_deq;
always_ff @(posedge clk) begin
   if (!rstn) begin
      cycles_since_last_deq <= 0;
   end else begin
      if (spill_fifo_empty & !l1.wvalid) begin
         cycles_since_last_deq <= cycles_since_last_deq + 1;
      end else begin
         cycles_since_last_deq <= 0;
      end
   end
end

always_comb begin
   state_next = state;
   tasks_remaining_next = tasks_remaining;

   spill_fifo_rd_en = 1'b0;

   l1.awid    = next_awid;
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
         if (start & !spill_fifo_empty & !free_list_empty) state_next = COAL_GRAB_LOCK;
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
         l1.wid = next_awid;
         if (l1.awready) begin
            state_next = COAL_WRITE_STACK_PTR_WAIT;
         end
      end
      COAL_WRITE_STACK_PTR_WAIT: begin
         if (l1.bvalid & l1.bready & (l1.bid[3:0] == write_stack_ptr_awid)) state_next = COAL_READ_STACK_TOP;
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
         if (!spill_fifo_empty & !free_list_empty) begin
           tasks_remaining_next = TASKS_PER_SPLITTER;
           l1.awaddr = ADDR_BASE_SPILL + (coal_id << LOG_SPLITTER_CHUNK_WIDTH);
           l1.awsize = LOG_TASK_WIDTH - 3;
           l1.awlen = TASKS_PER_SPLITTER - 1;
           l1.awvalid = 1'b1;
           if (l1.awready) begin
              state_next = COAL_WRITE_TASK;
           end
         end
      end
      COAL_WRITE_TASK: begin
         if (!spill_fifo_empty | (cycles_since_last_deq == '1)) begin
            l1.wvalid = 1'b1;
            if (!spill_fifo_empty) begin
               l1.wdata[TQ_WIDTH-1:0] = spill_fifo_rd_data;  
            end else begin
               l1.wdata[TQ_WIDTH] = 1'b1;
            end
            l1.wlast = (tasks_remaining == 1);
            l1.wid = reg_awid;
            if (l1.wready) begin
               spill_fifo_rd_en = !spill_fifo_empty;
               tasks_remaining_next = tasks_remaining - 1;
               if (tasks_remaining == 1) begin
                  state_next = COAL_WRITE_TASK_WAIT; 
               end
            end
         end
      end
      COAL_WRITE_TASK_WAIT: begin
         state_next = (coal_id[LOG_SPLITTERS_PER_CHUNK-1:0] == '1) ? COAL_INIT : COAL_IDLE;
      end
   endcase
end

   
assign overflow_ready = !(spill_fifo_full);   
assign spill_fifo_wr_en = overflow_valid & overflow_ready;
assign spill_fifo_wr_data = overflow_task;

logic [8:0] spill_fifo_size; 

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
   .rd_data(spill_fifo_rd_data),
   .size(spill_fifo_size)

);


logic [LOG_LOG_DEPTH:0] log_size; 

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
      if (overflow_valid & overflow_ready) begin
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
         CORE_STATE    : reg_bus.rdata <= {
            l1.wvalid, l1.wready, l1.awvalid, l1.awready,
            tasks_remaining, 3'b0, spill_fifo_size, state};
         COAL_STACK_PTR : reg_bus.rdata <= {coal_id, stack_ptr};
         DEBUG_CAPACITY : reg_bus.rdata <= log_size;
         
      endcase
   end else begin
      reg_bus.rvalid <= 1'b0;
   end
end  

generate 
if (SPLITTER_LOGGING[TILE_ID]) begin
   
   logic log_valid;
   typedef struct packed {
  
      logic [7:0] tasks_remaining;

      logic [127:0] wdata;
      logic [31:0] awaddr;
      
      logic [15:0] awid;
      logic [15:0] wid;
      logic [15:0] bid;
      logic [15:0] coal_id;
      logic [15:0] write_stack_ptr_awid;
      logic [15:0] stack_ptr;

      logic wlast;
      logic [10:0] spill_fifo_size;
      logic [7:0] coal_child_fifo_size; 
      logic [3:0] state;

      logic awvalid;
      logic awready;
      logic wvalid;
      logic wready;
      logic arvalid;
      logic arready;
      logic bvalid;
      logic bready;
   } coal_log_t;
   coal_log_t log_word;
   always_comb begin
      log_valid = (l1.bvalid & l1.bready) | (l1.awvalid ) | (l1.wvalid & l1.wready) |
                  (state == COAL_WRITE_STACK_PTR_WAIT);

      log_word = '0;
      log_word.bready = l1.bready;
      log_word.bvalid = l1.bvalid;
      log_word.arready = l1.arready;
      log_word.arvalid = l1.arvalid;
      log_word.awready = l1.awready;
      log_word.awvalid = l1.awvalid;
      log_word.wready = l1.wready;
      log_word.wvalid = l1.wvalid;
      log_word.wlast = l1.wlast;
      log_word.state  = state;
      log_word.coal_child_fifo_size  = coal_child_fifo_size;
      log_word.spill_fifo_size  = spill_fifo_size;
      log_word.stack_ptr = stack_ptr;
      log_word.write_stack_ptr_awid = write_stack_ptr_awid;
      log_word.coal_id = coal_id;
      log_word.awid = l1.awid;
      log_word.wid = l1.wid;
      log_word.bid = l1.bid;
      log_word.awaddr = l1.awaddr;
      log_word.wdata[126:0] = l1.wdata;
      log_word.wdata[127] = l1.wdata[TQ_WIDTH];
      log_word.tasks_remaining = tasks_remaining;
   end

   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) TASK_UNIT_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid(log_valid),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end
endgenerate

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
