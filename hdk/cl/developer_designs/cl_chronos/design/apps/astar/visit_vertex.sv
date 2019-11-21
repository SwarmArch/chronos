`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import chronos::*;

module visit_vertex
#(
) (
   input ap_clk,
   input ap_rst_n,

   input ap_start,
   output logic ap_done,
   output logic ap_idle,
   output logic ap_ready,

   input [TQ_WIDTH-1:0] task_in, 

   output logic [TQ_WIDTH-1:0] task_out_V_TDATA,
   output logic task_out_V_TVALID,
   input task_out_V_TREADY,
        
   output logic [UNDO_LOG_ADDR_WIDTH + UNDO_LOG_DATA_WIDTH -1:0] undo_log_entry,
   output logic undo_log_entry_ap_vld,
   input undo_log_entry_ap_rdy,
   
   output logic         m_axi_l1_V_AWVALID ,
   input                m_axi_l1_V_AWREADY,
   output logic [31:0]  m_axi_l1_V_AWADDR ,
   output logic [7:0]   m_axi_l1_V_AWLEN  ,
   output logic [2:0]   m_axi_l1_V_AWSIZE ,
   output logic         m_axi_l1_V_WVALID ,
   input                m_axi_l1_V_WREADY ,
   output logic [31:0]  m_axi_l1_V_WDATA  ,
   output logic [3:0]   m_axi_l1_V_WSTRB  ,
   output logic         m_axi_l1_V_WLAST  ,
   output logic         m_axi_l1_V_ARVALID,
   input                m_axi_l1_V_ARREADY,
   output logic [31:0]  m_axi_l1_V_ARADDR ,
   output logic [7:0]   m_axi_l1_V_ARLEN  ,
   output logic [2:0]   m_axi_l1_V_ARSIZE ,
   input                m_axi_l1_V_RVALID ,
   output logic         m_axi_l1_V_RREADY ,
   input [31:0]         m_axi_l1_V_RDATA  ,
   input                m_axi_l1_V_RLAST  ,
   input                m_axi_l1_V_RID    ,
   input [1:0]          m_axi_l1_V_RRESP  ,
   input                m_axi_l1_V_BVALID ,
   output logic         m_axi_l1_V_BREADY ,
   input [1:0]          m_axi_l1_V_BRESP  ,
   input                m_axi_l1_V_BID    ,
   
   output logic [31:0]  ap_state
);

typedef enum logic[4:0] {
      NEXT_TASK,
      READ_BASE_OFFSET, WAIT_BASE_OFFSET,
      READ_BASE_NEIGHBORS, WAIT_BASE_NEIGHBORS,
      READ_BASE_DATA, WAIT_BASE_DATA,
      READ_TARGET, WAIT_TARGET,
      READ_PARENT, WAIT_PARENT, 
      CHECK_TARGET,
      READ_EDGE_OFFSET, WAIT_EDGE_OFFSET,
      READ_NEIGHBORS, WAIT_NEIGHBOR, WAIT_NEIGHBOR_WEIGHT , 
      WAIT_WRITE, 
      FINISH_TASK} sssp_state_t;
typedef enum logic[1:0] {IDLE, UNDO_LOG, AWADDR, BVALID
      } write_state_t;


task_t task_rdata, task_wdata; 
assign {task_rdata.args, task_rdata.ttype, task_rdata.object, task_rdata.ts} = task_in; 

assign task_out_V_TDATA = 
      {task_wdata.args, task_wdata.ttype, task_wdata.object, task_wdata.ts}; 

logic clk, rstn;
assign clk = ap_clk;
assign rstn = ap_rst_n;

sssp_state_t state, state_next;
write_state_t write_state, write_state_next;
logic [31:0] virtex_id;
logic [31:0] fScore;
logic [31:0] gScore;
logic [31:0] parent;
logic [31:0] edge_offset_start, edge_offset_start_next;
logic [31:0] edge_offset_end, edge_offset_end_next;

logic [31:0] neighbor, neighbor_next;

logic [63:0] base_edge_offset;
logic [63:0] base_neighbors;
logic [63:0] base_data;
logic [31:0] target_node;

logic [2:0] terminate_tile_id; 

assign ap_done = (state == FINISH_TASK);
assign ap_idle = (state == NEXT_TASK);
assign ap_ready = (state == NEXT_TASK);

assign m_axi_l1_V_RREADY = ( 
                     (state == WAIT_BASE_OFFSET) |
                     (state == WAIT_BASE_NEIGHBORS) |
                     (state == WAIT_BASE_DATA) |
                     (state == WAIT_TARGET) |
                     (state == WAIT_PARENT) |
                     (state == WAIT_EDGE_OFFSET) |
                     (state == WAIT_NEIGHBOR) |
                     (state == WAIT_NEIGHBOR_WEIGHT & task_out_V_TREADY) );


logic [31:0] old_dist;
always_ff @(posedge clk) begin
   if ((state == WAIT_PARENT) & (m_axi_l1_V_RVALID)) begin
      old_dist <= m_axi_l1_V_RDATA;
   end
end

logic wr_begin;

logic initialized;

always_ff @(posedge clk) begin
   if (!rstn) begin
      initialized <= 1'b0;
   end else if (state == READ_BASE_OFFSET) begin
      initialized <= 1'b1;
   end
end

always_ff @(posedge clk) begin
   if (state == NEXT_TASK & ap_start) begin
      virtex_id <= task_rdata.object; 
      gScore <= task_rdata.ts;
      fScore <= task_rdata.args[31:0]; 
      parent <= task_rdata.args[63:32];
   end
end

always_ff@(posedge clk) begin
   if (state == NEXT_TASK & ap_start) begin
      terminate_tile_id <= 0;
   end else if (state == CHECK_TARGET & task_out_V_TVALID & task_out_V_TREADY) begin
      terminate_tile_id <= terminate_tile_id + 1;
   end
end

assign ap_state = state;

always_comb begin
   m_axi_l1_V_ARLEN   = 0; // 1 beat
   m_axi_l1_V_ARSIZE  = 3'b010; // 32 bits
   m_axi_l1_V_ARVALID = 1'b0;
   m_axi_l1_V_ARADDR  = 64'h0;

   task_out_V_TVALID = 1'b0;
   task_wdata  = 'x;
   
   wr_begin = 1'b0;

   edge_offset_start_next = edge_offset_start;
   edge_offset_end_next = edge_offset_end;
   state_next = state;

   neighbor_next = neighbor;

   case(state)
      NEXT_TASK: begin
         if (ap_start) begin
            state_next = initialized ? READ_PARENT : READ_BASE_OFFSET;
         end
      end
      READ_BASE_OFFSET: begin
         m_axi_l1_V_ARADDR = 3 << 2;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = WAIT_BASE_OFFSET;
         end
      end
      WAIT_BASE_OFFSET: begin
         if (m_axi_l1_V_RVALID) begin
            state_next = READ_BASE_NEIGHBORS;  
         end
      end
      READ_BASE_NEIGHBORS: begin
         m_axi_l1_V_ARADDR = 4 << 2;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = WAIT_BASE_NEIGHBORS;
         end
      end
      WAIT_BASE_NEIGHBORS: begin
         if (m_axi_l1_V_RVALID) begin
            state_next = READ_BASE_DATA;
         end
      end
      READ_BASE_DATA: begin
         m_axi_l1_V_ARADDR = 5 << 2;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = WAIT_BASE_DATA;
         end
      end
      WAIT_BASE_DATA: begin
         if (m_axi_l1_V_RVALID) begin
            state_next = READ_TARGET;
         end
      end
      READ_TARGET: begin
         m_axi_l1_V_ARADDR = 8 << 2;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = WAIT_TARGET;
         end
      end
      WAIT_TARGET: begin
         if (m_axi_l1_V_RVALID) begin
            state_next = READ_PARENT;
         end
      end
      READ_PARENT: begin
         m_axi_l1_V_ARADDR = base_data + virtex_id * 4;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next =  WAIT_PARENT;
         end
      end
      WAIT_PARENT: begin
         if (m_axi_l1_V_RVALID) begin
            if( (NON_SPEC & ( gScore < m_axi_l1_V_RDATA)) |
                (!NON_SPEC &  (m_axi_l1_V_RDATA == '1) ) ) begin 
               state_next = CHECK_TARGET; // can write dist in parallel
               wr_begin = 1'b1;
            end else begin
               state_next = FINISH_TASK;
            end
         end
      end
      CHECK_TARGET: begin
         if (target_node == virtex_id) begin
            // Enq a terminate task to each tile in the system
            // After a terminate tasks commits, CQ will not send 
            // any higher ts tasks to cores, immediately marking them finished
            task_wdata.ttype = TASK_TYPE_TERMINATE;
            task_wdata.object = terminate_tile_id << 4;
            task_wdata.args = 0; // vid
            task_wdata.ts = gScore;
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               if (terminate_tile_id == N_TILES -1) begin
                  state_next = WAIT_WRITE;
               end else begin
                  // increment terminate_tile_id and enq next task
               end
            end
         end else begin
            state_next = READ_EDGE_OFFSET;
         end
      end
      READ_EDGE_OFFSET: begin
         m_axi_l1_V_ARADDR = base_edge_offset + virtex_id * 4;
         m_axi_l1_V_ARVALID = 1'b1;
         m_axi_l1_V_ARLEN = 1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = WAIT_EDGE_OFFSET;
         end
      end
      WAIT_EDGE_OFFSET: begin
         if (m_axi_l1_V_RVALID) begin
            if (m_axi_l1_V_RLAST) begin
               edge_offset_end_next = m_axi_l1_V_RDATA;
               state_next = READ_NEIGHBORS;
            end else begin
               edge_offset_start_next = m_axi_l1_V_RDATA;
            end
         end
      end
      READ_NEIGHBORS: begin
         if (edge_offset_start == edge_offset_end) begin
            state_next = WAIT_WRITE;
         end else begin
            m_axi_l1_V_ARADDR = base_neighbors + edge_offset_start * 8 ;
            m_axi_l1_V_ARVALID = 1'b1;
            m_axi_l1_V_ARLEN = (edge_offset_end - edge_offset_start) *2 - 1;
            if (m_axi_l1_V_ARREADY) begin
               state_next = WAIT_NEIGHBOR;
            end
         end
      end
      WAIT_NEIGHBOR: begin
         if (m_axi_l1_V_RVALID) begin
            neighbor_next = m_axi_l1_V_RDATA;
            state_next = WAIT_NEIGHBOR_WEIGHT;
         end
      end

      WAIT_NEIGHBOR_WEIGHT: begin
         if (m_axi_l1_V_RVALID) begin
            task_wdata.ttype = 1;
            task_wdata.object = neighbor; // vid
            task_wdata.args[63:32] = virtex_id; // vid
            task_wdata.args[31: 0] = m_axi_l1_V_RDATA + fScore; //weight
            task_wdata.ts = gScore;
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               if (m_axi_l1_V_RLAST) begin
                  if (write_state == IDLE) begin                     
                     state_next = FINISH_TASK;
                  end else begin
                     state_next = WAIT_WRITE;
                  end
               end else begin
                  state_next = WAIT_NEIGHBOR;
               end
            end
         end
      end
      WAIT_WRITE: begin
         if (write_state == IDLE) begin                     
            state_next = FINISH_TASK;
         end
      end
      FINISH_TASK: begin
         state_next = NEXT_TASK;
      end

   endcase
end

assign m_axi_l1_V_BREADY  = (write_state == BVALID);

assign undo_log_entry_ap_vld = (write_state == UNDO_LOG); 
undo_log_addr_t undo_log_addr;
undo_log_data_t undo_log_data;

assign undo_log_addr = base_data + (virtex_id * 4);
assign undo_log_data = old_dist; 

assign undo_log_entry = {undo_log_data, undo_log_addr};

always_comb begin
   m_axi_l1_V_AWLEN   = 0; // 1 beat
   m_axi_l1_V_AWSIZE  = 3'b010; // 32 bits
   m_axi_l1_V_AWVALID = 0;
   m_axi_l1_V_AWADDR  = 0;
   m_axi_l1_V_WVALID  = 1'b0;
   m_axi_l1_V_WSTRB   = 4'b1111; 
   m_axi_l1_V_WLAST   = 1'b0;
   m_axi_l1_V_WDATA   = 'x;
   
   write_state_next = write_state;
   
   case (write_state)
      IDLE: begin
         if (wr_begin) begin
            write_state_next = UNDO_LOG;
         end
      end
      UNDO_LOG: begin
         if (undo_log_entry_ap_rdy) begin
            write_state_next = AWADDR;
         end
      end
      AWADDR: begin
         m_axi_l1_V_AWVALID = 1'b1;
         m_axi_l1_V_AWADDR  = base_data + virtex_id * 4;
         m_axi_l1_V_WDATA   = gScore;
         m_axi_l1_V_WVALID  = 1'b1;
         m_axi_l1_V_WLAST   = 1'b1;
         if (m_axi_l1_V_AWREADY & m_axi_l1_V_WREADY) begin
            write_state_next = BVALID;
         end            
      end
      BVALID: begin
         if (m_axi_l1_V_BVALID) begin               
            write_state_next = IDLE;
         end
      end

   endcase  
end


always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= NEXT_TASK;
      write_state <= IDLE;
      edge_offset_start <= 'x;
      edge_offset_end <= 'x;
      neighbor <= 'x;
   end else begin
      state <= state_next;
      edge_offset_start <= edge_offset_start_next;
      edge_offset_end <= edge_offset_end_next;
      write_state <= write_state_next;
      neighbor <= neighbor_next;
   end
end


always_ff @(posedge clk) begin
   if (m_axi_l1_V_RVALID) begin
      case (state)
         WAIT_BASE_OFFSET: base_edge_offset <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
         WAIT_BASE_NEIGHBORS: base_neighbors <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
         WAIT_BASE_DATA: base_data <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
         WAIT_TARGET: target_node <= m_axi_l1_V_RDATA;
      endcase
   end
end



endmodule
