
import swarm::*;

module l2_arbiter
#(parameter NUM_SI)
( 
	input clk,
	input rstn,
   // _id[15:4] designates the master
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
	
   axi_bus_t.slave  l2
);

localparam LOG_NUM_SI = $clog2(NUM_SI);

// AW Channel
logic [LOG_NUM_SI-1:0] aw_select;
logic aw_can_take_new;

lowbit #(
   .OUT_WIDTH(LOG_NUM_SI),
   .IN_WIDTH(NUM_SI)
) AW_SELECT (
   .in(s_awvalid),
   .out(aw_select)
);

assign aw_can_take_new = (!l2.awvalid | l2.awready); 

logic [63:0] r_awaddr;
logic [511:0] r_wdata;
logic [63:0] r_wstrb;

assign l2.awaddr = {r_awaddr[63:6], 6'b0};

always @(posedge clk) begin
   if (!rstn) begin
      l2.awvalid <= 1'b0;
      l2.wvalid  <= 1'b0;
   end else begin
      if (s_awvalid[aw_select] & s_awready[aw_select]) begin 
         l2.awid    <= s_awid   [aw_select];
         r_awaddr  <= s_awaddr [aw_select];
         l2.awlen   <= s_awlen  [aw_select];
         l2.awsize  <= s_awsize [aw_select];

         l2.wid     <= s_wid    [aw_select];
         r_wdata   <= s_wdata  [aw_select];
         r_wstrb   <= s_wstrb  [aw_select];
         l2.wlast   <= s_wlast  [aw_select];

         l2.awvalid <= 1'b1;
         l2.wvalid  <= 1'b1;
      end else if (l2.awvalid & l2.awready) begin
         l2.awvalid <= 1'b0;
         l2.wvalid  <= 1'b0;
      end
   end
end

always_comb begin
   l2.wstrb = 0;
   l2.wdata = 'x;
   case (l2.awsize) 
      0: begin
         l2.wstrb[r_awaddr[5:0]*1 +:1]      = r_wstrb[0];
         l2.wdata[r_awaddr[5:0]*8 +:8]      = r_wdata[7:0];
      end
      1: begin
         l2.wstrb[r_awaddr[5:1]* 2 +: 2]    = r_wstrb[ 1:0];
         l2.wdata[r_awaddr[5:1]*16 +:16]    = r_wdata[15:0];
      end
      2: begin
         l2.wstrb[r_awaddr[5:2]* 4 +: 4]    = r_wstrb[ 3:0];
         l2.wdata[r_awaddr[5:2]*32 +:32]    = r_wdata[31:0];
      end
      3: begin
         l2.wstrb[r_awaddr[5:3]* 8 +: 8]    = r_wstrb[ 7:0];
         l2.wdata[r_awaddr[5:3]*64 +:64]    = r_wdata[63:0];
      end
      4: begin
         l2.wstrb[r_awaddr[5:4]* 16 +: 16]  = r_wstrb[ 15:0];
         l2.wdata[r_awaddr[5:4]*128 +:128]  = r_wdata[127:0];
      end
      5: begin
         l2.wstrb[r_awaddr[5]* 32 +: 32]    = r_wstrb[ 31:0];
         l2.wdata[r_awaddr[5]*256 +:256]    = r_wdata[255:0];
      end
      default: begin
         l2.wstrb                         = r_wstrb;
         l2.wdata                         = r_wdata;
      end
   endcase
end

always_comb begin
   for (integer i=0;i <NUM_SI; i=i+1) begin   
      if (aw_can_take_new & s_awvalid[i] & (i==aw_select)) begin 
         s_awready[i] = 1'b1;
         s_wready[i] = 1'b1;
      end else begin
         s_awready[i] = 1'b0;
         s_wready[i] = 1'b0;
      end
   end
end

// AR Channel
logic [LOG_NUM_SI-1:0] ar_select;
logic ar_can_take_new;

lowbit #(
   .OUT_WIDTH(LOG_NUM_SI),
   .IN_WIDTH(NUM_SI)
) AR_SELECT (
   .in(s_arvalid),
   .out(ar_select)
);

assign ar_can_take_new = (!l2.arvalid | l2.arready); 

always @(posedge clk) begin
   if (!rstn) begin
      l2.arvalid <= 1'b0;
   end else begin
      if (s_arvalid[ar_select] & s_arready[ar_select]) begin 
         l2.arid    <= s_arid   [ar_select];
         l2.araddr  <= s_araddr [ar_select];
         l2.arlen   <= s_arlen  [ar_select];
         l2.arsize  <= s_arsize [ar_select];

         l2.arvalid <= 1'b1;
      end else if (l2.arvalid & l2.arready) begin
         l2.arvalid <= 1'b0;
      end
   end
end

always_comb begin
   for (integer i=0;i <NUM_SI; i=i+1) begin   
      if (ar_can_take_new & s_arvalid[i] & (i==ar_select)) begin 
         s_arready[i] = 1'b1;
      end else begin
         s_arready[i] = 1'b0;
      end
   end
end

// B Channel
logic b_can_take_new;
axi_id_t reg_bid;
axi_resp_t reg_bresp;
logic reg_bvalid;

always @(posedge clk) begin
   if (!rstn) begin
      reg_bvalid <= 1'b0;
      reg_bid <= 0;
      reg_bresp <= 0;
   end else begin
      if (l2.bvalid) begin
         if (l2.bready) begin
            reg_bvalid <= 1'b1;
            reg_bid <= l2.bid;
            reg_bresp <= l2.bresp;
         end
      end else if (reg_bvalid & b_can_take_new) begin
            reg_bvalid <= 1'b0;
      end
   end
end

assign l2.bready = !reg_bvalid |  b_can_take_new;
always_comb begin
   b_can_take_new = 1'b0;
   for (integer i=0;i<NUM_SI;i=i+1) begin
      s_bid[i] = reg_bid;
      s_bresp[i] = reg_bresp;
      if (reg_bvalid & (reg_bid[9:4] == i)) begin
         s_bvalid[i] = 1'b1;
      end else begin
         s_bvalid[i] = 1'b0;
      end 
      if (s_bvalid[i] & s_bready[i]) begin
         b_can_take_new = 1'b1;
      end
   end

end

// R Channel
logic r_can_take_new;
axi_id_t reg_rid;
axi_resp_t reg_rresp;
axi_data_t reg_rdata;
logic reg_rlast;
logic reg_rvalid;

always @(posedge clk) begin
   if (!rstn) begin
      reg_rvalid <= 1'b0;
      reg_rid <= 0;
      reg_rresp <= 0;
      reg_rdata <= 0;
      reg_rlast <= 0;
   end else begin
      if (l2.rvalid) begin
         if (l2.rready) begin
            reg_rvalid <= 1'b1;
            reg_rid <= l2.rid;
            reg_rresp <= l2.rresp;
            reg_rdata <= l2.rdata;
            reg_rlast <= l2.rlast;
         end 
      end else if (reg_rvalid & r_can_take_new) begin
            reg_rvalid <= 1'b0;
      end
   end
end

assign l2.rready = !reg_rvalid |  r_can_take_new;
always_comb begin
   r_can_take_new = 1'b0;
   for (integer i=0;i<NUM_SI;i=i+1) begin
      s_rid[i] = reg_rid;
      s_rresp[i] = reg_rresp;
      s_rdata[i] = reg_rdata;
      s_rlast[i] = reg_rlast;
      if (reg_rvalid & (reg_rid[9:4] == i)) begin
         s_rvalid[i] = 1'b1;
      end else begin
         s_rvalid[i] = 1'b0;
      end 
      if (s_rvalid[i] & s_rready[i]) begin
         r_can_take_new = 1'b1;
      end
   end

end
endmodule
