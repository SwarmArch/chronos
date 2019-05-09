`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif

module splitter
#(
   parameter CORE_ID=2,
   parameter TILE_ID=0
) (
   input clk,
   input rstn,

   axi_bus_t.slave l1,
   reg_bus_t.master reg_bus, // write-only bus from OCL to all other modules

   input splitter_valid,
   output logic splitter_ready,
   input task_t splitter_task,

   output logic task_wvalid,
   output task_t task_wdata, 
   input task_wready,

   output logic stack_lock_out,
   input stack_lock_in,
    
   pci_debug_bus_t.master pci_debug,

   output ts_t lvt
);


typedef enum logic[3:0] {SPLITTER_IDLE,  
      SPLITTER_READ_MEM, SPLITTER_WAIT_MEMORY,
      SPLITTER_ENQ_CHILD,
      SPLITTER_READ_SCRATCHPAD, SPLITTER_READ_SCRATCHPAD_WAIT,
      SPLITTER_WRITE_SCRATCHPAD, SPLITTER_WRITE_SCRATCHPAD_WAIT,
      SPLITTER_GRAB_LOCK,
      SPLITTER_READ_STACK_PTR, SPLITTER_READ_STACK_PTR_WAIT,
      SPLITTER_WRITE_STACK_PTR, SPLITTER_WRITE_STACK_PTR_WAIT,
      SPLITTER_WRITE_STACK_TOP, SPLITTER_WRITE_STACK_TOP_WAIT,
      SPLITTER_RELEASE_LOCK
   } splitter_state_t;

logic start;

splitter_state_t state, state_next;
locale_t coal_id;


always_comb begin
   l1.rready = 1'b0;
   case (state) 
      SPLITTER_WAIT_MEMORY,
      SPLITTER_READ_SCRATCHPAD_WAIT,
      SPLITTER_READ_STACK_PTR_WAIT
         : l1.rready = 1'b1;
   endcase
end

always_comb begin
   l1.bready = 1'b0;
   case (state) 
      SPLITTER_WRITE_SCRATCHPAD_WAIT,
      SPLITTER_WRITE_STACK_PTR_WAIT,
      SPLITTER_WRITE_STACK_TOP_WAIT
         : l1.bready = 1'b1;
   endcase
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      stack_lock_out <= 1'b0; 
   end else begin
      // in case both the splitter and coalsecer tried to grab the lock on the
      // same cycle, splitter has priority.
      if (state == SPLITTER_GRAB_LOCK & !stack_lock_in) begin
         stack_lock_out <= 1'b1;
      end else if (state == SPLITTER_RELEASE_LOCK) begin
         stack_lock_out <= 1'b0;
      end
   end
end

logic [15:0] stack_ptr;

logic [SPLITTERS_PER_CHUNK-1:0] scratchpad_entry;
logic [TQ_WIDTH-1:0] next_enq_task;
logic last_enq_task;

logic [31:0] ADDR_BASE_SPILL;
logic [31:0] ADDR_BASE_SPLITTER_SCRATCHPAD; 
logic [31:0] ADDR_BASE_SPLITTER_STACK; 
logic [31:0] ADDR_SPLITTER_STACK_PTR; 
   
always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= SPLITTER_IDLE;
      lvt <= '1;
   end else begin
      state <= state_next;
      if (splitter_valid & splitter_ready) begin
         coal_id <= splitter_task.locale >> 16;
      end
      if (state == SPLITTER_READ_SCRATCHPAD_WAIT & l1.rvalid ) begin
         scratchpad_entry <= l1.rdata[SPLITTERS_PER_CHUNK-1:0] |
            (1<< (coal_id[LOG_SPLITTERS_PER_CHUNK-1:0] )) ;
      end
      if (state == SPLITTER_READ_STACK_PTR_WAIT & l1.rvalid) begin
         stack_ptr <= l1.rdata[15:0];
      end
      if (state == SPLITTER_WAIT_MEMORY & l1.rvalid) begin
         next_enq_task <= l1.rdata[TQ_WIDTH-1:0];
         last_enq_task <= l1.rlast;
      end
      if (splitter_valid & splitter_ready) begin
         lvt <= splitter_task.ts;
      end else if (state == SPLITTER_IDLE) begin
         lvt <= '1;
      end
   end
end

assign l1.awid = 0;
assign l1.wid = 0;
always_comb begin
   l1.arid    = 0;
   l1.arlen   = 0;
   l1.arsize  = 1; 
   l1.arvalid = 1'b0;
   l1.araddr  = 64'h0;

   l1.awlen   = 0; // 1 beat
   l1.awsize  = 3'b001; // 16 bits
   l1.awvalid = 0;
   l1.awaddr  = 0;
   l1.wvalid  = 1'b0;
   l1.wstrb   = 64'b1111; 
   l1.wlast   = 1'b0;
   l1.wdata   = 'x;
   
   task_wvalid = 1'b0;
   task_wdata  = 'x;

   splitter_ready = 1'b0;

   state_next = state;

   if (~rstn) begin
   end else begin
      case(state)
         SPLITTER_IDLE: begin
            if (start) begin
               if (splitter_valid) begin
                  splitter_ready = 1'b1;
                  state_next = SPLITTER_READ_MEM; 
               end
            end
         end
         SPLITTER_READ_MEM: begin
            l1.araddr = ADDR_BASE_SPILL +  (coal_id << LOG_SPLITTER_CHUNK_WIDTH);
            l1.arvalid = 1'b1;
            l1.arlen = TASKS_PER_SPLITTER - 1;
            l1.arsize =  $clog2(TQ_WIDTH) -3; 
            if (l1.arready) begin
               state_next = SPLITTER_WAIT_MEMORY;
            end
         end
         SPLITTER_WAIT_MEMORY: begin
            if (l1.rvalid) begin
               state_next = SPLITTER_ENQ_CHILD;
            end
         end
         SPLITTER_ENQ_CHILD: begin
            task_wvalid = 1'b1;
            task_wdata = next_enq_task;
            if (task_wready) begin
               state_next = last_enq_task ? SPLITTER_READ_SCRATCHPAD : SPLITTER_WAIT_MEMORY;
            end
         end
         SPLITTER_READ_SCRATCHPAD: begin
            l1.araddr = ADDR_BASE_SPLITTER_SCRATCHPAD + (coal_id >> 3);
            l1.araddr[ LOG_SPLITTERS_PER_CHUNK -4:0] = 0; // align to 2 byte address
            l1.arsize = LOG_SPLITTERS_PER_CHUNK - 3;
            l1.arlen = 0;
            l1.arvalid = 1;
            if (l1.arready) state_next = SPLITTER_READ_SCRATCHPAD_WAIT;
         end
         SPLITTER_READ_SCRATCHPAD_WAIT: begin
            if (l1.rvalid) begin
              state_next = SPLITTER_WRITE_SCRATCHPAD; 
            end
         end
         SPLITTER_WRITE_SCRATCHPAD: begin
            l1.awaddr = ADDR_BASE_SPLITTER_SCRATCHPAD + (coal_id >> 3);
            l1.awaddr[ LOG_SPLITTERS_PER_CHUNK -4:0] = 0; // align to 2 byte address
            l1.awsize = LOG_SPLITTERS_PER_CHUNK - 3;
            l1.awvalid = 1;
            l1.wvalid = 1;
            l1.wlast = 1;
            if (scratchpad_entry == '1) begin
               l1.wdata = 0;
            end else begin
               l1.wdata = scratchpad_entry;
            end
            if (l1.awready) begin
               state_next = SPLITTER_WRITE_SCRATCHPAD_WAIT;
            end
         end
         SPLITTER_WRITE_SCRATCHPAD_WAIT: begin
            if (l1.bvalid) begin
               state_next = (scratchpad_entry == '1) ? SPLITTER_GRAB_LOCK : SPLITTER_IDLE;
            end
         end
         SPLITTER_GRAB_LOCK: begin
            if (!stack_lock_in) state_next = SPLITTER_READ_STACK_PTR;
         end
         SPLITTER_READ_STACK_PTR: begin
            l1.araddr = ADDR_SPLITTER_STACK_PTR;
            l1.arsize = 1;
            l1.arlen = 0;
            l1.arvalid = 1;
            if (l1.arready) begin
               state_next = SPLITTER_READ_STACK_PTR_WAIT;
            end
         end
         SPLITTER_READ_STACK_PTR_WAIT: begin
            if (l1.rvalid) begin
               state_next = SPLITTER_WRITE_STACK_PTR;
            end
         end
         SPLITTER_WRITE_STACK_PTR: begin
            l1.awaddr = ADDR_SPLITTER_STACK_PTR;
            l1.awsize = 1;
            l1.awlen = 0;
            l1.awvalid = 1;
            l1.wvalid = 1;
            l1.wdata = stack_ptr - 1;
            l1.wlast = 1;
            if (l1.awready) begin
               state_next = SPLITTER_WRITE_STACK_PTR_WAIT;
            end
         end
         SPLITTER_WRITE_STACK_PTR_WAIT: begin
            if (l1.bvalid) state_next = SPLITTER_WRITE_STACK_TOP;
         end
         SPLITTER_WRITE_STACK_TOP: begin
            l1.awaddr = ADDR_BASE_SPLITTER_STACK + 
               ( (stack_ptr-1) << (LOG_SPLITTER_STACK_ENTRY_WIDTH -3));
            l1.awsize = LOG_SPLITTER_STACK_ENTRY_WIDTH - 3;
            l1.awlen = 0;
            l1.awvalid = 1;
            l1.wvalid = 1;
            l1.wdata = (coal_id >> LOG_SPLITTERS_PER_CHUNK);
            l1.wlast = 1;
            if (l1.awready) begin
               state_next = SPLITTER_WRITE_STACK_TOP_WAIT;
            end

         end
         SPLITTER_WRITE_STACK_TOP_WAIT: begin
            if (l1.bvalid) state_next = SPLITTER_RELEASE_LOCK;
         end
         SPLITTER_RELEASE_LOCK: begin
            state_next = SPLITTER_IDLE;
         end



      endcase
   end
end


`ifdef DEBUG
integer cycle;
always_ff @(posedge clk) begin
   if (!rstn) cycle <= 0;
   else cycle <= cycle + 1;
end
always_ff @(posedge clk) begin
   if (state == SPLITTER_IDLE) begin
      if (splitter_valid & splitter_ready) begin
         $display("[%5d][splitter-%2d] dequeue_task: (%5d,%5d)",
            cycle, TILE_ID, splitter_task.ts, splitter_task.locale >> 16);
      end
   end

   if (task_wvalid & task_wready) begin
         $display("[%5d][splitter-%2d] enqueue_task: (%2d,%5d,%5d)",
            cycle, TILE_ID, task_wdata.ttype, task_wdata.ts, task_wdata.locale);

   end
   if (l1.awvalid & l1.awready & l1.wvalid & l1.wready) begin
      case (state)
         SPLITTER_WRITE_STACK_PTR:
            $display("[%5d][splitter-%2d] write stack ptr : %6d",
                  cycle, TILE_ID, l1.wdata);
         SPLITTER_WRITE_STACK_TOP:
            $display("[%5d][splitter-%2d] write stack top : %6d",
                  cycle, TILE_ID,  l1.wdata);
      endcase

   end
end


`endif

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
      if (task_wvalid & task_wready) begin
         num_enqueues <= num_enqueues + 1;
      end
      if (splitter_valid & splitter_ready) begin
         num_dequeues <= num_dequeues + 1;
      end
   end
end


logic [LOG_LOG_DEPTH:0] log_size; 

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
      logic[31:0] num_dequeues;
      logic[15:0] coal_id; 
      logic[15:0] scratchpad_entry;

   } splitter_log_t;
   splitter_log_t log_word;
   always_comb begin
      log_valid = (state == SPLITTER_WRITE_SCRATCHPAD_WAIT & l1.bvalid);

      log_word = '0;
      log_word.num_dequeues = num_dequeues;
      log_word.coal_id = coal_id;
      log_word.scratchpad_entry = scratchpad_entry;
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

endmodule
