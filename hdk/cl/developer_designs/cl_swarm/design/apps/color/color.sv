`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

module color
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
   input                m_axi_l1_V_BID,

   output logic [31:0]  ap_state
);

localparam ENQUEUER_TASK = 0;
localparam CALC_TASK = 1;
localparam COLOR_TASK = 2;
localparam RECEIVE_TASK = 3;

localparam VID_BITMAP_OFFSET = 0;
localparam VID_COUNTER_OFFSET = 4;

typedef enum logic[5:0] {
      NEXT_TASK,
      READ_HEADERS, WAIT_HEADERS,
      DISPATCH_TASK, 
      // 4
      ENQUEUER_ENQ_CONTINUATION,
      ENQUEUER_ENQ_NODE,
      // 6
      CALC_READ_OFFSET, CALC_WAIT_OFFSET,
      CALC_READ_NEIGHBOR, CALC_WAIT_NEIGHBOR, 
      CALC_READ_NEIGHBOR_OFFSET, CALC_WAIT_NEIGHBOR_OFFSET,
      CALC_INC_IN_DEGREE,
      CALC_READ_JOIN_COUNTER,
      CALC_WAIT_JOIN_COUNTER,
      CALC_WRITE_JOIN_COUNTER,
      CALC_ENQ_COLOR,
      // 17
      COLOR_READ_BITMAP, COLOR_WAIT_BITMAP,
      COLOR_CALC_COLOR, // and write color
      COLOR_READ_OFFSET, COLOR_WAIT_OFFSET,
      COLOR_ENQ_CONTINUATION,
      COLOR_READ_NEIGHBOR, COLOR_WAIT_NEIGHBOR,
      COLOR_READ_NEIGHBOR_OFFSET, COLOR_WAIT_NEIGHBOR_OFFSET,
      COLOR_ENQ_RECEIVE,
      
      // 28
      RECEIVE_READ_SCRATCH, RECEIVE_WAIT_SCRATCH, // bitmap, counter 
      RECEIVE_WRITE_BITMAP,
      RECEIVE_WRITE_COUNTER, // if (scratch[vid] was not already set
      RECEIVE_ENQ_CALC,
      FINISH_TASK
   } color_state_t;


task_t task_rdata, task_wdata; 
assign {task_rdata.args, task_rdata.ttype, task_rdata.hint, task_rdata.ts} = task_in; 

assign task_out_V_TDATA = 
      {task_wdata.args, task_wdata.ttype, task_wdata.hint, task_wdata.ts}; 

logic clk, rstn;
assign clk = ap_clk;
assign rstn = ap_rst_n;

undo_log_addr_t undo_log_addr;
undo_log_data_t undo_log_data;

color_state_t state, state_next;
task_t cur_task;

assign ap_state = state;

// next expected read word in a burst read
logic [3:0] word_id;
always_ff @(posedge clk) begin
   if (!rstn) begin
      word_id <= 0;
   end else begin
      if (m_axi_l1_V_ARVALID) begin
         word_id <= 0;
      end else if (m_axi_l1_V_RVALID) begin
         word_id <= word_id + 1;
      end
   end
end

// headers
logic [31:0] numV, numE;
logic [31:0] base_edge_offset;
logic [31:0] base_neighbors;
logic [31:0] base_color;
logic [31:0] base_scratch;
logic [6:0]  enq_limit;

logic [31:0] eo_begin, eo_end;

// vertex data
logic [31:0] bitmap;
logic [31:0] join_counter;

logic [31:0] edge_dest;
logic [6:0] neighbor_offset;
logic [31:0] neighbor_degree;

logic [31:0] degree;
assign degree = eo_end - eo_begin;

logic [31:0] cur_arg_0;

logic [4:0] bitmap_color;
logic [5:0] assign_color;

lowbit #(
   .OUT_WIDTH(5),
   .IN_WIDTH(32)
) FINISH_TASK_SELECT (
   .in(~bitmap),
   .out(bitmap_color)
);

always_comb begin
   if (bitmap == 0) begin
      assign_color = 0;
   end else if (bitmap == '1) begin
      assign_color = 32;
   end else begin
      assign_color = bitmap_color;
   end
end

always_ff @(posedge clk) begin
   if (m_axi_l1_V_RVALID) begin
      case (state) 
         WAIT_HEADERS: begin
            case (word_id)
               1: numV <= m_axi_l1_V_RDATA;
               2: numE <= m_axi_l1_V_RDATA;
               3: base_edge_offset <= {m_axi_l1_V_RDATA[30:0], 2'b00};
               4: base_neighbors <= {m_axi_l1_V_RDATA[30:0], 2'b00};
               5: base_color <= {m_axi_l1_V_RDATA[30:0], 2'b00};
               6: base_scratch <= {m_axi_l1_V_RDATA[30:0], 2'b00};
               8: enq_limit <= m_axi_l1_V_RDATA[6:0];
            endcase
         end
         CALC_WAIT_OFFSET,
         COLOR_WAIT_OFFSET: begin
            case (word_id)
               0: eo_begin <= m_axi_l1_V_RDATA; 
               1: eo_end <= m_axi_l1_V_RDATA;
            endcase
         end
         CALC_WAIT_NEIGHBOR, 
         COLOR_WAIT_NEIGHBOR : begin
            edge_dest <= m_axi_l1_V_RDATA;
         end
         CALC_WAIT_NEIGHBOR_OFFSET, 
         COLOR_WAIT_NEIGHBOR_OFFSET : begin
            case (word_id)
               0: neighbor_degree <= m_axi_l1_V_RDATA;  // eo_begin
               1: neighbor_degree <= (m_axi_l1_V_RDATA - neighbor_degree); // eo_end
            endcase
         end
         CALC_WAIT_JOIN_COUNTER : begin
            join_counter <= join_counter + m_axi_l1_V_RDATA;
         end
         COLOR_WAIT_BITMAP : begin
            bitmap <= m_axi_l1_V_RDATA;
         end
         RECEIVE_WAIT_SCRATCH: begin
            case (word_id)
               0: bitmap <= m_axi_l1_V_RDATA;
               1: join_counter <= m_axi_l1_V_RDATA;
            endcase
         end
      endcase
   end else if (m_axi_l1_V_AWVALID & m_axi_l1_V_AWREADY) begin
      case (state) 
         CALC_WRITE_JOIN_COUNTER: join_counter <= m_axi_l1_V_WDATA;
         RECEIVE_WRITE_COUNTER: join_counter <= m_axi_l1_V_WDATA;
      endcase
   end else if (state == CALC_READ_OFFSET) begin
      join_counter <= 0;
   end else if (state == CALC_INC_IN_DEGREE) begin
      if ( (neighbor_degree > degree) ||
           ((neighbor_degree == degree) & (edge_dest < cur_task.hint))) begin
         join_counter <= join_counter + 1;
      end
   end
end

always_ff @(posedge clk) begin
   if (state == DISPATCH_TASK) begin
      if (cur_task.ttype == ENQUEUER_TASK) begin
         neighbor_offset <= cur_arg_0;
      end else if (cur_task.ttype == COLOR_TASK)  begin
         neighbor_offset <= cur_arg_0;
      end else begin
         neighbor_offset <= 0;
      end
   end else if (state == ENQUEUER_ENQ_NODE) begin
      if (task_out_V_TVALID & task_out_V_TREADY) begin
         neighbor_offset <= neighbor_offset + 1;
      end
   end else if (state ==  CALC_INC_IN_DEGREE
      && state_next == CALC_READ_NEIGHBOR) begin
      neighbor_offset <= neighbor_offset + 1;
   end else if (state == COLOR_ENQ_RECEIVE 
      && state_next == COLOR_READ_NEIGHBOR) begin
      neighbor_offset <= neighbor_offset + 1;
   end
end


assign ap_done = (state == FINISH_TASK);
assign ap_idle = (state == NEXT_TASK);
assign ap_ready = (state == NEXT_TASK);

assign m_axi_l1_V_RREADY = ( 
                     (state == WAIT_HEADERS) 
                   | (state == CALC_WAIT_OFFSET) 
                   | (state == CALC_WAIT_NEIGHBOR) 
                   | (state == CALC_WAIT_NEIGHBOR_OFFSET) 
                   | (state == CALC_WAIT_JOIN_COUNTER) 
                   | (state == COLOR_WAIT_BITMAP) 
                   | (state == COLOR_WAIT_OFFSET) 
                   | (state == COLOR_WAIT_NEIGHBOR) 
                   | (state == COLOR_WAIT_NEIGHBOR_OFFSET) 
                   | (state == RECEIVE_WAIT_SCRATCH) 
                     );

logic initialized;

always_ff @(posedge clk) begin
   if (!rstn) begin
      initialized <= 1'b0;
   end else if (state == DISPATCH_TASK) begin
      initialized <= 1'b1;
   end
end

always_ff @(posedge clk) begin
   if (state == NEXT_TASK & ap_start) begin
      cur_task <= task_rdata;
   end
end

assign m_axi_l1_V_ARSIZE  = 3'b010; // 32 bits
assign m_axi_l1_V_AWSIZE  = 3'b010; // 32 bits
assign m_axi_l1_V_WSTRB   = 4'b1111; 

logic [31:0] cur_vertex_addr;

assign cur_arg_0 = cur_task.args[31:0];
assign undo_log_entry_ap_vld = 1'b0;

logic [31:0] enq_start, enq_end;
assign enq_start = cur_arg_0;
logic [31:0] enq_last; 

always_comb begin
   case (state)
      ENQUEUER_ENQ_CONTINUATION, 
      ENQUEUER_ENQ_NODE : enq_last = numV;
      default: enq_last = degree;
   endcase
end
always_comb begin
   if (enq_start + enq_limit > enq_last) begin
      enq_end = numV;
   end else begin
      enq_end = enq_start + enq_limit;
   end
end

always_comb begin
   m_axi_l1_V_ARLEN   = 0; // 1 beat
   m_axi_l1_V_ARVALID = 1'b0;
   m_axi_l1_V_ARADDR  = 64'h0;

   task_out_V_TVALID = 1'b0;
   task_wdata  = 'x;

   undo_log_addr = 'x;
   undo_log_data = 'x;
   
   m_axi_l1_V_AWVALID = 0;
   m_axi_l1_V_WVALID = 0;
   m_axi_l1_V_AWADDR  = 0;
   m_axi_l1_V_AWLEN   = 0; // 1 beat
   m_axi_l1_V_WDATA   = 'x;
   m_axi_l1_V_WLAST   = 0;
   
   state_next = state;

   case(state)
      NEXT_TASK: begin
         if (ap_start) begin
            state_next = initialized ? DISPATCH_TASK : READ_HEADERS;
         end
      end
      READ_HEADERS: begin
         m_axi_l1_V_ARADDR = 0;
         m_axi_l1_V_ARVALID = 1'b1;
         m_axi_l1_V_ARLEN = 8;
         if (m_axi_l1_V_ARREADY) begin
            state_next = WAIT_HEADERS;
         end
      end
      WAIT_HEADERS: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = DISPATCH_TASK;  
         end
      end
      DISPATCH_TASK: begin
         case (cur_task.ttype)
            0: state_next = ENQUEUER_ENQ_CONTINUATION;
            1: state_next = CALC_READ_OFFSET;
            2: state_next = COLOR_READ_BITMAP;
            3: state_next = RECEIVE_READ_SCRATCH;
            default: state_next = FINISH_TASK;
         endcase
      end

      ENQUEUER_ENQ_CONTINUATION: begin
         if (enq_end < numV) begin
            task_wdata.ttype = ENQUEUER_TASK;
            task_wdata.hint = cur_arg_0 << 4; // random
            task_wdata.args = enq_end;
            task_wdata.ts = 0; 
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               state_next = ENQUEUER_ENQ_NODE;
            end 
         end else begin
            state_next = ENQUEUER_ENQ_NODE;
         end
      end
      ENQUEUER_ENQ_NODE: begin
         if (neighbor_offset < enq_end) begin
            task_wdata.ttype = CALC_TASK;
            task_wdata.hint = neighbor_offset;
            task_wdata.args = 'x;
            task_wdata.ts = 0; 
            task_out_V_TVALID = 1'b1;
         end else begin
            state_next = FINISH_TASK;
         end
      end


      CALC_READ_OFFSET: begin
         m_axi_l1_V_ARADDR = base_edge_offset + (cur_task.hint << 2);
         m_axi_l1_V_ARLEN = 1;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = CALC_WAIT_OFFSET;
         end
      end
      CALC_WAIT_OFFSET: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = CALC_READ_NEIGHBOR;
         end
      end
      CALC_READ_NEIGHBOR: begin
         if (eo_begin + neighbor_offset == eo_end) begin
            state_next = CALC_READ_JOIN_COUNTER;
         end else begin
            m_axi_l1_V_ARADDR = base_neighbors + ( (eo_begin + neighbor_offset) << 2);
            m_axi_l1_V_ARLEN = 0;
            m_axi_l1_V_ARVALID = 1'b1;
            if (m_axi_l1_V_ARREADY) begin
               state_next = CALC_WAIT_NEIGHBOR;
            end
         end
      end
      CALC_WAIT_NEIGHBOR: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = CALC_READ_NEIGHBOR_OFFSET;
         end
      end
      CALC_READ_NEIGHBOR_OFFSET: begin
         m_axi_l1_V_ARADDR = base_edge_offset + (edge_dest << 2);
         m_axi_l1_V_ARLEN = 1;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = CALC_WAIT_NEIGHBOR_OFFSET;
         end
      end
      CALC_WAIT_NEIGHBOR_OFFSET: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = CALC_INC_IN_DEGREE;
         end
      end
      CALC_INC_IN_DEGREE: begin
         state_next = CALC_READ_NEIGHBOR;
      end
      CALC_READ_JOIN_COUNTER: begin
         m_axi_l1_V_ARADDR = (base_scratch + (cur_task.hint << 3)) | VID_COUNTER_OFFSET;
         m_axi_l1_V_ARLEN = 0;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = CALC_WAIT_JOIN_COUNTER;
         end
      end
      CALC_WAIT_JOIN_COUNTER: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = CALC_WRITE_JOIN_COUNTER;
         end
      end
      CALC_WRITE_JOIN_COUNTER: begin
         m_axi_l1_V_AWADDR = (base_scratch + (cur_task.hint << 3)) | VID_COUNTER_OFFSET;
         m_axi_l1_V_WDATA = join_counter;
         m_axi_l1_V_AWVALID = 1'b1;
         m_axi_l1_V_WVALID = 1'b1;
         m_axi_l1_V_WLAST = 1'b1;
         if (m_axi_l1_V_AWREADY) begin
            state_next = (join_counter ==0) ? CALC_ENQ_COLOR : FINISH_TASK;
         end
      end
      CALC_ENQ_COLOR: begin
         task_wdata.ttype = COLOR_TASK;
         task_wdata.hint = cur_task.hint;
         task_wdata.args = 0;
         task_wdata.ts = 0; 
         task_out_V_TVALID = 1'b1;
         if (task_out_V_TREADY) begin
            state_next = FINISH_TASK;
         end 
      end


      COLOR_READ_BITMAP: begin
         m_axi_l1_V_ARADDR = (base_scratch + (cur_task.hint << 3)) | VID_BITMAP_OFFSET;
         m_axi_l1_V_ARLEN = 0;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = COLOR_WAIT_BITMAP;
         end
      end
      COLOR_WAIT_BITMAP: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = COLOR_CALC_COLOR;
         end
      end
      COLOR_CALC_COLOR: begin
         m_axi_l1_V_AWADDR = (base_color + (cur_task.hint << 2));
         m_axi_l1_V_WDATA = assign_color;
         m_axi_l1_V_AWVALID = 1'b1;
         m_axi_l1_V_WVALID = 1'b1;
         m_axi_l1_V_WLAST = 1'b1;
         if (m_axi_l1_V_AWREADY) begin
            state_next = COLOR_READ_OFFSET;
         end
      end
      COLOR_READ_OFFSET: begin
         m_axi_l1_V_ARADDR = base_edge_offset + (cur_task.hint << 2);
         m_axi_l1_V_ARLEN = 1;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = COLOR_WAIT_OFFSET;
         end
      end
      COLOR_WAIT_OFFSET: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = COLOR_ENQ_CONTINUATION;
         end
      end
      COLOR_ENQ_CONTINUATION: begin
         if (enq_end < degree) begin
            task_wdata.ttype = COLOR_TASK;
            task_wdata.hint = cur_task.hint;
            task_wdata.args = enq_end;
            task_wdata.ts = 0; 
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               state_next = COLOR_READ_NEIGHBOR;
            end 
         end else begin
            state_next = COLOR_READ_NEIGHBOR;
         end
      end
      COLOR_READ_NEIGHBOR: begin
         if (eo_begin + neighbor_offset == eo_end) begin
            state_next = FINISH_TASK;
         end else begin
            m_axi_l1_V_ARADDR = base_neighbors + ( (eo_begin + neighbor_offset) << 2);
            m_axi_l1_V_ARLEN = 0;
            m_axi_l1_V_ARVALID = 1'b1;
            if (m_axi_l1_V_ARREADY) begin
               state_next = COLOR_WAIT_NEIGHBOR;
            end
         end
      end
      COLOR_WAIT_NEIGHBOR: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = COLOR_READ_NEIGHBOR_OFFSET;
         end
      end
      COLOR_READ_NEIGHBOR_OFFSET: begin
         m_axi_l1_V_ARADDR = base_edge_offset + (edge_dest << 2);
         m_axi_l1_V_ARLEN = 1;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = COLOR_WAIT_NEIGHBOR_OFFSET;
         end
      end
      COLOR_WAIT_NEIGHBOR_OFFSET: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = COLOR_ENQ_RECEIVE;
         end
      end
      COLOR_ENQ_RECEIVE: begin
         if( (neighbor_degree < degree )  ||
             ((neighbor_degree == degree) & (edge_dest > cur_task.hint))) begin
            task_wdata.ttype = RECEIVE_TASK;
            task_wdata.hint = edge_dest;
            task_wdata.args = assign_color;
            task_wdata.ts = 0; 
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               state_next = COLOR_READ_NEIGHBOR;
            end 
         end else begin
            state_next = COLOR_READ_NEIGHBOR;
         end
      end
      
      
      RECEIVE_READ_SCRATCH: begin
         m_axi_l1_V_ARADDR = (base_scratch + (cur_task.hint << 3)) ;
         m_axi_l1_V_ARLEN = 1;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = RECEIVE_WAIT_SCRATCH;
         end
      end
      RECEIVE_WAIT_SCRATCH: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = RECEIVE_WRITE_BITMAP;
         end
      end
      RECEIVE_WRITE_BITMAP: begin
         m_axi_l1_V_AWADDR = (base_scratch + (cur_task.hint << 3));
         m_axi_l1_V_WDATA = bitmap_color | (1<<cur_arg_0);
         m_axi_l1_V_AWLEN = 1; 
         m_axi_l1_V_AWVALID = 1'b1;
         m_axi_l1_V_WVALID = 1'b1;
         if (m_axi_l1_V_AWREADY) begin
            state_next = RECEIVE_WRITE_COUNTER;
         end
      end
      RECEIVE_WRITE_COUNTER: begin
         m_axi_l1_V_WDATA = join_counter - 1;
         m_axi_l1_V_WVALID = 1;
         m_axi_l1_V_WLAST = 1;
         if (m_axi_l1_V_WREADY) begin
            state_next = (join_counter == 1) ? RECEIVE_ENQ_CALC : FINISH_TASK;
         end
      end
      RECEIVE_ENQ_CALC: begin
         task_wdata.ttype = COLOR_TASK;
         task_wdata.hint = cur_task.hint;
         task_wdata.args = 0;
         task_wdata.ts = 0; 
         task_out_V_TVALID = 1'b1;
         if (task_out_V_TREADY) begin
            state_next = FINISH_TASK;
         end 
      end





      FINISH_TASK: begin
         state_next = NEXT_TASK;
      end
   endcase
end

assign m_axi_l1_V_BREADY  = 1'b1;
assign undo_log_entry = {undo_log_data, undo_log_addr};


always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= NEXT_TASK;
   end else begin
      state <= state_next;
   end
end




endmodule
