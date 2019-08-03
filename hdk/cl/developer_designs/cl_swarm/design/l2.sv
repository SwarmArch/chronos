import swarm::*;

typedef enum logic[1:0] {VALID, INVALID, PENDING} line_state_t;
typedef struct packed {
   line_state_t state;
   logic [CACHE_TAG_WIDTH-1:0] tag;
   logic dirty;
   // Each way maintains its replacement priority. (0 - most likely) 
   // think: higher prio -> higher priority that this line should stay)
   // These priorites are unique in the range of (0, CACHE_NUM_WAYS -1)
   lru_width_t prio; 
} tag_way_t;
typedef tag_way_t [CACHE_NUM_WAYS-1:0] tag_entry_t;

typedef enum logic[2:0] {NONE, READ, WRITE, EVICT, RESP_READ, RESP_WRITE, FLUSH} pipe_op_t;
typedef logic [CACHE_INDEX_WIDTH-1:0] tag_addr_t;
typedef logic [CACHE_INDEX_WIDTH+CACHE_LOG_WAYS-1:0] data_addr_t;
typedef logic [15:0] id_t;

typedef logic [LOG_N_MSHR-1:0] mshr_addr_t;
typedef struct packed {
   id_t incoming_id; //id of the lower level
   logic is_read;
   mem_addr_t addr;
   cache_line_t wdata;
   logic [63:0] wstrb;
} mshr_t;


module l2
#( 
   parameter TILE_ID = 1,
   parameter BANK_ID = 0,
   parameter BYPASS_TAG_ON_WRITES = 0
) (
	input clk,
	input rstn,

	axi_bus_t.master l1,
   output cache_addr_t rindex,
   axi_bus_t.slave mem_bus,

   reg_bus_t.master reg_bus,

   pci_debug_bus_t.master pci_debug
);

   logic stall_in[1:2]; 
   logic stall_out[2:3];

   logic read_resp_valid;
   cache_line_t read_resp_data;
   logic read_resp_ready;

   tag_addr_t tag_raddr, tag_waddr;
   tag_entry_t tag_rdata, tag_wdata;
   logic tag_rvalid, tag_wvalid;
   logic tag_en;
   
   logic write_buf_match;

   cache_line_t  p12_wdata;
   logic [63:0]  p12_wstrb;
   id_t          p12_cid;
   mem_addr_t    p12_addr;
   pipe_op_t     p12_op;
   
   mshr_addr_t mshr_raddr, mshr_next;
   logic mshr_clear, mshr_claim, mshr_available;
   mshr_t mshr_rdata, mshr_wdata;
   
   data_addr_t darr_addr;
   cache_line_t darr_wdata, darr_rdata;
   logic darr_en;
   logic [63:0]  darr_wr;

   pipe_op_t p23_op;
   id_t      p23_cid; // id from core 
   id_t      p23_mid; // id to memory
   logic     p23_retry; 

   logic retry_fifo_wr_en, retry_fifo_rd_en;
   mshr_t retry_fifo_wdata, retry_fifo_rdata;
   logic retry_fifo_empty;
   logic [4:0] retry_fifo_size;
   logic retry_fifo_almost_full;

   assign retry_fifo_almost_full = retry_fifo_size > 13;

   assign stall_in[1] = stall_out[2] | stall_out[3];
   assign stall_in[2] = stall_out[3];

   assign mem_bus.awlen = 0; // 1 beat
   assign mem_bus.awsize = 6; // 512 bit
   assign mem_bus.arlen = 0;
   assign mem_bus.arsize = 6;

   assign l1.wready = l1.awready;
   assign l1.bresp = 0;
   assign l1.rlast = 1'b1;
   assign l1.rresp = 0;

   logic circulate_on_mem_stall;
   logic [31:0] write_mshr_valid, read_mshr_valid;

   logic block_aw_on_w_not_ready;
   logic stage_2_awready;
   
   always_ff@(posedge clk) begin
      if (!rstn) begin
         circulate_on_mem_stall <= 1'b0;
         block_aw_on_w_not_ready <= 1'b1;
      end else if (reg_bus.wvalid & (reg_bus.waddr == L2_CIRCULATE_ON_STALL)) begin
         circulate_on_mem_stall <= reg_bus.wdata[0];
         block_aw_on_w_not_ready <= reg_bus.wdata[1];
      end
   end

   assign stage_2_awready = block_aw_on_w_not_ready ? (mem_bus.awready & mem_bus.wready & !mem_bus.wvalid) 
                                 : mem_bus.awready;

   typedef struct packed {

     logic [3:0] mshr_next; 
     logic m_arvalid;
     logic m_arready;
     logic m_rvalid;
     logic m_rready;
     logic [7:0] m_arid;
     logic [7:0] m_rid;
     
     logic m_bvalid;
     logic m_bready;
     logic [13:0] m_bid;

     logic m_awvalid;
     logic m_awready;
     logic write_buf_match;
     logic [12:0] m_awid;
     logic [15:0] write_buf_mshr_valid;
     logic [31:0] m_awaddr;

     logic [31:0] tag_rdata_3;
     logic [31:0] tag_rdata_2;
     logic [31:0] tag_rdata_1;
     logic [31:0] tag_rdata_0;
     logic [63:0] wstrb; 
     logic [4:0] unused;
     id_t id;
     mem_addr_t addr;
     pipe_op_t op;

     logic retry;
     logic hit;
     logic [CACHE_LOG_WAYS-1:0] way;

     mem_addr_t repl_addr;
   } l2_log_t;

   l2_log_t log_word;
   assign log_word.wstrb = p12_wstrb;
   assign log_word.id = p12_cid;
   assign log_word.addr = p12_addr;
   assign log_word.op = p12_op;
   assign log_word.retry = retry_fifo_wr_en;
   assign log_word.m_awvalid = mem_bus.awvalid;
   assign log_word.m_awready = mem_bus.awready;
   assign log_word.m_awid = mem_bus.awid;
   assign log_word.m_arid = mem_bus.arid;
   assign log_word.m_rid = mem_bus.rid;
   assign log_word.m_awaddr = mem_bus.awaddr;
   assign log_word.m_bvalid = mem_bus.bvalid;
   assign log_word.m_bready = mem_bus.bready;
   assign log_word.m_rvalid = mem_bus.rvalid;
   assign log_word.m_rready = mem_bus.rready;
   assign log_word.m_arvalid = mem_bus.arvalid;
   assign log_word.m_arready = mem_bus.arready;
   assign log_word.mshr_next = mshr_next;
   assign log_word.m_bid = mem_bus.bid;
   assign log_word.write_buf_match = write_buf_match; 
   assign log_word.write_buf_mshr_valid = write_mshr_valid;
   always_comb begin
      log_word.repl_addr = tag_rdata[ log_word.way ].tag;
      log_word.tag_rdata_0 = tag_rdata[0];
      log_word.tag_rdata_1 = tag_rdata[1];
      log_word.tag_rdata_2 = tag_rdata[2];
      log_word.tag_rdata_3 = tag_rdata[3];
   end
   logic log_valid;
   logic log_bvalid;
   always_ff@(posedge clk) begin
      if (!rstn) begin
         log_bvalid <= 1'b0;
      end else if (reg_bus.wvalid & (reg_bus.waddr == L2_LOG_BVALID)) begin
         log_bvalid <= reg_bus.wdata[0];
      end
   end
   assign log_valid = ((p12_op != NONE) & !stall_in[2] & !stall_out[2]) | (log_bvalid & ((mem_bus.bvalid & mem_bus.bready) | (mem_bus.rvalid) ));

`ifdef XILINX_SIMULATOR
   if (1) begin
      logic [63:0] cycle;
      integer file,r;
      string file_name;
      initial begin
         $sformat(file_name, "l2_%0d_%0d.log", TILE_ID, BANK_ID);
         file = $fopen(file_name,"w");
      end
      always_ff @(posedge clk) begin
         if (!rstn) cycle <=0;
         else cycle <= cycle + 1;
      end

      always_ff @(posedge clk) begin
         if ((p12_op != NONE) & !stall_in[2] & !stall_out[2]) begin
            $fwrite(file,"[%5d] [l2-%2d-%1d] [%4x] %d %s %1d %2d %8x (tag:%5x index:%3x) %6x wstrb:%8x_%8x \n", 
               cycle, TILE_ID, BANK_ID, log_word.id,
               log_word.op,
               log_word.hit ? "H" : "M",
               log_word.retry,
               log_word.way,
               log_word.addr,
               log_word.addr >> 18,
               (log_word.addr >> 6) & 32'hfff,
               log_word.repl_addr,
               log_word.wstrb[63:32],
               log_word.wstrb[31:0]
            ) ;
         end
         $fflush(file);
      end
   end
`endif


   logic [31:0] stat_read_hits;
   logic [31:0] stat_read_misses;
   logic [31:0] stat_write_hits;
   logic [31:0] stat_write_misses;
   logic [31:0] stat_evictions;

   logic [31:0] stat_stall_retry_full;
   logic [31:0] stat_retry_not_empty;
   logic [31:0] stat_retry_count;
   logic [31:0] stat_stall_in;

   logic [7:0] aw_req, w_req;
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
         stat_read_hits    <= 0;
         stat_read_misses  <= 0;
         stat_write_hits   <= 0;
         stat_write_misses <= 0;
         stat_evictions    <= 0; 
         stat_stall_retry_full <= 0;
         stat_retry_not_empty <= 0;
         stat_retry_count <= 0;
         stat_stall_in <= 0;

      end else begin
         if (p12_op == READ & log_word.hit & !retry_fifo_wr_en & !stall_in[2]) begin
           stat_read_hits <= stat_read_hits + 1; 
         end
         if (p12_op == WRITE & log_word.hit & !retry_fifo_wr_en & !stall_in[2]) begin
           stat_write_hits <= stat_write_hits + 1; 
         end
         if (p12_op == READ & !log_word.hit & !retry_fifo_wr_en &
            !stall_in[2] & !stall_out[2]) begin
           stat_read_misses <= stat_read_misses + 1; 
         end
         if (p12_op == WRITE & !log_word.hit & !retry_fifo_wr_en & 
            !stall_in[2] & !stall_out[2]) begin
           stat_write_misses <= stat_write_misses + 1; 
         end
         if (p23_op == EVICT & !stall_out[3]) begin
            stat_evictions <= stat_evictions + 1;
         end
         if (retry_fifo_almost_full) begin
            stat_stall_retry_full <= stat_stall_retry_full + 1; 
         end
         if (!retry_fifo_empty) begin
            stat_retry_not_empty <= stat_retry_not_empty + 1;
         end
         if (retry_fifo_wr_en) begin
            stat_retry_count <= stat_retry_count + 1;
         end
         if (stall_in[1]) begin
            stat_stall_in <= stat_stall_in + 1;
         end
         if (mem_bus.awvalid & mem_bus.awready) begin 
            aw_req <= aw_req + 1;
         end
         if (mem_bus.wvalid & mem_bus.wready) begin 
            w_req <= w_req + 1;
         end

      end
   end

   always_ff @(posedge clk) begin
      if (!rstn) begin
         reg_bus.rvalid <= 1'b0;
      end
      if (reg_bus.arvalid) begin
         reg_bus.rvalid <= 1'b1;
         case (reg_bus.araddr) 
            L2_FLUSH        : reg_bus.rdata <= !flush_ready;
            DEBUG_CAPACITY  : reg_bus.rdata <= log_size;
            L2_READ_HITS    : reg_bus.rdata <= stat_read_hits;
            L2_READ_MISSES  : reg_bus.rdata <= stat_read_misses;
            L2_WRITE_HITS   : reg_bus.rdata <= stat_write_hits;
            L2_WRITE_MISSES : reg_bus.rdata <= stat_write_misses;
            L2_EVICTIONS    : reg_bus.rdata <= stat_evictions;
            L2_RETRY_STALL    : reg_bus.rdata <= stat_stall_retry_full;
            L2_RETRY_NOT_EMPTY    : reg_bus.rdata <= stat_retry_not_empty;
            L2_RETRY_COUNT    : reg_bus.rdata <= stat_retry_count;
            L2_STALL_IN       : reg_bus.rdata <= stat_stall_in;
            L2_MISC_DEBUG   : reg_bus.rdata <= {
                              {1'b0, p12_op},
                              {1'b0, p23_op},
                              mshr_next[3:0],
                              mem_bus.rid[3:0],
                              2'b0, stall_in[1], stall_in[2],
                              l1.rvalid, l1.rready, l1.bvalid, l1.bready,
                              mem_bus.arvalid, mem_bus.arready, 
                              mem_bus.awvalid, mem_bus.awready, 
                              mem_bus.wvalid , mem_bus.wready,
                              mem_bus.rvalid, mem_bus.bvalid};
            L2_MISC_DEBUG + 4 : reg_bus.rdata <= {aw_req, w_req};
            L2_MISC_DEBUG + 8 : reg_bus.rdata <= {write_mshr_valid[15:0], read_mshr_valid[15:0]};
            
         endcase
      end else begin
         reg_bus.rvalid <= 1'b0;
      end
   end   


   logic flush_valid;
   logic flush_ready; // if down, flush is in progress
   
   always_ff @(posedge clk) begin
      if (!rstn) begin
         flush_valid <= 1'b0;
      end else
      if (reg_bus.wvalid & reg_bus.waddr == L2_FLUSH) begin
         flush_valid <= 1'b1;
      end else if (!flush_ready) begin
         flush_valid <= 1'b0;
      end
   end

   logic [LOG_LOG_DEPTH:0] log_size; 
generate 
if (L2_LOGGING[TILE_ID] ) begin
   log #(
      .WIDTH($bits(log_word)),
      .LOG_DEPTH(LOG_LOG_DEPTH)
   ) L2_LOG (
      .clk(clk),
      .rstn(rstn),

      .wvalid( log_valid ),
      .wdata(log_word),

      .pci(pci_debug),

      .size(log_size)

   );
end
endgenerate

   memory_response_handler MEM_RESP_HANDLER (
      .clk(clk),
      .rstn(rstn),

      .m_rdata(mem_bus.rdata),
      .m_rvalid(mem_bus.rvalid),
      .m_rid(mem_bus.rid),
      .m_rready(mem_bus.rready),

      .mshr_addr(mshr_raddr),
      .mshr_clear(mshr_clear),

      .out_valid(read_resp_valid),
      .out_data(read_resp_data),
      .out_ready(read_resp_ready)
   );

   fifo #(
      .WIDTH($bits(retry_fifo_wdata)),
      .LOG_DEPTH(4)
   ) RETRY_FIFO (
      .clk(clk),
      .rstn(rstn),
      
      .wr_en(retry_fifo_wr_en),
      .rd_en(retry_fifo_rd_en),
      .wr_data(retry_fifo_wdata),
      .rd_data(retry_fifo_rdata),

      .full(),
      .empty(retry_fifo_empty),

      .size(retry_fifo_size)

   );

   logic flush_advance_tag; // Stage 2 -> Stage 1
  
   l2_stage_1  
   #( 
      .TILE_ID(TILE_ID),
      .BANK_ID(BANK_ID)
   ) L2_STAGE_1 (
      .clk(clk),
      .rstn(rstn),

      .stall_in(stall_in[1]),

      .c_wvalid( l1.awvalid),
      .c_waddr(l1.awaddr[ADDR_BITS-1:0]),
      .c_wdata(l1.wdata),
      .c_wid(l1.wid),
      .c_wstrb(l1.wstrb),
      .c_wready(l1.awready),

      .c_arvalid(l1.arvalid),
      .c_araddr(l1.araddr[ADDR_BITS-1:0]),
      .c_arid(l1.arid),
      .c_arready(l1.arready),

      .retry_rdata(retry_fifo_rdata),
      .retry_valid(!retry_fifo_empty),
      .retry_rd_en(retry_fifo_rd_en),
      .retry_almost_full(retry_fifo_almost_full),

      .read_resp_mshr(mshr_rdata),
      .read_resp_valid(read_resp_valid),
      .read_resp_data(read_resp_data),
      .read_resp_ready(read_resp_ready),

      .tag_raddr(tag_raddr),
      .tag_rvalid(tag_rvalid),

      .p_wdata(p12_wdata),
      .p_wstrb(p12_wstrb),
      .p_cid(p12_cid),
      .p_addr(p12_addr),
      .p_op(p12_op),

      .flush_valid(flush_valid),
      .flush_ready(flush_ready),

      .flush_advance_tag(flush_advance_tag)
   );
   
   assign tag_en = tag_rvalid | tag_wvalid;

   tag_array TAG_ARRAY (
      .clk(clk),
      .rstn(rstn),

      .raddr(tag_raddr),
      .waddr(tag_waddr),

      .wdata(tag_wdata),
      .rdata(tag_rdata),

      .en(tag_en),
      .wr(tag_wvalid)
   );

   logic write_buf_available;
   logic [LOG_N_MSHR-1:0] write_buf_id;
   
   
   write_buffer WRITE_BUFFER (
      .clk(clk),
      .rstn(rstn),

      .check_addr({p12_addr[33:6], 6'd0}),

      .bid(mem_bus.bid),
      .bvalid(mem_bus.bvalid),
      .bready(mem_bus.bready),

      // from/to l2_stage 2
      .awvalid(mem_bus.awvalid & mem_bus.awready),
      .awaddr(mem_bus.awaddr),
      .awready(write_buf_available),
      .awid(write_buf_id), 

      //if a writeback for this address is ongoing.
      .match(write_buf_match),
      .debug_mshr_valid(write_mshr_valid)

   );

   l2_stage_2
   #( 
      .TILE_ID(TILE_ID),
      .BANK_ID(BANK_ID)
   ) L2_STAGE_2 (
      .clk(clk),
      .rstn(rstn),
      
      .stall_in(stall_in[2]),
      .stall_out(stall_out[2]),

      .tag_entry(tag_rdata),   

      .tag_waddr(tag_waddr),
      .tag_wen(tag_wvalid),
      .tag_wdata(tag_wdata),

      .i_wdata(p12_wdata),
      .i_wstrb(p12_wstrb),
      .i_cid(p12_cid),
      .i_addr(p12_addr),
      .i_op(p12_op),

      .m_awvalid(mem_bus.awvalid),
      .m_awaddr(mem_bus.awaddr),
      .m_awid(mem_bus.awid),
      .m_awready(stage_2_awready),

      .m_arvalid(mem_bus.arvalid),
      .m_araddr(mem_bus.araddr),
      .m_arid(mem_bus.arid),
      .m_arready(mem_bus.arready),

      .retry_wdata(retry_fifo_wdata),
      .retry_wr_en(retry_fifo_wr_en),

      .mshr_available(mshr_available),
      .mshr_next(mshr_next),
      .mshr_set(mshr_claim),
      .mshr_data(mshr_wdata),

      .d_addr(darr_addr),
      .d_wdata(darr_wdata),
      .d_en(darr_en),
      .d_wr(darr_wr),

      .p_op(p23_op),
      .p_cid(p23_cid),
      .p_mid(p23_mid),
      
      .flush_advance_tag(flush_advance_tag),

      .write_buf_available(write_buf_available),
      .write_buf_id(write_buf_id),

      .write_buf_match(write_buf_match),
      .circulate_on_mem_stall(circulate_on_mem_stall),

      .log_hit(log_word.hit),
      .log_way(log_word.way)

   );

   data_array DATA_ARRAY (
      .clk(clk),
      .rstn(rstn),

      .addr(darr_addr),
      .wdata(darr_wdata),
      .rdata(darr_rdata),

      .en(darr_en),
      .wr(darr_wr)
   );

   l2_stage_3
   #( 
      .TILE_ID(TILE_ID),
      .BANK_ID(BANK_ID)
   ) L2_STAGE_3 (
      .clk(clk),
      .rstn(rstn),
      
      .stall_out(stall_out[3]),
      
      .i_op(p23_op),
      .i_cid(p23_cid),
      .i_mid(p23_mid),

      .d_rdata(darr_rdata),

      .c_rready(l1.rready),
      .c_rdata(l1.rdata),
      .c_rvalid(l1.rvalid),
      .c_rid(l1.rid),

      .c_bready(l1.bready),
      .c_bvalid(l1.bvalid),
      .c_bid(l1.bid),
      
      .m_wid(mem_bus.wid),
      .m_wdata(mem_bus.wdata),
      .m_wstrb(mem_bus.wstrb),
      .m_wvalid(mem_bus.wvalid),
      .m_wlast(mem_bus.wlast),
      .m_wready(mem_bus.wready)
   );

   mshr_manager MSHR_MANAGER (
      .clk(clk),
      .rstn(rstn),

      .read_addr(mshr_raddr),
      .mshr_clear(mshr_clear),
      .rd_data(mshr_rdata),

      .mshr_available(mshr_available),
      .next_available(mshr_next),
      .wr_data(mshr_wdata),
      .mshr_claim(mshr_claim),

      .debug_mshr_valid(read_mshr_valid)
   );
   
endmodule

module tag_array 
( 
   input clk,
   input rstn,

   input tag_addr_t raddr,
   input tag_addr_t waddr,
   
   input tag_entry_t wdata,
   output tag_entry_t rdata,
   input en,
   input wr

);
   localparam TAG_ENTRY_WIDTH = $bits(wdata);
   (* ram_style = "block" *)
   logic[TAG_ENTRY_WIDTH-1:0] array [0:2**CACHE_INDEX_WIDTH-1];
   tag_entry_t out;
   
   tag_entry_t init_data;
   initial begin
      for (int i=0;i<CACHE_NUM_WAYS;i++) begin
          init_data[i].state = INVALID;
          init_data[i].tag = 0;
          init_data[i].dirty = 0;
          init_data[i].prio = i;
      end
      for (integer i=0;i<2**CACHE_INDEX_WIDTH; i=i+1) begin
         array[i] = init_data;
      end
   end

   always_ff @(posedge clk) begin
      if (en) begin
         if (wr) begin 
            array[waddr] <= wdata;
         end
         out <= array[raddr];
      end
   end
   
   // ensure write first behaviour in simulation.
   logic addr_collision;
   tag_entry_t p_wdata;
   always @(posedge clk) begin
      if (en) begin
         addr_collision <= (wr & (waddr == raddr));
         p_wdata <= wdata;
      end
   end

   assign rdata = addr_collision ? p_wdata : out;

endmodule

module data_array 
( 
   input clk,
   input rstn,

   input data_addr_t addr,
   
   input cache_line_t wdata,
   output cache_line_t rdata,
   
   input en,
   input [63:0] wr

);
   (* ram_style = "ultra" *)
   cache_line_t array [0:(2**CACHE_INDEX_WIDTH)*CACHE_NUM_WAYS-1];
   generate genvar i;
   for (i=0;i<64;i=i+1)
      always_ff @(posedge clk) begin
         if (en) begin // Write First
            if (wr[i]) begin 
               array[addr][i*8 +:8] <= wdata[i*8 +:8];
               rdata[i*8 +:8] <= wdata[i*8 +:8];
            end else begin
               rdata[i*8 +:8] <= array[addr][i*8 +:8];
            end
         end
      end
   endgenerate

endmodule

module l2_stage_1
#( 
   parameter TILE_ID = 1,
   parameter BANK_ID = 0
) (
   input clk,
   input rstn,

   input                stall_in,
   
   // writes/read channel from cores
   input                c_wvalid,
   input mem_addr_t     c_waddr,
   input cache_line_t   c_wdata,
   input id_t           c_wid,
   input [63:0]         c_wstrb,
   output logic         c_wready,

   input                c_arvalid,
   input mem_addr_t     c_araddr,
   input id_t           c_arid,
   output logic         c_arready,

   input mshr_t         retry_rdata,
   input                retry_valid,
   output logic         retry_rd_en,
   input                retry_almost_full,

   // read from mem_ctrl returned
   input mshr_t         read_resp_mshr,
   input                read_resp_valid,
   input cache_line_t   read_resp_data,
   output logic         read_resp_ready,
   
   // tag_array interface
   output tag_addr_t    tag_raddr,
   output logic         tag_rvalid,
   
   // data to next pipe_stage
   output cache_line_t  p_wdata,
   output logic [63:0]  p_wstrb,
   output id_t          p_cid,
   output mem_addr_t    p_addr,
   output pipe_op_t     p_op,

   input                flush_valid,
   output logic         flush_ready,

   input flush_advance_tag // from Stage 2

);

   cache_line_t next_p_wdata;
   logic [63:0] next_p_wstrb;
   id_t         next_p_cid;
   mem_addr_t   next_p_addr;
   pipe_op_t    next_p_op;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         p_op <= NONE;
      end else begin
         p_wdata <= next_p_wdata;
         p_wstrb <= next_p_wstrb;
         p_cid <= next_p_cid;
         p_addr <= next_p_addr;
         p_op <= next_p_op;
      end
   end

   tag_addr_t flush_addr;
   logic in_flush;
   logic flush_advanced_last_cycle;

   // force this net in testbench for shorter simulation time
   tag_addr_t flush_addr_last;
   assign flush_addr_last = '1;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         flush_addr <= 0;
         in_flush <= 1'b0;
         flush_ready <= 1'b1;
         flush_advanced_last_cycle <= 1'b0;
      end else begin
         if (in_flush) begin
            if (flush_advance_tag & !flush_advanced_last_cycle) begin   
               flush_addr <= flush_addr + 1;
               if (flush_addr == flush_addr_last) begin
                  flush_ready <= 1'b1;
                  in_flush <= 1'b0;
               end
               flush_advanced_last_cycle <= 1'b1;
            end else begin
               flush_advanced_last_cycle <= 1'b0;
            end
         end else if (flush_valid) begin
            in_flush <= 1'b1;
            flush_addr <= 0;
            flush_ready <= 1'b0;
         end
      end
   end
   
   always_comb begin
      next_p_wdata = 'x;
      next_p_wstrb = 'x;
      next_p_cid = 'x;
      next_p_addr = 'x;
      next_p_op = NONE;

      c_wready = 1'b0;
      c_arready = 1'b0;
      read_resp_ready = 1'b0;

      retry_rd_en = 1'b0;
      
      tag_raddr = 'x;
      tag_rvalid = 1'b0;

      if (stall_in) begin
         next_p_op = p_op; // keep the last op
         next_p_wdata = p_wdata;
         next_p_wstrb = p_wstrb;
         next_p_cid = p_cid;
         next_p_addr = p_addr;
      end else begin
         if (in_flush) begin
            tag_raddr = flush_addr;
            tag_rvalid = 1'b1;
            next_p_op = FLUSH;
            next_p_addr.index = flush_addr;
         end else

         // priority for read_resp
         if (read_resp_valid) begin
            next_p_op = read_resp_mshr.is_read ? RESP_READ : RESP_WRITE;
            next_p_cid = read_resp_mshr.incoming_id;
            next_p_addr = read_resp_mshr.addr;
            for (integer i=0;i<64;i=i+1) begin
               next_p_wdata[i*8 +:8] = read_resp_mshr.wstrb[i] ? 
                                            read_resp_mshr.wdata[i*8 +:8] :
                                            read_resp_data[i*8 +:8];
            end
            next_p_wstrb = '1; // all 1

            read_resp_ready = 1'b1;
            tag_raddr = next_p_addr.index;
            tag_rvalid = 1'b1;
         end else if (!retry_almost_full & (c_wvalid | c_arvalid)) begin 
            // if the retry queue is (almost) full, take the conservative
            // approach. Do not take any new requests.
            if (c_wvalid) begin
               next_p_op = WRITE;
               next_p_cid = c_wid;
               next_p_addr = c_waddr;
               next_p_wdata = c_wdata;
               next_p_wstrb = c_wstrb;

               c_wready = 1'b1;
               tag_raddr = c_waddr.index;
               tag_rvalid = 1'b1;
            end else if (c_arvalid) begin
               next_p_op = READ;
               next_p_cid = c_arid;
               next_p_addr = c_araddr;
               next_p_wdata = 'x;
               next_p_wstrb = 0;

               c_arready = 1'b1;
               tag_raddr = c_araddr.index;
               tag_rvalid = 1'b1;
            end
         end else begin
            if (retry_valid) begin
               next_p_op = retry_rdata.is_read ? READ: WRITE;
               next_p_cid = retry_rdata.incoming_id;
               next_p_addr = retry_rdata.addr;
               next_p_wdata = retry_rdata.wdata;
               next_p_wstrb = retry_rdata.wstrb;

               retry_rd_en = 1'b1;
               tag_raddr = retry_rdata.addr.index;
               tag_rvalid = 1'b1;
            end
         end

      end
   end
   

endmodule

// Search through the returned tag entry for the ref_tag and output the way in
// which it is found. If not found return the LRU replacement way.
module lru_repl
(
   input tag_entry_t tag_rdata, // entry from tag array, contains all ways
   input [CACHE_TAG_WIDTH-1:0] ref_tag, // tag to search for

   input is_flush, // consider as hit if VALID

   output logic hit,
   output logic [CACHE_LOG_WAYS-1:0] way // if hit, found in which way; if miss, replacement way,
);

   // tree of comparators for finding the minimum prio ( replacement candidate) 
   typedef struct packed {
      lru_width_t prio;
      logic [CACHE_LOG_WAYS-1:0] id;
      logic hit;
   } tree_node;   

   tree_node tree [CACHE_LOG_WAYS+1][CACHE_NUM_WAYS];
   genvar i,j;
   
   generate 
      for (i=0;i<CACHE_NUM_WAYS;i++) begin
         assign tree[CACHE_LOG_WAYS][i].prio    = tag_rdata[i].prio;
         assign tree[CACHE_LOG_WAYS][i].id    = i;
         assign tree[CACHE_LOG_WAYS][i].hit   =
               is_flush ? 
                  (tag_rdata[i].state == VALID) && (tag_rdata[i].dirty):
                  ( tag_rdata[i].state != INVALID) && (tag_rdata[i].tag == ref_tag);
      end

   endgenerate

   generate
      for (i=CACHE_LOG_WAYS-1;i>=0;i--) begin
         for (j=0;j< 2**i;  j++) begin
            always_comb begin
               if (tree[i+1][2*j].hit) begin
                  tree[i][j] = tree[i+1][j*2];
               end else if (tree[i+1][j*2+1].hit) begin 
                  tree[i][j] = tree[i+1][j*2+1];
               end else begin
                  tree[i][j] = (tree[i+1][j*2].prio < tree[i+1][j*2+1].prio) ? 
                                             tree[i+1][j*2] : tree[i+1][j*2+1];
               end
            end
         end
      end
   endgenerate


   assign way = tree[0][0].id;
   assign hit = tree[0][0].hit; 
   

endmodule

module l2_stage_2
#( 
   parameter TILE_ID = 1,
   parameter BANK_ID = 0
) (
   input clk,
   input rstn,
   
   input                stall_in,
   output logic         stall_out,

   // tag_array output
   input tag_entry_t    tag_entry,
   
   // tag_array write port
   output tag_addr_t    tag_waddr,
   output logic         tag_wen,
   output tag_entry_t   tag_wdata,

   // from previous pipe_stage
   input cache_line_t   i_wdata,
   input [63:0]         i_wstrb,
   input id_t           i_cid,
   input mem_addr_t     i_addr,
   input pipe_op_t      i_op, 

   // mem_ctrl axi aw and ar
   output logic         m_awvalid,
   output logic [63:0]  m_awaddr,
   output logic [15:0]  m_awid,
   input                m_awready,

   output logic         m_arvalid,
   output logic [63:0]  m_araddr,
   output logic [15:0]  m_arid,
   input                m_arready,

   // retry_fifo. Note that fullness is checked before stage 1
   output mshr_t        retry_wdata,
   output logic         retry_wr_en,
  
   // MSHRs
   input                mshr_available,
   input mshr_addr_t    mshr_next,
   output logic         mshr_set, // grab mshr_next
   output mshr_t        mshr_data,

   // data_array, read/write
   output data_addr_t   d_addr,
   output cache_line_t  d_wdata,
   output logic         d_en,
   output logic [63:0]  d_wr,

   // next pipe stage
   output pipe_op_t     p_op,
   output id_t          p_cid,
   output id_t          p_mid,

   output logic         flush_advance_tag,

   input write_buf_available,
   input [LOG_N_MSHR-1:0] write_buf_id,

   input write_buf_match,

   input circulate_on_mem_stall,


   // debug
   output logic [CACHE_LOG_WAYS-1:0] log_way,
   output logic log_hit

);

   pipe_op_t next_p_op;
   id_t next_p_cid, next_p_mid;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         p_op <= NONE;
      end else begin
         p_op <= next_p_op;
         p_cid <= next_p_cid;
         p_mid <= next_p_mid;
      end
   end

   id_t mshr_next_id;
   assign mshr_next_id = {12'b0, mshr_next};

   // which way to replace with
   logic [CACHE_LOG_WAYS-1:0] way;
   logic hit;
   lru_repl REPL (
      .tag_rdata(tag_entry),
      .ref_tag(i_addr.tag),

      .is_flush(i_op == FLUSH),

      .hit(hit),
      .way(way)
   );
   logic writeback_required; 
   // a simple assign statement does not work here. I suppose the 'way'
   // indirect indexing is not captured properly in simulations
   always_comb begin
      writeback_required = (tag_entry[way].state==VALID & tag_entry[way].dirty); 
      flush_advance_tag = (i_op == FLUSH) & ( (tag_entry[way].state != VALID) | !tag_entry[way].dirty);
   end

   assign log_hit = hit;
   assign log_way = way;

   always_comb begin
      next_p_op = NONE;
      next_p_cid = 'x;
      next_p_mid = 'x;

      retry_wr_en = 1'b0;
      retry_wdata = 'x;
         
      stall_out = 1'b0;

      tag_wen = 1'b0;
      tag_waddr = 'x;
      tag_wdata = tag_entry;

      m_awaddr = 'x;
      m_awid = 'x;
      m_awvalid = 1'b0;

      m_araddr = 'x;
      m_arid = 'x;
      m_arvalid = 1'b0;

      mshr_set = 1'b0;
      mshr_data = 'x;

      d_addr = 'x;
      d_wdata = 'x;
      d_wr = '0;
      d_en = 1'b0;

      if (stall_in) begin 
         next_p_op = p_op;
         next_p_cid = p_cid;
         next_p_mid = p_mid;
      end else begin   
         case (i_op) 
            FLUSH : begin
               if (!flush_advance_tag & writeback_required) begin
                  m_awaddr = {tag_entry[way].tag, i_addr.index, 6'b0};
                  m_awid = (TILE_ID << 10) + (1<<15) + (BANK_ID<<8) + write_buf_id;

                  m_awvalid = write_buf_available; 
                  if (m_awready & m_awvalid) begin
                     next_p_op = EVICT;
                     d_addr = i_addr.index * CACHE_NUM_WAYS + way;
                     d_en = 1'b1;
                     next_p_mid = write_buf_id;
                     
                     tag_wen = 1'b1;
                     tag_wdata[way].state = INVALID;
                     tag_waddr = i_addr.index;
                     tag_wdata[way].tag = 'x;
                     // Selected way is invalid. Select it as the most likely
                     // replacement target
                     for (int i=0;i<CACHE_NUM_WAYS;i++) begin
                        if (i== way) begin
                           tag_wdata[i].prio = 0;
                        end else if (tag_entry[i].prio < tag_entry[way].prio) begin
                           tag_wdata[i].prio = tag_entry[i].prio + 1 ;
                        end 
                     end
                  end else begin
                     stall_out = 1'b1;
                  end
               end else begin
                  for (int i=0;i <CACHE_NUM_WAYS;i++) begin
                     tag_wdata[i].state = INVALID;
                     tag_wdata[i].prio = i;
                     tag_wdata[i].dirty = 0;
                     tag_wen = 1'b1;
                     tag_waddr = i_addr.index;
                  end
               end
            end
            READ, WRITE: begin
               if ( tag_entry[way].state == PENDING) begin
                  // A request for this addr is pending (or no non-pending ways) . Push to the
                  // retry_fifo
                  retry_wr_en = 1'b1;
                  retry_wdata.incoming_id = i_cid;
                  retry_wdata.is_read = (i_op == READ);
                  retry_wdata.addr = i_addr;
                  retry_wdata.wdata = i_wdata;
                  retry_wdata.wstrb = i_wstrb;
               end else if (hit) begin
                  d_addr = i_addr.index * CACHE_NUM_WAYS + way ;
                  d_en = 1'b1;
                  next_p_cid = i_cid;
                  if (i_op == READ) begin
                     next_p_op = READ;
                  end else begin
                     d_wdata = i_wdata;
                     d_wr = i_wstrb;
                     next_p_op = WRITE;
                     tag_wen = 1'b1;
                     tag_waddr = i_addr.index;
                     tag_wdata[way].dirty = 1'b1;
                     // Make this the least likely replacement target. 
                     for (int i=0;i<CACHE_NUM_WAYS;i++) begin
                        if (i== way) begin
                           tag_wdata[i].prio = CACHE_NUM_WAYS - 1;
                        end else if (tag_entry[i].prio > tag_entry[way].prio) begin
                           tag_wdata[i].prio = tag_entry[i].prio - 1 ;
                        end 
                     end
                  end
               end else begin // miss
                  if (write_buf_match) begin
                     // The request address was recently evicted which has not
                     // completed yet
                     retry_wr_en = 1'b1;
                     retry_wdata.incoming_id = i_cid;
                     retry_wdata.is_read = (i_op == READ);
                     retry_wdata.addr = i_addr;
                     retry_wdata.wdata = i_wdata;
                     retry_wdata.wstrb = i_wstrb;
                  end else begin
                     m_awaddr = {tag_entry[way].tag, i_addr.index, 6'b0};
                     m_awid = (TILE_ID <<10)+ (1<<15)+ (BANK_ID<<8) + write_buf_id;

                     m_araddr = i_addr;
                     m_arid = (TILE_ID << 10)+ (1<<15) + (BANK_ID<<8) + mshr_next_id;
                    
                     mshr_data.incoming_id = i_cid;
                     mshr_data.is_read = (i_op == READ);
                     mshr_data.addr = i_addr;
                     mshr_data.wdata = i_wdata;
                     mshr_data.wstrb = i_wstrb;
                     
                     // valid depends on ready, this is not ideal but makes life
                     // easy.
                     if (mshr_available & m_arready  & 
                        (!writeback_required| (m_awready & write_buf_available ))) begin
                        m_arvalid = 1'b1;   
                        m_awvalid = writeback_required; 
                        mshr_set = 1'b1;
                        stall_out = 1'b0;
                        if (writeback_required) begin // if dirty
                           next_p_op = EVICT;
                           next_p_mid = write_buf_id;
                           d_addr = i_addr.index * CACHE_NUM_WAYS + way;
                           d_en = 1'b1;
                        end
                        tag_wen = 1'b1;
                        tag_wdata[way].state = PENDING;
                        tag_waddr = i_addr.index;
                        tag_wdata[way].tag = i_addr.tag;
                        // least priority replacement candidate. 
                        for (int i=0;i<CACHE_NUM_WAYS;i++) begin
                           if (i== way) begin
                              tag_wdata[i].prio = CACHE_NUM_WAYS - 1;
                           end else if (tag_entry[i].prio > tag_entry[way].prio) begin
                              tag_wdata[i].prio = tag_entry[i].prio - 1 ;
                           end 
                        end
                     end else begin
                        if (circulate_on_mem_stall) begin
                           retry_wr_en = 1'b1;
                           retry_wdata.incoming_id = i_cid;
                           retry_wdata.is_read = (i_op == READ);
                           retry_wdata.addr = i_addr;
                           retry_wdata.wdata = i_wdata;
                           retry_wdata.wstrb = i_wstrb;
                        end else begin
                           stall_out = 1'b1;
                        end
                     end
                  end
               end
            end
            RESP_READ, RESP_WRITE: begin
               // The response from memory received for what was originally
               // a READ/WRITE
               tag_wen = 1'b1;
               tag_wdata[way].state = VALID;
               tag_wdata[way].dirty = (i_op == RESP_WRITE);
               // priority no change
               tag_waddr = i_addr.index;

               d_en = 1'b1;
               d_wr = i_wstrb;
               d_wdata = i_wdata;
               d_addr = i_addr.index * CACHE_NUM_WAYS + way;

               next_p_cid = i_cid;
               if (i_op==RESP_READ) begin
                  next_p_op = READ;
               end else begin
                  next_p_op = WRITE;
               end
            end
            default: begin // NONE
               // nothing to do
            end
         endcase
      end

   end

endmodule



module l2_stage_3
#( 
   parameter TILE_ID = 1,
   parameter BANK_ID = 0
) (
   input clk,
   input rstn,

   output logic         stall_out,

   input pipe_op_t      i_op,
   input id_t           i_cid,
   input id_t           i_mid,

   input cache_line_t   d_rdata,

   input                c_rready,
   output cache_line_t  c_rdata,
   output logic         c_rvalid,
   output id_t          c_rid,

   input                c_bready,
   output logic         c_bvalid,
   output id_t          c_bid,

   output id_t          m_wid,
   output cache_line_t  m_wdata,
   output logic [63:0]  m_wstrb, // all 1s
   output logic         m_wvalid,
   output logic         m_wlast,
   input                m_wready

);

   always_comb begin
      c_rdata = 'x;
      c_rvalid = 1'b0;
      c_rid = 'x;

      c_bvalid = 1'b0;
      c_bid = 'x;

      m_wid = 'x;
      m_wdata = 'x;
      m_wstrb = '1;
      m_wvalid = 1'b0;
      m_wlast = 1'b1;

      stall_out = 1'b0;
      case (i_op) 
         READ: begin
            c_rdata = d_rdata;
            c_rvalid = 1'b1;
            c_rid = i_cid;
            if (!c_rready) begin
               stall_out = 1'b1;
            end 
         end
         WRITE: begin
            c_bvalid = 1'b1;
            c_bid = i_cid;
            if (!c_bready) begin
               stall_out = 1'b1;
            end
         end
         EVICT: begin
            if (!m_wready) begin
               stall_out = 1'b1;
            end else begin
               m_wdata = d_rdata;
               m_wvalid = 1'b1;
               m_wid = (TILE_ID << 10) + (1<<15) + (BANK_ID<<8) + i_mid;
            end
         end
         default: begin
            // nothing to do. make compiler happy
         end
      endcase
   end

endmodule

module mshr_manager ( 
   input clk,
   input rstn,

   input mshr_addr_t    read_addr,
   input                mshr_clear, // clear the entry at read_addr (works as rd_en)
   output mshr_t        rd_data,

   output mshr_addr_t   next_available,
   output logic         mshr_available,
   input mshr_t         wr_data,
   input                mshr_claim,

   output logic [31:0]  debug_mshr_valid
); 
   localparam N_MSHR = 2**LOG_N_MSHR;
   mshr_t mem[0:N_MSHR-1];

   logic [N_MSHR-1:0] mshr_valid;
   mshr_addr_t mshr_next;

   lowbit #(.OUT_WIDTH(LOG_N_MSHR)) MSHR_NEXT (
      .in(~mshr_valid),
      .out(mshr_next)
   );

   assign debug_mshr_valid = mshr_valid;

   always_comb begin
      mshr_available = !mshr_valid[mshr_next];
      next_available = mshr_next;
   end

   always_ff @(posedge clk) begin
      if (mshr_clear) begin
         rd_data <= mem[read_addr];
      end
      if (mshr_claim) begin
         mem[mshr_next] <= wr_data;
      end
   end

   always_ff @(posedge clk) begin
      if (!rstn) begin
         mshr_valid <= 0;
      end else begin
         if (mshr_clear) begin
            mshr_valid[read_addr] <= 1'b0;
         end
         if (mshr_claim) begin
            mshr_valid[mshr_next] <= 1'b1;
         end
      end
   end

endmodule

module write_buffer (
   input clk,
   input rstn,

   input mem_addr_t check_addr,

   // from mem ctrl
   input id_t bid,
   input bvalid,
   output logic bready,

   // from/to l2_stage 2
   input awvalid,
   input mem_addr_t awaddr,
   output logic awready,
   // l2 handles the AW channel, this module only supplies the id 
   output logic [LOG_N_MSHR-1:0] awid, 

   //if a writeback for this address is ongoing.
   output logic match,

   output logic [15:0] debug_mshr_valid

);

   localparam N_MSHR = 2**LOG_N_MSHR;
   mem_addr_t mem[0:N_MSHR-1];

   logic [N_MSHR-1:0] mshr_valid;
   mshr_addr_t mshr_next;

   assign debug_mshr_valid = mshr_valid;

   lowbit #(.OUT_WIDTH(LOG_N_MSHR)) MSHR_NEXT (
      .in(~mshr_valid),
      .out(mshr_next)
   );
   
   always_comb begin
      awready = !mshr_valid[mshr_next];
      awid = mshr_next;
   end
   assign bready = 1'b1;

   always_ff @(posedge clk) begin
      if (!rstn) begin
         mshr_valid <= 0;
      end else begin
         if (bvalid) begin
            mshr_valid[bid[LOG_N_MSHR-1:0] ] <= 1'b0;
         end
         if (awvalid & awready) begin
            mshr_valid[mshr_next] <= 1'b1;
            mem[mshr_next] <= awaddr;
         end
      end
   end

   logic [N_MSHR-1:0] local_match;
   generate genvar i;
      for (i=0;i<N_MSHR;i++) begin
         assign local_match[i] = mshr_valid[i] & (mem[i] == check_addr);
      end
   endgenerate
   assign match = |local_match;

endmodule

module memory_response_handler (
   input clk,
   input rstn,

   input cache_line_t   m_rdata,
   input logic          m_rvalid,
   input [15:0]         m_rid,
   output logic         m_rready,

   output mshr_addr_t   mshr_addr,
   output logic         mshr_clear,


   output reg           out_valid,
   output cache_line_t  out_data,
   input                out_ready

); 
   
   logic can_take_request;
   // can process a new mem response if one was not processed in prev cycle
   // or the one processed was immediately taken by the next stage
   // TODO: change name to m_rrready
   assign can_take_request = !out_valid | out_ready;

   always_comb begin
      mshr_clear = 1'b0;
      mshr_addr = 'x;
      m_rready = 1'b0;
      if (can_take_request) begin
       // no dependence on rvalid. This is a signal where we do not control
       // the master
         m_rready = 1'b1;
         if (m_rvalid) begin
            mshr_clear = 1'b1;
            mshr_addr = m_rid[LOG_N_MSHR-1:0]; 
         end
      end
   end

   always_ff @(posedge clk) begin
      if (!rstn) begin
         out_valid <= 1'b0;
      end else begin
         if (can_take_request & m_rvalid) begin
            out_valid <= 1'b1;
            out_data <= m_rdata;
         end else if (out_ready) begin
            out_valid <= 1'b0;
         end
      end

   end

endmodule
