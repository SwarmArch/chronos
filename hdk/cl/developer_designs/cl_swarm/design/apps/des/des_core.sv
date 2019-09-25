`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

`ifndef DES_TYPES_DEFINED
`define DES_TYPES_DEFINED
typedef enum logic [2:0] { BUF, INV, NAND2, NOR2, AND2, OR2, XOR2, XNOR2 } gate_t;
typedef enum logic [1:0] { LOGIC_0 =0, LOGIC_1=1, LOGIC_X=2, LOGIC_Z=3 } logic_val_t; 
`endif
module des_core
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


typedef enum logic[3:0] {
      NEXT_TASK,
      READ_BASE_OFFSET, WAIT_BASE_OFFSET,
      READ_BASE_NEIGHBORS, WAIT_BASE_NEIGHBORS,
      READ_BASE_DATA, WAIT_BASE_DATA,
      READ_DATA, WAIT_DATA, 
      EVAL_GATE,
      READ_EDGE_OFFSET, WAIT_EDGE_OFFSET,
      READ_NEIGHBORS, WAIT_NEIGHBOR,  
      WAIT_WRITE, 
      FINISH_TASK} des_state_t;
typedef enum logic[1:0] {IDLE, UNDO_LOG, AWADDR, BVALID
      } write_state_t;

logic start;


// if '1' , only sends an output msg if the output actually changes
logic sparse_msgs;
assign sparse_msgs = 1'b1;

task_t task_rdata, task_wdata; 
assign {task_rdata.args, task_rdata.ttype, task_rdata.locale, task_rdata.ts} = task_in; 

assign task_out_V_TDATA = 
      {task_wdata.args, task_wdata.ttype, task_wdata.locale, task_wdata.ts}; 

logic clk, rstn;
assign clk = ap_clk;
assign rstn = ap_rst_n;


des_state_t state, state_next;
write_state_t write_state, write_state_next;
logic [31:0] virtex_id;
logic_val_t  input_logic_val;
logic        input_port;
ts_t         input_ts;

gate_t       logic_gate;
logic_val_t  logic_val_0, logic_val_1;
logic [15:0] gate_delay;

logic [31:0] edge_offset_start;
logic [31:0] edge_offset_end;

logic [31:0] neighbor, neighbor_next;

logic [63:0] base_edge_offset;
logic [63:0] base_neighbors;
logic [63:0] base_dist;

assign ap_done = (state == FINISH_TASK);
assign ap_idle = (state == NEXT_TASK);
assign ap_ready = (state == NEXT_TASK);

assign m_axi_l1_V_RREADY = ( 
                     (state == WAIT_BASE_OFFSET) |
                     (state == WAIT_BASE_NEIGHBORS) |
                     (state == WAIT_BASE_DATA) |
                     (state == WAIT_DATA) |
                     (state == WAIT_EDGE_OFFSET) |
                     (state == WAIT_NEIGHBOR & task_out_V_TREADY) );

assign ap_state = state;
logic initialized;

always_ff @(posedge clk) begin
   if (!rstn) begin
      initialized <= 1'b0;
   end else if (state == READ_BASE_OFFSET) begin
      initialized <= 1'b1;
   end
end

logic_val_t current_gate_output;
always_ff @(posedge clk) begin
   if (state == NEXT_TASK) begin
      virtex_id <= task_rdata.locale;
      case (task_rdata.args[1:0])
         0: input_logic_val <= LOGIC_0;
         1: input_logic_val <= LOGIC_1;
         2: input_logic_val <= LOGIC_X;
         3: input_logic_val <= LOGIC_Z;
      endcase
      //input_logic_val <= task_rdata.args[1:0];
      input_port      <= task_rdata.args[2];
      input_ts        <= task_rdata.ts;
   end
   if ((state == WAIT_DATA) & m_axi_l1_V_RVALID) begin
      case (m_axi_l1_V_RDATA[25:24])
         0: current_gate_output <= LOGIC_0;
         1: current_gate_output <= LOGIC_1;
         2: current_gate_output <= LOGIC_X;
         3: current_gate_output <= LOGIC_Z;
      endcase
      case (m_axi_l1_V_RDATA[23:22])
         0: logic_val_0 <= LOGIC_0;
         1: logic_val_0 <= LOGIC_1;
         2: logic_val_0 <= LOGIC_X;
         3: logic_val_0 <= LOGIC_Z;
      endcase
      case (m_axi_l1_V_RDATA[21:20])
         0: logic_val_1 <= LOGIC_0;
         1: logic_val_1 <= LOGIC_1;
         2: logic_val_1 <= LOGIC_X;
         3: logic_val_1 <= LOGIC_Z;
      endcase
      case (m_axi_l1_V_RDATA[18:16])
         0: logic_gate <= BUF;
         1: logic_gate <= INV;
         2: logic_gate <= NAND2;
         3: logic_gate <= NOR2;
         4: logic_gate <= AND2;
         5: logic_gate <= OR2;
         6: logic_gate <= XOR2;
         7: logic_gate <= XNOR2;
      endcase
      gate_delay <= m_axi_l1_V_RDATA[15:0];
   end
   if ((state == WAIT_EDGE_OFFSET) & m_axi_l1_V_RVALID) begin
      if (m_axi_l1_V_RLAST) begin
         edge_offset_end <= m_axi_l1_V_RDATA;
      end else begin
         edge_offset_start <= m_axi_l1_V_RDATA;
      end
   end
end

// Assumes no X or Z 
logic gate_output_changed;
logic gate_input_changed;
logic_val_t new_gate_output;

logic_val_t new_gate_in0;
logic_val_t new_gate_in1;
assign new_gate_in0 = (~input_port ? input_logic_val : logic_val_0);
assign new_gate_in1 = ( input_port ? input_logic_val : logic_val_1);

logic_eval GATE_EVAL (
   .p0(new_gate_in0),
   .p1(new_gate_in1),
   .gate(logic_gate),
   .o(new_gate_output)
);

assign gate_output_changed = (current_gate_output != new_gate_output);
assign gate_input_changed = (new_gate_in0 != logic_val_0) | (new_gate_in1 != logic_val_1);

logic wr_begin;

always_comb begin
   m_axi_l1_V_ARLEN   = 0; // 1 beat
   m_axi_l1_V_ARSIZE  = 3'b010; // 32 bits
   m_axi_l1_V_ARVALID = 1'b0;
   m_axi_l1_V_ARADDR  = 64'h0;

   task_out_V_TVALID = 1'b0;
   task_wdata  = 'x;

   wr_begin = 1'b0;

   state_next = state;

   neighbor_next = neighbor;

   case(state)
      NEXT_TASK: begin
         if (ap_start) begin
            state_next = initialized ? READ_DATA : READ_BASE_OFFSET;
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
            state_next = READ_DATA;
         end
      end
      READ_DATA: begin
         m_axi_l1_V_ARADDR = base_dist + virtex_id * 4;
         m_axi_l1_V_ARVALID = 1'b1;
         if (m_axi_l1_V_ARREADY) begin
            state_next =  WAIT_DATA;
         end
      end
      WAIT_DATA: begin
         if (m_axi_l1_V_RVALID) begin
            state_next = EVAL_GATE;
         end
      end
      EVAL_GATE: begin
         if (gate_output_changed | ~sparse_msgs) begin
            state_next = READ_EDGE_OFFSET; // can write dist in parallel
            wr_begin = 1'b1;
         end else if (gate_input_changed) begin
            wr_begin = 1'b1;
            state_next = WAIT_WRITE;
         end else begin
            state_next = FINISH_TASK;
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
            state_next = WAIT_WRITE;
         end else begin
            m_axi_l1_V_ARADDR = base_neighbors + edge_offset_start * 4 ;
            m_axi_l1_V_ARVALID = 1'b1;
            m_axi_l1_V_ARLEN = (edge_offset_end - edge_offset_start) - 1;
            if (m_axi_l1_V_ARREADY) begin
               state_next = WAIT_NEIGHBOR;
            end
         end
      end
      WAIT_NEIGHBOR: begin
         if (m_axi_l1_V_RVALID) begin
            task_wdata.ttype = 0;
            task_wdata.locale = m_axi_l1_V_RDATA[31:1]; // vid
            task_wdata.args[2] = m_axi_l1_V_RDATA[0]; // port
            task_wdata.args[1:0] = new_gate_output; // port
            task_wdata.args[ARG_WIDTH-1:3] = 0;
            task_wdata.ts = input_ts + gate_delay; //weight
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
         state_next =  NEXT_TASK;
      end

   endcase
end

assign m_axi_l1_V_BREADY  = (write_state == BVALID);

undo_log_addr_t undo_log_addr;
undo_log_data_t undo_log_data;

assign undo_log_addr = base_dist + (virtex_id * 4);
assign undo_log_entry_ap_vld = (write_state == UNDO_LOG); 
assign undo_log_data = {6'b0, current_gate_output,
               logic_val_0, logic_val_1,
               1'b0, logic_gate, gate_delay}; 
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
         if (undo_log_entry_ap_vld & undo_log_entry_ap_rdy) begin
            write_state_next = AWADDR;
         end
      end
      AWADDR: begin
         m_axi_l1_V_AWVALID = 1'b1;
         m_axi_l1_V_AWADDR  = base_dist + virtex_id * 4;
         m_axi_l1_V_WVALID  = 1'b1;
         m_axi_l1_V_WLAST   = 1'b1;
         if (m_axi_l1_V_AWREADY & m_axi_l1_V_WREADY) begin
            write_state_next = BVALID;
         end            
         m_axi_l1_V_WDATA[25:24] = new_gate_output;
         m_axi_l1_V_WDATA[23:22] = ~input_port ? input_logic_val : logic_val_0;
         m_axi_l1_V_WDATA[21:20] =  input_port ? input_logic_val : logic_val_1;
         m_axi_l1_V_WDATA[19:16] =  logic_gate;
         m_axi_l1_V_WDATA[15: 0] =  gate_delay;
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
   end else begin
      state <= state_next;
      write_state <= write_state_next;
      neighbor <= neighbor_next;
   end
end


always_ff @(posedge clk) begin
   if (m_axi_l1_V_RVALID) begin
      case (state)
         WAIT_BASE_OFFSET: base_edge_offset <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
         WAIT_BASE_NEIGHBORS: base_neighbors <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
         WAIT_BASE_DATA: base_dist <= {30'b0, m_axi_l1_V_RDATA, 2'b0};
      endcase
   end
end

endmodule


module logic_eval (
   input logic_val_t p0,
   input logic_val_t p1,
   gate_t gate,
   
   output logic_val_t o
   
);

always_comb begin
   case (gate) 
      BUF: o = p0;
      INV: begin
         if (p0 == LOGIC_0) o = LOGIC_1;
         else if (p0 == LOGIC_1) o= LOGIC_0;
         else o = p0;
      end
      NAND2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) | (p1 == LOGIC_0)) o = LOGIC_1;
         else o = LOGIC_X;
      end
      NOR2: begin
         if ((p0 == LOGIC_1) | (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_1;
         else o = LOGIC_X;
      end
      AND2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) | (p1 == LOGIC_0)) o = LOGIC_0;
         else o = LOGIC_X;
      end
      OR2: begin
         if ((p0 == LOGIC_1) | (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_0;
         else o = LOGIC_X;
      end
      XOR2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_1) & (p1 == LOGIC_0)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_0;
         else o = LOGIC_X;
      end
      XNOR2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_1) & (p1 == LOGIC_0)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_1;
         else o = LOGIC_X;
      end

   endcase

end

endmodule
