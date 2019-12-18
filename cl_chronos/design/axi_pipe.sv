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


module axi_pipe
#( 
   parameter STAGES = 1,
   parameter NO_RESP = 0, // only register AW,W,AR channels
   parameter WRITE_TOGETHER = 1
) (
   input clk,
   input rstn,
   axi_bus_t in,
   axi_bus_t out
);

logic i_awvalid;
logic i_wvalid;
logic i_awready;
logic i_wready;

generate 
if (WRITE_TOGETHER) begin
    assign out.awvalid = i_awvalid & i_wvalid;
    assign out.wvalid = i_awvalid & i_wvalid;
    assign i_awready = out.awready & out.wready & out.awvalid;
    assign i_wready = out.awready & out.wready & out.awvalid;
end else begin
    assign out.awvalid = i_awvalid;
    assign out.wvalid = i_wvalid;
    assign i_awready = out.awready;
    assign i_wready = out.wready;
end
endgenerate

register_slice
#(
   .WIDTH(16+64+8+3),
   .STAGES(STAGES)
)
AW_SLICE (
   .clk(clk),
   .rstn(rstn),

   .s_valid(in.awvalid),
   .s_ready(in.awready),
   
   .m_valid(i_awvalid),
   .m_ready(i_awready),

   .s_data( { in.awid,  in.awaddr,  in.awlen,  in.awsize}),
   .m_data( {out.awid, out.awaddr, out.awlen, out.awsize})

);

register_slice
#(
   .WIDTH(16+512+64+1),
   .STAGES(STAGES)
)
W_SLICE (
   .clk(clk),
   .rstn(rstn),

   .s_valid(in.wvalid),
   .s_ready(in.wready),
   
   .m_valid(i_wvalid),
   .m_ready(i_wready),

   .s_data( { in.wid,  in.wdata,  in.wstrb,  in.wlast}),
   .m_data( {out.wid, out.wdata, out.wstrb, out.wlast})

);

register_slice
#(
   .WIDTH(16+64+8+3),
   .STAGES(STAGES)
)
AR_SLICE (
   .clk(clk),
   .rstn(rstn),

   .s_valid(in.arvalid),
   .s_ready(in.arready),
   
   .m_valid(out.arvalid),
   .m_ready(out.arready),

   .s_data( { in.arid,  in.araddr,  in.arlen,  in.arsize}),
   .m_data( {out.arid, out.araddr, out.arlen, out.arsize})

);

register_slice
#(
   .WIDTH(16+512+1+2),
   .STAGES(NO_RESP ? 0 : STAGES)
)
R_SLICE (
   .clk(clk),
   .rstn(rstn),

   .s_valid(out.rvalid),
   .s_ready(out.rready),
   
   .m_valid(in.rvalid),
   .m_ready(in.rready),

   .s_data( {out.rid, out.rdata, out.rlast, out.rresp}),
   .m_data( { in.rid,  in.rdata,  in.rlast,  in.rresp})

);

register_slice
#(
   .WIDTH(16+2),
   .STAGES(STAGES)
)
B_SLICE (
   .clk(clk),
   .rstn(rstn),

   .s_valid(out.bvalid),
   .s_ready(out.bready),
   
   .m_valid(in.bvalid),
   .m_ready(in.bready),

   .s_data( {out.bid, out.bresp}),
   .m_data( { in.bid,  in.bresp})

);

endmodule

module axi_mux
#( 
   parameter ID_BIT = 0,
   parameter DELAY = 1
) (
   input clk,
   input rstn,
   axi_bus_t.master a,
   axi_bus_t.master b,

   axi_bus_t.slave out_q
);

axi_bus_t out();

typedef enum logic[0:0] {
   A,
   B
} axi_port_id;

// priority given to this port
axi_port_id last_aw_sel, last_ar_sel;

logic awsel, arsel; //0-A, 1-B
logic w_waiting, w_wait_sel;
always_ff @(posedge clk) begin
   if (!rstn) begin
      w_waiting <= 1'b0;
   end else begin
      if ((a.awvalid & a.awready) & !(a.wvalid & a.wready)) begin
         w_waiting <= 1;
         w_wait_sel <= 0;
      end else if ((b.awvalid & b.awready) & !(b.wvalid & b.wready)) begin
         w_waiting <= 1;
         w_wait_sel <= 1;
      end else if (w_waiting) begin
         if (!w_wait_sel & a.wvalid & a.wready & !(a.awvalid & a.awready)) begin
            w_waiting <= 0;
         end else if (w_wait_sel & b.wvalid & b.wready & !(b.awvalid & b.awready) ) begin
            w_waiting <= 0;
         end
      end
   end
end

always_ff @(posedge clk) begin
   if (!rstn) begin
      last_ar_sel <= A;
      last_aw_sel <= A;
   end else begin 
      if (a.awvalid & a.awready) last_aw_sel <= A;
      else if (b.awvalid & b.awready) last_aw_sel <= B;

      if (a.arvalid & a.arready) last_ar_sel <= A;
      else if (b.arvalid & b.arready) last_ar_sel <= B;
   end
end

always_comb begin
   // only give in to the other if the priority port is not valid
   if (last_ar_sel == B) begin
      arsel = !a.arvalid;
   end else begin
      arsel = b.arvalid;
   end

   if (w_waiting) begin
      awsel = w_wait_sel;
   end else begin
      if (last_aw_sel == B) begin
         awsel = !a.awvalid;
      end else begin
         awsel = b.awvalid;
      end
   end
end

always_comb begin

   if (!awsel) begin
      out.awid       = a.awid;
      out.awaddr     = a.awaddr;
      out.awvalid    = a.awvalid & !w_waiting & (out.awready & out.wready);
      out.awlen      = a.awlen;
      out.awsize     = a.awsize;

      out.wid        = a.wid;
      out.wdata      = a.wdata;
      out.wstrb      = a.wstrb;
      out.wlast      = a.wlast;
      out.wvalid     = a.wvalid;
      
   end else begin
      out.awid       = b.awid;
      out.awaddr     = b.awaddr;
      out.awvalid    = b.awvalid & !w_waiting;
      out.awlen      = b.awlen;
      out.awsize     = b.awsize;

      out.wid        = b.wid;
      out.wdata      = b.wdata;
      out.wstrb      = b.wstrb;
      out.wlast      = b.wlast;
      out.wvalid     = b.wvalid;
   end
end

always_comb begin
   if (!arsel) begin
      out.arid       = a.arid;
      out.araddr     = a.araddr;
      out.arvalid    = a.arvalid;
      out.arlen      = a.arlen;
      out.arsize     = a.arsize;
   end else begin
      out.arid       = b.arid;
      out.araddr     = b.araddr;
      out.arvalid    = b.arvalid;
      out.arlen      = b.arlen;
      out.arsize     = b.arsize;
   end
end

assign a.awready = out.awready & !awsel & !w_waiting ;
assign a.wready  = out.wready & !awsel ;
assign a.arready = out.arready & !arsel;
assign b.awready = out.awready & awsel  & !w_waiting;
assign b.wready  = out.wready & awsel ;
assign b.arready = out.arready & arsel;

assign out.bready = out.bid[ID_BIT] ? b.bready : a.bready;
assign out.rready = out.rid[ID_BIT] ? b.rready : a.rready;

assign a.bvalid = out.bvalid & !out.bid[ID_BIT];
assign b.bvalid = out.bvalid &  out.bid[ID_BIT];
assign a.rvalid = out.rvalid & !out.rid[ID_BIT];
assign b.rvalid = out.rvalid &  out.rid[ID_BIT];

assign a.bresp = out.bresp;
assign a.bid = out.bid;
assign b.bresp = out.bresp;
assign b.bid = out.bid;

assign a.rresp = out.rresp;
assign a.rid   = out.rid;
assign a.rdata = out.rdata;
assign a.rlast = out.rlast;

assign b.rresp = out.rresp;
assign b.rid   = out.rid;
assign b.rdata = out.rdata;
assign b.rlast = out.rlast;

   axi_pipe 
   #(
      .STAGES(DELAY)
   ) AXI_PIPE (
      .clk(clk),
      .rstn(rstn),

      .in(out),
      .out(out_q)
   );

endmodule

module axi_debug(
   input clk,
   input rstn,

   axi_bus_t.snoop a,
   axi_bus_t.snoop b,
   axi_bus_t.snoop out,


   pci_debug_bus_t.master                 pci_debug,
   reg_bus_t.master                       reg_bus

);

// Ideally this should be in the top-level config.sv
// However this should be very rarely used, so putting it here.
// Also helps maintain backwards compatibility with validation scripts
localparam AXI_DEBUG=0;

   logic log_valid;
   typedef struct packed {
        
      logic [31:0] a_awaddr;
      logic [31:0] b_awaddr;
      logic [31:0] out_awaddr;
      logic [15:0] a_awid;
      logic [15:0] a_wid;
      logic [15:0] b_awid;
      logic [15:0] b_wid;
      logic [15:0] out_awid;
      logic [15:0] out_wid;

      logic [19:0] unused_1;
      logic a_awvalid;
      logic a_awready;
      logic a_wvalid;
      logic a_wready;
      logic b_awvalid;
      logic b_awready;
      logic b_wvalid;
      logic b_wready;
      logic out_awvalid;
      logic out_awready;
      logic out_wvalid;
      logic out_wready;



   } axi_log_t;
   axi_log_t log_word;

logic [LOG_LOG_DEPTH:0] log_size; 
always_comb begin
   log_word = 0;
      log_word.a_awaddr = a.awaddr;
      log_word.b_awaddr = b.awaddr;
      log_word.out_awaddr = out.awaddr;
      log_word.a_awid = a.awid;
      log_word.b_awid = b.awid;
      log_word.out_awid = out.awid;
      log_word.a_wid = a.wid;
      log_word.b_wid = b.wid;
      log_word.out_wid = out.wid;

      log_word.a_awvalid = a.awvalid;
      log_word.a_awready = a.awready;
      log_word.a_wvalid = a.wvalid;
      log_word.a_wready = a.wready;
      log_word.b_awvalid = b.awvalid;
      log_word.b_awready = b.awready;
      log_word.b_wvalid = b.wvalid;
      log_word.b_wready = b.wready;
      log_word.out_awvalid = out.awvalid;
      log_word.out_awready = out.awready;
      log_word.out_wvalid = out.wvalid;
      log_word.out_wready = out.wready;

      log_valid = (a.awvalid | a.wvalid | b.awvalid | b.wvalid | out.awvalid | out.wvalid);
end
generate
if (AXI_DEBUG) begin
   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) AXI_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid(log_valid),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end else begin 
    assign log_size=0;
end
endgenerate


always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_bus.rvalid <= 1'b0;
      reg_bus.rdata <= 'x;
   end else
   if (reg_bus.arvalid) begin
      reg_bus.rvalid <= 1'b1;
      case (reg_bus.araddr) 
         DEBUG_CAPACITY : reg_bus.rdata <= log_size;
      endcase
   end
end

endmodule
