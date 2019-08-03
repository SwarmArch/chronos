`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

typedef struct packed {
   logic [31:0] eo_begin;
   logic [15:0] neighbor_degrees_pending;
   logic [15:0] neighbor_colors_pending;
   logic [31:0] scratch;
   logic [15:0] degree;
   logic [15:0] color;
} color_data_t;

parameter COLOR_ENQ_TASK = 0;
      // 31:0 enq_start
parameter COLOR_SEND_DEGREE_TASK = 1;
      // 15:0 enq_start
parameter COLOR_RECEIVE_DEGREE_TASK = 2;
      // [15:0] enq_start
      // [31:16] neighbor degree
      // [63:32] neighbor id
parameter COLOR_RECEIVE_COLOR_TASK = 3;
      // [15:0] enq_start
      // [63:32] neighbor id
      // [79:64] neighbor color

module color_rw
#(
   parameter TILE_ID=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input object_t          in_data,
   input cq_slice_slot_t   in_cq_slot,
   
   output logic            wvalid,
   output logic [31:0]     waddr,
   output object_t         wdata,

   output logic            out_valid,
   output task_t           out_task,

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   reg_bus_t               reg_bus

);

// headers
logic [31:0] numV, numE;
logic [31:0] base_neighbors;
logic [31:0] base_data;
logic [6:0]  enq_limit;

color_data_t read_word, write_word;
assign read_word = in_data;
assign wdata = write_word;

assign task_in_ready = sched_task_valid & sched_task_ready;
assign sched_task_valid = task_in_valid;

logic [31:0] neighbor_id; 
logic [15:0] neighbor_degree;
logic [15:0] enq_start;
assign neighbor_id = in_task.args[63:32];
assign enq_start = (in_task.ttype == COLOR_ENQ_TASK) ? in_task.args[31:0] : in_task.args[15:0];
assign neighbor_degree = in_task.args[31:16];

logic [4:0] assign_color, bitmap_color;
logic [31:0] bitmap;
assign bitmap = write_word.scratch;
lowbit #(
   .OUT_WIDTH(5),
   .IN_WIDTH(32)
) COLOR_SELECT (
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
always_comb begin 
   wvalid = 0;
   waddr = base_data + ( in_task.locale << 4) ;
   write_word = read_word;
   out_valid = 1'b0;

   out_task = in_task;

   if (task_in_valid) begin
      case (in_task.ttype)
         COLOR_ENQ_TASK: begin
            out_valid = 1'b1;
         end
         COLOR_SEND_DEGREE_TASK: begin
            if (enq_start == 0) begin
               //write_word.neighbor_degrees_pending += read_word.degree;
               //wvalid = 1'b1;
            end
            if (read_word.degree == 0) begin
               write_word.color = 0;
               wvalid = 1'b1;
            end else begin
               out_valid = 1'b1;
               out_task.args[15:0] = enq_start;
               out_task.args[31:16] = read_word.degree;
               out_task.args[63:32] = read_word.eo_begin;
            end
         end
         COLOR_RECEIVE_DEGREE_TASK: begin
            wvalid = 1'b1;
            write_word.neighbor_degrees_pending -= 1;
            if ( (neighbor_degree > read_word.degree) || ( 
               (neighbor_degree == read_word.degree) & (neighbor_id < in_task.locale) )) begin
               write_word.neighbor_colors_pending += 1;
            end
            if ((write_word.neighbor_degrees_pending == 0) && (write_word.neighbor_colors_pending==0)) begin
               out_valid = 1'b1;
               out_task.args[63:32] = read_word.eo_begin;
               out_task.args[31:16] = read_word.degree;
               out_task.args[79:64]  = assign_color;
               write_word.color = assign_color;
            end
         end
         COLOR_RECEIVE_COLOR_TASK: begin
            if (enq_start == 0) begin
               if ( (neighbor_degree > read_word.degree) || ( 
                  (neighbor_degree == read_word.degree) & (neighbor_id < in_task.locale) )) begin
                  wvalid = 1'b1;
                  write_word.neighbor_colors_pending -= 1;
                  write_word.scratch |= (1<<in_task.args[68:64]);
                  write_word.color = assign_color;
                  if ( (write_word.neighbor_degrees_pending == 0) && (write_word.neighbor_colors_pending==0)) begin
                     write_word.color = assign_color;
                     out_valid = 1'b1;
                     out_task.args[63:32] = read_word.eo_begin; 
                     out_task.args[31:16] = read_word.degree;
                     out_task.args[79:64]  = assign_color;
                  end
               end
            end else begin
               out_valid = 1'b1;
               out_task.args[63:32] = read_word.eo_begin; 
               out_task.args[31:16] = read_word.degree;
               out_task.args[79:64] = read_word.color;
            end
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
             4 : numV <= reg_bus.wdata;
             8 : numE <= reg_bus.wdata;
            16 : base_neighbors <= {reg_bus.wdata[29:0], 2'b00};
            20 : base_data <= {reg_bus.wdata[29:0], 2'b00};
            36 : enq_limit <= reg_bus.wdata;
         endcase
      end
   end
end

`ifdef XILINX_SIMULATOR
   logic [31:0] cycle;
   always_ff @(posedge clk) begin
      if (!rstn) cycle <=0;
      else cycle <= cycle+1;
   end
   always_ff @(posedge clk) begin
      if (task_in_valid & task_in_ready) begin
         $display("[%5d] [rob-%2d] [rw] [%3d] type:%1d locale:%4d | args: (%4d %4d %4d %4d) | ndp:%4d ncp:%d sc:%4x | eo:%4d d:%4d | out:%1d ",
         cycle, TILE_ID, in_cq_slot,
         in_task.ttype, in_task.locale, 
         in_task.args[15:0], in_task.args[31:16], in_task.args[63:32], in_task.args[79:64],
         read_word.neighbor_degrees_pending, read_word.neighbor_colors_pending, read_word.scratch,
         read_word.eo_begin, read_word.degree, out_valid) ;
      end
   end
`endif
endmodule

module color_worker
#(
   parameter TILE_ID=0,
   parameter SUBTYPE=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input data_t            in_data,
   input byte_t            in_word_id,
   input cq_slice_slot_t   in_cq_slot,

   output cq_slice_slot_t  out_cq_slot,
   
   output logic            arvalid,
   output logic [31:0]     araddr,
   output logic [2:0]      arsize,
   output logic [7:0]      arlen,
   output task_t           resp_task, //each mem resp will create a new task with this parameters
   output subtype_t        resp_subtype,
   output logic            resp_mark_last, // mark the last resp task as last

   output logic            out_valid,
   output task_t           out_task,
   output subtype_t        out_subtype,

   output logic            out_task_is_child, // if 0, out_task is re-enqueued back to a FIFO, else sent to CM

   output logic            sched_task_valid,
   input logic             sched_task_ready,


   reg_bus_t               reg_bus

);

assign sched_task_valid = task_in_valid;
assign task_in_ready = sched_task_ready;
assign out_cq_slot = in_cq_slot;

// headers
logic [31:0] numV, numE;
logic [31:0] base_neighbors;
logic [31:0] base_data;
logic [6:0]  enq_limit;

logic [31:0] enq_start;
assign enq_start = (in_task.ttype == COLOR_ENQ_TASK) ? in_task.args[31:0] : {16'b0, in_task.args[15:0]};
logic [15:0] degree, n_rem_neighbors;
logic [31:0] eo_begin;
logic [15:0] color;
assign degree = in_task.args[31:16];
assign n_rem_neighbors = in_task.args[31:16];
assign color = in_task.args[79:64];
assign eo_begin = in_task.args[63:32];


always_comb begin
   araddr = 'x;
   arsize = 2;
   arlen = 0;
   arvalid = 1'b0;
   out_valid = 1'b0;
   resp_mark_last = 1'b0;
   out_task = in_task;
   out_task_is_child = 1'b1;
   resp_subtype = 1;
   resp_task = in_task;
   
   if (task_in_valid) begin
      case (in_task.ttype) 
         COLOR_ENQ_TASK: begin
            case (SUBTYPE) 
               0: begin
                  araddr = base_neighbors;
                  arvalid = 1'b1;
                  if (enq_start + enq_limit >= numV) begin
                     arlen = (numV - enq_start)-1;
                  end else begin
                     arlen = enq_limit;
                  end
               end
               1: begin
                  out_valid = 1'b1;
                  if (in_word_id == enq_limit) begin
                     out_task.ttype = COLOR_ENQ_TASK;
                     out_task.producer = 1'b1;
                     out_task.locale = enq_start + enq_limit;
                     out_task.args[31:0] = enq_start + enq_limit;
                  end else begin
                     out_task.ttype = COLOR_SEND_DEGREE_TASK;
                     out_task.producer = 1'b1;
                     out_task.locale = enq_start + in_word_id;
                     out_task.args[31:0] = 0; // enq_start
                  end
               end
            endcase
         end
         COLOR_SEND_DEGREE_TASK,
         COLOR_RECEIVE_DEGREE_TASK,
         COLOR_RECEIVE_COLOR_TASK         : begin
            case (SUBTYPE) 
               0: begin
                  araddr = base_neighbors + ( (eo_begin + enq_start) << 2);
                  arvalid = 1'b1;
                  if (enq_start + enq_limit >= degree) begin
                     arlen =  (degree - enq_start)-1;
                  end else begin
                     arlen = enq_limit;
                  end
               end
               1: begin
                  out_valid = 1'b1;
                  if (in_word_id == enq_limit) begin
                     out_task.ttype = (in_task.ttype == COLOR_SEND_DEGREE_TASK) ?
                                    COLOR_SEND_DEGREE_TASK : COLOR_RECEIVE_COLOR_TASK ;
                     out_task.producer = 1'b1;
                     out_task.args[15:0] = enq_start + enq_limit;
                  end else begin
                     if (in_task.ttype == COLOR_SEND_DEGREE_TASK) begin
                        out_task.ttype = COLOR_RECEIVE_DEGREE_TASK;
                        out_task.args[63:32] = in_task.locale;
                        out_task.args[31:16] = degree;
                        out_task.args[15:0] = 0;
                     end else begin
                        out_task.ttype = COLOR_RECEIVE_COLOR_TASK;
                        out_task.args[63:32] = in_task.locale;
                        out_task.args[79:64] = color;
                        out_task.args[15:0] = 0;

                     end
                     out_task.producer = 1'b0;
                     out_task.args[15: 0] = 0;
                     out_task.locale = in_data;
                  end
               end
            endcase
         end
      endcase
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
   end else begin
      if (reg_bus.wvalid) begin
         case (reg_bus.waddr) 
             4 : numV <= reg_bus.wdata;
             8 : numE <= reg_bus.wdata;
            16 : base_neighbors <= {reg_bus.wdata[29:0], 2'b00};
            20 : base_data <= {reg_bus.wdata[29:0], 2'b00};
            36 : enq_limit <= reg_bus.wdata;
         endcase
      end
   end
end


endmodule

//======================================================

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

localparam VID_COUNTER_OFFSET = 0;
localparam VID_BITMAP_OFFSET = 4;

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
      RECEIVE_WRITE_COUNTER, 
      RECEIVE_WRITE_BITMAP, // if (scratch[vid] was not already set
      RECEIVE_ENQ_CALC,
      FINISH_TASK
   } color_state_t;


task_t task_rdata, task_wdata; 
assign {task_rdata.args, task_rdata.ttype, task_rdata.locale, task_rdata.ts} = task_in; 

assign task_out_V_TDATA = 
      {task_wdata.args, task_wdata.ttype, task_wdata.locale, task_wdata.ts}; 

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

logic [31:0] neighbor_offset;
logic [31:0] neighbor_degree;

logic [31:0] degree;
assign degree = eo_end - eo_begin;

logic [31:0] cur_arg_0;

logic [4:0] bitmap_color;
logic [5:0] assign_color;

logic [31:0] edge_dest [0:15];
logic [31:0] cur_neighbor;
always_comb begin
   cur_neighbor = edge_dest[neighbor_offset[3:0]];
end

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

// because extracting a variable bit is not a thing
logic [31:0] new_bitmap;
assign new_bitmap = (bitmap | (1<<cur_arg_0));
logic cur_bit_set;
always_comb begin
   cur_bit_set = (bitmap == new_bitmap);
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
               7: base_scratch <= {m_axi_l1_V_RDATA[30:0], 2'b00};
               9: enq_limit <= m_axi_l1_V_RDATA[6:0];
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
            edge_dest[word_id] <= m_axi_l1_V_RDATA;
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
               0: join_counter <= m_axi_l1_V_RDATA;
               1: bitmap <= m_axi_l1_V_RDATA;
            endcase
         end
      endcase
   end else if (state == CALC_READ_OFFSET) begin
      join_counter <= 0;
   end else if (state == CALC_INC_IN_DEGREE) begin
      if ( (neighbor_degree > degree) ||
           ((neighbor_degree == degree) & (cur_neighbor < cur_task.locale))) begin
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
   end else if (state ==  CALC_INC_IN_DEGREE) begin
      neighbor_offset <= neighbor_offset + 1;
   end else if (state == COLOR_ENQ_RECEIVE 
      && state_next == COLOR_READ_NEIGHBOR_OFFSET) begin
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
      enq_end = enq_last;
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
         m_axi_l1_V_ARLEN = 9;
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
            task_wdata.locale = cur_arg_0 << 4; // random
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
            task_wdata.locale = neighbor_offset;
            task_wdata.args = 'x;
            task_wdata.ts = 0; 
            task_out_V_TVALID = 1'b1;
         end else begin
            state_next = FINISH_TASK;
         end
      end


      CALC_READ_OFFSET: begin
         m_axi_l1_V_ARADDR = base_edge_offset + (cur_task.locale << 2);
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
            m_axi_l1_V_ARLEN = (degree-neighbor_offset) > 16 ? 15 : (degree - neighbor_offset-1);  
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
         m_axi_l1_V_ARADDR = base_edge_offset + (cur_neighbor << 2);
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
         state_next = ((neighbor_offset[3:0] == '1) |
                        (neighbor_offset == degree -1))
                  ? CALC_READ_NEIGHBOR : CALC_READ_NEIGHBOR_OFFSET;
      end
      CALC_READ_JOIN_COUNTER: begin
         m_axi_l1_V_ARADDR = (base_scratch + (cur_task.locale << 3)) | VID_COUNTER_OFFSET;
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
         m_axi_l1_V_AWADDR = (base_scratch + (cur_task.locale << 3)) | VID_COUNTER_OFFSET;
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
         task_wdata.locale = cur_task.locale;
         task_wdata.args = 0;
         task_wdata.ts = 0; 
         task_out_V_TVALID = 1'b1;
         if (task_out_V_TREADY) begin
            state_next = FINISH_TASK;
         end 
      end


      COLOR_READ_BITMAP: begin
         m_axi_l1_V_ARADDR = (base_scratch + (cur_task.locale << 3)) | VID_BITMAP_OFFSET;
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
         m_axi_l1_V_AWADDR = (base_color + (cur_task.locale << 2));
         m_axi_l1_V_WDATA = assign_color;
         m_axi_l1_V_AWVALID = 1'b1;
         m_axi_l1_V_WVALID = 1'b1;
         m_axi_l1_V_WLAST = 1'b1;
         if (m_axi_l1_V_AWREADY) begin
            state_next = COLOR_READ_OFFSET;
         end
      end
      COLOR_READ_OFFSET: begin
         m_axi_l1_V_ARADDR = base_edge_offset + (cur_task.locale << 2);
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
            task_wdata.locale = cur_task.locale;
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
         if (degree == 0) begin
            state_next = FINISH_TASK;
         end else begin
            m_axi_l1_V_ARADDR = base_neighbors + ( (eo_begin + neighbor_offset) << 2);
            m_axi_l1_V_ARLEN = (enq_end-enq_start) -1;
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
         if (neighbor_offset == enq_end) begin
            state_next = FINISH_TASK;
         end else begin
            m_axi_l1_V_ARADDR = base_edge_offset + (cur_neighbor << 2);
            m_axi_l1_V_ARLEN = 1;
            m_axi_l1_V_ARVALID = 1'b1;
            if (m_axi_l1_V_ARREADY) begin
               state_next = COLOR_WAIT_NEIGHBOR_OFFSET;
            end
         end
      end
      COLOR_WAIT_NEIGHBOR_OFFSET: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = COLOR_ENQ_RECEIVE;
         end
      end
      COLOR_ENQ_RECEIVE: begin
         if( (neighbor_degree < degree )  ||
             ((neighbor_degree == degree) & (cur_neighbor > cur_task.locale))) begin
            task_wdata.ttype = RECEIVE_TASK;
            task_wdata.locale = cur_neighbor;
            task_wdata.args = assign_color;
            task_wdata.ts = 0; 
            task_out_V_TVALID = 1'b1;
            if (task_out_V_TREADY) begin
               state_next = COLOR_READ_NEIGHBOR_OFFSET;
            end 
         end else begin
            state_next = COLOR_READ_NEIGHBOR_OFFSET;
         end
      end
      
      
      RECEIVE_READ_SCRATCH: begin
         m_axi_l1_V_ARADDR = (base_scratch + (cur_task.locale << 3)) ;
         m_axi_l1_V_ARLEN = 1;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next = RECEIVE_WAIT_SCRATCH;
         end
      end
      RECEIVE_WAIT_SCRATCH: begin
         if (m_axi_l1_V_RVALID & m_axi_l1_V_RLAST) begin
            state_next = RECEIVE_WRITE_COUNTER;
         end
      end
      RECEIVE_WRITE_COUNTER: begin
         m_axi_l1_V_AWADDR = (base_scratch + (cur_task.locale << 3));
         m_axi_l1_V_WDATA = join_counter - 1;
         m_axi_l1_V_AWLEN = (cur_bit_set) ? 0 : 1; 
         m_axi_l1_V_AWVALID = 1'b1;
         m_axi_l1_V_WVALID = 1'b1;
         m_axi_l1_V_WVALID = 1;
         m_axi_l1_V_WLAST = (cur_bit_set);
         if (m_axi_l1_V_AWREADY) begin
            if (cur_bit_set) begin
               state_next = (join_counter == 1) ? RECEIVE_ENQ_CALC : FINISH_TASK;
            end else begin
               state_next = RECEIVE_WRITE_BITMAP;
            end
         end
      end
      RECEIVE_WRITE_BITMAP: begin
         m_axi_l1_V_WVALID = 1;
         m_axi_l1_V_WDATA = new_bitmap;
         m_axi_l1_V_WLAST = 1'b1;
         if (m_axi_l1_V_WREADY) begin
            state_next = (join_counter == 1) ? RECEIVE_ENQ_CALC : FINISH_TASK;
         end
      end
      RECEIVE_ENQ_CALC: begin
         task_wdata.ttype = COLOR_TASK;
         task_wdata.locale = cur_task.locale;
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
