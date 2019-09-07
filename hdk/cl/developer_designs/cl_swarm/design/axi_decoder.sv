import swarm::*;

// Reformat AXI transactions in units of cache line size by either:
// 1) Break up long accesses that span cache lines
// 2) Combine a narrow (low SIZE) but long (high LEN) 
//     transaction into several cache-line-wide ones. 
//
// When conected to cores, this modules acts like a single-cache-line L1 
module axi_decoder 
 #(
    parameter ID_BASE = 0,
    // These two setting can be used to save registers (and also routing),
    // The impact maybe small, but considering this module is instantiated 100s
    // of times, they add up.
    parameter MAX_AWSIZE = 6,
    parameter MAX_ARSIZE = 6
 )
(
   input clk,
   input rstn,
  
   // TODO chage core/l2 to more general names (i.e master/slave, in/out)
   axi_bus_t.master core,    
   axi_bus_t.slave l2 

);


// Write Logic
typedef enum logic [2:0] {WRITE_IDLE, WRITE_WAITING_DATA, WRITE_WAITING_L2,
      WRITE_WAITING_L2_WREADY, WRITE_WAITING_BVALID} write_state_t;
write_state_t write_state, next_write_state;

always_ff @(posedge clk) begin
   if (!rstn) begin
      write_state <= WRITE_IDLE;
   end else begin
      write_state <= next_write_state;
   end
end

logic [8:0] ack_remaining [0:15];
axi_id_t  full_bid [0:15];

// Note: In general it is not safe to assign these signals default
// values and then overwrite in the same always_comb block. 
// Simulator could deadlock where the same two events are being repeatedly
// added to the event list.
assign core.awready = (write_state == WRITE_IDLE) & (ack_remaining[core.awid[3:0]] == 0);
assign core.wready = (write_state == WRITE_IDLE | write_state == WRITE_WAITING_DATA);


logic [63:0] reg_awaddr, next_awaddr;
logic [3:0] reg_awsize;
logic [8:0] reg_awlen;

always_ff @(posedge clk) begin
   if (core.awvalid & core.awready) begin
      reg_awsize <= core.awsize;
      if (core.wvalid & core.wready) begin
         reg_awlen <= core.awlen ;
      end else begin
         reg_awlen <= core.awlen+1;
      end
   end else if (core.wvalid & core.wready) begin
      reg_awlen <= reg_awlen -1;
   end
end

logic [63:0] awaddr;
logic [3:0] awsize;
assign awaddr =  (core.awvalid & core.awready & core.wvalid) ? core.awaddr : reg_awaddr;
assign awsize =  (core.awvalid & core.awready & core.wvalid) ? core.awsize : reg_awsize;

always_comb begin
   next_awaddr = awaddr;
   if (core.wvalid & core.wready) begin
      case (awsize) 
         0:  next_awaddr = awaddr + 1; 
         1:  next_awaddr = awaddr + 2; 
         2:  next_awaddr = awaddr + 4; 
         3:  next_awaddr = awaddr + 8; 
         4:  next_awaddr = awaddr + 16; 
         5:  next_awaddr = awaddr + 32; 
         default:  next_awaddr = awaddr + 64; 
      endcase
   end
end

always_ff @(posedge clk) begin
   if (core.awvalid & core.awready & !core.wvalid) begin
      reg_awaddr <= core.awaddr;
   end else begin
      reg_awaddr <= next_awaddr;
   end
end

// Tracks how many writes have been issued to L2 in a single transaction. 
// Currently limited to 16, which is sufficient for a burst of 256 32-bit words. 
// (where initial address is cache-line aligned)
logic [7:0] reg_id;
logic [3:0] tx_id;

always_ff @(posedge clk) begin
   if (!rstn) begin
      reg_id <=0;
   end else if ( (write_state == WRITE_WAITING_L2 | write_state == WRITE_WAITING_L2_WREADY)
            & next_write_state == WRITE_WAITING_DATA) begin
      reg_id <= reg_id + 1;
   end else if (next_write_state == WRITE_IDLE) begin
      reg_id <= 0;
   end
end

generate
always_ff @(posedge clk) begin
   if (!rstn) begin
         l2.wstrb <= 0;
         l2.wdata <= 'x;
   end else 
   if (core.wvalid & core.wready) begin 
      // This code should easily have been condensed by if'ing each case, but vivado freaks out with 
      // 'part-select direction is opposite from prefix index direction'
      if (MAX_AWSIZE == 6) begin
         case (awsize) 
            0: begin
               l2.wstrb[awaddr[5:0]*1 +:1]      <= core.wstrb[0];
               l2.wdata[awaddr[5:0]*8 +:8]      <= core.wdata[7:0];
            end
            1: begin
               l2.wstrb[awaddr[5:1]* 2 +: 2]    <= core.wstrb[ 1:0];
               l2.wdata[awaddr[5:1]*16 +:16]    <= core.wdata[15:0];
            end
            2: begin
               l2.wstrb[awaddr[5:2]* 4 +: 4]    <= core.wstrb[ 3:0];
               l2.wdata[awaddr[5:2]*32 +:32]    <= core.wdata[31:0];
            end
            3: begin
               l2.wstrb[awaddr[5:3]* 8 +: 8]    <= core.wstrb[ 7:0];
               l2.wdata[awaddr[5:3]*64 +:64]    <= core.wdata[63:0];
            end
            4: begin
               l2.wstrb[awaddr[5:4]* 16 +: 16]  <= core.wstrb[ 15:0];
               l2.wdata[awaddr[5:4]*128 +:128]  <= core.wdata[127:0];
            end
            5: begin
               l2.wstrb[awaddr[5]* 32 +: 32]    <= core.wstrb[ 31:0];
               l2.wdata[awaddr[5]*256 +:256]    <= core.wdata[255:0];
            end
            default: begin
               l2.wstrb                         <= core.wstrb[63:0];
               l2.wdata                         <= core.wdata[511:0];
            end
         endcase
      end else if (MAX_AWSIZE == 5) begin
         case (awsize) 
            0: begin
               l2.wstrb[awaddr[4:0]*1 +:1]      <= core.wstrb[0];
               l2.wdata[awaddr[4:0]*8 +:8]      <= core.wdata[7:0];
            end
            1: begin
               l2.wstrb[awaddr[4:1]* 2 +: 2]    <= core.wstrb[ 1:0];
               l2.wdata[awaddr[4:1]*16 +:16]    <= core.wdata[15:0];
            end
            2: begin
               l2.wstrb[awaddr[4:2]* 4 +: 4]    <= core.wstrb[ 3:0];
               l2.wdata[awaddr[4:2]*32 +:32]    <= core.wdata[31:0];
            end
            3: begin
               l2.wstrb[awaddr[4:3]* 8 +: 8]    <= core.wstrb[ 7:0];
               l2.wdata[awaddr[4:3]*64 +:64]    <= core.wdata[63:0];
            end
            4: begin
               l2.wstrb[awaddr[4]* 16 +: 16]  <= core.wstrb[ 15:0];
               l2.wdata[awaddr[4]*128 +:128]  <= core.wdata[127:0];
            end
            default: begin
               l2.wstrb                         <= core.wstrb[31:0];
               l2.wdata                         <= core.wdata[255:0];
            end
         endcase
      end else if (MAX_AWSIZE == 4) begin
         case (awsize) 
            0: begin
               l2.wstrb[awaddr[3:0]*1 +:1]      <= core.wstrb[0];
               l2.wdata[awaddr[3:0]*8 +:8]      <= core.wdata[7:0];
            end
            1: begin
               l2.wstrb[awaddr[3:1]* 2 +: 2]    <= core.wstrb[ 1:0];
               l2.wdata[awaddr[3:1]*16 +:16]    <= core.wdata[15:0];
            end
            2: begin
               l2.wstrb[awaddr[3:2]* 4 +: 4]    <= core.wstrb[ 3:0];
               l2.wdata[awaddr[3:2]*32 +:32]    <= core.wdata[31:0];
            end
            3: begin
               l2.wstrb[awaddr[3]* 8 +: 8]    <= core.wstrb[ 7:0];
               l2.wdata[awaddr[3]*64 +:64]    <= core.wdata[63:0];
            end
            default: begin
               l2.wstrb                         <= core.wstrb[15:0];
               l2.wdata                         <= core.wdata[127:0];
            end
         endcase
      end else if (MAX_AWSIZE == 3) begin
         case (awsize) 
            0: begin
               l2.wstrb[awaddr[2:0]*1 +:1]      <= core.wstrb[0];
               l2.wdata[awaddr[2:0]*8 +:8]      <= core.wdata[7:0];
            end
            1: begin
               l2.wstrb[awaddr[2:1]* 2 +: 2]    <= core.wstrb[ 1:0];
               l2.wdata[awaddr[2:1]*16 +:16]    <= core.wdata[15:0];
            end
            2: begin
               l2.wstrb[awaddr[2]* 4 +: 4]    <= core.wstrb[ 3:0];
               l2.wdata[awaddr[2]*32 +:32]    <= core.wdata[31:0];
            end
            default: begin
               l2.wstrb                         <= core.wstrb[7:0];
               l2.wdata                         <= core.wdata[63:0];
            end
         endcase
      end else if (MAX_AWSIZE == 2) begin
         case (awsize) 
            0: begin
               l2.wstrb[awaddr[1:0]*1 +:1]      <= core.wstrb[0];
               l2.wdata[awaddr[1:0]*8 +:8]      <= core.wdata[7:0];
            end
            1: begin
               l2.wstrb[awaddr[1]* 2 +: 2]    <= core.wstrb[ 1:0];
               l2.wdata[awaddr[1]*16 +:16]    <= core.wdata[15:0];
            end
            default: begin
               l2.wstrb                         <= core.wstrb[3:0];
               l2.wdata                         <= core.wdata[31:0];
            end
         endcase
      end else if (MAX_AWSIZE == 1) begin
         case (awsize) 
            0: begin
               l2.wstrb[awaddr[0]*1 +:1]      <= core.wstrb[0];
               l2.wdata[awaddr[0]*8 +:8]      <= core.wdata[7:0];
            end
            default: begin
               l2.wstrb                         <= core.wstrb[1:0];
               l2.wdata                         <= core.wdata[15:0];
            end
         endcase
      end else if (MAX_AWSIZE == 0) begin
         l2.wstrb                         <= core.wstrb[0];
         l2.wdata                         <= core.wdata[7:0];
      end
   end else if (l2.wvalid & l2.wready) begin
      l2.wstrb <= 0;
      l2.wdata <= 0;
   end
end
endgenerate

assign l2.wlast = 1'b1;
assign l2.awsize = MAX_AWSIZE;
assign l2.awlen = 0;
always_ff @(posedge clk) begin
   if (write_state != WRITE_WAITING_L2 & next_write_state == WRITE_WAITING_L2) begin
      l2.awaddr = {awaddr[63:MAX_AWSIZE], {MAX_AWSIZE{1'b0}}};
   end
end

initial begin
   for (integer i=0;i<16;i++) begin
      ack_remaining[i] = 0;
   end
end
always_ff @(posedge clk) begin
   if (l2.wvalid & l2.wready & reg_awlen==0) begin
      ack_remaining[tx_id] <= ack_remaining[tx_id] + reg_id + 1;
   end else if (l2.bvalid & l2.bready) begin
      ack_remaining[l2.bid[11:8]] <= ack_remaining[l2.bid[11:8]] - 1;
   end
end
always_ff @(posedge clk) begin
   if (core.awvalid & core.awready) begin
      tx_id <= core.awid[3:0];
      full_bid[core.awid[3:0]] <= core.awid;
   end
end

logic bvalid_fifo_full, bvalid_fifo_empty;
logic bvalid_fifo_wr_en;
assign bvalid_fifo_wr_en = l2.bvalid & l2.bready & (ack_remaining[l2.bid[11:8]] == 1);

logic [3:0] s_bid;

fifo #(
      .WIDTH(4),
      .LOG_DEPTH(1)
   ) BVALID_FIFO (
      .clk(clk),
      .rstn(rstn),
      .wr_en(bvalid_fifo_wr_en),
      .wr_data(l2.bid[11:8]),

      .full(bvalid_fifo_full),
      .empty(bvalid_fifo_empty),

      .rd_en(core.bvalid & core.bready),
      .rd_data(s_bid)
   );

always_comb begin
   core.bid = full_bid[s_bid];
end
assign core.bvalid = !bvalid_fifo_empty;

assign l2.bready = !bvalid_fifo_full & !(l2.wvalid & l2.wready & (reg_awlen==0));
assign l2.awid = ID_BASE | (tx_id << 8) | reg_id;;
assign l2.wid = ID_BASE | (tx_id << 8) | reg_id;;

assign core.bresp = 0;

always_comb begin
   next_write_state = write_state;


   l2.awvalid = 1'b0;
   l2.wvalid = 1'b0;
  
   case (write_state)
      WRITE_IDLE: begin
         if (core.awvalid & core.awready) begin
            if (core.wvalid & core.wready) begin
               next_write_state = WRITE_WAITING_L2;
            end else begin
               next_write_state = WRITE_WAITING_DATA;
            end
         end
      end
      WRITE_WAITING_DATA: begin
         if (core.wvalid & core.wready & 
            // ideally should check for all bits > MAX_AWSIZE, but for burst
            // writes, the difference between adjacet writes shouldn't be that
            // large so checking upto bit 10 should be fine.
            ( (next_awaddr[10:MAX_AWSIZE] != awaddr[10:MAX_AWSIZE] ) | core.wlast)  ) begin
            next_write_state = WRITE_WAITING_L2;
         end
      end
      WRITE_WAITING_L2: begin
         l2.awvalid = 1'b1;
         l2.wvalid = 1'b1;
         // Try to push both AW and W, if only AW is accepted try W next
         // cycle
         if (l2.awready) begin
            if (l2.wready) begin
               if (reg_awlen == 0) begin
                  next_write_state = WRITE_IDLE;
               end else begin
                  next_write_state = WRITE_WAITING_DATA;
               end
            end else begin
               next_write_state = WRITE_WAITING_L2_WREADY; 
            end
         end
      end
      WRITE_WAITING_L2_WREADY: begin
         l2.wvalid = 1'b1;
         if (l2.wready) begin
            if (reg_awlen == 0) begin
               next_write_state = WRITE_IDLE;
            end else begin
               next_write_state = WRITE_WAITING_DATA;
            end
         end
      end
      default: begin
         // make compiler happy
      end
   endcase
end


// Read Logic. 
typedef enum logic [1:0] {READ_IDLE, READ_WAITING_L2, READ_WAITING_RESP, READ_DATA_OUT} read_state_t;

read_state_t read_state, next_read_state;
logic [63:0] next_l2_raddr, l2_araddr;
logic [2**(MAX_ARSIZE+3)-1:0] read_data, next_read_data;
logic [MAX_ARSIZE-1:0] read_word, next_read_word;
logic [2:0] read_size, next_read_size;
logic [7:0] read_len, next_read_len;

always_ff @(posedge clk) begin
   if (!rstn) begin
      read_state <= READ_IDLE;
      l2_araddr <= 'x;
      read_len <= 'x;
      read_word <= 'x;
      read_size <= 'x;
      read_data <= 'x;
   end else begin
      read_state <= next_read_state;
      l2_araddr <= next_l2_raddr;
      read_len <= next_read_len;
      read_word <= next_read_word;
      read_size <= next_read_size;
      read_data <= next_read_data;
   end

end

assign core.arready = (read_state == READ_IDLE);
assign l2.rready = (read_state == READ_WAITING_RESP);

logic [5:0] read_word_limit;
//assign read_word_limit = (2**(MAX_ARSIZE -read_size))-1;

always_comb begin
   case (read_size) 
      0: read_word_limit = 2**(MAX_ARSIZE)   -1 ;
      1: read_word_limit = 2**(MAX_ARSIZE-1) -1;
      2: read_word_limit = 2**(MAX_ARSIZE-2) -1;
      3: read_word_limit = 2**(MAX_ARSIZE-3) -1;
      4: read_word_limit = 2**(MAX_ARSIZE-4) -1;
      5: read_word_limit = 2**(MAX_ARSIZE-5) -1;
      default : read_word_limit = 0;
   endcase
end

assign core.rid = 0;
assign core.rresp = 0;
assign core.rvalid = (read_state == READ_DATA_OUT);

always_comb begin
   next_read_state = read_state;
   next_read_len = read_len;
   next_read_word = read_word;
   next_read_size = read_size;
   next_read_data = read_data;

   next_l2_raddr = l2_araddr;

   core.rlast = 1'b0;
   core.rdata = 'x;

   l2.arid = ID_BASE;
   l2.arvalid = 1'b0;
   l2.araddr = {l2_araddr[63:6], 6'b0};
   l2.arsize = 6;
   l2.arlen = 0;
   
   case (read_state)
      READ_IDLE: begin
         if (core.arvalid) begin
            next_l2_raddr = core.araddr;
            next_read_state =  READ_WAITING_L2;
            case (MAX_ARSIZE)  
               1: case (core.arsize) 
                  0: next_read_word = core.araddr[0];
                  default: next_read_word = 1'd0;
               endcase
               2: case (core.arsize) 
                  0: next_read_word = core.araddr[1:0];
                  1: next_read_word = {1'd0, core.araddr[1]};
                  default: next_read_word = 2'd0;
               endcase
               3: case (core.arsize) 
                  0: next_read_word = core.araddr[2:0];
                  1: next_read_word = {1'd0, core.araddr[2:1]};
                  2: next_read_word = {2'd0, core.araddr[2  ]};
                  default: next_read_word = 3'd0;
               endcase
               4: case (core.arsize) 
                  0: next_read_word = core.araddr[3:0];
                  1: next_read_word = {1'd0, core.araddr[3:1]};
                  2: next_read_word = {2'd0, core.araddr[3:2]};
                  3: next_read_word = {3'd0, core.araddr[3  ]};
                  default: next_read_word = 4'd0;
               endcase
               5: case (core.arsize) 
                  0: next_read_word = core.araddr[4:0];
                  1: next_read_word = {1'd0, core.araddr[4:1]};
                  2: next_read_word = {2'd0, core.araddr[4:2]};
                  3: next_read_word = {3'd0, core.araddr[4:3]};
                  4: next_read_word = {4'd0, core.araddr[4  ]};
                  default: next_read_word = 5'd0;
               endcase
               6: case (core.arsize) 
                  0: next_read_word = core.araddr[5:0];
                  1: next_read_word = {1'd0, core.araddr[5:1]};
                  2: next_read_word = {2'd0, core.araddr[5:2]};
                  3: next_read_word = {3'd0, core.araddr[5:3]};
                  4: next_read_word = {4'd0, core.araddr[5:4]};
                  5: next_read_word = {5'd0, core.araddr[5]};
                  default: next_read_word = 6'd0;
               endcase
               default: next_read_word = 0;
            endcase
            next_read_len = core.arlen;
            next_read_size = core.arsize;
         end
      end
      READ_WAITING_L2: begin
         l2.arvalid = 1'b1;
         if (l2.arready) begin
            next_read_state = READ_WAITING_RESP;
         end
      end
      READ_WAITING_RESP: begin
         if (l2.rvalid) begin
            case (MAX_ARSIZE) 
               0: next_read_data = l2.rdata[ l2_araddr[5:0]*  8 +:   8];
               1: next_read_data = l2.rdata[ l2_araddr[5:1]* 16 +:  16];
               2: next_read_data = l2.rdata[ l2_araddr[5:2]* 32 +:  32];
               3: next_read_data = l2.rdata[ l2_araddr[5:3]* 64 +:  64];
               4: next_read_data = l2.rdata[ l2_araddr[5:4]*128 +: 128];
               5: next_read_data = l2.rdata[ l2_araddr[5  ]*256 +: 256];
               default: next_read_data = l2.rdata[511:0];
            endcase
            //next_read_data = l2.rdata[ 2**(MAX_ARSIZE+3)-1:0];
            next_read_state = READ_DATA_OUT;
         end
      end
      READ_DATA_OUT: begin
         case (read_size) 
            0: core.rdata = read_data[ read_word*  8 +:  8];
            1: core.rdata = read_data[ read_word* 16 +: 16];
            2: core.rdata = read_data[ read_word* 32 +: 32];
            3: core.rdata = read_data[ read_word* 64 +: 64];
            4: core.rdata = read_data[ read_word*128 +:128];
            5: core.rdata = read_data[ read_word*256 +:256];
            default: core.rdata = read_data;
         endcase
         if (core.rready) begin
            if (read_len == 0) begin
               next_read_state =  READ_IDLE;
               core.rlast = 1'b1;
               next_l2_raddr = 'x;
            end else begin
               next_read_len = read_len -1;
               if (read_word == read_word_limit) begin
                  next_read_state = READ_WAITING_L2;
                  next_read_word = 0;
                  next_l2_raddr = l2_araddr + (1<<MAX_ARSIZE);
               end else begin
                  next_read_word = read_word + 1;
               end
            end
         end
      end
   endcase
end


endmodule


