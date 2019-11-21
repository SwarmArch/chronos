`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import chronos::*;

typedef struct packed {
   logic [31:0] eo_end;
   logic [31:0] eo_begin;
   logic [9:0] [31:0] flow;
   logic [31:0] last_visited_iter;
   logic [31:0] height;
   logic [ 7:0] counter;
   logic [23:0] min_height;
   logic signed [31:0] excess;
} maxflow_data_t;

typedef struct packed {
   logic signed [31:0] capacity;
   logic [ 7:0] reverse_edge_id;
   logic [23:0] dest;
} maxflow_edge_t;

parameter MAXFLOW_DISCHARGE_TASK = 0;
parameter MAXFLOW_GET_HEIGHT_TASK = 1; 
      // say node v enqueue get_height_task for node n
      //  [23: 0] v_vid,
      //  [27:24] v's reverse edge id, i.e location of v in n's edge list, 
      //  [31:28] fwd_edge_id, i.e location of n in v's edge list
      //  [63:32] edge_cap,

parameter MAXFLOW_PUSH_TASK = 2; 
      //  [23:0] n's height,
      //  [27:24] v's reverse edge id, i.e location of v in n's edge list, 
      //  [31:28] fwd_edge_id, i.e location of n in v's edge list
      //  [63:32] edge_cap,
      //  [95:64] n_id

parameter MAXFLOW_RECEIVE_TASK = 3;  
      //  [31: 0] flow_amount
      //  [35:32] v's reverse edge id, i.e location of v in n's edge list, 
      
parameter MAXFLOW_BFS_CHECK_RESIDUAL_TASK = 4;
      //  [23: 0] v_vid (parent of visit),
      //  [27:24] v's reverse edge id, i.e location of v in n's edge list, 
      //  [31:28] fwd_edge_id, i.e location of n in v's edge list
parameter MAXFLOW_BFS_UPDATE_HEIGHT_TASK = 5;
parameter MAXFLOW_BFS_ENQ_NBR_TASK = 6;

module maxflow_rw
#(
   parameter TILE_ID=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input rw_data_t          in_data,
   input cq_slice_slot_t   in_cq_slot,
   
   output logic            wvalid,
   output logic [31:0]     waddr,
   output rw_data_t         wdata,

   output logic            out_valid,
   output task_t           out_task,
   output ro_data_t           out_data,

   output logic            sched_task_valid,
   input logic             sched_task_ready,

   reg_bus_t               reg_bus

);

// headers
logic [31:0] numV, numE;
logic [31:0] base_edge_offset;
logic [31:0] base_neighbors;
logic [31:0] base_vertex_data;
logic [31:0] sourceNode, sinkNode;
logic [31:0] global_relabel_mask;
logic [31:0] iteration_no_mask;
logic ordered_edges;

maxflow_data_t read_word, write_word;
assign read_word = in_data;
assign wdata = write_word;

assign task_in_ready = sched_task_valid & sched_task_ready;
assign sched_task_valid = task_in_valid;

logic signed [31:0] push_task_edge_capacity;
logic signed [31:0] push_task_edge_flow;
logic [3:0] push_task_neighbor_id;
assign push_task_neighbor_id = in_task.args[31:28];
assign push_task_edge_capacity = in_task.args[63:32];
always_comb begin
   push_task_edge_flow = read_word.flow[push_task_neighbor_id];
end
logic [31:0] push_task_neighbor_height;
logic [3:0] push_task_reverse_edge_id;
assign push_task_neighbor_height = {8'd0, in_task.args[23:0]};
assign push_task_reverse_edge_id = in_task.args[27:24];

logic signed [31:0] flow_amount;

always_comb begin 
   wvalid = 0;
   waddr = base_vertex_data + ( in_task.object << 6) ;
   write_word = read_word;
   out_valid = 1'b0;

   out_task = in_task;
   flow_amount = read_word.excess;

   if (task_in_valid) begin
      case (in_task.ttype)
         MAXFLOW_DISCHARGE_TASK: begin
            if ((in_task.ts & global_relabel_mask) ==0) begin
               out_valid = 1'b1;
            end else begin
               write_word.counter = read_word.eo_end - read_word.eo_begin;
               write_word.min_height = 2*numV;
               wvalid = 1'b1;
               out_valid = 1'b1;
               out_task.args[31:0] = read_word.eo_begin;
               out_task.args[63:32] = read_word.eo_end;
            end
         end
         MAXFLOW_GET_HEIGHT_TASK: begin
            out_valid = 1'b1;
            out_task.args[95:64] = read_word.height;
         end
         MAXFLOW_PUSH_TASK: begin
            wvalid = 1'b1;
            write_word.counter = write_word.counter -1;
            if ((read_word.height == push_task_neighbor_height + 1) || (in_task.object == sourceNode)) begin
               if ( flow_amount > (push_task_edge_capacity - push_task_edge_flow)) begin
                  flow_amount = push_task_edge_capacity - push_task_edge_flow;              
               end
               if (flow_amount > 0) begin
                  write_word.flow[push_task_neighbor_id] = push_task_edge_flow + flow_amount; 
                  write_word.excess = read_word.excess - flow_amount;
               end
            end else begin
               flow_amount = 0;
            end
            // consider for relabelling
            if (push_task_edge_capacity > (push_task_edge_flow + flow_amount)) begin
               if (push_task_neighbor_height < read_word.min_height) begin
                  write_word.min_height = push_task_neighbor_height;
               end
            end
            if ( (write_word.counter == 0) & (write_word.excess > 0) ) begin
               write_word.height = write_word.min_height + 1;
            end
            out_task.args[31:0] = flow_amount;
            out_task.args[35:32] = push_task_reverse_edge_id;
            out_task.args[36] = ( (write_word.counter == 0) && (write_word.excess > 0)); // reenqueue node
            out_task.args[95:64] = in_task.args[95:64]; // neighbor vid
            out_valid = (flow_amount >0) || out_task.args[36]; 
         end
         MAXFLOW_RECEIVE_TASK: begin
            wvalid = 1'b1;
            write_word.excess = read_word.excess + in_task.args[31:0];
            write_word.flow[ in_task.args[35:32] ] = read_word.flow[in_task.args[35:32]] - in_task.args[31:0];
            out_valid = (read_word.excess == 0) & (in_task.object != sourceNode) & (in_task.object != sinkNode);
         end
         MAXFLOW_BFS_CHECK_RESIDUAL_TASK: begin
            wvalid = 1'b0;
            if (read_word.last_visited_iter < (in_task.ts & iteration_no_mask)) begin
               out_valid = 1'b1;
               out_task.args[63:32] = read_word.eo_begin;
               out_task.args[95:64] = $signed(read_word.flow[ in_task.args[27:24]]);
            end
            
         end 
         MAXFLOW_BFS_UPDATE_HEIGHT_TASK: begin
            if (read_word.last_visited_iter < (in_task.ts & iteration_no_mask)) begin
               write_word.last_visited_iter = (in_task.ts & iteration_no_mask);
               write_word.height = in_task.ts[10:0] + (in_task.ts[11] ? numV : 0); 
               wvalid = 1'b1;
               out_task.args[31: 0] = read_word.eo_begin;
               out_task.args[63:32] = read_word.eo_end;
               out_valid = 1'b1;
            end
         end
         MAXFLOW_BFS_ENQ_NBR_TASK: begin
            out_valid = 1'b1;
            if (!out_task.no_read) begin
               out_task.args[31: 0] = read_word.eo_begin;
               out_task.args[63:32] = read_word.eo_end;
            end
            wvalid = 1'b0;
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
            12 : base_edge_offset <= {reg_bus.wdata[29:0], 2'b00};
            16 : base_neighbors <= {reg_bus.wdata[29:0], 2'b00};
            20 : base_vertex_data <= {reg_bus.wdata[29:0], 2'b00};
            28 : sourceNode <= reg_bus.wdata;
            36 : sinkNode <= reg_bus.wdata;
            44 : global_relabel_mask <= reg_bus.wdata;
            48 : iteration_no_mask <= reg_bus.wdata;
            52 : ordered_edges <= reg_bus.wdata;
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
         case (in_task.ttype) 
         MAXFLOW_DISCHARGE_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] DISCHARGE ts:%8x object:%4x | | excess:%4d height:%4d",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object, read_word.excess, read_word.height) ;
         end
         MAXFLOW_GET_HEIGHT_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] GET_HEIGHT ts:%8x object:%4x | v_vid:%4x rev_edge:%1x fwd_edge:%1x cap:%4d  ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object, in_task.args[23:0], in_task.args[27:24], in_task.args[31:28], in_task.args[63:32] ) ;
         end
         MAXFLOW_PUSH_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] PUSH ts:%8x object:%4x | height:%2d rev_edge:%1x fwd_edge:%1x cap:%4d n_id:%4x | v_height:%2d ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object, 
            in_task.args[23:0], in_task.args[27:24], in_task.args[31:28], in_task.args[63:32], in_task.args[95:64],
            read_word.height
            ) ;
         end
         MAXFLOW_RECEIVE_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] RECEIVE ts:%8x object:%4x | flow:%4d rev_edge:%1x ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object, in_task.args[31:0], in_task.args[35:32]) ;
         end
         MAXFLOW_BFS_CHECK_RESIDUAL_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] BFS_RESIDUAL ts:%8x object:%4x | visited:%4x rev_edge:%1x rev_flow:%d ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object, read_word.last_visited_iter, in_task.args[27:24], out_task.args[95:64]) ;
         end
         
         MAXFLOW_BFS_UPDATE_HEIGHT_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] BFS_UPDATE ts:%8x object:%4x | visited:%4x ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object, read_word.last_visited_iter) ;
         end
         MAXFLOW_BFS_ENQ_NBR_TASK: begin
            $display("[%5d] [rob-%2d] [rw] [%3d] BFS_ENQ_NBR ts:%8x object:%4x | visited:%4x ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object, read_word.last_visited_iter) ;
         end

         endcase
      end
   end 
`endif

endmodule

module maxflow_ro
#(
   parameter TILE_ID=0,
   parameter SUBTYPE=0
) (

   input clk,
   input rstn,

   input logic             task_in_valid,
   output logic            task_in_ready,

   input task_t            in_task, 
   input ro_data_t            in_data,
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

   output logic [31:0]     log_output,

   reg_bus_t               reg_bus

);

assign sched_task_valid = task_in_valid;
assign task_in_ready = sched_task_ready;
assign out_cq_slot = in_cq_slot;
// headers
logic [31:0] numV, numE;
logic [31:0] base_edge_offset;
logic [31:0] base_neighbors;
logic [31:0] base_vertex_data;
logic [31:0] sourceNode, sinkNode;
logic [31:0] global_relabel_mask;
logic [31:0] iteration_no_mask;
logic ordered_edges;
logic use_bfs_producer_tasks;
logic bfs_is_non_spec;

assign resp_task = in_task;
maxflow_edge_t in_data_edge;
assign in_data_edge = in_data;
always_comb begin
   araddr = 'x;
   arsize = 3;
   arlen = 0;
   arvalid = 1'b0;
   out_valid = 1'b0;
   resp_mark_last = 1'b0;
   out_task = in_task;
   out_task.producer = 1'b0;
   out_task.no_read  = 1'b0;
   out_task.no_write = 1'b0;
   out_task.non_spec = 1'b0;

   out_task_is_child = 1'b1;
   resp_subtype = 'x;
   
   if (task_in_valid) begin
      case (in_task.ttype) 
         MAXFLOW_DISCHARGE_TASK: begin
            case (SUBTYPE) 
               0: begin
                  if ((in_task.ts & global_relabel_mask) ==0) begin
                     // reenqueue original task
                     out_valid = 1'b1;
                     out_task = in_task;
                     out_task_is_child = 1'b1;
                     if ((in_task.ts & 32'hf0) == 0) begin // tile == 0
                        araddr = 0;
                        arlen = 1;
                        arvalid = 1'b1;
                        resp_subtype = 1;
                     end
                  end else begin
                     araddr = base_neighbors + (in_task.args[31:0] << 3);
                     arlen = (in_task.args[63:32]- in_task.args[31:0])-1;
                     resp_subtype = 2;
                     arvalid = (in_task.args[63:32] != in_task.args[31:0]); 
                  end
               end
               1: begin
                  out_valid = 1'b1;
                  out_task.ttype = MAXFLOW_BFS_UPDATE_HEIGHT_TASK;
                  out_task.ts = (in_word_id == 0)? in_task.ts : in_task.ts + (1<<11) ;
                  out_task.object = (in_word_id == 0) ? sinkNode : sourceNode;
                  out_task.producer = 1'b1;
                  out_task.non_spec = bfs_is_non_spec;
               end
               2: begin
                  out_valid = 1'b1;
                  out_task.ttype = MAXFLOW_GET_HEIGHT_TASK; 
                  out_task.object = in_data_edge.dest;
                  out_task.ts = in_task.ts | (ordered_edges ? in_word_id : 0); 
                  out_task.args[23: 0] = in_task.object[23:0];
                  out_task.args[27:24] = in_data_edge.reverse_edge_id;
                  out_task.args[31:28] = in_word_id;
                  out_task.args[63:32] = in_data_edge.capacity;
               end

            endcase
         end
         MAXFLOW_GET_HEIGHT_TASK: begin
            out_valid = 1'b1;
            out_task.ttype = MAXFLOW_PUSH_TASK;
            out_task.object = in_task.args[23:0];
            out_task.args[23:0] = in_task.args[87:64]; // height
            out_task.args[95:64] = in_task.object;
         end
         MAXFLOW_PUSH_TASK: begin
            case (SUBTYPE)
               0: begin
                  if (in_task.args[31:0] > 0) begin
                     out_valid = 1'b1;
                     out_task.ttype = MAXFLOW_RECEIVE_TASK;
                     out_task.object = in_task.args[95:64];
                  end
                  if (in_task.args[36]) begin // if reenqueue task
                     araddr = 0;
                     arlen = 0;
                     arvalid = 1'b1;
                     resp_subtype = 1;
                  end
               end
               1: begin
                  out_valid = 1'b1;
                  out_task.ttype = MAXFLOW_DISCHARGE_TASK;
                  out_task.args = 'x;
               end
            endcase
         end
         MAXFLOW_RECEIVE_TASK: begin
            if (SUBTYPE == 0) begin
               out_valid = 1'b1;
               out_task.ttype = MAXFLOW_DISCHARGE_TASK;
               out_task.args = 'x;
            end
         end
         MAXFLOW_BFS_CHECK_RESIDUAL_TASK: begin
            if (SUBTYPE==0) begin
               // read capacity of reverse edge
               araddr = base_neighbors + ( (in_task.args[63:32] + in_task.args[27:24]) << 3);
               arlen = 0;
               resp_subtype = 1;
               arvalid = 1'b1;
            end else if (SUBTYPE == 1) begin
               out_valid = (in_data_edge.capacity > $signed(in_task.args[95:64]));
               out_task.producer = 1'b1;
               out_task.non_spec = bfs_is_non_spec;
               out_task.ttype = MAXFLOW_BFS_UPDATE_HEIGHT_TASK;
               out_task.ts = out_task.ts;
            end

         end
         MAXFLOW_BFS_UPDATE_HEIGHT_TASK,
         MAXFLOW_BFS_ENQ_NBR_TASK: begin
            if (SUBTYPE == 0) begin
               if ((in_task.ttype == MAXFLOW_BFS_UPDATE_HEIGHT_TASK) & use_bfs_producer_tasks) begin
                  out_valid = 1'b1;
                  out_task.ttype = MAXFLOW_BFS_ENQ_NBR_TASK;
                  out_task.producer = 1'b1;
                  out_task.non_spec = bfs_is_non_spec;
                  //out_task.no_read = 1'b1;
                  out_task.ts = in_task.ts + 1;
               end else begin
                  araddr = base_neighbors + (in_task.args[31:0] << 3);
                  arlen = (in_task.args[63:32]- in_task.args[31:0])-1;
                  resp_subtype = 1;
                  arvalid = (in_task.args[63:32] != in_task.args[31:0]); 
               end
            end else if (SUBTYPE==1) begin
               out_valid = 1'b1;
               out_task.ttype = MAXFLOW_BFS_CHECK_RESIDUAL_TASK; 
               out_task.producer = 1'b0;
               out_task.non_spec = bfs_is_non_spec;
               out_task.object = in_data_edge.dest;
               out_task.ts = in_task.ts + (use_bfs_producer_tasks ? 1'b0 : 1'b1) ; 
               out_task.args[23: 0] = in_task.object[23:0];
               out_task.args[27:24] = in_data_edge.reverse_edge_id;
               out_task.args[31:28] = in_word_id;
               out_task.args[63:32] = 'x;
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
            12 : base_edge_offset <= {reg_bus.wdata[29:0], 2'b00};
            16 : base_neighbors <= {reg_bus.wdata[29:0], 2'b00};
            20 : base_vertex_data <= {reg_bus.wdata[29:0], 2'b00};
            28 : sourceNode <= reg_bus.wdata;
            36 : sinkNode <= reg_bus.wdata;
            44 : global_relabel_mask <= reg_bus.wdata;
            48 : iteration_no_mask <= reg_bus.wdata;
            52 : ordered_edges <= reg_bus.wdata;
            56 : use_bfs_producer_tasks <= reg_bus.wdata;
            60 : bfs_is_non_spec <= reg_bus.wdata;
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
         case (in_task.ttype) 
         MAXFLOW_DISCHARGE_TASK: begin
            if (SUBTYPE == 0) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t DISCHARGE 0 ts:%8x object:%4x | eo_begin:%4d eo_end:%4d",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_task.args[31:0], in_task.args[63:32]) ;
            end
            if (SUBTYPE == 1) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t DISCHARGE 1 ts:%8x object:%4x ",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object) ;
            end
            if (SUBTYPE == 2) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t DISCHARGE 2 ts:%8x object:%4x | word_id:%1d dest:%4x cap:%4d",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_word_id, in_data_edge.dest, in_data_edge.capacity) ;
            end
         end
         MAXFLOW_GET_HEIGHT_TASK: begin
            $display("[%5d] [rob-%2d] [ro] [%3d] \t GET_HEIGHT 0 ts:%8x object:%4x ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object) ;
         end
         MAXFLOW_PUSH_TASK: begin
            $display("[%5d] [rob-%2d] [ro] [%3d] \t PUSH %d ts:%8x object:%4x ",
            cycle, TILE_ID, in_cq_slot, SUBTYPE,
            in_task.ts, in_task.object ) ;
         end
         MAXFLOW_RECEIVE_TASK: begin
            $display("[%5d] [rob-%2d] [ro] [%3d] \t RECEIVE 0 ts:%8x object:%4x ",
            cycle, TILE_ID, in_cq_slot,
            in_task.ts, in_task.object) ;
         end
         MAXFLOW_BFS_CHECK_RESIDUAL_TASK: begin
            if (SUBTYPE==1) begin
               $display("[%5d] [rob-%2d] [ro] [%3d] \t BFS_RESIDUAL 0 ts:%8x object:%4x | cap:%d flow:%d",
               cycle, TILE_ID, in_cq_slot,
               in_task.ts, in_task.object, in_data_edge.capacity, $signed(in_task.args[95:64])) ;
            end
         end

         endcase
      end
   end 
`endif

endmodule

