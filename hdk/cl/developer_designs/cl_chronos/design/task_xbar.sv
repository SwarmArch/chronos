

import chronos::*;

module tile_xbar
#(
   parameter NUM_SI=N_TILES, 
   parameter NUM_MI=N_TILES,
   parameter DATA_WIDTH = 32
)
( 
	input clk,
	input rstn,
   
   input logic        [NUM_SI-1:0] s_wvalid,
   output logic       [NUM_SI-1:0] s_wready,
   input [NUM_SI-1:0] [DATA_WIDTH-1:0] s_wdata,
   input tile_id_t  [NUM_SI-1:0]       s_port,
   
   output logic       [NUM_MI-1:0] m_wvalid,
   input              [NUM_MI-1:0] m_wready,
   output logic [NUM_SI-1:0] [DATA_WIDTH-1:0] m_wdata
);

localparam LOG_NUM_SI = $clog2(NUM_SI);
localparam LOG_NUM_MI = $clog2(NUM_MI);
typedef logic [NUM_SI-1:0] slave_vec_t;
typedef logic [LOG_NUM_SI-1:0] slave_index_t;
genvar i,j;
   
   logic       [NUM_SI-1:0] s_wvalid_q;
   logic       [NUM_SI-1:0] s_wready_q;
   logic [NUM_SI-1:0] [DATA_WIDTH-1:0] s_wdata_q;
   tile_id_t   [NUM_SI-1:0] s_port_q;
   
   logic       [NUM_MI-1:0] m_wvalid_p;
   logic       [NUM_MI-1:0] m_wready_p;
   logic [NUM_SI-1:0] [DATA_WIDTH-1:0] m_wdata_p;

// W Channel
slave_vec_t          [NUM_MI-1:0] w_sched_in;
slave_index_t        [NUM_MI-1:0] w_sched_out;
logic                [NUM_MI-1:0] w_can_take_new;

generate 
for (i=0;i<NUM_SI;i++) begin
   register_slice 
   #(
      .WIDTH($bits(s_wdata[i]) + $bits(s_port[i]) ),
      .STAGES(2)
   ) XBAR_IN_SLICE (
      .clk(clk),
      .rstn(rstn),

      .s_valid(s_wvalid[i]),
      .s_ready(s_wready[i]),
      .s_data ( {s_wdata[i], s_port[i]} ),
      
      .m_valid(s_wvalid_q[i]),
      .m_ready(s_wready_q[i]),
      .m_data ( {s_wdata_q[i], s_port_q[i]} )
   );
end
endgenerate

generate
for (i=0;i<NUM_MI;i++) begin : w_sched
   for (j=0;j<NUM_SI;j++) begin
      assign w_sched_in[i][j] = s_wvalid_q[j] & (i== s_port_q[j]);
   end
   assign w_can_take_new[i] = (!m_wvalid_p[i] | m_wready_p[i]); 

   rr_sched #(
      .OUT_WIDTH(LOG_NUM_SI),
      .IN_WIDTH(NUM_SI)
   ) W_SELECT (
      .clk(clk),
      .rstn(rstn),

      .in(w_sched_in[i]),
      .out(w_sched_out[i]),

      .advance(m_wvalid_p[i] & m_wready_p[i])
   );

   always @(posedge clk) begin
      if (!rstn) begin
         m_wvalid_p[i] <= 1'b0;
      end else begin
         if (s_wvalid_q[w_sched_out[i]] & s_wready_q[w_sched_out[i]] & 
               (s_port_q[ w_sched_out[i] ] == i) ) begin 
            m_wdata_p  [i] <= s_wdata_q [w_sched_out[i]];

            m_wvalid_p [i] <= 1'b1;
         end else if (m_wvalid_p[i] & m_wready_p[i]) begin
            m_wvalid_p [i] <= 1'b0;
         end
      end
   end
end
endgenerate

generate 
for (i=0;i <NUM_SI; i=i+1) begin   
   always_comb begin
      if (w_can_take_new[ s_port_q[i] ] & s_wvalid_q[i] & (i==w_sched_out[s_port_q[i]])) begin 
         // master can take new req & we are valid & scheduler chose us 
         s_wready_q[i] = 1'b1;
      end else begin
         s_wready_q[i] = 1'b0;
      end
   end
end
endgenerate

generate 
for (i=0;i<NUM_MI;i++) begin
   register_slice 
   #(
      .WIDTH($bits(s_wdata[i])),
      .STAGES(2)
   ) XBAR_OUT_SLICE (
      .clk(clk),
      .rstn(rstn),

      .s_valid(m_wvalid_p[i]),
      .s_ready(m_wready_p[i]),
      .s_data ( m_wdata_p[i]),
      
      .m_valid(m_wvalid[i]),
      .m_ready(m_wready[i]),
      .m_data ( m_wdata[i])
   );
end
endgenerate

endmodule
