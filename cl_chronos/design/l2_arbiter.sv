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

module l2_arbiter
#(parameter NUM_SI=12, NUM_MI=1)
( 
	input clk,
	input rstn,
   // _id[15:8] designates the master
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

   input             s_prefetch_valid, 
   input axi_addr_t  s_prefetch_addr, 
	
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

   input axi_id_t     [NUM_MI-1:0] m_bid,
   input axi_resp_t   [NUM_MI-1:0] m_bresp,
   input logic        [NUM_MI-1:0] m_bvalid,
   output logic       [NUM_MI-1:0] m_bready,

   output axi_id_t    [NUM_MI-1:0] m_arid,
   output axi_addr_t  [NUM_MI-1:0] m_araddr,
   output axi_len_t   [NUM_MI-1:0] m_arlen,
   output axi_size_t  [NUM_MI-1:0] m_arsize,
   output logic       [NUM_MI-1:0] m_arvalid,
   input logic        [NUM_MI-1:0] m_arready,

   input axi_id_t     [NUM_MI-1:0] m_rid,
   input axi_data_t   [NUM_MI-1:0] m_rdata,
   input axi_resp_t   [NUM_MI-1:0] m_rresp,
   input logic        [NUM_MI-1:0] m_rlast,
   input logic        [NUM_MI-1:0] m_rvalid,
   output logic       [NUM_MI-1:0] m_rready,
   
   output logic       [NUM_MI-1:0] m_prefetch_valid, 
   input              [NUM_MI-1:0] m_prefetch_ready, 
   output axi_addr_t  [NUM_MI-1:0] m_prefetch_addr 
);

localparam LOG_NUM_SI = $clog2(NUM_SI);
localparam LOG_NUM_MI = NUM_MI == 1 ? 1 : $clog2(NUM_MI);

logic  [NUM_SI-1:0] [LOG_NUM_MI:0] s_aw_port;
logic  [NUM_SI-1:0] [LOG_NUM_MI:0] s_ar_port;

typedef logic [NUM_SI-1:0] slave_vec_t;
typedef logic [NUM_MI-1:0] master_vec_t;
typedef logic [LOG_NUM_SI-1:0] slave_index_t;
typedef logic [LOG_NUM_MI-1:0] master_index_t;
genvar i,j;

// AW Channel
slave_vec_t          [NUM_MI-1:0] aw_sched_in;
slave_index_t        [NUM_MI-1:0] aw_sched_out;
logic                [NUM_MI-1:0] aw_can_take_new;

axi_addr_t [NUM_MI-1:0] r_awaddr;
axi_data_t [NUM_MI-1:0] r_wdata;
axi_strb_t [NUM_MI-1:0] r_wstrb;

generate
for (i=0;i<NUM_SI;i++) begin
   assign s_aw_port[i] = (NUM_MI == 1) ? 0 : ^(s_awaddr[i][31:6]);
end

for (i=0;i<NUM_MI;i++) begin : aw_sched
   for (j=0;j<NUM_SI;j++) begin
      assign aw_sched_in[i][j] = s_awvalid[j] & (i== s_aw_port[j]);
   end
   assign aw_can_take_new[i] = (!m_awvalid[i] | m_awready[i]);

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
               (s_aw_port[ aw_sched_out[i] ] == i) ) begin 
            m_awid   [i] <= s_awid   [aw_sched_out[i]];
            r_awaddr [i] <= s_awaddr [aw_sched_out[i]];
            m_awlen  [i] <= s_awlen  [aw_sched_out[i]];
            m_awsize [i] <= s_awsize [aw_sched_out[i]];
            
            m_wid    [i] <= s_wid   [aw_sched_out[i]];
            r_wdata  [i] <= s_wdata [aw_sched_out[i]];
            r_wstrb  [i] <= s_wstrb [aw_sched_out[i]];
            m_wlast  [i] <= s_wlast [aw_sched_out[i]];
         

            m_awvalid[i] <= 1'b1;
            m_wvalid[i] <= 1'b1;

         end else if (m_awvalid[i] & m_awready[i]) begin
            m_awvalid[i] <= 1'b0;
            m_wvalid[i] <= 1'b0;
         end
      end
   end
end
endgenerate
generate 
for (i=0;i <NUM_SI; i=i+1) begin   
   always_comb begin
      if (aw_can_take_new[ s_aw_port[i] ] & s_awvalid[i] & (i==aw_sched_out[s_aw_port[i]])) begin 
         // master can take new req & we are valid & scheduler chose us 
         s_awready[i] = 1'b1;
         s_wready[i] = 1'b1;
      end else begin
         s_awready[i] = 1'b0;
         s_wready[i] = 1'b0;
      end
   end
end 
for (i=0;i<NUM_MI;i=i+1) begin
   
   assign m_awaddr[i] = {r_awaddr[i][63:6], 6'b0};
   always_comb begin
      m_wstrb[i] = 0;
      m_wdata[i] = 'x;
      case (m_awsize[i]) 
         0: begin
            m_wstrb[i][r_awaddr[i][5:0]*1 +:1]      = r_wstrb[i][0];
            m_wdata[i][r_awaddr[i][5:0]*8 +:8]      = r_wdata[i][7:0];
         end
         1: begin
            m_wstrb[i][r_awaddr[i][5:1]* 2 +: 2]    = r_wstrb[i][ 1:0];
            m_wdata[i][r_awaddr[i][5:1]*16 +:16]    = r_wdata[i][15:0];
         end
         2: begin
            m_wstrb[i][r_awaddr[i][5:2]* 4 +: 4]    = r_wstrb[i][ 3:0];
            m_wdata[i][r_awaddr[i][5:2]*32 +:32]    = r_wdata[i][31:0];
         end
         3: begin
            m_wstrb[i][r_awaddr[i][5:3]* 8 +: 8]    = r_wstrb[i][ 7:0];
            m_wdata[i][r_awaddr[i][5:3]*64 +:64]    = r_wdata[i][63:0];
         end
         4: begin
            m_wstrb[i][r_awaddr[i][5:4]* 16 +: 16]  = r_wstrb[i][ 15:0];
            m_wdata[i][r_awaddr[i][5:4]*128 +:128]  = r_wdata[i][127:0];
         end
         5: begin
            m_wstrb[i][r_awaddr[i][5]* 32 +: 32]    = r_wstrb[i][ 31:0];
            m_wdata[i][r_awaddr[i][5]*256 +:256]    = r_wdata[i][255:0];
         end
         default: begin
            m_wstrb[i]                         = r_wstrb[i];
            m_wdata[i]                         = r_wdata[i];
         end
      endcase
   end

end
endgenerate


// AR Channel
slave_vec_t          [NUM_MI-1:0] ar_sched_in;
slave_index_t        [NUM_MI-1:0] ar_sched_out;
logic                [NUM_MI-1:0] ar_can_take_new;


generate
for (i=0;i<NUM_SI;i++) begin
   assign s_ar_port[i] = (NUM_MI == 1) ? 0 : ^(s_araddr[i][31:6]);
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
            m_araddr [i] <= s_araddr [ar_sched_out[i]];
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
   assign m_b_port[i] = m_bid[i][10 +: LOG_NUM_SI ]; 
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
   assign m_r_port[i] = m_rid[i][10 +: LOG_NUM_SI ]; 
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

// Prefetch

logic [LOG_NUM_MI:0] prefetch_port; 
assign prefetch_port = (NUM_MI == 1) ? 0 : ^(s_prefetch_addr[31:6]);
generate
for (i=0;i<NUM_MI;i++) begin : prefetch
   always @(posedge clk) begin
      if (!rstn) begin
         m_prefetch_valid[i] <= 1'b0;
      end else begin
         if (s_prefetch_valid  &  
               (prefetch_port == i) ) begin 
            m_prefetch_valid[i] <= 1'b1;
            m_prefetch_addr[i] <= s_prefetch_addr;
         end else if (m_prefetch_valid[i] & m_prefetch_ready[i]) begin
            m_prefetch_valid[i] <= 1'b0;
         end
      end
   end
end
endgenerate
endmodule
