`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

module des_enqueuer
#(
   parameter CORE_ID=0,
   parameter TILE_ID=0
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
   input                m_axi_l1_V_BID    
);

typedef enum logic[3:0] {
      NEXT_TASK,
      READ_BASE_OFFSET, WAIT_BASE_OFFSET,
      READ_BASE_NEIGHBORS, WAIT_BASE_NEIGHBORS,
      READ_EDGE_OFFSET, WAIT_EDGE_OFFSET,
      READ_NEIGHBORS, WAIT_NEIGHBOR,  
      ENQ_NEXT_ENQUEUER, 
      FINISH_TASK} des_state_t;


task_t task_rdata, task_wdata; 
assign {task_rdata.args, task_rdata.ttype, task_rdata.hint, task_rdata.ts} = task_in; 

assign task_out_V_TDATA = 
      {task_wdata.args, task_wdata.ttype, task_wdata.hint, task_wdata.ts}; 

logic clk, rstn;
assign clk = ap_clk;
assign rstn = ap_rst_n;

des_state_t state, state_next;
logic [31:0] virtex_id;
logic_val_t  logic_val;

ts_t         next_enq_ts;


logic [15:0] enqueuer_start;

logic [31:0] edge_offset_start;
logic [31:0] edge_offset_end;

logic [31:0] neighbor, neighbor_next;

logic [31:0] base_edge_offset;
logic [31:0] base_neighbors;

always_ff @(posedge clk) begin
   if ((state == WAIT_NEIGHBOR) & m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
      next_enq_ts <= m_axi_l1_V_RDATA[23:0];
   end
end
assign ap_done = (state == FINISH_TASK);
assign ap_idle = (state == NEXT_TASK);
assign ap_ready = (state == NEXT_TASK);

assign m_axi_l1_V_RREADY = ( 
                     (state == WAIT_BASE_OFFSET) |
                     (state == WAIT_BASE_NEIGHBORS) |
                     (state == WAIT_EDGE_OFFSET) |
                     (state == WAIT_NEIGHBOR & task_out_V_TREADY) );

logic initialized;

always_ff @(posedge clk) begin
   if (!rstn) begin
      initialized <= 1'b0;
   end else if (state == READ_BASE_OFFSET) begin
      initialized <= 1'b1;
   end
end

always_ff @(posedge clk) begin
   if (state == NEXT_TASK) begin
      virtex_id <= task_rdata.hint;
      enqueuer_start <= task_rdata.args[15:0];
   end
   if ((state == WAIT_EDGE_OFFSET) & m_axi_l1_V_RVALID) begin
      if (m_axi_l1_V_RLAST) begin
         edge_offset_end <= m_axi_l1_V_RDATA;
      end else begin
         edge_offset_start <= m_axi_l1_V_RDATA + enqueuer_start;
      end
   end
end



always_comb begin
   m_axi_l1_V_ARLEN   = 0; // 1 beat
   m_axi_l1_V_ARSIZE  = 3'b010; // 32 bits
   m_axi_l1_V_ARVALID = 1'b0;
   m_axi_l1_V_ARADDR  = 64'h0;

   task_out_V_TVALID = 1'b0;
   task_wdata  = 'x;

   state_next = state;

   neighbor_next = neighbor;

   case(state)
      NEXT_TASK: begin
         if (ap_start) begin
            state_next = initialized ? READ_EDGE_OFFSET : READ_BASE_OFFSET;
         end
      end
      READ_BASE_OFFSET: begin
         m_axi_l1_V_ARADDR = 8 << 2;
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
         m_axi_l1_V_ARADDR = 9 << 2;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = WAIT_BASE_NEIGHBORS;
         end
      end
      WAIT_BASE_NEIGHBORS: begin
         if (m_axi_l1_V_RVALID) begin
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
               state_next = READ_NEIGHBORS;
            end
         end
      end
      READ_NEIGHBORS: begin
         if (edge_offset_start == edge_offset_end) begin
            state_next = FINISH_TASK;
         end else begin
            m_axi_l1_V_ARADDR = base_neighbors + edge_offset_start * 4 ;
            m_axi_l1_V_ARVALID = 1'b1;
            m_axi_l1_V_ARLEN = (edge_offset_end - edge_offset_start) - 1;
            if (edge_offset_end > edge_offset_start + 7) begin
               m_axi_l1_V_ARLEN = 6;
            end else begin
               m_axi_l1_V_ARLEN = (edge_offset_end - edge_offset_start) - 1;
            end
            if (m_axi_l1_V_ARREADY) begin
               state_next = WAIT_NEIGHBOR;
            end
         end
      end
      WAIT_NEIGHBOR: begin
         if (m_axi_l1_V_RVALID) begin
            task_wdata.ttype = 0;
            task_wdata.ts  = m_axi_l1_V_RDATA[23:0]; 
            task_wdata.hint = virtex_id; // vid
            task_wdata.args = {13'b0, 1'b0 /*port*/, m_axi_l1_V_RDATA[25:24]}; 
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               if (m_axi_l1_V_RLAST) begin
                  state_next = ENQ_NEXT_ENQUEUER;
               end else begin
                  state_next = WAIT_NEIGHBOR;
               end
            end
         end
      end
      ENQ_NEXT_ENQUEUER: begin
         if (edge_offset_end > edge_offset_start + 7) begin
            task_wdata.ttype = 1;
            task_wdata.ts  = next_enq_ts; 
            task_wdata.hint = virtex_id; // vid
            task_wdata.args[15:0] = enqueuer_start + 7;  
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               state_next = FINISH_TASK;
            end
         end else begin
            state_next = FINISH_TASK;
         end
      end
      FINISH_TASK: begin
         state_next =  NEXT_TASK;
      end
   endcase
end

assign m_axi_l1_V_BREADY = 1'b1;

assign undo_log_entry_ap_vld = 1'b0; 
assign undo_log_entry = 'x;

always_comb begin
   m_axi_l1_V_AWLEN   = 0; // 1 beat
   m_axi_l1_V_AWSIZE  = 3'b010; // 32 bits
   m_axi_l1_V_AWVALID = 0;
   m_axi_l1_V_AWADDR  = 0;
   m_axi_l1_V_WVALID  = 1'b0;
   m_axi_l1_V_WSTRB   = 4'b1111; 
   m_axi_l1_V_WLAST   = 1'b0;
   m_axi_l1_V_WDATA   = 'x;
end

always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= NEXT_TASK;
   end else begin
      state <= state_next;
      neighbor <= neighbor_next;
   end
end

always_ff @(posedge clk) begin
   if (m_axi_l1_V_RVALID) begin
      case (state)
         WAIT_BASE_OFFSET: base_edge_offset <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
         WAIT_BASE_NEIGHBORS: base_neighbors <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
      endcase
   end
end


endmodule

