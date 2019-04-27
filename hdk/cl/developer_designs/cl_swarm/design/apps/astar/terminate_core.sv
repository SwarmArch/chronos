`ifdef XILINX_SIMULATOR
   `define DEBUG
`endif
import swarm::*;

// place where tasks go to die
module terminate_core
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

typedef enum logic[1:0] {
      NEXT_TASK,
      FINISH_TASK} sssp_state_t;

task_t task_rdata, task_wdata; 
assign {task_rdata.args, task_rdata.ttype, task_rdata.locale, task_rdata.ts} = task_in; 

assign task_out_V_TDATA = 
      {task_wdata.args, task_wdata.ttype, task_wdata.locale, task_wdata.ts}; 

logic clk, rstn;
assign clk = ap_clk;
assign rstn = ap_rst_n;

sssp_state_t state, state_next;
assign ap_done = (state == FINISH_TASK);
assign ap_idle = (state == NEXT_TASK);
assign ap_ready = (state == NEXT_TASK);

assign m_axi_l1_V_RREADY = 1'b0; 
always_comb begin
   m_axi_l1_V_ARLEN   = 0; // 1 beat
   m_axi_l1_V_ARSIZE  = 3'b010; // 32 bits
   m_axi_l1_V_ARVALID = 1'b0;
   m_axi_l1_V_ARADDR  = 64'h0;

   task_out_V_TVALID = 1'b0;
   task_wdata  = 'x;
   state_next = state;
   
   case(state)
      NEXT_TASK: begin
         if (ap_start) begin
            state_next = FINISH_TASK;
         end
      end
      FINISH_TASK: begin
         state_next = NEXT_TASK;
      end

   endcase
end

assign m_axi_l1_V_BREADY  = 1'b0;;

assign undo_log_entry_ap_vld = 1'b0;
assign m_axi_l1_V_AWVALID = 1'b0;
assign m_axi_l1_V_WVALID = 1'b0;

assign ap_state = 0;


always_ff @(posedge clk) begin
   if (~rstn) begin
      state <= NEXT_TASK;
   end else begin
      state <= state_next;
   end
end

endmodule
