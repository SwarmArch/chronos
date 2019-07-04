// FWFT FIFO
module fifo #(
      parameter WIDTH = 32,
      parameter LOG_DEPTH = 1
) (
   input  clk,
   input  rstn,

   input wr_en,
   input rd_en,
   input [WIDTH-1:0] wr_data,

   output logic full, 
   output logic empty,  // aka out_valid
   output logic [WIDTH-1:0] rd_data,

   // optional port. Hopefully should not be synthesized if not connected
   output logic [LOG_DEPTH:0] size
);

   logic [LOG_DEPTH:0] wr_ptr, rd_ptr, next_rd_ptr;
   logic [WIDTH-1:0] mem [0:(1<<LOG_DEPTH)-1];

   logic [WIDTH-1:0] mem_out, wr_data_q;
   logic addr_collision;

   // distinction between empty and full is from the MSB
   assign empty = (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]) & 
      (wr_ptr[LOG_DEPTH] == rd_ptr[LOG_DEPTH]);
   assign full = (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]) & 
      (wr_ptr[LOG_DEPTH] != rd_ptr[LOG_DEPTH]);
   assign next_rd_ptr = rd_ptr + (rd_en ? 1'b1 : 1'b0);
   always_ff @(posedge clk) begin
      if (!rstn) begin
         wr_ptr <= 0;
         rd_ptr <= 0;
      end else begin
         if (wr_en) begin
            assert(!full | rd_en)  else $error("wr when full");
            wr_ptr <= wr_ptr + 1;
         end
         if (rd_en) begin
            assert(!empty | wr_en)  else $error("rd when empty");
            rd_ptr <= rd_ptr + 1;
         end
      end
   end
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
         addr_collision <= 1'b0;
      end else begin
         addr_collision <= (wr_en & (wr_ptr == next_rd_ptr));
         wr_data_q <= wr_data;
      end
   end
   always_ff @(posedge clk) begin
      if (wr_en) begin
         mem[wr_ptr[LOG_DEPTH-1:0]] <= wr_data;
      end
      mem_out <= mem[next_rd_ptr[LOG_DEPTH-1:0]];
   end

   assign rd_data = addr_collision ? wr_data_q : mem_out;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         size <= 0;
      end else begin
         if (wr_en & !rd_en) begin
            size <= size + 1;
         end else if (rd_en & !wr_en) begin
            size <= size - 1;
         end
      end
   end

endmodule

// fifo that rotates elements on idle cycles
module recirculating_fifo #(
      parameter WIDTH = 32,
      parameter LOG_DEPTH = 1
) (
   input  clk,
   input  rstn,

   input wr_en,
   input rd_en,
   input [WIDTH-1:0] wr_data,

   output logic full, 
   output logic empty,  // aka out_valid
   output logic [WIDTH-1:0] rd_data,

   output logic [LOG_DEPTH:0] size
);

logic s_wr_en, s_rd_en;
logic [WIDTH-1:0] s_wr_data;

always_comb begin
   if (wr_en | rd_en) begin
      s_wr_en = wr_en;
      s_rd_en = rd_en;
      s_wr_data = wr_data;
   end else begin
      s_wr_en = 1'b1;
      s_rd_en = 1'b1;
      s_wr_data = rd_data;
   end
end

fifo #(
      .WIDTH(WIDTH),
      .LOG_DEPTH(LOG_DEPTH)
   ) FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(s_wr_en),
      .wr_data(s_wr_data),

      .full(full),
      .empty(empty),

      .rd_en(s_rd_en),
      .rd_data(rd_data),

      .size(size)

   );
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
      end else begin
         if (wr_en) begin
            assert(!full | rd_en)  else $error("wr when full");
         end
         if (rd_en) begin
            assert(!empty)  else $error("rd when empty");
         end
      end
   end

endmodule

// Attaches to a component and logs last N specified events.
// Can be read via PCIS
module log #(
      parameter WIDTH = 384,
      parameter LOG_DEPTH = 12
) (
   input  clk,
   input  rstn,

   input wvalid,
   input [WIDTH-1:0] wdata,

   pci_debug_bus_t.master pci,

   // optional port. Hopefully should not be synthesized if not connected
   output logic [LOG_DEPTH:0] size
);

   // Store cycle number and sequence number in addition to user data
   (* ram_style = "ultra" *)
   logic [WIDTH-1 + 64:0] mem [0:(1<<LOG_DEPTH)-1];
   logic [LOG_DEPTH:0] wr_ptr, rd_ptr, next_rd_ptr;

   logic [31:0] cycle;
   logic [31:0] seq;
   logic [WIDTH-1 + 64:0] fifo_head;

   logic wvalid_q;
   logic [WIDTH-1:0] wdata_q;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         cycle <= 0;
         seq <= 0;
      end else begin
         cycle <= cycle + 1;
         if (wvalid) seq <= seq + 1;
      end
   end

   always_ff @(posedge clk) begin
      wvalid_q <= wvalid;
      wdata_q <= wdata;
   end

   logic fifo_rd_en;
   logic fifo_full;

   logic [7:0] read_remaining;

   always_comb begin
      fifo_rd_en = (pci.rready & (read_remaining > 0) ) | (fifo_full & wvalid);
   end

   assign pci.rvalid = (read_remaining > 0);
   assign pci.rlast = (read_remaining == 1);

   assign next_rd_ptr = rd_ptr + (fifo_rd_en ? 1'b1 : 1'b0);
   always_ff @(posedge clk) begin
      if (!rstn) begin
         read_remaining <= 0;
      end else begin
         if (pci.arvalid) begin
            read_remaining <= pci.arlen + 1; // assumes arsize ==6
         end else if ((read_remaining >0) & pci.rready) begin
            read_remaining <= read_remaining - 1;
         end

      end
   end

   // distinction between empty and full is from the MSB
   assign fifo_full = (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]) & 
      (wr_ptr[LOG_DEPTH] != rd_ptr[LOG_DEPTH]);

   always_ff @(posedge clk) begin
      if (!rstn) begin
         wr_ptr <= 0;
         rd_ptr <= 0;
      end else begin
         if (wvalid) begin
            wr_ptr <= wr_ptr + 1;
         end
         if (fifo_rd_en) begin
            rd_ptr <= rd_ptr + 1;
         end
      end
   end

   always_ff @(posedge clk) begin
      if (wvalid) begin   
         mem[wr_ptr[LOG_DEPTH-1:0]] <= {wdata, cycle, seq};
      end
      fifo_head <= mem[next_rd_ptr[LOG_DEPTH-1:0]];
   end
   assign pci.rdata = fifo_head;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         size <= 0;
      end else begin
         if (wvalid & !fifo_rd_en) begin
            size <= size + 1;
         end else if (fifo_rd_en & !wvalid) begin
            size <= size - 1;
         end
      end
   end

endmodule

//https://stackoverflow.com/questions/38230450/first-non-zero-element-encoder-in-verilog
module highbit #(
    parameter OUT_WIDTH = 4, 
    parameter IN_WIDTH = 1<<(OUT_WIDTH)
) (
    input [IN_WIDTH-1:0]in,
    output [OUT_WIDTH-1:0]out
);

   wire [OUT_WIDTH-1:0]out_stage[0:IN_WIDTH];
   assign out_stage[0] = ~0;
   generate genvar i;
       for(i=0; i<IN_WIDTH; i=i+1)
           assign out_stage[i+1] = in[i] ? i : out_stage[i]; 
   endgenerate
   assign out = out_stage[IN_WIDTH];

endmodule

// first bit (LSB) that is set
module lowbit #(
    parameter OUT_WIDTH = 4, 
    parameter IN_WIDTH = 1<<(OUT_WIDTH)
) (
    input [IN_WIDTH-1:0]in,
    output [OUT_WIDTH-1:0]out
);

   // default 0
   wire [OUT_WIDTH-1:0]out_stage[0:IN_WIDTH];
   assign out_stage[IN_WIDTH] = 0;
   generate genvar i;
       for(i=IN_WIDTH-1; i>=0; i=i-1)
           assign out_stage[i] = in[i] ? i : out_stage[i+1]; 
   endgenerate
   assign out = out_stage[0];

endmodule

// A round robin scheduler. 
// This design duplicates the input vector and feeds into a lowbit module
// If the critical path is too long, alternative design is possible 
// where the input vector is barrel shfted into place, and the 
// output vector adjusted correspondingly
module rr_sched #(
    parameter OUT_WIDTH = 4, 
    parameter IN_WIDTH = 1<<(OUT_WIDTH)
) (
   input clk,
   input rstn,

   input [IN_WIDTH-1:0]in,
   output [OUT_WIDTH-1:0]out,

   input advance 
);
logic [OUT_WIDTH-1:0] last_sel;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         last_sel <= 0;
      end else if (advance) begin
         last_sel <= out;
      end
   end

   logic [2*IN_WIDTH-1:0] lowbit_in;
   logic [2*OUT_WIDTH-1:0] lowbit_out;

   generate genvar i;
      for (i=0;i<IN_WIDTH;i++) begin
         assign lowbit_in[           i] = in[i] & (i>last_sel);
         assign lowbit_in[IN_WIDTH + i] = in[i] ;
      end
   endgenerate

   lowbit #(
      .IN_WIDTH(2*IN_WIDTH),
      .OUT_WIDTH(2*OUT_WIDTH)
   ) LOW_BIT  (
      .in(lowbit_in),
      .out(lowbit_out)
   );
   assign out = (lowbit_out < IN_WIDTH) ? lowbit_out :  lowbit_out - IN_WIDTH;

endmodule


module register_slice #
  (
   parameter WIDTH = 32,
   parameter STAGES = 1
   )
  (
   // System Signals
   input wire clk,
   input wire rstn,

   // Slave side
   input  [WIDTH-1:0] s_data,
   input  s_valid,
   output logic s_ready,

   // Master side
   output logic [WIDTH-1:0] m_data,
   output logic m_valid,
   input  m_ready
   );

   logic [STAGES:0] valid;
   logic [STAGES:0] ready;
   logic [STAGES:0] [WIDTH-1:0] data;
   
   assign valid[0] = s_valid;
   assign data[0] = s_data;
   assign s_ready = ready[0];

   assign m_valid = valid[STAGES];
   assign m_data = data[STAGES];
   assign ready[STAGES] = m_ready;

   genvar i;
generate
   for(i=0;i<STAGES;i++) begin : rs
      register_slice_single
         #(.WIDTH(WIDTH))
      SLICE (
         .clk(clk),
         .rstn(rstn),

         .s_valid(valid[i]),
         .s_ready(ready[i]),
         .s_data (data [i]),

         .m_valid(valid[i+1]),
         .m_ready(ready[i+1]),
         .m_data (data [i+1])
      );

   end

endgenerate

endmodule

// A single register slice for valid/ready handshake signals
module register_slice_single #
  (
   parameter WIDTH = 32
   )
  (
   // System Signals
   input wire clk,
   input wire rstn,

   // Slave side
   input  [WIDTH-1:0] s_data,
   input  s_valid,
   output logic s_ready,

   // Master side
   output logic [WIDTH-1:0] m_data,
   output logic m_valid,
   input  m_ready
   );

      reg [WIDTH-1:0] m_payload_i;
      reg [WIDTH-1:0] skid_buffer;

      reg [1:0] aresetn_d = 2'b00; // Reset delay shifter
      always @(posedge clk) begin
        if (~rstn) begin
          aresetn_d <= 2'b00;
        end else begin
          aresetn_d <= {aresetn_d[0], rstn};
        end
      end
      
      always @(posedge clk) begin
        if (~aresetn_d[0]) begin
          s_ready <= 1'b0;
        end else begin
          s_ready <= m_ready | ~m_valid | (s_ready & ~s_valid);
        end
        
        if (~aresetn_d[1]) begin
          m_valid <= 1'b0;
        end else begin
          m_valid <= s_valid | ~s_ready | (m_valid & ~m_ready);
        end
        
        if (m_ready | ~m_valid) begin
          m_data <= s_ready ? s_data : skid_buffer;
        end
        
        if (s_ready) begin
          skid_buffer <= s_data;
        end
      end

endmodule

module free_list #(
      parameter LOG_DEPTH=13 
) (
   input  clk,
   input  rstn,

   input wr_en,
   input rd_en,
   input [LOG_DEPTH-1:0] wr_data,

   output logic full, 
   output logic empty,  // aka out_valid
   output logic [LOG_DEPTH-1:0] rd_data,

   // optional port. Hopefully should not be synthesized if not connected
   output logic [LOG_DEPTH:0] size
);

   logic [LOG_DEPTH:0] wr_ptr, rd_ptr, next_rd_ptr;
   
   logic [LOG_DEPTH-1:0] mem [0:(1<<LOG_DEPTH)-1];

   initial begin
      for (integer i=0;i<2**LOG_DEPTH;i++) begin
         mem[i] = i;
      end
   end

   // distinction between empty and full is from the MSB
   assign empty = (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]) & 
      (wr_ptr[LOG_DEPTH] == rd_ptr[LOG_DEPTH]);
   assign full = (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]) & 
      (wr_ptr[LOG_DEPTH] != rd_ptr[LOG_DEPTH]);
   assign next_rd_ptr = rd_ptr + (rd_en ? 1'b1 : 1'b0);
   always_ff @(posedge clk) begin
      if (!rstn) begin
         wr_ptr <= 2**LOG_DEPTH;
         rd_ptr <= 0;
      end else begin
         if (wr_en) begin
            assert(!full | rd_en)  else $error("wr when full");
            mem[wr_ptr[LOG_DEPTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
         end
         if (rd_en) begin
            assert(!empty)  else $error("rd when empty");
            rd_ptr <= rd_ptr + 1;
         end
         if (wr_en & (wr_ptr == next_rd_ptr)) begin
            rd_data <= wr_data;
         end else begin
            rd_data <= mem[next_rd_ptr[LOG_DEPTH-1:0]];
         end
      end
   end


   always_ff @(posedge clk) begin
      if (!rstn) begin
         size <= 2**LOG_DEPTH;
      end else begin
         if (wr_en & !rd_en) begin
            size <= size + 1;
         end else if (rd_en & !wr_en) begin
            size <= size - 1;
         end
      end
   end

endmodule

module free_list_bram #(
      parameter LOG_DEPTH=13 
) (
   input  clk,
   input  rstn,

   input wr_en,
   input rd_en,
   input [LOG_DEPTH-1:0] wr_data,

   output logic full, 
   output logic empty,  // aka out_valid
   output logic [LOG_DEPTH-1:0] rd_data,

   // optional port. Hopefully should not be synthesized if not connected
   output logic [LOG_DEPTH:0] size
);

   logic [LOG_DEPTH:0] wr_ptr, rd_ptr, next_rd_ptr;
   
   (* ram_style = "block" *)
   logic [LOG_DEPTH-1:0] mem [0:(1<<LOG_DEPTH)-1];

   initial begin
      for (integer i=0;i<2**LOG_DEPTH;i++) begin
         mem[i] = i;
      end
   end

   logic addr_collision;
   logic [LOG_DEPTH-1:0] wdata_reg, mem_out;

   // distinction between empty and full is from the MSB
   assign empty = (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]) & 
      (wr_ptr[LOG_DEPTH] == rd_ptr[LOG_DEPTH]);
   assign full = (wr_ptr[LOG_DEPTH-1:0] == rd_ptr[LOG_DEPTH-1:0]) & 
      (wr_ptr[LOG_DEPTH] != rd_ptr[LOG_DEPTH]);
   assign next_rd_ptr = rd_ptr + (rd_en ? 1'b1 : 1'b0);
   always_ff @(posedge clk) begin
      if (!rstn) begin
         wr_ptr <= 2**LOG_DEPTH;
         rd_ptr <= 0;
      end else begin
         if (wr_en) begin
            assert(!full | rd_en)  else $error("wr when full");
            mem[wr_ptr[LOG_DEPTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
         end
         if (rd_en) begin
            assert(!empty)  else $error("rd when empty");
            rd_ptr <= rd_ptr + 1;
         end
         mem_out <= mem[next_rd_ptr[LOG_DEPTH-1:0]];
         
      end
   end

   assign rd_data = addr_collision ? wdata_reg : mem_out;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         addr_collision <= 1'b0;
         wdata_reg <= 'x;
      end else begin
         addr_collision <= (wr_en & (wr_ptr == next_rd_ptr));
         wdata_reg <= wr_data;
      end
   end


   always_ff @(posedge clk) begin
      if (!rstn) begin
         size <= 2**LOG_DEPTH;
      end else begin
         if (wr_en & !rd_en) begin
            size <= size + 1;
         end else if (rd_en & !wr_en) begin
            size <= size - 1;
         end
      end
   end

endmodule
