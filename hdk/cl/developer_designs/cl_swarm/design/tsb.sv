
`include "config.sv"

import swarm::*;

module tsb
	(
	input clk,
	input rstn,
    
    // from child_manager
	input                   s_wvalid ,
	output logic            s_wready,
	input task_t            s_wdata,
   input                   s_tied,
   input cq_slice_slot_t   s_cq_slot,
   input child_id_t        s_child_id,

   output logic            s_only_untied,

   input                   retry_valid,
   output logic            retry_ready,
   input tsb_entry_id_t    retry_tsb_id,
   input                   retry_abort,
   input                   retry_tied,

    // Tile: Task Enq Req
	output logic            task_enq_valid,
	input                   task_enq_ready,
	output task_t           task_enq_data,
   output logic            task_enq_tied,
   output tile_id_t        task_enq_dest_tile,
   output tsb_entry_id_t   task_enq_tsb_id,

   // Tile: Task Resp 
   input                   task_resp_valid,
   output logic            task_resp_ready,
   input                   task_resp_ack,
   input tsb_entry_id_t    task_resp_tsb_id,
   input epoch_t           task_resp_epoch,
   input tq_slot_t         task_resp_tq_slot,

   // Resp: To child manager
   output logic            m_resp_valid,
   input                   m_resp_ready,
   output logic            m_resp_ack,
   output tsb_entry_id_t   m_tsb_slot,
   output epoch_t          m_epoch,
   output tq_slot_t        m_tq_slot,
   output tile_id_t        m_tile_id,
   output cq_slice_slot_t  m_cq_slot,
   output child_id_t       m_child_id,
   
   reg_bus_t.master reg_bus,

   output ts_t    lvt,
   output logic   empty // for termination detection

);
   logic [3:0] dest_tile;
   always_comb begin
      case (n_tiles) 
         1: dest_tile = 0;
         2: dest_tile = s_wdata.locale[4];
         3: dest_tile = (s_wdata.locale[30:4])%3;
         4: dest_tile = s_wdata.locale[5:4];
         5: dest_tile = (s_wdata.locale[30:4])%5;
         6: dest_tile = (s_wdata.locale[30:4])%6;
         7: dest_tile = (s_wdata.locale[30:4])%7;
         8: dest_tile = s_wdata.locale[6:4];
         9: dest_tile = (s_wdata.locale[30:4])%9;
         10: dest_tile = (s_wdata.locale[30:4])%10;
         11: dest_tile = (s_wdata.locale[30:4])%11;
         12: dest_tile = (s_wdata.locale[30:4])%12;
         default: dest_tile = s_wdata.locale[7:4];
      endcase
   end
   logic [4:0] n_tiles;
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
         n_tiles <= N_TILES;
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               TSB_LOG_N_TILES : n_tiles <= reg_bus.wdata;
            endcase
         end
      end 
   end


generate 
if (NON_SPEC) begin


   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_enq_valid <= 1'b0;
      end else begin
         if (s_wready & s_wvalid) begin
            task_enq_valid <= 1'b1;
            task_enq_data <= s_wdata;
            task_enq_dest_tile <= dest_tile;
            task_enq_tied <= s_tied;
            task_enq_tsb_id <= 0; 
         end else if (task_enq_valid & task_enq_ready) begin
            task_enq_valid <= 1'b0;
         end
      end 
   end
   
   assign reg_bus.rvalid = 1'b1;
   assign reg_bus.rdata = 0;

   assign s_wready = (!task_enq_valid | (task_enq_valid & task_enq_ready) ); 
   assign s_only_untied = 1'b0;
   assign retry_ready = 1'b1;
   assign task_resp_ready = 1'b1;

   assign m_resp_valid = 1'b0;
   assign lvt = '1;
   
   assign empty = !task_enq_valid;

end else begin

   logic [2**LOG_TSB_SIZE -1: 0] tsb_entry_valid;

   cq_slice_slot_t      tsb_entry_cq_slot  [2**LOG_TSB_SIZE -1:0] ;
   child_id_t           tsb_entry_child_id [2**LOG_TSB_SIZE -1:0] ;
   tile_id_t            tsb_entry_tile_id  [2**LOG_TSB_SIZE -1:0] ;
   logic                tsb_entry_tied     [2**LOG_TSB_SIZE -1:0] ;
   logic[TQ_WIDTH-1:0]  tsb_entry_task     [2**LOG_TSB_SIZE -1:0] ;

   tsb_entry_id_t next_tsb_entry;
   
   lowbit #(
      .OUT_WIDTH(LOG_TSB_SIZE),
      .IN_WIDTH(2**LOG_TSB_SIZE)
   ) WRITE_SELECT (
      .in(~tsb_entry_valid),
      .out(next_tsb_entry)
   );

   logic [2:0] log_n_tiles;
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
         log_n_tiles <= $clog2(N_TILES);
      end else begin
         if (reg_bus.wvalid) begin
            case (reg_bus.waddr) 
               TSB_LOG_N_TILES : log_n_tiles <= reg_bus.wdata;
            endcase
         end
      end 
   end
   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
      end
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
         casex (reg_bus.araddr) 
            TSB_ENTRY_VALID  : reg_bus.rdata <= tsb_entry_valid;
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end  

   always_comb begin
      s_wready = 1'b0;
      retry_ready = 1'b0;
      if (!task_enq_valid | (task_enq_valid & task_enq_ready) ) begin
         if (s_wvalid &  !tsb_entry_valid[next_tsb_entry]) begin
            s_wready = 1'b1;
         end else if (retry_valid) begin
            retry_ready = 1'b1;
         end
      end
   end
   assign task_resp_ready = !m_resp_valid;


   always_ff @(posedge clk) begin
      if (!rstn) begin
         task_enq_valid <= 1'b0;
      end else begin
         if (s_wready & s_wvalid) begin
            task_enq_valid <= 1'b1;
            task_enq_data <= s_wdata;
            task_enq_dest_tile <= dest_tile;
            task_enq_tied <= s_tied;
            task_enq_tsb_id <= next_tsb_entry; 
            tsb_entry_cq_slot[next_tsb_entry] <= s_cq_slot;
            tsb_entry_child_id[next_tsb_entry] <= s_child_id;
            tsb_entry_tile_id[next_tsb_entry] <= dest_tile;
            tsb_entry_task[next_tsb_entry] <= s_wdata;
            tsb_entry_tied[next_tsb_entry] <= s_tied;
         end else if (retry_valid & retry_ready & !retry_abort) begin
            task_enq_valid <= 1'b1;
            task_enq_data <= tsb_entry_task[retry_tsb_id];
            task_enq_dest_tile <= tsb_entry_tile_id[retry_tsb_id];
            task_enq_tied <= retry_tied;
            tsb_entry_tied[retry_tsb_id] <= retry_tied;
            task_enq_tsb_id <= retry_tsb_id; 
         end else if (task_enq_valid & task_enq_ready) begin
            task_enq_valid <= 1'b0;
         end
      end
   end

   always_ff @(posedge clk) begin
      if (!rstn) begin
         m_resp_valid <= 1'b0;
      end else begin
         if (task_resp_valid & task_resp_ready & tsb_entry_tied[task_resp_tsb_id] ) begin
            m_resp_valid <= 1'b1;
            m_epoch <= task_resp_epoch;
            m_resp_ack <= task_resp_ack;
            m_tq_slot <= task_resp_tq_slot;
            m_tile_id <= tsb_entry_tile_id[task_resp_tsb_id]; 
            m_cq_slot <= tsb_entry_cq_slot[task_resp_tsb_id]; 
            m_child_id <= tsb_entry_child_id[task_resp_tsb_id]; 
            m_tsb_slot <= task_resp_tsb_id;
         end else if (m_resp_valid & m_resp_ready) begin
            m_resp_valid <= 1'b0;
         end
      end
   end


   logic n_tsb_size_inc, n_tsb_size_dec_resp, n_tsb_size_dec_retry;
   assign n_tsb_size_inc = s_wvalid & s_wready;
   assign n_tsb_size_dec_resp = task_resp_valid & task_resp_ready & task_resp_ack;
   assign n_tsb_size_dec_retry = retry_valid & retry_ready & retry_abort;

   logic [LOG_TSB_SIZE:0] n_tsb_size;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         n_tsb_size <= 0;
      end else begin
         n_tsb_size <= n_tsb_size + n_tsb_size_inc - n_tsb_size_dec_resp - n_tsb_size_dec_retry;
      end
   end

   assign s_only_untied = (n_tsb_size > (2**LOG_TSB_SIZE -3));


   genvar i, j;
      for (i=0;i<2**LOG_TSB_SIZE;i++) begin
         always_ff @(posedge clk) begin
            if (!rstn) begin
               tsb_entry_valid[i] <= 1'b0;
            end else begin
               // untied tasks do not need a tsb entry
               if (s_wready & s_wvalid & (i== next_tsb_entry)) begin
                  tsb_entry_valid[i] <= 1'b1;
               end else if (retry_valid & retry_ready& (i==retry_tsb_id) & 
                     retry_abort)  begin
                  tsb_entry_valid[i] <= 1'b0;
               end else if (task_resp_valid & task_resp_ready & task_resp_ack &
                     (i==task_resp_tsb_id) ) begin
                  tsb_entry_valid[i] <= 1'b0;
               end
            end
         end 
      end

   task_t lvt_tsb_entry;
   assign lvt_tsb_entry = tsb_entry_task[cur_cycle];

   ts_t lvt_fixed;
   ts_t lvt_rolling;
   logic [LOG_TSB_SIZE-1:0] cur_cycle;
   always_ff @(posedge clk) begin
      if (!rstn) begin
         lvt_fixed <= 0;
         lvt_rolling <= 0;
         cur_cycle <= 0;
      end else begin
         cur_cycle <= cur_cycle + 1;
         if (cur_cycle == 0) begin
            lvt_fixed <= lvt_rolling;
            lvt_rolling <= tsb_entry_valid[0] ? lvt_tsb_entry.ts : '1;
         end else begin
            if (tsb_entry_valid[cur_cycle] & (lvt_tsb_entry.ts < lvt_rolling)) begin
               lvt_rolling <= lvt_tsb_entry.ts;
            end
         end
      end
   end
   assign lvt = lvt_fixed;
/*
   ts_t tree [LOG_TSB_SIZE+1][2**LOG_TSB_SIZE];
   generate 
      for (i=0;i<2**LOG_TSB_SIZE;i++) begin
         assign tree[LOG_TSB_SIZE][i] = (tsb_entry_valid[i]) ? tsb_entry_task[i].ts : '1;
      end
   endgenerate
   generate
      for (i=LOG_TSB_SIZE-1;i>=0;i--) begin
         for (j=0;j< 2**i;  j++) begin
            always_ff @(posedge clk) begin
               tree[i][j] <= (tree[i+1][j*2] < tree[i+1][j*2+1]) ? 
                                          tree[i+1][j*2] : tree[i+1][j*2+1];
            end
         end
      end
   endgenerate

   assign lvt = tree[0][0];
*/
   assign empty = (tsb_entry_valid==0) ;
end
endgenerate
endmodule
