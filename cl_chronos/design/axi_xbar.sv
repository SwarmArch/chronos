/** $lic$
 * Copyright (C) 2014-2019 by Massachusetts Institute of Technology
 *
 * This file is part of the Chronos FPGA Acceleration Framework.
 *
 * Chronos is free software; you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, version 2.
 *
 * If you use this framework in your research, we request that you reference
 * the Chronos paper ("Chronos: Efficient Speculative Parallelism for
 * Accelerators", Abeydeera and Sanchez, ASPLOS-25, March 2020), and that
 * you send us a citation of your work.
 *
 * Chronos is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */



import chronos::*;

module axi_xbar
#(
   parameter NUM_SI=4, 
   parameter NUM_MI=4,
   // use these bits of ID to route the response
   parameter RESP_ID_START = 10,
   parameter RESP_ID_PCI = 15
)
( 
	input clk,
	input rstn,
   
   input axi_id_t    [NUM_SI-1:0] s_awid,
   input axi_addr_t  [NUM_SI-1:0] s_awaddr,
   input axi_len_t   [NUM_SI-1:0] s_awlen,
   input axi_size_t  [NUM_SI-1:0] s_awsize,
   input logic       [NUM_SI-1:0] s_awvalid,
   output logic      [NUM_SI-1:0] s_awready,
   
   input axi_id_t    [NUM_SI-1:0] s_wid,
   input axi_data_t  [NUM_SI-1:0] s_wdata,
   input axi_strb_t  [NUM_SI-1:0] s_wstrb,
   input logic       [NUM_SI-1:0] s_wlast,
   input logic       [NUM_SI-1:0] s_wvalid,
   output logic      [NUM_SI-1:0] s_wready,

   output axi_id_t   [NUM_SI-1:0] s_bid,
   output axi_resp_t [NUM_SI-1:0] s_bresp,
   output logic      [NUM_SI-1:0] s_bvalid,
   input logic       [NUM_SI-1:0] s_bready,

   input axi_id_t    [NUM_SI-1:0] s_arid,
   input axi_addr_t  [NUM_SI-1:0] s_araddr,
   input axi_len_t   [NUM_SI-1:0] s_arlen,
   input axi_size_t  [NUM_SI-1:0] s_arsize,
   input logic       [NUM_SI-1:0] s_arvalid,
   output logic      [NUM_SI-1:0] s_arready,

   output axi_id_t   [NUM_SI-1:0] s_rid,
   output axi_data_t [NUM_SI-1:0] s_rdata,
   output axi_resp_t [NUM_SI-1:0] s_rresp,
   output logic      [NUM_SI-1:0] s_rlast,
   output logic      [NUM_SI-1:0] s_rvalid,
   input logic       [NUM_SI-1:0] s_rready,

   // which master should this request go to
   // (No '-1' because clog2(NUM_MI) could be 0) 
   // Note that dimension order is reversed because word is not a struct, 
   // (it is not possible to make it a struct because the width is
   // parameterized)

   output axi_id_t    [NUM_MI-1:0] m_awid,
   output axi_addr_t  [NUM_MI-1:0] m_awaddr,
   output axi_len_t   [NUM_MI-1:0] m_awlen,
   output axi_size_t  [NUM_MI-1:0] m_awsize,
   output logic       [NUM_MI-1:0] m_awvalid,
   input              [NUM_MI-1:0] m_awready,
   
   output axi_id_t    [NUM_MI-1:0] m_wid,
   output axi_data_t  [NUM_MI-1:0] m_wdata,
   output axi_strb_t  [NUM_MI-1:0] m_wstrb,
   output logic       [NUM_MI-1:0] m_wlast,
   output logic       [NUM_MI-1:0] m_wvalid,
   input              [NUM_MI-1:0] m_wready,

   input  axi_id_t    [NUM_MI-1:0] m_bid,
   input  axi_resp_t  [NUM_MI-1:0] m_bresp,
   input              [NUM_MI-1:0] m_bvalid,
   output logic       [NUM_MI-1:0] m_bready,

   output axi_id_t    [NUM_MI-1:0] m_arid,
   output axi_addr_t  [NUM_MI-1:0] m_araddr,
   output axi_len_t   [NUM_MI-1:0] m_arlen,
   output axi_size_t  [NUM_MI-1:0] m_arsize,
   output logic       [NUM_MI-1:0] m_arvalid,
   input              [NUM_MI-1:0] m_arready,

   input axi_id_t     [NUM_MI-1:0] m_rid,
   input axi_data_t   [NUM_MI-1:0] m_rdata,
   input axi_resp_t   [NUM_MI-1:0] m_rresp,
   input              [NUM_MI-1:0] m_rlast,
   input              [NUM_MI-1:0] m_rvalid,
   output logic       [NUM_MI-1:0] m_rready,

   input [2:0]        num_mem_ctrl
);

logic  [NUM_SI-1:0] [$clog2(NUM_MI):0] s_aw_port;
logic  [NUM_SI-1:0] [$clog2(NUM_MI):0] s_w_port;
logic  [NUM_SI-1:0] [$clog2(NUM_MI):0] s_ar_port;

localparam LOG_NUM_SI = $clog2(NUM_SI);
localparam LOG_NUM_MI = $clog2(NUM_MI);
typedef logic [NUM_SI-1:0] slave_vec_t;
typedef logic [NUM_MI-1:0] master_vec_t;
typedef logic [LOG_NUM_SI-1:0] slave_index_t;
typedef logic [LOG_NUM_MI-1:0] master_index_t;
genvar i,j;

// AW Channel
slave_vec_t          [NUM_MI-1:0] aw_sched_in;
slave_index_t        [NUM_MI-1:0] aw_sched_out;

logic                [NUM_MI-1:0] aw_can_take_new;
logic                [NUM_MI-1:0] w_can_take_new;

generate
for (i=0;i<NUM_SI;i++) begin
   always_comb begin
      if (num_mem_ctrl == 1) begin
         s_aw_port[i] = 2;
      end else if (num_mem_ctrl == 2) begin
         s_aw_port[i] = s_awaddr[i][6] ? 3 : 2;
      end else begin
         s_aw_port[i] = s_awaddr[i][7:6];
      end
   end
end

for (i=0;i<NUM_MI;i++) begin : aw_sched
   for (j=0;j<NUM_SI;j++) begin
      assign aw_sched_in[i][j] = s_awvalid[j] & (i== s_aw_port[j]);
   end
   assign aw_can_take_new[i] = (!m_awvalid[i] | m_awready[i]);
   assign w_can_take_new[i] = (!m_wvalid[i] | m_wready[i]); 

   rr_sched #(
      .OUT_WIDTH(LOG_NUM_SI),
      .IN_WIDTH(NUM_SI)
   ) AW_SELECT (
      .clk(clk),
      .rstn(rstn),

      .in(aw_sched_in[i]),
      .out(aw_sched_out[i]),

      .advance(m_awvalid[i] & m_awready[i])
   );

   always @(posedge clk) begin
      if (!rstn) begin
         m_awvalid[i] <= 1'b0;
         m_wvalid[i] <= 1'b0;
      end else begin
         if (s_awvalid[aw_sched_out[i]] & s_awready[aw_sched_out[i]] &
             s_wvalid[aw_sched_out[i]] & s_wready[aw_sched_out[i]] &
               (s_aw_port[ aw_sched_out[i] ] == i) ) begin 
            m_awid   [i] <= s_awid   [aw_sched_out[i]];
            if (num_mem_ctrl == 1) begin
               m_awaddr [i] <= {s_awaddr [aw_sched_out[i]][63:6], 6'b0};
            end else if (num_mem_ctrl == 2) begin
               m_awaddr [i] <= {1'b0, s_awaddr [aw_sched_out[i]][63:7], 6'b0};
            end else begin
               m_awaddr [i] <= {2'b0, s_awaddr [aw_sched_out[i]][63:8], 6'b0};
            end
            m_awlen  [i] <= s_awlen  [aw_sched_out[i]];
            m_awsize [i] <= s_awsize [aw_sched_out[i]];
            m_wid    [i] <= s_wid   [aw_sched_out[i]];
            m_wdata  [i] <= s_wdata [aw_sched_out[i]];
            m_wstrb  [i] <= s_wstrb [aw_sched_out[i]];
            m_wlast  [i] <= s_wlast [aw_sched_out[i]];


            m_awvalid[i] <= 1'b1;
            m_wvalid [i] <= 1'b1;

        end else begin
            if (m_awvalid[i] & m_awready[i]) begin
                m_awvalid[i] <= 1'b0;
            end 
            if (m_wvalid[i] & m_wready[i]) begin
                m_wvalid[i] <= 1'b0;
            end 
         end
      end
   end
end
endgenerate

generate 
for (i=0;i <NUM_SI; i=i+1) begin   
   always_comb begin
      if (aw_can_take_new[ s_aw_port[i] ] & s_awvalid[i] &
          w_can_take_new[s_aw_port[i]] & s_wvalid[i] &
          (i==aw_sched_out[s_aw_port[i]])) begin 
         // master can take new req & we are valid & scheduler chose us 
         s_awready[i] = 1'b1;
         s_wready[i] = 1'b1;
      end else begin
         s_awready[i] = 1'b0;
         s_wready[i] = 1'b0;
      end
   end

   always_ff @(posedge clk) begin
      if (s_awvalid[i] & s_awready[i]) begin
         s_w_port[i] <= s_aw_port[i];
      end
   end
end
endgenerate

/*
generate 
for (i=0; i<NUM_MI;i++) begin
   always_ff @(posedge clk) begin
      if (!rstn) begin
         waiting_for_w[i] <= 0;
      end else begin
         // If the AW channel consumed, set to 1, if not set to 0 if 
         // W channel consumed something
         if (s_awvalid[aw_sched_out[i]] & s_awready[aw_sched_out[i]] &
               (s_aw_port[ aw_sched_out[i] ] == i) ) begin 
            waiting_for_w[i] <= 1;
         end else if (s_wvalid[w_sched_out[i]] & s_wready[w_sched_out[i]] & 
                  (s_w_port[ w_sched_out[i] ] == i) ) begin 
            waiting_for_w[i] <= 0;
         end
      end
   end
end

endgenerate

// W Channel


generate
for (i=0;i<NUM_MI;i++) begin : w_sched
   assign w_can_take_new[i] = (!m_wvalid[i] | m_wready[i]) & waiting_for_w[i]; 

   always @(posedge clk) begin
      if (!rstn) begin
         m_wvalid[i] <= 1'b0;
      end else begin
         if (s_wvalid[w_sched_out[i]] & s_wready[w_sched_out[i]] & 
               (s_w_port[ w_sched_out[i] ] == i) ) begin 
            m_wid    [i] <= s_wid   [w_sched_out[i]];
            m_wdata  [i] <= s_wdata [w_sched_out[i]];
            m_wstrb  [i] <= s_wstrb [w_sched_out[i]];
            m_wlast  [i] <= s_wlast [w_sched_out[i]];

            m_wvalid [i] <= 1'b1;
         end else if (m_wvalid[i] & m_wready[i]) begin
            m_wvalid [i] <= 1'b0;
         end
      end
   end
end
endgenerate

generate 
for (i=0;i <NUM_SI; i=i+1) begin   
   always_comb begin
      if (w_can_take_new[ s_w_port[i] ] & s_wvalid[i] & (i==w_sched_out[s_w_port[i]])) begin 
         // master can take new req & we are valid & scheduler chose us 
         s_wready[i] = 1'b1;
      end else begin
         s_wready[i] = 1'b0;
      end
   end
end
endgenerate
*/

// AR Channel
slave_vec_t          [NUM_MI-1:0] ar_sched_in;
slave_index_t        [NUM_MI-1:0] ar_sched_out;
logic                [NUM_MI-1:0] ar_can_take_new;


generate
for (i=0;i<NUM_SI;i++) begin
   always_comb begin
      if (num_mem_ctrl == 1) begin
         s_ar_port[i] = 2;
      end else if (num_mem_ctrl == 2) begin
         s_ar_port[i] = s_araddr[i][6] ? 3 :2 ;
      end else begin
         s_ar_port[i] = s_araddr[i][7:6];
      end
   end
end
for (i=0;i<NUM_MI;i++) begin : ar_sched
   for (j=0;j<NUM_SI;j++) begin
      assign ar_sched_in[i][j] = s_arvalid[j] & (i== s_ar_port[j]);
   end
   assign ar_can_take_new[i] = (!m_arvalid[i] | m_arready[i]); 

   rr_sched #(
      .OUT_WIDTH(LOG_NUM_SI),
      .IN_WIDTH(NUM_SI)
   ) AR_SELECT (
      .clk(clk),
      .rstn(rstn),

      .in(ar_sched_in[i]),
      .out(ar_sched_out[i]),

      .advance(m_arvalid[i] & m_arready[i])
   );

   always @(posedge clk) begin
      if (!rstn) begin
         m_arvalid[i] <= 1'b0;
      end else begin
         if (s_arvalid[ar_sched_out[i]] & s_arready[ar_sched_out[i]] & 
               (s_ar_port[ ar_sched_out[i] ] == i) ) begin 
            m_arid   [i] <= s_arid   [ar_sched_out[i]];
            if (num_mem_ctrl == 1) begin
               m_araddr [i] <= {s_araddr [ar_sched_out[i]][63:6], 6'b0};
            end else if (num_mem_ctrl == 2) begin
               m_araddr [i] <= {1'b0, s_araddr [ar_sched_out[i]][63:7], 6'b0};
            end else begin
               m_araddr [i] <= {2'b0, s_araddr [ar_sched_out[i]][63:8], 6'b0};
            end
            m_arlen  [i] <= s_arlen  [ar_sched_out[i]];
            m_arsize [i] <= s_arsize [ar_sched_out[i]];

            m_arvalid[i] <= 1'b1;
         end else if (m_arvalid[i] & m_arready[i]) begin
            m_arvalid[i] <= 1'b0;
         end
      end
   end
end
endgenerate

generate 
for (i=0;i <NUM_SI; i=i+1) begin   
   always_comb begin
      if (ar_can_take_new[ s_ar_port[i] ] & s_arvalid[i] & (i==ar_sched_out[s_ar_port[i]])) begin 
         // master can take new req & we are valid & scheduler chose us 
         s_arready[i] = 1'b1;
      end else begin
         s_arready[i] = 1'b0;
      end
   end
end
endgenerate

// B Channel
master_vec_t         [NUM_SI-1:0] b_sched_in;
master_index_t       [NUM_SI-1:0] b_sched_out;
logic                [NUM_SI-1:0] b_can_take_new;

logic [NUM_MI-1:0] [$clog2(NUM_SI):0] m_b_port;

generate
for (i=0;i<NUM_MI;i++) begin
   if (NUM_SI==2) begin 
      assign m_b_port[i] = m_bid[i][RESP_ID_PCI] ? 1 : 0;
   end else begin
      assign m_b_port[i] = m_bid[i][RESP_ID_PCI] ? 
         (m_bid[i][RESP_ID_START + $clog2(N_TILES) -1 -: $clog2(NUM_SI-1)] + 1) : 0;
   end
end

for (i=0;i<NUM_SI;i++) begin : b_sched
   for (j=0;j<NUM_MI;j++) begin
      assign b_sched_in[i][j] = m_bvalid[j] & (i== m_b_port[j]);
   end
   assign b_can_take_new[i] = (!s_bvalid[i] | s_bready[i]); 

   rr_sched #(
      .OUT_WIDTH(LOG_NUM_MI),
      .IN_WIDTH(NUM_MI)
   ) B_SELECT (
      .clk(clk),
      .rstn(rstn),

      .in(b_sched_in[i]),
      .out(b_sched_out[i]),

      .advance(s_bvalid[i] & s_bready[i])
   );

   always @(posedge clk) begin
      if (!rstn) begin
         s_bvalid[i] <= 1'b0;
      end else begin
         if (m_bvalid[b_sched_out[i]] & m_bready[b_sched_out[i]] & 
               ( m_b_port[ b_sched_out[i] ] == i) ) begin 
            s_bid    [i] <= m_bid    [b_sched_out[i]];
            s_bresp  [i] <= m_bresp  [b_sched_out[i]];

            s_bvalid[i] <= 1'b1;
         end else if (s_bvalid[i] & s_bready[i]) begin
            s_bvalid[i] <= 1'b0;
         end
      end
   end
end
endgenerate

generate 
for (i=0;i <NUM_MI; i=i+1) begin   
   always_comb begin
      if (b_can_take_new[ m_b_port[i] ] 
         & m_bvalid[i] 
         & (i==b_sched_out[ m_b_port[i] ])) begin 
         // slave can take new resp & we are valid & scheduler chose us 
         m_bready[i] = 1'b1;
      end else begin
         m_bready[i] = 1'b0;
      end
   end
end
endgenerate

// R Channel
master_vec_t         [NUM_SI-1:0] r_sched_in;
master_index_t       [NUM_SI-1:0] r_sched_out;
logic                [NUM_SI-1:0] r_can_take_new;

logic [NUM_MI-1:0] [$clog2(NUM_SI):0] m_r_port;

generate
for (i=0;i<NUM_MI;i++) begin
   if (NUM_SI==2) begin 
      assign m_r_port[i] = m_rid[i][RESP_ID_PCI] ? 1 : 0;
   end else begin
      assign m_r_port[i] = m_rid[i][RESP_ID_PCI] ? 
         (m_rid[i][RESP_ID_START + $clog2(N_TILES) -1 -: $clog2(NUM_SI-1)] + 1) : 0;
   end
end

for (i=0;i<NUM_SI;i++) begin : r_sched
   for (j=0;j<NUM_MI;j++) begin
      assign r_sched_in[i][j] = m_rvalid[j] & (i== m_r_port[j]);
   end
   assign r_can_take_new[i] = (!s_rvalid[i] | s_rready[i]); 

   rr_sched #(
      .OUT_WIDTH(LOG_NUM_MI),
      .IN_WIDTH(NUM_MI)
   ) R_SELECT (
      .clk(clk),
      .rstn(rstn),

      .in(r_sched_in[i]),
      .out(r_sched_out[i]),

      .advance(s_rvalid[i] & s_rready[i])
   );

   always @(posedge clk) begin
      if (!rstn) begin
         s_rvalid[i] <= 1'b0;
      end else begin
         if (m_rvalid[r_sched_out[i]] & m_rready[r_sched_out[i]] & 
               ( m_r_port[ r_sched_out[i] ] == i) ) begin 
            s_rid    [i] <= m_rid    [r_sched_out[i]];
            s_rresp  [i] <= m_rresp  [r_sched_out[i]];
            s_rdata  [i] <= m_rdata  [r_sched_out[i]];
            s_rlast  [i] <= m_rlast  [r_sched_out[i]];

            s_rvalid[i] <= 1'b1;
         end else if (s_rvalid[i] & s_rready[i]) begin
            s_rvalid[i] <= 1'b0;
         end
      end
   end
end
endgenerate

generate 
for (i=0;i <NUM_MI; i=i+1) begin   
   always_comb begin
      if (r_can_take_new[ m_r_port[i] ] 
         & m_rvalid[i] 
         & (i==r_sched_out[ m_r_port[i] ])) begin 
         // slave can take new resp & we are valid & scheduler chose us 
         m_rready[i] = 1'b1;
      end else begin
         m_rready[i] = 1'b0;
      end
   end
end
endgenerate

endmodule
