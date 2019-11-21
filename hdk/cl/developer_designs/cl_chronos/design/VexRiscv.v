// Generator : SpinalHDL v1.2.0    git head : cf3b44dbd881428e70669e5b623479c23b2d0ddd
// Date      : 28/11/2018, 02:46:56
// Component : VexRiscv


`define AluCtrlEnum_defaultEncoding_type [1:0]
`define AluCtrlEnum_defaultEncoding_ADD_SUB 2'b00
`define AluCtrlEnum_defaultEncoding_SLT_SLTU 2'b01
`define AluCtrlEnum_defaultEncoding_BITWISE 2'b10

`define AluBitwiseCtrlEnum_defaultEncoding_type [1:0]
`define AluBitwiseCtrlEnum_defaultEncoding_XOR_1 2'b00
`define AluBitwiseCtrlEnum_defaultEncoding_OR_1 2'b01
`define AluBitwiseCtrlEnum_defaultEncoding_AND_1 2'b10
`define AluBitwiseCtrlEnum_defaultEncoding_SRC1 2'b11

`define BranchCtrlEnum_defaultEncoding_type [1:0]
`define BranchCtrlEnum_defaultEncoding_INC 2'b00
`define BranchCtrlEnum_defaultEncoding_B 2'b01
`define BranchCtrlEnum_defaultEncoding_JAL 2'b10
`define BranchCtrlEnum_defaultEncoding_JALR 2'b11

`define ShiftCtrlEnum_defaultEncoding_type [1:0]
`define ShiftCtrlEnum_defaultEncoding_DISABLE_1 2'b00
`define ShiftCtrlEnum_defaultEncoding_SLL_1 2'b01
`define ShiftCtrlEnum_defaultEncoding_SRL_1 2'b10
`define ShiftCtrlEnum_defaultEncoding_SRA_1 2'b11

`define Src1CtrlEnum_defaultEncoding_type [1:0]
`define Src1CtrlEnum_defaultEncoding_RS 2'b00
`define Src1CtrlEnum_defaultEncoding_IMU 2'b01
`define Src1CtrlEnum_defaultEncoding_PC_INCREMENT 2'b10

`define EnvCtrlEnum_defaultEncoding_type [1:0]
`define EnvCtrlEnum_defaultEncoding_NONE 2'b00
`define EnvCtrlEnum_defaultEncoding_EBREAK 2'b01
`define EnvCtrlEnum_defaultEncoding_MRET 2'b10

`define Src2CtrlEnum_defaultEncoding_type [1:0]
`define Src2CtrlEnum_defaultEncoding_RS 2'b00
`define Src2CtrlEnum_defaultEncoding_IMI 2'b01
`define Src2CtrlEnum_defaultEncoding_IMS 2'b10
`define Src2CtrlEnum_defaultEncoding_PC 2'b11

module InstructionCache (
      input   io_flush_cmd_valid,
      output  io_flush_cmd_ready,
      output  io_flush_rsp,
      input   io_cpu_prefetch_isValid,
      output reg  io_cpu_prefetch_haltIt,
      input  [31:0] io_cpu_prefetch_pc,
      input   io_cpu_fetch_isValid,
      input   io_cpu_fetch_isStuck,
      input   io_cpu_fetch_isRemoved,
      input  [31:0] io_cpu_fetch_pc,
      output [31:0] io_cpu_fetch_data,
      output  io_cpu_fetch_mmuBus_cmd_isValid,
      output [31:0] io_cpu_fetch_mmuBus_cmd_virtualAddress,
      output  io_cpu_fetch_mmuBus_cmd_bypassTranslation,
      input  [31:0] io_cpu_fetch_mmuBus_rsp_physicalAddress,
      input   io_cpu_fetch_mmuBus_rsp_isIoAccess,
      input   io_cpu_fetch_mmuBus_rsp_allowRead,
      input   io_cpu_fetch_mmuBus_rsp_allowWrite,
      input   io_cpu_fetch_mmuBus_rsp_allowExecute,
      input   io_cpu_fetch_mmuBus_rsp_allowUser,
      input   io_cpu_fetch_mmuBus_rsp_miss,
      input   io_cpu_fetch_mmuBus_rsp_hit,
      output  io_cpu_fetch_mmuBus_end,
      output [31:0] io_cpu_fetch_physicalAddress,
      input   io_cpu_decode_isValid,
      input   io_cpu_decode_isStuck,
      input  [31:0] io_cpu_decode_pc,
      output [31:0] io_cpu_decode_physicalAddress,
      output [31:0] io_cpu_decode_data,
      output  io_cpu_decode_cacheMiss,
      output  io_cpu_decode_error,
      output  io_cpu_decode_mmuMiss,
      output  io_cpu_decode_illegalAccess,
      input   io_cpu_decode_isUser,
      input   io_cpu_fill_valid,
      input  [31:0] io_cpu_fill_payload,
      output  io_mem_cmd_valid,
      input   io_mem_cmd_ready,
      output [31:0] io_mem_cmd_payload_address,
      output [2:0] io_mem_cmd_payload_size,
      input   io_mem_rsp_valid,
      input  [31:0] io_mem_rsp_payload_data,
      input   io_mem_rsp_payload_error,
      input   clk,
      input   reset);
  reg [21:0] _zz_12_;
  reg [31:0] _zz_13_;
  wire  _zz_14_;
  wire [0:0] _zz_15_;
  wire [0:0] _zz_16_;
  wire [21:0] _zz_17_;
  reg  _zz_1_;
  reg  _zz_2_;
  reg  lineLoader_fire;
  reg  lineLoader_valid;
  reg [31:0] lineLoader_address;
  reg  lineLoader_hadError;
  reg [7:0] lineLoader_flushCounter;
  reg  _zz_3_;
  reg  lineLoader_flushFromInterface;
  wire  _zz_4_;
  reg  _zz_4__regNext;
  reg  lineLoader_cmdSent;
  reg  lineLoader_wayToAllocate_willIncrement;
  wire  lineLoader_wayToAllocate_willClear;
  wire  lineLoader_wayToAllocate_willOverflowIfInc;
  wire  lineLoader_wayToAllocate_willOverflow;
  reg [2:0] lineLoader_wordIndex;
  wire  lineLoader_write_tag_0_valid;
  wire [6:0] lineLoader_write_tag_0_payload_address;
  wire  lineLoader_write_tag_0_payload_data_valid;
  wire  lineLoader_write_tag_0_payload_data_error;
  wire [19:0] lineLoader_write_tag_0_payload_data_address;
  wire  lineLoader_write_data_0_valid;
  wire [9:0] lineLoader_write_data_0_payload_address;
  wire [31:0] lineLoader_write_data_0_payload_data;
  wire  _zz_5_;
  wire [6:0] _zz_6_;
  wire  _zz_7_;
  wire  fetchStage_read_waysValues_0_tag_valid;
  wire  fetchStage_read_waysValues_0_tag_error;
  wire [19:0] fetchStage_read_waysValues_0_tag_address;
  wire [21:0] _zz_8_;
  wire [9:0] _zz_9_;
  wire  _zz_10_;
  wire [31:0] fetchStage_read_waysValues_0_data;
  reg [31:0] decodeStage_mmuRsp_physicalAddress;
  reg  decodeStage_mmuRsp_isIoAccess;
  reg  decodeStage_mmuRsp_allowRead;
  reg  decodeStage_mmuRsp_allowWrite;
  reg  decodeStage_mmuRsp_allowExecute;
  reg  decodeStage_mmuRsp_allowUser;
  reg  decodeStage_mmuRsp_miss;
  reg  decodeStage_mmuRsp_hit;
  reg  decodeStage_hit_0_valid;
  reg  decodeStage_hit_0_error;
  reg [19:0] decodeStage_hit_0_address;
  wire  decodeStage_hit_hits_0;
  wire  decodeStage_hit_valid;
  wire  decodeStage_hit_error;
  reg [31:0] _zz_11_;
  wire [31:0] decodeStage_hit_data;
  wire [31:0] decodeStage_hit_word;
  (* ram_style = "block" *)
  reg [21:0] ways_0_tags [0:127];
  (* ram_style = "block" *)
  reg [31:0] ways_0_datas [0:1023];
  assign _zz_14_ = (! lineLoader_flushCounter[7]);
  assign _zz_15_ = _zz_8_[0 : 0];
  assign _zz_16_ = _zz_8_[1 : 1];
  assign _zz_17_ = {lineLoader_write_tag_0_payload_data_address,{lineLoader_write_tag_0_payload_data_error,lineLoader_write_tag_0_payload_data_valid}};
  always @ (posedge clk) begin
    if(_zz_2_) begin
      ways_0_tags[lineLoader_write_tag_0_payload_address] <= _zz_17_;
    end
  end

  always @ (posedge clk) begin
    if(_zz_7_) begin
      _zz_12_ <= ways_0_tags[_zz_6_];
    end
  end

  always @ (posedge clk) begin
    if(_zz_1_) begin
      ways_0_datas[lineLoader_write_data_0_payload_address] <= lineLoader_write_data_0_payload_data;
    end
  end

  always @ (posedge clk) begin
    if(_zz_10_) begin
      _zz_13_ <= ways_0_datas[_zz_9_];
    end
  end

  always @ (*) begin
    _zz_1_ = 1'b0;
    if(lineLoader_write_data_0_valid)begin
      _zz_1_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_2_ = 1'b0;
    if(lineLoader_write_tag_0_valid)begin
      _zz_2_ = 1'b1;
    end
  end

  always @ (*) begin
    io_cpu_prefetch_haltIt = 1'b0;
    if(lineLoader_valid)begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
    if(_zz_14_)begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
    if((! _zz_3_))begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
    if(io_flush_cmd_valid)begin
      io_cpu_prefetch_haltIt = 1'b1;
    end
  end

  always @ (*) begin
    lineLoader_fire = 1'b0;
    if(io_mem_rsp_valid)begin
      if((lineLoader_wordIndex == (3'b111)))begin
        lineLoader_fire = 1'b1;
      end
    end
  end

  assign io_flush_cmd_ready = (! (lineLoader_valid || io_cpu_fetch_isValid));
  assign _zz_4_ = lineLoader_flushCounter[7];
  assign io_flush_rsp = ((_zz_4_ && (! _zz_4__regNext)) && lineLoader_flushFromInterface);
  assign io_mem_cmd_valid = (lineLoader_valid && (! lineLoader_cmdSent));
  assign io_mem_cmd_payload_address = {lineLoader_address[31 : 5],(5'b00000)};
  assign io_mem_cmd_payload_size = (3'b101);
  always @ (*) begin
    lineLoader_wayToAllocate_willIncrement = 1'b0;
    if(lineLoader_fire)begin
      lineLoader_wayToAllocate_willIncrement = 1'b1;
    end
  end

  assign lineLoader_wayToAllocate_willClear = 1'b0;
  assign lineLoader_wayToAllocate_willOverflowIfInc = 1'b1;
  assign lineLoader_wayToAllocate_willOverflow = (lineLoader_wayToAllocate_willOverflowIfInc && lineLoader_wayToAllocate_willIncrement);
  assign _zz_5_ = 1'b1;
  assign lineLoader_write_tag_0_valid = ((_zz_5_ && lineLoader_fire) || (! lineLoader_flushCounter[7]));
  assign lineLoader_write_tag_0_payload_address = (lineLoader_flushCounter[7] ? lineLoader_address[11 : 5] : lineLoader_flushCounter[6 : 0]);
  assign lineLoader_write_tag_0_payload_data_valid = lineLoader_flushCounter[7];
  assign lineLoader_write_tag_0_payload_data_error = (lineLoader_hadError || io_mem_rsp_payload_error);
  assign lineLoader_write_tag_0_payload_data_address = lineLoader_address[31 : 12];
  assign lineLoader_write_data_0_valid = (io_mem_rsp_valid && _zz_5_);
  assign lineLoader_write_data_0_payload_address = {lineLoader_address[11 : 5],lineLoader_wordIndex};
  assign lineLoader_write_data_0_payload_data = io_mem_rsp_payload_data;
  assign _zz_6_ = io_cpu_prefetch_pc[11 : 5];
  assign _zz_7_ = (! io_cpu_fetch_isStuck);
  assign _zz_8_ = _zz_12_;
  assign fetchStage_read_waysValues_0_tag_valid = _zz_15_[0];
  assign fetchStage_read_waysValues_0_tag_error = _zz_16_[0];
  assign fetchStage_read_waysValues_0_tag_address = _zz_8_[21 : 2];
  assign _zz_9_ = io_cpu_prefetch_pc[11 : 2];
  assign _zz_10_ = (! io_cpu_fetch_isStuck);
  assign fetchStage_read_waysValues_0_data = _zz_13_;
  assign io_cpu_fetch_data = fetchStage_read_waysValues_0_data[31 : 0];
  assign io_cpu_fetch_mmuBus_cmd_isValid = io_cpu_fetch_isValid;
  assign io_cpu_fetch_mmuBus_cmd_virtualAddress = io_cpu_fetch_pc;
  assign io_cpu_fetch_mmuBus_cmd_bypassTranslation = 1'b0;
  assign io_cpu_fetch_mmuBus_end = ((! io_cpu_fetch_isStuck) || io_cpu_fetch_isRemoved);
  assign io_cpu_fetch_physicalAddress = io_cpu_fetch_mmuBus_rsp_physicalAddress;
  assign decodeStage_hit_hits_0 = (decodeStage_hit_0_valid && (decodeStage_hit_0_address == decodeStage_mmuRsp_physicalAddress[31 : 12]));
  assign decodeStage_hit_valid = (decodeStage_hit_hits_0 != (1'b0));
  assign decodeStage_hit_error = decodeStage_hit_0_error;
  assign decodeStage_hit_data = _zz_11_;
  assign decodeStage_hit_word = decodeStage_hit_data[31 : 0];
  assign io_cpu_decode_data = decodeStage_hit_word;
  assign io_cpu_decode_cacheMiss = (! decodeStage_hit_valid);
  assign io_cpu_decode_error = decodeStage_hit_error;
  assign io_cpu_decode_mmuMiss = decodeStage_mmuRsp_miss;
  assign io_cpu_decode_illegalAccess = ((! decodeStage_mmuRsp_allowExecute) || (io_cpu_decode_isUser && (! decodeStage_mmuRsp_allowUser)));
  assign io_cpu_decode_physicalAddress = decodeStage_mmuRsp_physicalAddress;
  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      lineLoader_valid <= 1'b0;
      lineLoader_hadError <= 1'b0;
      lineLoader_flushCounter <= (8'b00000000);
      lineLoader_flushFromInterface <= 1'b0;
      lineLoader_cmdSent <= 1'b0;
      lineLoader_wordIndex <= (3'b000);
    end else begin
      if(lineLoader_fire)begin
        lineLoader_valid <= 1'b0;
      end
      if(lineLoader_fire)begin
        lineLoader_hadError <= 1'b0;
      end
      if(io_cpu_fill_valid)begin
        lineLoader_valid <= 1'b1;
      end
      if(_zz_14_)begin
        lineLoader_flushCounter <= (lineLoader_flushCounter + (8'b00000001));
      end
      if(io_flush_cmd_valid)begin
        if(io_flush_cmd_ready)begin
          lineLoader_flushCounter <= (8'b00000000);
          lineLoader_flushFromInterface <= 1'b1;
        end
      end
      if((io_mem_cmd_valid && io_mem_cmd_ready))begin
        lineLoader_cmdSent <= 1'b1;
      end
      if(lineLoader_fire)begin
        lineLoader_cmdSent <= 1'b0;
      end
      if(io_mem_rsp_valid)begin
        lineLoader_wordIndex <= (lineLoader_wordIndex + (3'b001));
        if(io_mem_rsp_payload_error)begin
          lineLoader_hadError <= 1'b1;
        end
      end
    end
  end

  always @ (posedge clk) begin
    if(io_cpu_fill_valid)begin
      lineLoader_address <= io_cpu_fill_payload;
    end
    _zz_3_ <= lineLoader_flushCounter[7];
    _zz_4__regNext <= _zz_4_;
    if((! io_cpu_decode_isStuck))begin
      decodeStage_mmuRsp_physicalAddress <= io_cpu_fetch_mmuBus_rsp_physicalAddress;
      decodeStage_mmuRsp_isIoAccess <= io_cpu_fetch_mmuBus_rsp_isIoAccess;
      decodeStage_mmuRsp_allowRead <= io_cpu_fetch_mmuBus_rsp_allowRead;
      decodeStage_mmuRsp_allowWrite <= io_cpu_fetch_mmuBus_rsp_allowWrite;
      decodeStage_mmuRsp_allowExecute <= io_cpu_fetch_mmuBus_rsp_allowExecute;
      decodeStage_mmuRsp_allowUser <= io_cpu_fetch_mmuBus_rsp_allowUser;
      decodeStage_mmuRsp_miss <= io_cpu_fetch_mmuBus_rsp_miss;
      decodeStage_mmuRsp_hit <= io_cpu_fetch_mmuBus_rsp_hit;
    end
    if((! io_cpu_decode_isStuck))begin
      decodeStage_hit_0_valid <= fetchStage_read_waysValues_0_tag_valid;
      decodeStage_hit_0_error <= fetchStage_read_waysValues_0_tag_error;
      decodeStage_hit_0_address <= fetchStage_read_waysValues_0_tag_address;
    end
    if((! io_cpu_decode_isStuck))begin
      _zz_11_ <= fetchStage_read_waysValues_0_data;
    end
  end

endmodule

module VexRiscv (
      input   timerInterrupt,
      input   externalInterrupt,
      output  iBus_cmd_valid,
      input   iBus_cmd_ready,
      output reg [31:0] iBus_cmd_payload_address,
      output [2:0] iBus_cmd_payload_size,
      input   iBus_rsp_valid,
      input  [31:0] iBus_rsp_payload_data,
      input   iBus_rsp_payload_error,
      output  dBus_cmd_valid,
      input   dBus_cmd_ready,
      output  dBus_cmd_payload_wr,
      output [31:0] dBus_cmd_payload_address,
      output [31:0] dBus_cmd_payload_data,
      output [1:0] dBus_cmd_payload_size,
      input   dBus_rsp_ready,
      input   dBus_rsp_error,
      input  [31:0] dBus_rsp_data,
      input   clk,
      output [31:0] debug_pc,
      input   reset);
  reg  _zz_166_;
  wire  _zz_167_;
  wire  _zz_168_;
  wire  _zz_169_;
  wire  _zz_170_;
  wire  _zz_171_;
  wire  _zz_172_;
  wire  _zz_173_;
  wire  _zz_174_;
  wire  _zz_175_;
  wire  _zz_176_;
  wire  _zz_177_;
  reg [55:0] _zz_178_;
  reg [31:0] _zz_179_;
  reg [31:0] _zz_180_;
  reg [31:0] _zz_181_;
  reg [3:0] _zz_182_;
  reg [31:0] _zz_183_;
  wire  _zz_184_;
  wire  _zz_185_;
  wire  _zz_186_;
  wire [31:0] _zz_187_;
  wire [31:0] _zz_188_;
  wire  _zz_189_;
  wire [31:0] _zz_190_;
  wire  _zz_191_;
  wire  _zz_192_;
  wire  _zz_193_;
  wire  _zz_194_;
  wire  _zz_195_;
  wire [31:0] _zz_196_;
  wire  _zz_197_;
  wire [31:0] _zz_198_;
  wire  _zz_199_;
  wire [31:0] _zz_200_;
  wire [2:0] _zz_201_;
  wire  _zz_202_;
  wire  _zz_203_;
  wire  _zz_204_;
  wire  _zz_205_;
  wire [1:0] _zz_206_;
  wire  _zz_207_;
  wire [2:0] _zz_208_;
  wire [2:0] _zz_209_;
  wire [31:0] _zz_210_;
  wire [7:0] _zz_211_;
  wire [21:0] _zz_212_;
  wire [29:0] _zz_213_;
  wire [7:0] _zz_214_;
  wire [1:0] _zz_215_;
  wire [0:0] _zz_216_;
  wire [1:0] _zz_217_;
  wire [0:0] _zz_218_;
  wire [1:0] _zz_219_;
  wire [1:0] _zz_220_;
  wire [0:0] _zz_221_;
  wire [1:0] _zz_222_;
  wire [0:0] _zz_223_;
  wire [1:0] _zz_224_;
  wire [0:0] _zz_225_;
  wire [0:0] _zz_226_;
  wire [0:0] _zz_227_;
  wire [0:0] _zz_228_;
  wire [0:0] _zz_229_;
  wire [0:0] _zz_230_;
  wire [0:0] _zz_231_;
  wire [0:0] _zz_232_;
  wire [0:0] _zz_233_;
  wire [0:0] _zz_234_;
  wire [0:0] _zz_235_;
  wire [2:0] _zz_236_;
  wire [11:0] _zz_237_;
  wire [11:0] _zz_238_;
  wire [31:0] _zz_239_;
  wire [31:0] _zz_240_;
  wire [31:0] _zz_241_;
  wire [31:0] _zz_242_;
  wire [1:0] _zz_243_;
  wire [31:0] _zz_244_;
  wire [1:0] _zz_245_;
  wire [1:0] _zz_246_;
  wire [32:0] _zz_247_;
  wire [31:0] _zz_248_;
  wire [32:0] _zz_249_;
  wire [1:0] _zz_250_;
  wire [1:0] _zz_251_;
  wire [2:0] _zz_252_;
  wire [3:0] _zz_253_;
  wire [4:0] _zz_254_;
  wire [31:0] _zz_255_;
  wire [19:0] _zz_256_;
  wire [11:0] _zz_257_;
  wire [11:0] _zz_258_;
  wire [0:0] _zz_259_;
  wire [0:0] _zz_260_;
  wire [0:0] _zz_261_;
  wire [0:0] _zz_262_;
  wire [0:0] _zz_263_;
  wire [0:0] _zz_264_;
  wire [55:0] _zz_265_;
  wire  _zz_266_;
  wire  _zz_267_;
  wire [1:0] _zz_268_;
  wire [31:0] _zz_269_;
  wire [31:0] _zz_270_;
  wire [31:0] _zz_271_;
  wire [31:0] _zz_272_;
  wire  _zz_273_;
  wire [0:0] _zz_274_;
  wire [0:0] _zz_275_;
  wire [1:0] _zz_276_;
  wire [1:0] _zz_277_;
  wire  _zz_278_;
  wire [0:0] _zz_279_;
  wire [17:0] _zz_280_;
  wire [31:0] _zz_281_;
  wire [31:0] _zz_282_;
  wire [31:0] _zz_283_;
  wire [31:0] _zz_284_;
  wire [31:0] _zz_285_;
  wire  _zz_286_;
  wire [1:0] _zz_287_;
  wire [1:0] _zz_288_;
  wire  _zz_289_;
  wire [0:0] _zz_290_;
  wire [14:0] _zz_291_;
  wire [31:0] _zz_292_;
  wire [31:0] _zz_293_;
  wire [31:0] _zz_294_;
  wire [31:0] _zz_295_;
  wire [31:0] _zz_296_;
  wire [31:0] _zz_297_;
  wire [0:0] _zz_298_;
  wire [4:0] _zz_299_;
  wire [0:0] _zz_300_;
  wire [0:0] _zz_301_;
  wire  _zz_302_;
  wire [0:0] _zz_303_;
  wire [11:0] _zz_304_;
  wire [31:0] _zz_305_;
  wire [31:0] _zz_306_;
  wire  _zz_307_;
  wire [0:0] _zz_308_;
  wire [1:0] _zz_309_;
  wire [31:0] _zz_310_;
  wire [31:0] _zz_311_;
  wire [31:0] _zz_312_;
  wire  _zz_313_;
  wire  _zz_314_;
  wire [0:0] _zz_315_;
  wire [8:0] _zz_316_;
  wire [31:0] _zz_317_;
  wire [31:0] _zz_318_;
  wire [31:0] _zz_319_;
  wire [31:0] _zz_320_;
  wire [31:0] _zz_321_;
  wire  _zz_322_;
  wire  _zz_323_;
  wire [0:0] _zz_324_;
  wire [0:0] _zz_325_;
  wire  _zz_326_;
  wire [0:0] _zz_327_;
  wire [5:0] _zz_328_;
  wire [31:0] _zz_329_;
  wire [31:0] _zz_330_;
  wire  _zz_331_;
  wire  _zz_332_;
  wire  _zz_333_;
  wire [1:0] _zz_334_;
  wire [1:0] _zz_335_;
  wire  _zz_336_;
  wire [0:0] _zz_337_;
  wire [1:0] _zz_338_;
  wire [31:0] _zz_339_;
  wire [31:0] _zz_340_;
  wire  _zz_341_;
  wire [0:0] _zz_342_;
  wire [0:0] _zz_343_;
  wire [1:0] _zz_344_;
  wire [1:0] _zz_345_;
  wire [3:0] _zz_346_;
  wire [3:0] _zz_347_;
  wire [31:0] _zz_348_;
  wire [31:0] _zz_349_;
  wire [31:0] _zz_350_;
  wire [31:0] _zz_351_;
  wire [31:0] _zz_352_;
  wire  _zz_353_;
  wire [31:0] _zz_354_;
  wire [31:0] _zz_355_;
  wire [31:0] _zz_356_;
  wire  _zz_357_;
  wire [0:0] _zz_358_;
  wire [11:0] _zz_359_;
  wire [31:0] _zz_360_;
  wire [31:0] _zz_361_;
  wire [31:0] _zz_362_;
  wire  _zz_363_;
  wire [0:0] _zz_364_;
  wire [5:0] _zz_365_;
  wire [31:0] _zz_366_;
  wire [31:0] _zz_367_;
  wire [31:0] _zz_368_;
  wire  _zz_369_;
  wire  _zz_370_;
  wire [31:0] memory_MEMORY_READ_DATA;
  wire  decode_PREDICTION_CONTEXT_hazard;
  wire  decode_PREDICTION_CONTEXT_hit;
  wire [21:0] decode_PREDICTION_CONTEXT_line_source;
  wire [1:0] decode_PREDICTION_CONTEXT_line_branchWish;
  wire [31:0] decode_PREDICTION_CONTEXT_line_target;
  wire `ShiftCtrlEnum_defaultEncoding_type decode_SHIFT_CTRL;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_1_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_2_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_3_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type decode_ALU_BITWISE_CTRL;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_4_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_5_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_6_;
  wire `AluCtrlEnum_defaultEncoding_type decode_ALU_CTRL;
  wire `AluCtrlEnum_defaultEncoding_type _zz_7_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_8_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_9_;
  wire `BranchCtrlEnum_defaultEncoding_type decode_BRANCH_CTRL;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_10_;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_11_;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_12_;
  wire  execute_FLUSH_ALL;
  wire  decode_FLUSH_ALL;
  wire [1:0] memory_MEMORY_ADDRESS_LOW;
  wire [1:0] execute_MEMORY_ADDRESS_LOW;
  wire `Src2CtrlEnum_defaultEncoding_type decode_SRC2_CTRL;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_13_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_14_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_15_;
  wire [31:0] writeBack_REGFILE_WRITE_DATA;
  wire [31:0] execute_REGFILE_WRITE_DATA;
  wire [31:0] memory_PC;
  wire [31:0] writeBack_FORMAL_PC_NEXT;
  wire [31:0] memory_FORMAL_PC_NEXT;
  wire [31:0] execute_FORMAL_PC_NEXT;
  wire [31:0] decode_FORMAL_PC_NEXT;
  wire `Src1CtrlEnum_defaultEncoding_type decode_SRC1_CTRL;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_16_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_17_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_18_;
  wire  decode_SRC_LESS_UNSIGNED;
  wire  decode_CSR_READ_OPCODE;
  wire  decode_CSR_WRITE_OPCODE;
  wire  execute_BYPASSABLE_MEMORY_STAGE;
  wire  decode_BYPASSABLE_MEMORY_STAGE;
  wire  decode_MEMORY_ENABLE;
  wire  decode_SRC_USE_SUB_LESS;
  wire  decode_BYPASSABLE_EXECUTE_STAGE;
  wire `EnvCtrlEnum_defaultEncoding_type decode_ENV_CTRL;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_19_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_20_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_21_;
  wire [31:0] execute_NEXT_PC2;
  wire [31:0] execute_BRANCH_CALC;
  wire  execute_BRANCH_DO;
  wire [31:0] _zz_22_;
  wire [31:0] _zz_23_;
  wire [31:0] execute_PC;
  wire [31:0] execute_RS1;
  wire `BranchCtrlEnum_defaultEncoding_type execute_BRANCH_CTRL;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_24_;
  wire  _zz_25_;
  wire  execute_CSR_READ_OPCODE;
  wire  execute_CSR_WRITE_OPCODE;
  wire [31:0] memory_REGFILE_WRITE_DATA;
  wire  execute_IS_CSR;
  wire  decode_IS_CSR;
  wire  _zz_26_;
  wire  _zz_27_;
  wire `EnvCtrlEnum_defaultEncoding_type execute_ENV_CTRL;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_28_;
  wire  decode_RS2_USE;
  wire  decode_RS1_USE;
  wire  execute_REGFILE_WRITE_VALID;
  wire  execute_BYPASSABLE_EXECUTE_STAGE;
  wire [31:0] _zz_29_;
  wire  memory_REGFILE_WRITE_VALID;
  wire  memory_BYPASSABLE_MEMORY_STAGE;
  wire  writeBack_REGFILE_WRITE_VALID;
  reg [31:0] decode_RS2;
  reg [31:0] decode_RS1;
  wire [31:0] execute_SHIFT_RIGHT;
  reg [31:0] _zz_30_;
  wire [31:0] _zz_31_;
  wire `ShiftCtrlEnum_defaultEncoding_type execute_SHIFT_CTRL;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_32_;
  wire  _zz_33_;
  wire [31:0] _zz_34_;
  wire [31:0] _zz_35_;
  wire  execute_SRC_LESS_UNSIGNED;
  wire  execute_SRC_USE_SUB_LESS;
  wire [31:0] _zz_36_;
  wire `Src2CtrlEnum_defaultEncoding_type execute_SRC2_CTRL;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_37_;
  wire [31:0] _zz_38_;
  wire `Src1CtrlEnum_defaultEncoding_type execute_SRC1_CTRL;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_39_;
  wire [31:0] _zz_40_;
  wire [31:0] execute_SRC_ADD_SUB;
  wire  execute_SRC_LESS;
  wire `AluCtrlEnum_defaultEncoding_type execute_ALU_CTRL;
  wire `AluCtrlEnum_defaultEncoding_type _zz_41_;
  wire [31:0] _zz_42_;
  wire [31:0] execute_SRC2;
  wire [31:0] execute_SRC1;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type execute_ALU_BITWISE_CTRL;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_43_;
  wire [31:0] _zz_44_;
  wire  _zz_45_;
  reg  _zz_46_;
  wire [31:0] _zz_47_;
  wire [31:0] _zz_48_;
  wire [31:0] decode_INSTRUCTION_ANTICIPATED;
  reg  decode_REGFILE_WRITE_VALID;
  wire  decode_LEGAL_INSTRUCTION;
  wire  decode_INSTRUCTION_READY;
  wire  _zz_49_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_50_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_51_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_52_;
  wire  _zz_53_;
  wire  _zz_54_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_55_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_56_;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_57_;
  wire  _zz_58_;
  wire  _zz_59_;
  wire  _zz_60_;
  wire  _zz_61_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_62_;
  wire  _zz_63_;
  wire  _zz_64_;
  wire  _zz_65_;
  wire  _zz_66_;
  reg [31:0] _zz_67_;
  wire  writeBack_MEMORY_ENABLE;
  wire [1:0] writeBack_MEMORY_ADDRESS_LOW;
  wire [31:0] writeBack_MEMORY_READ_DATA;
  wire [31:0] memory_INSTRUCTION;
  wire  memory_MEMORY_ENABLE;
  wire [31:0] _zz_68_;
  wire [1:0] _zz_69_;
  wire [31:0] execute_RS2;
  wire [31:0] execute_SRC_ADD;
  wire [31:0] execute_INSTRUCTION;
  wire  execute_ALIGNEMENT_FAULT;
  wire  execute_MEMORY_ENABLE;
  wire  memory_FLUSH_ALL;
  reg  IBusCachedPlugin_issueDetected;
  reg  _zz_70_;
  wire [31:0] _zz_71_;
  wire  execute_PREDICTION_CONTEXT_hazard;
  wire  execute_PREDICTION_CONTEXT_hit;
  wire [21:0] execute_PREDICTION_CONTEXT_line_source;
  wire [1:0] execute_PREDICTION_CONTEXT_line_branchWish;
  wire [31:0] execute_PREDICTION_CONTEXT_line_target;
  wire  _zz_72_;
  wire  _zz_73_;
  wire [21:0] _zz_74_;
  wire [1:0] _zz_75_;
  wire [31:0] _zz_76_;
  reg  _zz_77_;
  reg [31:0] _zz_78_;
  reg [31:0] _zz_79_;
  wire [31:0] _zz_80_;
  wire [31:0] _zz_81_;
  wire [31:0] _zz_82_;
  wire [31:0] writeBack_PC /* verilator public */ ;
  wire [31:0] writeBack_INSTRUCTION /* verilator public */ ;
  wire [31:0] decode_PC /* verilator public */ ;
  wire [31:0] decode_INSTRUCTION /* verilator public */ ;
  reg  decode_arbitration_haltItself /* verilator public */ ;
  reg  decode_arbitration_haltByOther;
  reg  decode_arbitration_removeIt;
  reg  decode_arbitration_flushAll /* verilator public */ ;
  wire  decode_arbitration_redoIt;
  wire  decode_arbitration_isValid /* verilator public */ ;
  wire  decode_arbitration_isStuck;
  wire  decode_arbitration_isStuckByOthers;
  wire  decode_arbitration_isFlushed;
  wire  decode_arbitration_isMoving;
  wire  decode_arbitration_isFiring;
  reg  execute_arbitration_haltItself;
  reg  execute_arbitration_haltByOther;
  reg  execute_arbitration_removeIt;
  wire  execute_arbitration_flushAll;
  wire  execute_arbitration_redoIt;
  reg  execute_arbitration_isValid;
  wire  execute_arbitration_isStuck;
  wire  execute_arbitration_isStuckByOthers;
  wire  execute_arbitration_isFlushed;
  wire  execute_arbitration_isMoving;
  wire  execute_arbitration_isFiring;
  reg  memory_arbitration_haltItself;
  reg  memory_arbitration_haltByOther;
  reg  memory_arbitration_removeIt;
  reg  memory_arbitration_flushAll;
  wire  memory_arbitration_redoIt;
  reg  memory_arbitration_isValid;
  wire  memory_arbitration_isStuck;
  wire  memory_arbitration_isStuckByOthers;
  wire  memory_arbitration_isFlushed;
  wire  memory_arbitration_isMoving;
  wire  memory_arbitration_isFiring;
  wire  writeBack_arbitration_haltItself;
  wire  writeBack_arbitration_haltByOther;
  reg  writeBack_arbitration_removeIt;
  wire  writeBack_arbitration_flushAll;
  wire  writeBack_arbitration_redoIt;
  reg  writeBack_arbitration_isValid /* verilator public */ ;
  wire  writeBack_arbitration_isStuck;
  wire  writeBack_arbitration_isStuckByOthers;
  wire  writeBack_arbitration_isFlushed;
  wire  writeBack_arbitration_isMoving;
  wire  writeBack_arbitration_isFiring /* verilator public */ ;
  wire  _zz_83_;
  wire [31:0] _zz_84_;
  wire  _zz_85_;
  wire [31:0] _zz_86_;
  reg  _zz_87_;
  wire [31:0] _zz_88_;
  wire  decodeExceptionPort_valid;
  wire [3:0] decodeExceptionPort_1_code;
  wire [31:0] decodeExceptionPort_1_badAddr;
  reg  _zz_89_;
  reg [31:0] _zz_90_;
  wire  contextSwitching;
  reg [1:0] _zz_91_;
  wire  _zz_92_;
  wire [31:0] _zz_93_;
  wire  execute_exception_agregat_valid;
  wire [3:0] execute_exception_agregat_payload_code;
  wire [31:0] execute_exception_agregat_payload_badAddr;
  wire  IBusCachedPlugin_jump_pcLoad_valid;
  wire [31:0] IBusCachedPlugin_jump_pcLoad_payload;
  wire [2:0] _zz_94_;
  wire [2:0] _zz_95_;
  wire  _zz_96_;
  wire  _zz_97_;
  wire  IBusCachedPlugin_fetchPc_preOutput_valid;
  wire  IBusCachedPlugin_fetchPc_preOutput_ready;
  wire [31:0] IBusCachedPlugin_fetchPc_preOutput_payload;
  wire  _zz_98_;
  wire  IBusCachedPlugin_fetchPc_output_valid;
  wire  IBusCachedPlugin_fetchPc_output_ready;
  wire [31:0] IBusCachedPlugin_fetchPc_output_payload;
  wire  IBusCachedPlugin_fetchPc_predictionPcLoad_valid;
  wire [31:0] IBusCachedPlugin_fetchPc_predictionPcLoad_payload;
  reg [31:0] IBusCachedPlugin_fetchPc_pcReg /* verilator public */ ;
  reg  IBusCachedPlugin_fetchPc_inc;
  reg [31:0] IBusCachedPlugin_fetchPc_pc;
  reg  IBusCachedPlugin_fetchPc_samplePcNext;
  reg  _zz_99_;
  wire  IBusCachedPlugin_iBusRsp_input_valid;
  wire  IBusCachedPlugin_iBusRsp_input_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_input_payload;
  wire  IBusCachedPlugin_iBusRsp_inputPipeline_0_valid;
  wire  IBusCachedPlugin_iBusRsp_inputPipeline_0_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_inputPipeline_0_payload;
  wire  IBusCachedPlugin_1_valid;
  wire  IBusCachedPlugin_1_ready;
  wire [31:0] IBusCachedPlugin_1_payload;
  reg  IBusCachedPlugin_iBusRsp_inputPipelineHalt_0;
  wire  _zz_100_;
  reg  _zz_101_;
  reg [31:0] _zz_102_;
  wire  _zz_103_;
  wire  _zz_104_;
  wire  _zz_105_;
  reg  _zz_106_;
  reg [31:0] _zz_107_;
  wire  IBusCachedPlugin_iBusRsp_readyForError;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_valid;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_ready;
  wire [31:0] IBusCachedPlugin_iBusRsp_decodeInput_payload_pc;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_error;
  wire [31:0] IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_rawInDecode;
  wire  IBusCachedPlugin_iBusRsp_decodeInput_payload_isRvc;
  reg  IBusCachedPlugin_injector_nextPcCalc_valids_0;
  reg  IBusCachedPlugin_injector_nextPcCalc_0;
  reg  IBusCachedPlugin_injector_nextPcCalc_1;
  reg  IBusCachedPlugin_injector_nextPcCalc_2;
  reg  IBusCachedPlugin_injector_nextPcCalc_3;
  reg  IBusCachedPlugin_injector_decodeRemoved;
  reg  IBusCachedPlugin_predictor_historyWrite_valid;
  wire [7:0] IBusCachedPlugin_predictor_historyWrite_payload_address;
  wire [21:0] IBusCachedPlugin_predictor_historyWrite_payload_data_source;
  reg [1:0] IBusCachedPlugin_predictor_historyWrite_payload_data_branchWish;
  wire [31:0] IBusCachedPlugin_predictor_historyWrite_payload_data_target;
  wire [29:0] _zz_108_;
  wire  _zz_109_;
  wire [21:0] IBusCachedPlugin_predictor_line_source;
  wire [1:0] IBusCachedPlugin_predictor_line_branchWish;
  wire [31:0] IBusCachedPlugin_predictor_line_target;
  wire [55:0] _zz_110_;
  wire  IBusCachedPlugin_predictor_hit;
  reg  IBusCachedPlugin_predictor_historyWriteLast_valid;
  reg [7:0] IBusCachedPlugin_predictor_historyWriteLast_payload_address;
  reg [21:0] IBusCachedPlugin_predictor_historyWriteLast_payload_data_source;
  reg [1:0] IBusCachedPlugin_predictor_historyWriteLast_payload_data_branchWish;
  reg [31:0] IBusCachedPlugin_predictor_historyWriteLast_payload_data_target;
  wire  IBusCachedPlugin_predictor_hazard;
  wire  IBusCachedPlugin_predictor_fetchContext_hazard;
  wire  IBusCachedPlugin_predictor_fetchContext_hit;
  wire [21:0] IBusCachedPlugin_predictor_fetchContext_line_source;
  wire [1:0] IBusCachedPlugin_predictor_fetchContext_line_branchWish;
  wire [31:0] IBusCachedPlugin_predictor_fetchContext_line_target;
  reg  IBusCachedPlugin_predictor_fetchContext_regNextWhen_hazard;
  reg  IBusCachedPlugin_predictor_fetchContext_regNextWhen_hit;
  reg [21:0] IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_source;
  reg [1:0] IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_branchWish;
  reg [31:0] IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_target;
  wire  IBusCachedPlugin_predictor_injectorContext_hazard;
  wire  IBusCachedPlugin_predictor_injectorContext_hit;
  wire [21:0] IBusCachedPlugin_predictor_injectorContext_line_source;
  wire [1:0] IBusCachedPlugin_predictor_injectorContext_line_branchWish;
  wire [31:0] IBusCachedPlugin_predictor_injectorContext_line_target;
  wire  _zz_111_;
  wire  IBusCachedPlugin_iBusRspOutputHalt;
  reg  IBusCachedPlugin_redoFetch;
  wire  _zz_112_;
  wire  _zz_113_;
  reg [31:0] _zz_114_;
  reg [3:0] _zz_115_;
  wire [3:0] execute_DBusSimplePlugin_formalMask;
  reg [31:0] writeBack_DBusSimplePlugin_rspShifted;
  wire  _zz_116_;
  reg [31:0] _zz_117_;
  wire  _zz_118_;
  reg [31:0] _zz_119_;
  reg [31:0] writeBack_DBusSimplePlugin_rspFormated;
  wire [23:0] _zz_120_;
  wire  _zz_121_;
  wire  _zz_122_;
  wire  _zz_123_;
  wire  _zz_124_;
  wire `Src2CtrlEnum_defaultEncoding_type _zz_125_;
  wire `BranchCtrlEnum_defaultEncoding_type _zz_126_;
  wire `EnvCtrlEnum_defaultEncoding_type _zz_127_;
  wire `Src1CtrlEnum_defaultEncoding_type _zz_128_;
  wire `ShiftCtrlEnum_defaultEncoding_type _zz_129_;
  wire `AluCtrlEnum_defaultEncoding_type _zz_130_;
  wire `AluBitwiseCtrlEnum_defaultEncoding_type _zz_131_;
  wire [4:0] decode_RegFilePlugin_regFileReadAddress1;
  wire [4:0] decode_RegFilePlugin_regFileReadAddress2;
  wire [31:0] decode_RegFilePlugin_rs1Data;
  wire [31:0] decode_RegFilePlugin_rs2Data;
  reg  writeBack_RegFilePlugin_regFileWrite_valid /* verilator public */ ;
  wire [4:0] writeBack_RegFilePlugin_regFileWrite_payload_address /* verilator public */ ;
  wire [31:0] writeBack_RegFilePlugin_regFileWrite_payload_data /* verilator public */ ;
  reg  _zz_132_;
  reg [31:0] execute_IntAluPlugin_bitwise;
  reg [31:0] _zz_133_;
  reg [31:0] _zz_134_;
  wire  _zz_135_;
  reg [19:0] _zz_136_;
  wire  _zz_137_;
  reg [19:0] _zz_138_;
  reg [31:0] _zz_139_;
  wire [31:0] execute_SrcPlugin_addSub;
  wire  execute_SrcPlugin_less;
  wire [4:0] execute_FullBarrelShifterPlugin_amplitude;
  reg [31:0] _zz_140_;
  wire [31:0] execute_FullBarrelShifterPlugin_reversed;
  reg [31:0] _zz_141_;
  reg  _zz_142_;
  reg  _zz_143_;
  reg  _zz_144_;
  reg [4:0] _zz_145_;
  reg [31:0] _zz_146_;
  wire  _zz_147_;
  wire  _zz_148_;
  wire  _zz_149_;
  wire  _zz_150_;
  wire  _zz_151_;
  wire  _zz_152_;
  wire [1:0] CsrPlugin_misa_base;
  wire [25:0] CsrPlugin_misa_extensions;
  wire [31:0] CsrPlugin_mtvec;
  reg [31:0] CsrPlugin_mepc;
  reg  CsrPlugin_mstatus_MIE;
  reg  CsrPlugin_mstatus_MPIE;
  reg [1:0] CsrPlugin_mstatus_MPP;
  reg  CsrPlugin_mip_MEIP;
  reg  CsrPlugin_mip_MTIP;
  reg  CsrPlugin_mip_MSIP;
  reg  CsrPlugin_mie_MEIE;
  reg  CsrPlugin_mie_MTIE;
  reg  CsrPlugin_mie_MSIE;
  reg  CsrPlugin_mcause_interrupt;
  reg [3:0] CsrPlugin_mcause_exceptionCode;
  reg [31:0] CsrPlugin_mbadaddr;
  reg [63:0] CsrPlugin_mcycle = 64'b0000000000000000000000000000000000000000000000000000000000000000;
  reg [63:0] CsrPlugin_minstret = 64'b0000000000000000000000000000000000000000000000000000000000000000;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_decode;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_execute;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_memory;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory;
  reg  CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack;
  reg [3:0] CsrPlugin_exceptionPortCtrl_exceptionContext_code;
  reg [31:0] CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr;
  wire  decode_exception_agregat_valid;
  wire [3:0] decode_exception_agregat_payload_code;
  wire [31:0] decode_exception_agregat_payload_badAddr;
  wire [1:0] _zz_153_;
  wire  _zz_154_;
  wire [0:0] _zz_155_;
  wire  CsrPlugin_interruptRequest;
  wire  CsrPlugin_interrupt;
  wire  CsrPlugin_exception;
  wire  CsrPlugin_writeBackWasWfi;
  reg  CsrPlugin_pipelineLiberator_done;
  wire [3:0] CsrPlugin_interruptCode /* verilator public */ ;
  wire  CsrPlugin_interruptJump /* verilator public */ ;
  reg  CsrPlugin_exception_regNext;
  reg  execute_CsrPlugin_illegalAccess;
  wire [31:0] execute_CsrPlugin_writeSrc;
  reg [31:0] execute_CsrPlugin_readData;
  reg  execute_CsrPlugin_readDataRegValid;
  reg [31:0] execute_CsrPlugin_writeData;
  wire  execute_CsrPlugin_writeInstruction;
  wire  execute_CsrPlugin_readInstruction;
  wire  execute_CsrPlugin_writeEnable;
  wire  execute_CsrPlugin_readEnable;
  wire [11:0] execute_CsrPlugin_csrAddress;
  wire  execute_BranchPlugin_eq;
  wire [2:0] _zz_156_;
  reg  _zz_157_;
  reg  _zz_158_;
  wire [31:0] execute_BranchPlugin_branch_src1;
  wire  _zz_159_;
  reg [10:0] _zz_160_;
  wire  _zz_161_;
  reg [19:0] _zz_162_;
  wire  _zz_163_;
  reg [18:0] _zz_164_;
  reg [31:0] _zz_165_;
  wire [31:0] execute_BranchPlugin_branch_src2;
  wire [31:0] execute_BranchPlugin_branchAdder;
  wire  execute_BranchPlugin_predictionMissmatch;
  reg `EnvCtrlEnum_defaultEncoding_type decode_to_execute_ENV_CTRL;
  reg  decode_to_execute_BYPASSABLE_EXECUTE_STAGE;
  reg [31:0] decode_to_execute_RS2;
  reg  decode_to_execute_SRC_USE_SUB_LESS;
  reg  decode_to_execute_IS_CSR;
  reg  decode_to_execute_MEMORY_ENABLE;
  reg  execute_to_memory_MEMORY_ENABLE;
  reg  memory_to_writeBack_MEMORY_ENABLE;
  reg  decode_to_execute_BYPASSABLE_MEMORY_STAGE;
  reg  execute_to_memory_BYPASSABLE_MEMORY_STAGE;
  reg [31:0] decode_to_execute_RS1;
  reg  decode_to_execute_CSR_WRITE_OPCODE;
  reg  decode_to_execute_CSR_READ_OPCODE;
  reg  decode_to_execute_REGFILE_WRITE_VALID;
  reg  execute_to_memory_REGFILE_WRITE_VALID;
  reg  memory_to_writeBack_REGFILE_WRITE_VALID;
  reg  decode_to_execute_SRC_LESS_UNSIGNED;
  reg `Src1CtrlEnum_defaultEncoding_type decode_to_execute_SRC1_CTRL;
  reg [31:0] decode_to_execute_FORMAL_PC_NEXT;
  reg [31:0] execute_to_memory_FORMAL_PC_NEXT;
  reg [31:0] memory_to_writeBack_FORMAL_PC_NEXT;
  reg [31:0] decode_to_execute_INSTRUCTION;
  reg [31:0] execute_to_memory_INSTRUCTION;
  reg [31:0] memory_to_writeBack_INSTRUCTION;
  reg [31:0] decode_to_execute_PC;
  reg [31:0] execute_to_memory_PC;
  reg [31:0] memory_to_writeBack_PC;
  reg [31:0] execute_to_memory_REGFILE_WRITE_DATA;
  reg [31:0] memory_to_writeBack_REGFILE_WRITE_DATA;
  reg `Src2CtrlEnum_defaultEncoding_type decode_to_execute_SRC2_CTRL;
  reg [1:0] execute_to_memory_MEMORY_ADDRESS_LOW;
  reg [1:0] memory_to_writeBack_MEMORY_ADDRESS_LOW;
  reg  decode_to_execute_FLUSH_ALL;
  reg  execute_to_memory_FLUSH_ALL;
  reg `BranchCtrlEnum_defaultEncoding_type decode_to_execute_BRANCH_CTRL;
  reg `AluCtrlEnum_defaultEncoding_type decode_to_execute_ALU_CTRL;
  reg `AluBitwiseCtrlEnum_defaultEncoding_type decode_to_execute_ALU_BITWISE_CTRL;
  reg `ShiftCtrlEnum_defaultEncoding_type decode_to_execute_SHIFT_CTRL;
  reg  decode_to_execute_PREDICTION_CONTEXT_hazard;
  reg  decode_to_execute_PREDICTION_CONTEXT_hit;
  reg [21:0] decode_to_execute_PREDICTION_CONTEXT_line_source;
  reg [1:0] decode_to_execute_PREDICTION_CONTEXT_line_branchWish;
  reg [31:0] decode_to_execute_PREDICTION_CONTEXT_line_target;
  reg [31:0] memory_to_writeBack_MEMORY_READ_DATA;
  reg [55:0] IBusCachedPlugin_predictor_history [0:255];
  reg [31:0] RegFilePlugin_regFile [0:31] /* verilator public */ ;
  assign _zz_202_ = (CsrPlugin_exception || CsrPlugin_interruptJump);
  assign _zz_203_ = (execute_arbitration_isValid && (execute_ENV_CTRL == `EnvCtrlEnum_defaultEncoding_MRET));
  assign _zz_204_ = (memory_arbitration_isValid || writeBack_arbitration_isValid);
  assign _zz_205_ = (IBusCachedPlugin_fetchPc_preOutput_valid && IBusCachedPlugin_fetchPc_preOutput_ready);
  assign _zz_206_ = writeBack_INSTRUCTION[13 : 12];
  assign _zz_207_ = execute_INSTRUCTION[13];
  assign _zz_208_ = (_zz_94_ - (3'b001));
  assign _zz_209_ = {IBusCachedPlugin_fetchPc_inc,(2'b00)};
  assign _zz_210_ = {29'd0, _zz_209_};
  assign _zz_211_ = _zz_108_[7:0];
  assign _zz_212_ = (IBusCachedPlugin_iBusRsp_inputPipeline_0_payload >>> 10);
  assign _zz_213_ = (IBusCachedPlugin_iBusRsp_inputPipeline_0_payload >>> 2);
  assign _zz_214_ = _zz_213_[7:0];
  assign _zz_215_ = (execute_PREDICTION_CONTEXT_line_branchWish + _zz_217_);
  assign _zz_216_ = (execute_PREDICTION_CONTEXT_line_branchWish == (2'b10));
  assign _zz_217_ = {1'd0, _zz_216_};
  assign _zz_218_ = (execute_PREDICTION_CONTEXT_line_branchWish == (2'b01));
  assign _zz_219_ = {1'd0, _zz_218_};
  assign _zz_220_ = (execute_PREDICTION_CONTEXT_line_branchWish - _zz_222_);
  assign _zz_221_ = execute_PREDICTION_CONTEXT_line_branchWish[1];
  assign _zz_222_ = {1'd0, _zz_221_};
  assign _zz_223_ = (! execute_PREDICTION_CONTEXT_line_branchWish[1]);
  assign _zz_224_ = {1'd0, _zz_223_};
  assign _zz_225_ = _zz_120_[0 : 0];
  assign _zz_226_ = _zz_120_[1 : 1];
  assign _zz_227_ = _zz_120_[2 : 2];
  assign _zz_228_ = _zz_120_[5 : 5];
  assign _zz_229_ = _zz_120_[6 : 6];
  assign _zz_230_ = _zz_120_[7 : 7];
  assign _zz_231_ = _zz_120_[8 : 8];
  assign _zz_232_ = _zz_120_[15 : 15];
  assign _zz_233_ = _zz_120_[16 : 16];
  assign _zz_234_ = _zz_120_[23 : 23];
  assign _zz_235_ = execute_SRC_LESS;
  assign _zz_236_ = (3'b100);
  assign _zz_237_ = execute_INSTRUCTION[31 : 20];
  assign _zz_238_ = {execute_INSTRUCTION[31 : 25],execute_INSTRUCTION[11 : 7]};
  assign _zz_239_ = ($signed(_zz_240_) + $signed(_zz_244_));
  assign _zz_240_ = ($signed(_zz_241_) + $signed(_zz_242_));
  assign _zz_241_ = execute_SRC1;
  assign _zz_242_ = (execute_SRC_USE_SUB_LESS ? (~ execute_SRC2) : execute_SRC2);
  assign _zz_243_ = (execute_SRC_USE_SUB_LESS ? _zz_245_ : _zz_246_);
  assign _zz_244_ = {{30{_zz_243_[1]}}, _zz_243_};
  assign _zz_245_ = (2'b01);
  assign _zz_246_ = (2'b00);
  assign _zz_247_ = ($signed(_zz_249_) >>> execute_FullBarrelShifterPlugin_amplitude);
  assign _zz_248_ = _zz_247_[31 : 0];
  assign _zz_249_ = {((execute_SHIFT_CTRL == `ShiftCtrlEnum_defaultEncoding_SRA_1) && execute_FullBarrelShifterPlugin_reversed[31]),execute_FullBarrelShifterPlugin_reversed};
  assign _zz_250_ = (_zz_153_ & (~ _zz_251_));
  assign _zz_251_ = (_zz_153_ - (2'b01));
  assign _zz_252_ = ((CsrPlugin_mip_MSIP && CsrPlugin_mie_MSIE) ? (3'b011) : (3'b111));
  assign _zz_253_ = {1'd0, _zz_252_};
  assign _zz_254_ = execute_INSTRUCTION[19 : 15];
  assign _zz_255_ = {27'd0, _zz_254_};
  assign _zz_256_ = {{{execute_INSTRUCTION[31],execute_INSTRUCTION[19 : 12]},execute_INSTRUCTION[20]},execute_INSTRUCTION[30 : 21]};
  assign _zz_257_ = execute_INSTRUCTION[31 : 20];
  assign _zz_258_ = {{{execute_INSTRUCTION[31],execute_INSTRUCTION[7]},execute_INSTRUCTION[30 : 25]},execute_INSTRUCTION[11 : 8]};
  assign _zz_259_ = execute_CsrPlugin_writeData[7 : 7];
  assign _zz_260_ = execute_CsrPlugin_writeData[3 : 3];
  assign _zz_261_ = execute_CsrPlugin_writeData[3 : 3];
  assign _zz_262_ = execute_CsrPlugin_writeData[11 : 11];
  assign _zz_263_ = execute_CsrPlugin_writeData[7 : 7];
  assign _zz_264_ = execute_CsrPlugin_writeData[3 : 3];
  assign _zz_265_ = {IBusCachedPlugin_predictor_historyWrite_payload_data_target,{IBusCachedPlugin_predictor_historyWrite_payload_data_branchWish,IBusCachedPlugin_predictor_historyWrite_payload_data_source}};
  assign _zz_266_ = 1'b1;
  assign _zz_267_ = 1'b1;
  assign _zz_268_ = {_zz_97_,_zz_96_};
  assign _zz_269_ = (decode_INSTRUCTION & (32'b00000000000000000010000000010000));
  assign _zz_270_ = (32'b00000000000000000010000000000000);
  assign _zz_271_ = (decode_INSTRUCTION & (32'b00000000000000000101000000000000));
  assign _zz_272_ = (32'b00000000000000000001000000000000);
  assign _zz_273_ = ((decode_INSTRUCTION & (32'b00000000000000000001000000000000)) == (32'b00000000000000000001000000000000));
  assign _zz_274_ = _zz_122_;
  assign _zz_275_ = ((decode_INSTRUCTION & _zz_281_) == (32'b00000000000000000010000000000000));
  assign _zz_276_ = {(_zz_282_ == _zz_283_),(_zz_284_ == _zz_285_)};
  assign _zz_277_ = (2'b00);
  assign _zz_278_ = (_zz_121_ != (1'b0));
  assign _zz_279_ = (_zz_286_ != (1'b0));
  assign _zz_280_ = {(_zz_287_ != _zz_288_),{_zz_289_,{_zz_290_,_zz_291_}}};
  assign _zz_281_ = (32'b00000000000000000011000000000000);
  assign _zz_282_ = (decode_INSTRUCTION & (32'b00000000000000000100000000000100));
  assign _zz_283_ = (32'b00000000000000000100000000000000);
  assign _zz_284_ = (decode_INSTRUCTION & (32'b00000000000000000000000001100100));
  assign _zz_285_ = (32'b00000000000000000000000000100100);
  assign _zz_286_ = ((decode_INSTRUCTION & (32'b00000000000000000111000001010100)) == (32'b00000000000000000101000000010000));
  assign _zz_287_ = {(_zz_292_ == _zz_293_),(_zz_294_ == _zz_295_)};
  assign _zz_288_ = (2'b00);
  assign _zz_289_ = ((_zz_296_ == _zz_297_) != (1'b0));
  assign _zz_290_ = ({_zz_298_,_zz_299_} != (6'b000000));
  assign _zz_291_ = {(_zz_300_ != _zz_301_),{_zz_302_,{_zz_303_,_zz_304_}}};
  assign _zz_292_ = (decode_INSTRUCTION & (32'b01000000000000000011000001010100));
  assign _zz_293_ = (32'b01000000000000000001000000010000);
  assign _zz_294_ = (decode_INSTRUCTION & (32'b00000000000000000111000001010100));
  assign _zz_295_ = (32'b00000000000000000001000000010000);
  assign _zz_296_ = (decode_INSTRUCTION & (32'b00000000000000000000000001011000));
  assign _zz_297_ = (32'b00000000000000000000000000000000);
  assign _zz_298_ = _zz_124_;
  assign _zz_299_ = {(_zz_305_ == _zz_306_),{_zz_307_,{_zz_308_,_zz_309_}}};
  assign _zz_300_ = ((decode_INSTRUCTION & _zz_310_) == (32'b00000000000000000000000000000100));
  assign _zz_301_ = (1'b0);
  assign _zz_302_ = ((_zz_311_ == _zz_312_) != (1'b0));
  assign _zz_303_ = (_zz_313_ != (1'b0));
  assign _zz_304_ = {1'b0,{_zz_314_,{_zz_315_,_zz_316_}}};
  assign _zz_305_ = (decode_INSTRUCTION & (32'b00000000000000000001000000010000));
  assign _zz_306_ = (32'b00000000000000000001000000010000);
  assign _zz_307_ = ((decode_INSTRUCTION & (32'b00000000000000000010000000010000)) == (32'b00000000000000000010000000010000));
  assign _zz_308_ = ((decode_INSTRUCTION & _zz_317_) == (32'b00000000000000000000000000010000));
  assign _zz_309_ = {(_zz_318_ == _zz_319_),(_zz_320_ == _zz_321_)};
  assign _zz_310_ = (32'b00000000000000000000000000010100);
  assign _zz_311_ = (decode_INSTRUCTION & (32'b00000000000000000000000001000100));
  assign _zz_312_ = (32'b00000000000000000000000000000100);
  assign _zz_313_ = ((decode_INSTRUCTION & (32'b00000000000000000011000001010000)) == (32'b00000000000000000000000001010000));
  assign _zz_314_ = ({_zz_124_,_zz_322_} != (2'b00));
  assign _zz_315_ = (_zz_323_ != (1'b0));
  assign _zz_316_ = {(_zz_324_ != _zz_325_),{_zz_326_,{_zz_327_,_zz_328_}}};
  assign _zz_317_ = (32'b00000000000000000000000001010000);
  assign _zz_318_ = (decode_INSTRUCTION & (32'b00000000000000000100000000000100));
  assign _zz_319_ = (32'b00000000000000000000000000000100);
  assign _zz_320_ = (decode_INSTRUCTION & (32'b00000000000000000000000000101000));
  assign _zz_321_ = (32'b00000000000000000000000000000000);
  assign _zz_322_ = ((decode_INSTRUCTION & (32'b00000000000000000100000000010100)) == (32'b00000000000000000000000000000100));
  assign _zz_323_ = ((decode_INSTRUCTION & (32'b00000000000000000000000001011000)) == (32'b00000000000000000000000001000000));
  assign _zz_324_ = _zz_123_;
  assign _zz_325_ = (1'b0);
  assign _zz_326_ = ({(_zz_329_ == _zz_330_),{_zz_331_,_zz_332_}} != (3'b000));
  assign _zz_327_ = (_zz_123_ != (1'b0));
  assign _zz_328_ = {(_zz_333_ != (1'b0)),{(_zz_334_ != _zz_335_),{_zz_336_,{_zz_337_,_zz_338_}}}};
  assign _zz_329_ = (decode_INSTRUCTION & (32'b00000000000000000000000001000100));
  assign _zz_330_ = (32'b00000000000000000000000001000000);
  assign _zz_331_ = ((decode_INSTRUCTION & (32'b01000000000000000000000000110000)) == (32'b01000000000000000000000000110000));
  assign _zz_332_ = ((decode_INSTRUCTION & (32'b00000000000000000010000000010100)) == (32'b00000000000000000010000000010000));
  assign _zz_333_ = ((decode_INSTRUCTION & (32'b00000000000000000000000001001000)) == (32'b00000000000000000000000000001000));
  assign _zz_334_ = {_zz_122_,(_zz_339_ == _zz_340_)};
  assign _zz_335_ = (2'b00);
  assign _zz_336_ = ({_zz_122_,_zz_341_} != (2'b00));
  assign _zz_337_ = ({_zz_342_,_zz_343_} != (2'b00));
  assign _zz_338_ = {(_zz_344_ != _zz_345_),(_zz_346_ != _zz_347_)};
  assign _zz_339_ = (decode_INSTRUCTION & (32'b00000000000000000000000001110000));
  assign _zz_340_ = (32'b00000000000000000000000000100000);
  assign _zz_341_ = ((decode_INSTRUCTION & (32'b00000000000000000000000000100000)) == (32'b00000000000000000000000000000000));
  assign _zz_342_ = ((decode_INSTRUCTION & (32'b00000000000000000001000001010000)) == (32'b00000000000000000001000001010000));
  assign _zz_343_ = ((decode_INSTRUCTION & (32'b00000000000000000010000001010000)) == (32'b00000000000000000010000001010000));
  assign _zz_344_ = {((decode_INSTRUCTION & _zz_348_) == (32'b00000000000000000000000000100000)),((decode_INSTRUCTION & _zz_349_) == (32'b00000000000000000000000001000000))};
  assign _zz_345_ = (2'b00);
  assign _zz_346_ = {((decode_INSTRUCTION & _zz_350_) == (32'b00000000000000000000000000000000)),{(_zz_351_ == _zz_352_),{_zz_121_,_zz_353_}}};
  assign _zz_347_ = (4'b0000);
  assign _zz_348_ = (32'b00000000000000000000000001100100);
  assign _zz_349_ = (32'b00000000000000000000000001010100);
  assign _zz_350_ = (32'b00000000000000000000000001000100);
  assign _zz_351_ = (decode_INSTRUCTION & (32'b00000000000000000000000000011000));
  assign _zz_352_ = (32'b00000000000000000000000000000000);
  assign _zz_353_ = ((decode_INSTRUCTION & (32'b00000000000000000101000000000100)) == (32'b00000000000000000001000000000000));
  assign _zz_354_ = (32'b00000000000000000010000001111111);
  assign _zz_355_ = (decode_INSTRUCTION & (32'b00000000001000000000000001111111));
  assign _zz_356_ = (32'b00000000000000000000000001101111);
  assign _zz_357_ = ((decode_INSTRUCTION & (32'b00000000000000000010000001111111)) == (32'b00000000000000000010000000010011));
  assign _zz_358_ = ((decode_INSTRUCTION & (32'b00000000000000000010000001111111)) == (32'b00000000000000000000000000000011));
  assign _zz_359_ = {((decode_INSTRUCTION & (32'b00000000000000000110000001011111)) == (32'b00000000000000000000000000000011)),{((decode_INSTRUCTION & (32'b00000000000000000101000001011111)) == (32'b00000000000000000000000000000011)),{((decode_INSTRUCTION & _zz_360_) == (32'b00000000000000000100000001100011)),{(_zz_361_ == _zz_362_),{_zz_363_,{_zz_364_,_zz_365_}}}}}};
  assign _zz_360_ = (32'b00000000000000000100000101111111);
  assign _zz_361_ = (decode_INSTRUCTION & (32'b00000000000000000010000101111111));
  assign _zz_362_ = (32'b00000000000000000000000001100011);
  assign _zz_363_ = ((decode_INSTRUCTION & (32'b00000000000000000111000001111111)) == (32'b00000000000000000100000000001111));
  assign _zz_364_ = ((decode_INSTRUCTION & (32'b00000000000000000111000001111111)) == (32'b00000000000000000000000001100111));
  assign _zz_365_ = {((decode_INSTRUCTION & (32'b11111110000000000000000001111111)) == (32'b00000000000000000000000000110011)),{((decode_INSTRUCTION & (32'b10111100000000000111000001111111)) == (32'b00000000000000000101000000010011)),{((decode_INSTRUCTION & _zz_366_) == (32'b00000000000000000001000000010011)),{(_zz_367_ == _zz_368_),{_zz_369_,_zz_370_}}}}};
  assign _zz_366_ = (32'b11111100000000000011000001111111);
  assign _zz_367_ = (decode_INSTRUCTION & (32'b10111110000000000111000001111111));
  assign _zz_368_ = (32'b00000000000000000101000000110011);
  assign _zz_369_ = ((decode_INSTRUCTION & (32'b10111110000000000111000001111111)) == (32'b00000000000000000000000000110011));
  assign _zz_370_ = ((decode_INSTRUCTION & (32'b11111111111111111111111111111111)) == (32'b00110000001000000000000001110011));
  always @ (posedge clk) begin
    if(_zz_77_) begin
      IBusCachedPlugin_predictor_history[IBusCachedPlugin_predictor_historyWrite_payload_address] <= _zz_265_;
    end
  end

  always @ (posedge clk) begin
    if(_zz_109_) begin
      _zz_178_ <= IBusCachedPlugin_predictor_history[_zz_211_];
    end
  end
 
  assign debug_pc = IBusCachedPlugin_fetchPc_pcReg; // [maleen]
  integer j;
  initial begin
    for (j = 0;j<32;j=j+1) begin
      RegFilePlugin_regFile[j] = 0;
    end
    for (j = 0;j<256;j=j+1) begin
      IBusCachedPlugin_predictor_history[j] = 0; 
    end
  end
  always @ (posedge clk) begin
    if(_zz_46_) begin
      RegFilePlugin_regFile[writeBack_RegFilePlugin_regFileWrite_payload_address] <= writeBack_RegFilePlugin_regFileWrite_payload_data;
    end
  end

  always @ (posedge clk) begin
    if(_zz_266_) begin
      _zz_179_ <= RegFilePlugin_regFile[decode_RegFilePlugin_regFileReadAddress1];
    end
  end

  always @ (posedge clk) begin
    if(_zz_267_) begin
      _zz_180_ <= RegFilePlugin_regFile[decode_RegFilePlugin_regFileReadAddress2];
    end
  end

  InstructionCache IBusCachedPlugin_cache ( 
    .io_flush_cmd_valid(_zz_166_),
    .io_flush_cmd_ready(_zz_184_),
    .io_flush_rsp(_zz_185_),
    .io_cpu_prefetch_isValid(IBusCachedPlugin_fetchPc_output_valid),
    .io_cpu_prefetch_haltIt(_zz_186_),
    .io_cpu_prefetch_pc(IBusCachedPlugin_fetchPc_output_payload),
    .io_cpu_fetch_isValid(IBusCachedPlugin_iBusRsp_inputPipeline_0_valid),
    .io_cpu_fetch_isStuck(_zz_167_),
    .io_cpu_fetch_isRemoved(_zz_168_),
    .io_cpu_fetch_pc(IBusCachedPlugin_iBusRsp_inputPipeline_0_payload),
    .io_cpu_fetch_data(_zz_187_),
    .io_cpu_fetch_mmuBus_cmd_isValid(_zz_189_),
    .io_cpu_fetch_mmuBus_cmd_virtualAddress(_zz_190_),
    .io_cpu_fetch_mmuBus_cmd_bypassTranslation(_zz_191_),
    .io_cpu_fetch_mmuBus_rsp_physicalAddress(_zz_88_),
    .io_cpu_fetch_mmuBus_rsp_isIoAccess(_zz_169_),
    .io_cpu_fetch_mmuBus_rsp_allowRead(_zz_170_),
    .io_cpu_fetch_mmuBus_rsp_allowWrite(_zz_171_),
    .io_cpu_fetch_mmuBus_rsp_allowExecute(_zz_172_),
    .io_cpu_fetch_mmuBus_rsp_allowUser(_zz_173_),
    .io_cpu_fetch_mmuBus_rsp_miss(_zz_174_),
    .io_cpu_fetch_mmuBus_rsp_hit(_zz_175_),
    .io_cpu_fetch_mmuBus_end(_zz_192_),
    .io_cpu_fetch_physicalAddress(_zz_188_),
    .io_cpu_decode_isValid(IBusCachedPlugin_1_valid),
    .io_cpu_decode_isStuck(_zz_176_),
    .io_cpu_decode_pc(IBusCachedPlugin_1_payload),
    .io_cpu_decode_physicalAddress(_zz_198_),
    .io_cpu_decode_data(_zz_196_),
    .io_cpu_decode_cacheMiss(_zz_197_),
    .io_cpu_decode_error(_zz_193_),
    .io_cpu_decode_mmuMiss(_zz_194_),
    .io_cpu_decode_illegalAccess(_zz_195_),
    .io_cpu_decode_isUser(_zz_177_),
    .io_cpu_fill_valid(IBusCachedPlugin_redoFetch),
    .io_cpu_fill_payload(_zz_198_),
    .io_mem_cmd_valid(_zz_199_),
    .io_mem_cmd_ready(iBus_cmd_ready),
    .io_mem_cmd_payload_address(_zz_200_),
    .io_mem_cmd_payload_size(_zz_201_),
    .io_mem_rsp_valid(iBus_rsp_valid),
    .io_mem_rsp_payload_data(iBus_rsp_payload_data),
    .io_mem_rsp_payload_error(iBus_rsp_payload_error),
    .clk(clk),
    .reset(reset) 
  );
  always @(*) begin
    case(_zz_268_)
      2'b00 : begin
        _zz_181_ = _zz_90_;
      end
      2'b01 : begin
        _zz_181_ = _zz_93_;
      end
      default : begin
        _zz_181_ = _zz_86_;
      end
    endcase
  end

  always @(*) begin
    case(_zz_155_)
      1'b0 : begin
        _zz_182_ = (_zz_112_ ? (4'b1110) : (4'b0001));
        _zz_183_ = IBusCachedPlugin_1_payload;
      end
      default : begin
        _zz_182_ = decodeExceptionPort_1_code;
        _zz_183_ = decodeExceptionPort_1_badAddr;
      end
    endcase
  end

  assign memory_MEMORY_READ_DATA = _zz_68_;
  assign decode_PREDICTION_CONTEXT_hazard = _zz_72_;
  assign decode_PREDICTION_CONTEXT_hit = _zz_73_;
  assign decode_PREDICTION_CONTEXT_line_source = _zz_74_;
  assign decode_PREDICTION_CONTEXT_line_branchWish = _zz_75_;
  assign decode_PREDICTION_CONTEXT_line_target = _zz_76_;
  assign decode_SHIFT_CTRL = _zz_1_;
  assign _zz_2_ = _zz_3_;
  assign decode_ALU_BITWISE_CTRL = _zz_4_;
  assign _zz_5_ = _zz_6_;
  assign decode_ALU_CTRL = _zz_7_;
  assign _zz_8_ = _zz_9_;
  assign decode_BRANCH_CTRL = _zz_10_;
  assign _zz_11_ = _zz_12_;
  assign execute_FLUSH_ALL = decode_to_execute_FLUSH_ALL;
  assign decode_FLUSH_ALL = _zz_61_;
  assign memory_MEMORY_ADDRESS_LOW = execute_to_memory_MEMORY_ADDRESS_LOW;
  assign execute_MEMORY_ADDRESS_LOW = _zz_69_;
  assign decode_SRC2_CTRL = _zz_13_;
  assign _zz_14_ = _zz_15_;
  assign writeBack_REGFILE_WRITE_DATA = memory_to_writeBack_REGFILE_WRITE_DATA;
  assign execute_REGFILE_WRITE_DATA = _zz_42_;
  assign memory_PC = execute_to_memory_PC;
  assign writeBack_FORMAL_PC_NEXT = memory_to_writeBack_FORMAL_PC_NEXT;
  assign memory_FORMAL_PC_NEXT = execute_to_memory_FORMAL_PC_NEXT;
  assign execute_FORMAL_PC_NEXT = decode_to_execute_FORMAL_PC_NEXT;
  assign decode_FORMAL_PC_NEXT = _zz_80_;
  assign decode_SRC1_CTRL = _zz_16_;
  assign _zz_17_ = _zz_18_;
  assign decode_SRC_LESS_UNSIGNED = _zz_49_;
  assign decode_CSR_READ_OPCODE = _zz_26_;
  assign decode_CSR_WRITE_OPCODE = _zz_27_;
  assign execute_BYPASSABLE_MEMORY_STAGE = decode_to_execute_BYPASSABLE_MEMORY_STAGE;
  assign decode_BYPASSABLE_MEMORY_STAGE = _zz_58_;
  assign decode_MEMORY_ENABLE = _zz_53_;
  assign decode_SRC_USE_SUB_LESS = _zz_59_;
  assign decode_BYPASSABLE_EXECUTE_STAGE = _zz_60_;
  assign decode_ENV_CTRL = _zz_19_;
  assign _zz_20_ = _zz_21_;
  assign execute_NEXT_PC2 = _zz_22_;
  assign execute_BRANCH_CALC = _zz_23_;
  assign execute_BRANCH_DO = _zz_25_;
  assign execute_PC = decode_to_execute_PC;
  assign execute_RS1 = decode_to_execute_RS1;
  assign execute_BRANCH_CTRL = _zz_24_;
  assign execute_CSR_READ_OPCODE = decode_to_execute_CSR_READ_OPCODE;
  assign execute_CSR_WRITE_OPCODE = decode_to_execute_CSR_WRITE_OPCODE;
  assign memory_REGFILE_WRITE_DATA = execute_to_memory_REGFILE_WRITE_DATA;
  assign execute_IS_CSR = decode_to_execute_IS_CSR;
  assign decode_IS_CSR = _zz_63_;
  assign execute_ENV_CTRL = _zz_28_;
  assign decode_RS2_USE = _zz_64_;
  assign decode_RS1_USE = _zz_65_;
  assign execute_REGFILE_WRITE_VALID = decode_to_execute_REGFILE_WRITE_VALID;
  assign execute_BYPASSABLE_EXECUTE_STAGE = decode_to_execute_BYPASSABLE_EXECUTE_STAGE;
  assign _zz_29_ = memory_REGFILE_WRITE_DATA;
  assign memory_REGFILE_WRITE_VALID = execute_to_memory_REGFILE_WRITE_VALID;
  assign memory_BYPASSABLE_MEMORY_STAGE = execute_to_memory_BYPASSABLE_MEMORY_STAGE;
  assign writeBack_REGFILE_WRITE_VALID = memory_to_writeBack_REGFILE_WRITE_VALID;
  always @ (*) begin
    decode_RS2 = _zz_47_;
    decode_RS1 = _zz_48_;
    if(_zz_144_)begin
      if((_zz_145_ == decode_INSTRUCTION[19 : 15]))begin
        decode_RS1 = _zz_146_;
      end
      if((_zz_145_ == decode_INSTRUCTION[24 : 20]))begin
        decode_RS2 = _zz_146_;
      end
    end
    if((writeBack_arbitration_isValid && writeBack_REGFILE_WRITE_VALID))begin
      if(1'b1)begin
        if(_zz_147_)begin
          decode_RS1 = _zz_67_;
        end
        if(_zz_148_)begin
          decode_RS2 = _zz_67_;
        end
      end
    end
    if((memory_arbitration_isValid && memory_REGFILE_WRITE_VALID))begin
      if(memory_BYPASSABLE_MEMORY_STAGE)begin
        if(_zz_149_)begin
          decode_RS1 = _zz_29_;
        end
        if(_zz_150_)begin
          decode_RS2 = _zz_29_;
        end
      end
    end
    if((execute_arbitration_isValid && execute_REGFILE_WRITE_VALID))begin
      if(execute_BYPASSABLE_EXECUTE_STAGE)begin
        if(_zz_151_)begin
          decode_RS1 = _zz_30_;
        end
        if(_zz_152_)begin
          decode_RS2 = _zz_30_;
        end
      end
    end
  end

  assign execute_SHIFT_RIGHT = _zz_31_;
  always @ (*) begin
    _zz_30_ = execute_REGFILE_WRITE_DATA;
    case(execute_SHIFT_CTRL)
      `ShiftCtrlEnum_defaultEncoding_SLL_1 : begin
        _zz_30_ = _zz_141_;
      end
      `ShiftCtrlEnum_defaultEncoding_SRL_1, `ShiftCtrlEnum_defaultEncoding_SRA_1 : begin
        _zz_30_ = execute_SHIFT_RIGHT;
      end
      default : begin
      end
    endcase
    if((execute_arbitration_isValid && execute_IS_CSR))begin
      _zz_30_ = execute_CsrPlugin_readData;
    end
  end

  assign execute_SHIFT_CTRL = _zz_32_;
  assign execute_SRC_LESS_UNSIGNED = decode_to_execute_SRC_LESS_UNSIGNED;
  assign execute_SRC_USE_SUB_LESS = decode_to_execute_SRC_USE_SUB_LESS;
  assign _zz_36_ = execute_PC;
  assign execute_SRC2_CTRL = _zz_37_;
  assign execute_SRC1_CTRL = _zz_39_;
  assign execute_SRC_ADD_SUB = _zz_35_;
  assign execute_SRC_LESS = _zz_33_;
  assign execute_ALU_CTRL = _zz_41_;
  assign execute_SRC2 = _zz_38_;
  assign execute_SRC1 = _zz_40_;
  assign execute_ALU_BITWISE_CTRL = _zz_43_;
  assign _zz_44_ = writeBack_INSTRUCTION;
  assign _zz_45_ = writeBack_REGFILE_WRITE_VALID;
  always @ (*) begin
    _zz_46_ = 1'b0;
    if(writeBack_RegFilePlugin_regFileWrite_valid)begin
      _zz_46_ = 1'b1;
    end
  end

  assign decode_INSTRUCTION_ANTICIPATED = _zz_71_;
  always @ (*) begin
    decode_REGFILE_WRITE_VALID = _zz_54_;
    if((decode_INSTRUCTION[11 : 7] == (5'b00000)))begin
      decode_REGFILE_WRITE_VALID = 1'b0;
    end
  end

  assign decode_LEGAL_INSTRUCTION = _zz_66_;
  assign decode_INSTRUCTION_READY = 1'b1;
  always @ (*) begin
    _zz_67_ = writeBack_REGFILE_WRITE_DATA;
    if((writeBack_arbitration_isValid && writeBack_MEMORY_ENABLE))begin
      _zz_67_ = writeBack_DBusSimplePlugin_rspFormated;
    end
  end

  assign writeBack_MEMORY_ENABLE = memory_to_writeBack_MEMORY_ENABLE;
  assign writeBack_MEMORY_ADDRESS_LOW = memory_to_writeBack_MEMORY_ADDRESS_LOW;
  assign writeBack_MEMORY_READ_DATA = memory_to_writeBack_MEMORY_READ_DATA;
  assign memory_INSTRUCTION = execute_to_memory_INSTRUCTION;
  assign memory_MEMORY_ENABLE = execute_to_memory_MEMORY_ENABLE;
  assign execute_RS2 = decode_to_execute_RS2;
  assign execute_SRC_ADD = _zz_34_;
  assign execute_INSTRUCTION = decode_to_execute_INSTRUCTION;
  assign execute_ALIGNEMENT_FAULT = 1'b0;
  assign execute_MEMORY_ENABLE = decode_to_execute_MEMORY_ENABLE;
  assign memory_FLUSH_ALL = execute_to_memory_FLUSH_ALL;
  always @ (*) begin
    IBusCachedPlugin_issueDetected = _zz_70_;
    _zz_87_ = 1'b0;
    if(((IBusCachedPlugin_1_valid && ((_zz_193_ || _zz_112_) || _zz_195_)) && (! _zz_70_)))begin
      IBusCachedPlugin_issueDetected = 1'b1;
      _zz_87_ = IBusCachedPlugin_iBusRsp_readyForError;
    end
  end

  always @ (*) begin
    _zz_70_ = 1'b0;
    IBusCachedPlugin_redoFetch = 1'b0;
    if(((IBusCachedPlugin_1_valid && _zz_197_) && (! 1'b0)))begin
      _zz_70_ = 1'b1;
      IBusCachedPlugin_redoFetch = IBusCachedPlugin_iBusRsp_readyForError;
    end
  end

  assign execute_PREDICTION_CONTEXT_hazard = decode_to_execute_PREDICTION_CONTEXT_hazard;
  assign execute_PREDICTION_CONTEXT_hit = decode_to_execute_PREDICTION_CONTEXT_hit;
  assign execute_PREDICTION_CONTEXT_line_source = decode_to_execute_PREDICTION_CONTEXT_line_source;
  assign execute_PREDICTION_CONTEXT_line_branchWish = decode_to_execute_PREDICTION_CONTEXT_line_branchWish;
  assign execute_PREDICTION_CONTEXT_line_target = decode_to_execute_PREDICTION_CONTEXT_line_target;
  always @ (*) begin
    _zz_77_ = 1'b0;
    if(IBusCachedPlugin_predictor_historyWrite_valid)begin
      _zz_77_ = 1'b1;
    end
  end

  always @ (*) begin
    _zz_78_ = execute_FORMAL_PC_NEXT;
    if(_zz_92_)begin
      _zz_78_ = _zz_93_;
    end
  end

  always @ (*) begin
    _zz_79_ = decode_FORMAL_PC_NEXT;
    if(_zz_85_)begin
      _zz_79_ = _zz_86_;
    end
  end

  assign writeBack_PC = memory_to_writeBack_PC;
  assign writeBack_INSTRUCTION = memory_to_writeBack_INSTRUCTION;
  assign decode_PC = _zz_82_;
  assign decode_INSTRUCTION = _zz_81_;
  always @ (*) begin
    decode_arbitration_haltItself = 1'b0;
    if((decode_arbitration_isValid && (_zz_142_ || _zz_143_)))begin
      decode_arbitration_haltItself = 1'b1;
    end
    if(((decode_arbitration_isValid && decode_IS_CSR) && (execute_arbitration_isValid || memory_arbitration_isValid)))begin
      decode_arbitration_haltItself = 1'b1;
    end
  end

  always @ (*) begin
    decode_arbitration_haltByOther = 1'b0;
    if(CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute)begin
      decode_arbitration_haltByOther = 1'b1;
    end
    if((CsrPlugin_interrupt && decode_arbitration_isValid))begin
      decode_arbitration_haltByOther = 1'b1;
    end
  end

  always @ (*) begin
    decode_arbitration_removeIt = 1'b0;
    if(decode_exception_agregat_valid)begin
      decode_arbitration_removeIt = 1'b1;
    end
    if(decode_arbitration_isFlushed)begin
      decode_arbitration_removeIt = 1'b1;
    end
  end

  always @ (*) begin
    decode_arbitration_flushAll = 1'b0;
    execute_arbitration_haltItself = 1'b0;
    memory_arbitration_haltItself = 1'b0;
    memory_arbitration_flushAll = 1'b0;
    _zz_89_ = 1'b0;
    _zz_90_ = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
    _zz_166_ = 1'b0;
    if((memory_arbitration_isValid && memory_FLUSH_ALL))begin
      _zz_166_ = 1'b1;
      decode_arbitration_flushAll = 1'b1;
      if((! _zz_184_))begin
        memory_arbitration_haltItself = 1'b1;
      end
    end
    if((((execute_arbitration_isValid && execute_MEMORY_ENABLE) && (! dBus_cmd_ready)) && (! execute_ALIGNEMENT_FAULT)))begin
      execute_arbitration_haltItself = 1'b1;
    end
    if((((memory_arbitration_isValid && memory_MEMORY_ENABLE) && (! memory_INSTRUCTION[5])) && (! dBus_rsp_ready)))begin
      memory_arbitration_haltItself = 1'b1;
    end
    if(_zz_202_)begin
      _zz_89_ = 1'b1;
      _zz_90_ = CsrPlugin_mtvec;
      memory_arbitration_flushAll = 1'b1;
    end
    if(_zz_203_)begin
      if(_zz_204_)begin
        execute_arbitration_haltItself = 1'b1;
      end else begin
        _zz_89_ = 1'b1;
        _zz_90_ = CsrPlugin_mepc;
        decode_arbitration_flushAll = 1'b1;
      end
    end
    if((execute_CsrPlugin_writeInstruction && (! execute_CsrPlugin_readDataRegValid)))begin
      execute_arbitration_haltItself = 1'b1;
    end
    if(_zz_92_)begin
      decode_arbitration_flushAll = 1'b1;
    end
  end

  assign decode_arbitration_redoIt = 1'b0;
  always @ (*) begin
    execute_arbitration_haltByOther = 1'b0;
    if(CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory)begin
      execute_arbitration_haltByOther = 1'b1;
    end
  end

  always @ (*) begin
    execute_arbitration_removeIt = 1'b0;
    CsrPlugin_exceptionPortCtrl_exceptionValids_execute = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute;
    if(execute_exception_agregat_valid)begin
      execute_arbitration_removeIt = 1'b1;
      CsrPlugin_exceptionPortCtrl_exceptionValids_execute = 1'b1;
    end
    if(execute_arbitration_isFlushed)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_execute = 1'b0;
    end
    if(execute_arbitration_isFlushed)begin
      execute_arbitration_removeIt = 1'b1;
    end
  end

  assign execute_arbitration_flushAll = 1'b0;
  assign execute_arbitration_redoIt = 1'b0;
  always @ (*) begin
    memory_arbitration_haltByOther = 1'b0;
    if(CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack)begin
      memory_arbitration_haltByOther = 1'b1;
    end
  end

  always @ (*) begin
    memory_arbitration_removeIt = 1'b0;
    if(memory_arbitration_isFlushed)begin
      memory_arbitration_removeIt = 1'b1;
    end
  end

  assign memory_arbitration_redoIt = 1'b0;
  assign writeBack_arbitration_haltItself = 1'b0;
  assign writeBack_arbitration_haltByOther = 1'b0;
  always @ (*) begin
    writeBack_arbitration_removeIt = 1'b0;
    if(writeBack_arbitration_isFlushed)begin
      writeBack_arbitration_removeIt = 1'b1;
    end
  end

  assign writeBack_arbitration_flushAll = 1'b0;
  assign writeBack_arbitration_redoIt = 1'b0;
  assign _zz_83_ = 1'b0;
  assign IBusCachedPlugin_jump_pcLoad_valid = ((_zz_85_ || _zz_89_) || _zz_92_);
  assign _zz_94_ = {_zz_85_,{_zz_92_,_zz_89_}};
  assign _zz_95_ = (_zz_94_ & (~ _zz_208_));
  assign _zz_96_ = _zz_95_[1];
  assign _zz_97_ = _zz_95_[2];
  assign IBusCachedPlugin_jump_pcLoad_payload = _zz_181_;
  assign _zz_98_ = (! 1'b0);
  assign IBusCachedPlugin_fetchPc_output_valid = (IBusCachedPlugin_fetchPc_preOutput_valid && _zz_98_);
  assign IBusCachedPlugin_fetchPc_preOutput_ready = (IBusCachedPlugin_fetchPc_output_ready && _zz_98_);
  assign IBusCachedPlugin_fetchPc_output_payload = IBusCachedPlugin_fetchPc_preOutput_payload;
  always @ (*) begin
    IBusCachedPlugin_fetchPc_pc = (IBusCachedPlugin_fetchPc_pcReg + _zz_210_);
    IBusCachedPlugin_fetchPc_samplePcNext = 1'b0;
    if(IBusCachedPlugin_fetchPc_predictionPcLoad_valid)begin
      IBusCachedPlugin_fetchPc_samplePcNext = 1'b1;
      IBusCachedPlugin_fetchPc_pc = IBusCachedPlugin_fetchPc_predictionPcLoad_payload;
    end
    if(IBusCachedPlugin_jump_pcLoad_valid)begin
      IBusCachedPlugin_fetchPc_samplePcNext = 1'b1;
      IBusCachedPlugin_fetchPc_pc = IBusCachedPlugin_jump_pcLoad_payload;
    end
    if(_zz_205_)begin
      IBusCachedPlugin_fetchPc_samplePcNext = 1'b1;
    end
  end

  assign IBusCachedPlugin_fetchPc_preOutput_valid = _zz_99_;
  assign IBusCachedPlugin_fetchPc_preOutput_payload = IBusCachedPlugin_fetchPc_pc;
  always @ (*) begin
    IBusCachedPlugin_iBusRsp_inputPipelineHalt_0 = 1'b0;
    if(((_zz_189_ && (! 1'b1)) && (! 1'b0)))begin
      IBusCachedPlugin_iBusRsp_inputPipelineHalt_0 = 1'b1;
    end
  end

  assign IBusCachedPlugin_iBusRsp_input_ready = ((1'b0 && (! _zz_100_)) || IBusCachedPlugin_iBusRsp_inputPipeline_0_ready);
  assign _zz_100_ = _zz_101_;
  assign IBusCachedPlugin_iBusRsp_inputPipeline_0_valid = _zz_100_;
  assign IBusCachedPlugin_iBusRsp_inputPipeline_0_payload = _zz_102_;
  assign _zz_103_ = (! IBusCachedPlugin_iBusRsp_inputPipelineHalt_0);
  assign IBusCachedPlugin_iBusRsp_inputPipeline_0_ready = (_zz_104_ && _zz_103_);
  assign _zz_104_ = ((1'b0 && (! _zz_105_)) || IBusCachedPlugin_1_ready);
  assign _zz_105_ = _zz_106_;
  assign IBusCachedPlugin_1_valid = _zz_105_;
  assign IBusCachedPlugin_1_payload = _zz_107_;
  assign IBusCachedPlugin_iBusRsp_readyForError = 1'b1;
  assign IBusCachedPlugin_iBusRsp_decodeInput_ready = (! decode_arbitration_isStuck);
  assign decode_arbitration_isValid = (IBusCachedPlugin_iBusRsp_decodeInput_valid && (! IBusCachedPlugin_injector_decodeRemoved));
  assign _zz_82_ = IBusCachedPlugin_iBusRsp_decodeInput_payload_pc;
  assign _zz_81_ = IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_rawInDecode;
  assign _zz_80_ = (decode_PC + (32'b00000000000000000000000000000100));
  assign _zz_108_ = (IBusCachedPlugin_fetchPc_output_payload >>> 2);
  assign _zz_109_ = (IBusCachedPlugin_iBusRsp_inputPipeline_0_ready || (IBusCachedPlugin_jump_pcLoad_valid || _zz_83_));
  assign _zz_110_ = _zz_178_;
  assign IBusCachedPlugin_predictor_line_source = _zz_110_[21 : 0];
  assign IBusCachedPlugin_predictor_line_branchWish = _zz_110_[23 : 22];
  assign IBusCachedPlugin_predictor_line_target = _zz_110_[55 : 24];
  assign IBusCachedPlugin_predictor_hit = ((IBusCachedPlugin_predictor_line_source == _zz_212_) && 1'b1);
  assign IBusCachedPlugin_predictor_hazard = (IBusCachedPlugin_predictor_historyWriteLast_valid && (IBusCachedPlugin_predictor_historyWriteLast_payload_address == _zz_214_));
  assign IBusCachedPlugin_fetchPc_predictionPcLoad_valid = (((IBusCachedPlugin_predictor_line_branchWish[1] && IBusCachedPlugin_predictor_hit) && (! IBusCachedPlugin_predictor_hazard)) && (IBusCachedPlugin_iBusRsp_inputPipeline_0_valid && IBusCachedPlugin_iBusRsp_inputPipeline_0_ready));
  assign IBusCachedPlugin_fetchPc_predictionPcLoad_payload = IBusCachedPlugin_predictor_line_target;
  assign IBusCachedPlugin_predictor_fetchContext_hazard = IBusCachedPlugin_predictor_hazard;
  assign IBusCachedPlugin_predictor_fetchContext_hit = IBusCachedPlugin_predictor_hit;
  assign IBusCachedPlugin_predictor_fetchContext_line_source = IBusCachedPlugin_predictor_line_source;
  assign IBusCachedPlugin_predictor_fetchContext_line_branchWish = IBusCachedPlugin_predictor_line_branchWish;
  assign IBusCachedPlugin_predictor_fetchContext_line_target = IBusCachedPlugin_predictor_line_target;
  assign IBusCachedPlugin_predictor_injectorContext_hazard = IBusCachedPlugin_predictor_fetchContext_regNextWhen_hazard;
  assign IBusCachedPlugin_predictor_injectorContext_hit = IBusCachedPlugin_predictor_fetchContext_regNextWhen_hit;
  assign IBusCachedPlugin_predictor_injectorContext_line_source = IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_source;
  assign IBusCachedPlugin_predictor_injectorContext_line_branchWish = IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_branchWish;
  assign IBusCachedPlugin_predictor_injectorContext_line_target = IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_target;
  assign _zz_72_ = IBusCachedPlugin_predictor_injectorContext_hazard;
  assign _zz_73_ = IBusCachedPlugin_predictor_injectorContext_hit;
  assign _zz_74_ = IBusCachedPlugin_predictor_injectorContext_line_source;
  assign _zz_75_ = IBusCachedPlugin_predictor_injectorContext_line_branchWish;
  assign _zz_76_ = IBusCachedPlugin_predictor_injectorContext_line_target;
  always @ (*) begin
    IBusCachedPlugin_predictor_historyWrite_valid = 1'b0;
    if((! execute_BranchPlugin_predictionMissmatch))begin
      IBusCachedPlugin_predictor_historyWrite_valid = execute_PREDICTION_CONTEXT_hit;
      IBusCachedPlugin_predictor_historyWrite_payload_data_branchWish = (_zz_215_ - _zz_219_);
    end else begin
      if(execute_PREDICTION_CONTEXT_hit)begin
        IBusCachedPlugin_predictor_historyWrite_valid = 1'b1;
        IBusCachedPlugin_predictor_historyWrite_payload_data_branchWish = (_zz_220_ + _zz_224_);
      end else begin
        IBusCachedPlugin_predictor_historyWrite_valid = 1'b1;
        IBusCachedPlugin_predictor_historyWrite_payload_data_branchWish = (2'b10);
      end
    end
    if((execute_PREDICTION_CONTEXT_hazard || (! execute_arbitration_isFiring)))begin
      IBusCachedPlugin_predictor_historyWrite_valid = 1'b0;
    end
  end

  assign IBusCachedPlugin_predictor_historyWrite_payload_address = _zz_84_[9 : 2];
  assign IBusCachedPlugin_predictor_historyWrite_payload_data_source = (_zz_84_ >>> 10);
  assign IBusCachedPlugin_predictor_historyWrite_payload_data_target = execute_BRANCH_CALC;
  assign iBus_cmd_valid = _zz_199_;
  always @ (*) begin
    iBus_cmd_payload_address = _zz_200_;
    iBus_cmd_payload_address = _zz_200_;
  end

  assign iBus_cmd_payload_size = _zz_201_;
  assign _zz_111_ = (! _zz_186_);
  assign IBusCachedPlugin_fetchPc_output_ready = (IBusCachedPlugin_iBusRsp_input_ready && _zz_111_);
  assign IBusCachedPlugin_iBusRsp_input_valid = (IBusCachedPlugin_fetchPc_output_valid && _zz_111_);
  assign IBusCachedPlugin_iBusRsp_input_payload = IBusCachedPlugin_fetchPc_output_payload;
  assign _zz_168_ = (IBusCachedPlugin_jump_pcLoad_valid || _zz_83_);
  assign IBusCachedPlugin_iBusRspOutputHalt = 1'b0;
  assign _zz_169_ = (_zz_88_[31 : 28] == (4'b1111));
  assign _zz_170_ = 1'b1;
  assign _zz_171_ = 1'b1;
  assign _zz_172_ = 1'b1;
  assign _zz_173_ = 1'b1;
  assign _zz_174_ = 1'b0;
  assign _zz_175_ = 1'b1;
  assign _zz_167_ = (! IBusCachedPlugin_iBusRsp_inputPipeline_0_ready);
  assign _zz_176_ = (! IBusCachedPlugin_1_ready);
  assign _zz_177_ = (_zz_91_ == (2'b00));
  assign _zz_71_ = (decode_arbitration_isStuck ? decode_INSTRUCTION : _zz_187_);
  assign _zz_85_ = IBusCachedPlugin_redoFetch;
  assign _zz_86_ = IBusCachedPlugin_1_payload;
  assign _zz_112_ = 1'b0;
  assign _zz_113_ = (! (IBusCachedPlugin_issueDetected || IBusCachedPlugin_iBusRspOutputHalt));
  assign IBusCachedPlugin_1_ready = (IBusCachedPlugin_iBusRsp_decodeInput_ready && _zz_113_);
  assign IBusCachedPlugin_iBusRsp_decodeInput_valid = (IBusCachedPlugin_1_valid && _zz_113_);
  assign IBusCachedPlugin_iBusRsp_decodeInput_payload_rsp_rawInDecode = _zz_196_;
  assign IBusCachedPlugin_iBusRsp_decodeInput_payload_pc = IBusCachedPlugin_1_payload;
  assign dBus_cmd_valid = ((((execute_arbitration_isValid && execute_MEMORY_ENABLE) && (! execute_arbitration_isStuckByOthers)) && (! execute_arbitration_removeIt)) && (! execute_ALIGNEMENT_FAULT));
  assign dBus_cmd_payload_wr = execute_INSTRUCTION[5];
  assign dBus_cmd_payload_address = execute_SRC_ADD;
  assign dBus_cmd_payload_size = execute_INSTRUCTION[13 : 12];
  always @ (*) begin
    case(dBus_cmd_payload_size)
      2'b00 : begin
        _zz_114_ = {{{execute_RS2[7 : 0],execute_RS2[7 : 0]},execute_RS2[7 : 0]},execute_RS2[7 : 0]};
      end
      2'b01 : begin
        _zz_114_ = {execute_RS2[15 : 0],execute_RS2[15 : 0]};
      end
      default : begin
        _zz_114_ = execute_RS2[31 : 0];
      end
    endcase
  end

  assign dBus_cmd_payload_data = _zz_114_;
  assign _zz_69_ = dBus_cmd_payload_address[1 : 0];
  always @ (*) begin
    case(dBus_cmd_payload_size)
      2'b00 : begin
        _zz_115_ = (4'b0001);
      end
      2'b01 : begin
        _zz_115_ = (4'b0011);
      end
      default : begin
        _zz_115_ = (4'b1111);
      end
    endcase
  end

  assign execute_DBusSimplePlugin_formalMask = (_zz_115_ <<< dBus_cmd_payload_address[1 : 0]);
  assign _zz_68_ = dBus_rsp_data;
  always @ (*) begin
    writeBack_DBusSimplePlugin_rspShifted = writeBack_MEMORY_READ_DATA;
    case(writeBack_MEMORY_ADDRESS_LOW)
      2'b01 : begin
        writeBack_DBusSimplePlugin_rspShifted[7 : 0] = writeBack_MEMORY_READ_DATA[15 : 8];
      end
      2'b10 : begin
        writeBack_DBusSimplePlugin_rspShifted[15 : 0] = writeBack_MEMORY_READ_DATA[31 : 16];
      end
      2'b11 : begin
        writeBack_DBusSimplePlugin_rspShifted[7 : 0] = writeBack_MEMORY_READ_DATA[31 : 24];
      end
      default : begin
      end
    endcase
  end

  assign _zz_116_ = (writeBack_DBusSimplePlugin_rspShifted[7] && (! writeBack_INSTRUCTION[14]));
  always @ (*) begin
    _zz_117_[31] = _zz_116_;
    _zz_117_[30] = _zz_116_;
    _zz_117_[29] = _zz_116_;
    _zz_117_[28] = _zz_116_;
    _zz_117_[27] = _zz_116_;
    _zz_117_[26] = _zz_116_;
    _zz_117_[25] = _zz_116_;
    _zz_117_[24] = _zz_116_;
    _zz_117_[23] = _zz_116_;
    _zz_117_[22] = _zz_116_;
    _zz_117_[21] = _zz_116_;
    _zz_117_[20] = _zz_116_;
    _zz_117_[19] = _zz_116_;
    _zz_117_[18] = _zz_116_;
    _zz_117_[17] = _zz_116_;
    _zz_117_[16] = _zz_116_;
    _zz_117_[15] = _zz_116_;
    _zz_117_[14] = _zz_116_;
    _zz_117_[13] = _zz_116_;
    _zz_117_[12] = _zz_116_;
    _zz_117_[11] = _zz_116_;
    _zz_117_[10] = _zz_116_;
    _zz_117_[9] = _zz_116_;
    _zz_117_[8] = _zz_116_;
    _zz_117_[7 : 0] = writeBack_DBusSimplePlugin_rspShifted[7 : 0];
  end

  assign _zz_118_ = (writeBack_DBusSimplePlugin_rspShifted[15] && (! writeBack_INSTRUCTION[14]));
  always @ (*) begin
    _zz_119_[31] = _zz_118_;
    _zz_119_[30] = _zz_118_;
    _zz_119_[29] = _zz_118_;
    _zz_119_[28] = _zz_118_;
    _zz_119_[27] = _zz_118_;
    _zz_119_[26] = _zz_118_;
    _zz_119_[25] = _zz_118_;
    _zz_119_[24] = _zz_118_;
    _zz_119_[23] = _zz_118_;
    _zz_119_[22] = _zz_118_;
    _zz_119_[21] = _zz_118_;
    _zz_119_[20] = _zz_118_;
    _zz_119_[19] = _zz_118_;
    _zz_119_[18] = _zz_118_;
    _zz_119_[17] = _zz_118_;
    _zz_119_[16] = _zz_118_;
    _zz_119_[15 : 0] = writeBack_DBusSimplePlugin_rspShifted[15 : 0];
  end

  always @ (*) begin
    case(_zz_206_)
      2'b00 : begin
        writeBack_DBusSimplePlugin_rspFormated = _zz_117_;
      end
      2'b01 : begin
        writeBack_DBusSimplePlugin_rspFormated = _zz_119_;
      end
      default : begin
        writeBack_DBusSimplePlugin_rspFormated = writeBack_DBusSimplePlugin_rspShifted;
      end
    endcase
  end

  assign _zz_88_ = _zz_190_;
  assign _zz_121_ = ((decode_INSTRUCTION & (32'b00000000000000000110000000000100)) == (32'b00000000000000000010000000000000));
  assign _zz_122_ = ((decode_INSTRUCTION & (32'b00000000000000000000000000000100)) == (32'b00000000000000000000000000000100));
  assign _zz_123_ = ((decode_INSTRUCTION & (32'b00000000000000000000000000010000)) == (32'b00000000000000000000000000010000));
  assign _zz_124_ = ((decode_INSTRUCTION & (32'b00000000000000000000000001001000)) == (32'b00000000000000000000000001001000));
  assign _zz_120_ = {({(_zz_269_ == _zz_270_),(_zz_271_ == _zz_272_)} != (2'b00)),{({_zz_273_,_zz_122_} != (2'b00)),{({_zz_274_,_zz_275_} != (2'b00)),{(_zz_276_ != _zz_277_),{_zz_278_,{_zz_279_,_zz_280_}}}}}};
  assign _zz_66_ = ({((decode_INSTRUCTION & (32'b00000000000000000000000001011111)) == (32'b00000000000000000000000000010111)),{((decode_INSTRUCTION & (32'b00000000000000000001000001101111)) == (32'b00000000000000000000000000000011)),{((decode_INSTRUCTION & (32'b00000000000000000001000001111111)) == (32'b00000000000000000001000001110011)),{((decode_INSTRUCTION & _zz_354_) == (32'b00000000000000000010000001110011)),{(_zz_355_ == _zz_356_),{_zz_357_,{_zz_358_,_zz_359_}}}}}}} != (19'b0000000000000000000));
  assign _zz_65_ = _zz_225_[0];
  assign _zz_64_ = _zz_226_[0];
  assign _zz_63_ = _zz_227_[0];
  assign _zz_125_ = _zz_120_[4 : 3];
  assign _zz_62_ = _zz_125_;
  assign _zz_61_ = _zz_228_[0];
  assign _zz_60_ = _zz_229_[0];
  assign _zz_59_ = _zz_230_[0];
  assign _zz_58_ = _zz_231_[0];
  assign _zz_126_ = _zz_120_[10 : 9];
  assign _zz_57_ = _zz_126_;
  assign _zz_127_ = _zz_120_[12 : 11];
  assign _zz_56_ = _zz_127_;
  assign _zz_128_ = _zz_120_[14 : 13];
  assign _zz_55_ = _zz_128_;
  assign _zz_54_ = _zz_232_[0];
  assign _zz_53_ = _zz_233_[0];
  assign _zz_129_ = _zz_120_[18 : 17];
  assign _zz_52_ = _zz_129_;
  assign _zz_130_ = _zz_120_[20 : 19];
  assign _zz_51_ = _zz_130_;
  assign _zz_131_ = _zz_120_[22 : 21];
  assign _zz_50_ = _zz_131_;
  assign _zz_49_ = _zz_234_[0];
  assign decodeExceptionPort_valid = ((decode_arbitration_isValid && decode_INSTRUCTION_READY) && (! decode_LEGAL_INSTRUCTION));
  assign decodeExceptionPort_1_code = (4'b0010);
  assign decodeExceptionPort_1_badAddr = (32'bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx);
  assign decode_RegFilePlugin_regFileReadAddress1 = decode_INSTRUCTION_ANTICIPATED[19 : 15];
  assign decode_RegFilePlugin_regFileReadAddress2 = decode_INSTRUCTION_ANTICIPATED[24 : 20];
  assign decode_RegFilePlugin_rs1Data = _zz_179_;
  assign decode_RegFilePlugin_rs2Data = _zz_180_;
  assign _zz_48_ = decode_RegFilePlugin_rs1Data;
  assign _zz_47_ = decode_RegFilePlugin_rs2Data;
  always @ (*) begin
    writeBack_RegFilePlugin_regFileWrite_valid = (_zz_45_ && writeBack_arbitration_isFiring);
    if(_zz_132_)begin
      writeBack_RegFilePlugin_regFileWrite_valid = 1'b1;
    end
  end

  assign writeBack_RegFilePlugin_regFileWrite_payload_address = _zz_44_[11 : 7];
  assign writeBack_RegFilePlugin_regFileWrite_payload_data = _zz_67_;
  always @ (*) begin
    case(execute_ALU_BITWISE_CTRL)
      `AluBitwiseCtrlEnum_defaultEncoding_AND_1 : begin
        execute_IntAluPlugin_bitwise = (execute_SRC1 & execute_SRC2);
      end
      `AluBitwiseCtrlEnum_defaultEncoding_OR_1 : begin
        execute_IntAluPlugin_bitwise = (execute_SRC1 | execute_SRC2);
      end
      `AluBitwiseCtrlEnum_defaultEncoding_XOR_1 : begin
        execute_IntAluPlugin_bitwise = (execute_SRC1 ^ execute_SRC2);
      end
      default : begin
        execute_IntAluPlugin_bitwise = execute_SRC1;
      end
    endcase
  end

  always @ (*) begin
    case(execute_ALU_CTRL)
      `AluCtrlEnum_defaultEncoding_BITWISE : begin
        _zz_133_ = execute_IntAluPlugin_bitwise;
      end
      `AluCtrlEnum_defaultEncoding_SLT_SLTU : begin
        _zz_133_ = {31'd0, _zz_235_};
      end
      default : begin
        _zz_133_ = execute_SRC_ADD_SUB;
      end
    endcase
  end

  assign _zz_42_ = _zz_133_;
  always @ (*) begin
    case(execute_SRC1_CTRL)
      `Src1CtrlEnum_defaultEncoding_RS : begin
        _zz_134_ = execute_RS1;
      end
      `Src1CtrlEnum_defaultEncoding_PC_INCREMENT : begin
        _zz_134_ = {29'd0, _zz_236_};
      end
      default : begin
        _zz_134_ = {execute_INSTRUCTION[31 : 12],(12'b000000000000)};
      end
    endcase
  end

  assign _zz_40_ = _zz_134_;
  assign _zz_135_ = _zz_237_[11];
  always @ (*) begin
    _zz_136_[19] = _zz_135_;
    _zz_136_[18] = _zz_135_;
    _zz_136_[17] = _zz_135_;
    _zz_136_[16] = _zz_135_;
    _zz_136_[15] = _zz_135_;
    _zz_136_[14] = _zz_135_;
    _zz_136_[13] = _zz_135_;
    _zz_136_[12] = _zz_135_;
    _zz_136_[11] = _zz_135_;
    _zz_136_[10] = _zz_135_;
    _zz_136_[9] = _zz_135_;
    _zz_136_[8] = _zz_135_;
    _zz_136_[7] = _zz_135_;
    _zz_136_[6] = _zz_135_;
    _zz_136_[5] = _zz_135_;
    _zz_136_[4] = _zz_135_;
    _zz_136_[3] = _zz_135_;
    _zz_136_[2] = _zz_135_;
    _zz_136_[1] = _zz_135_;
    _zz_136_[0] = _zz_135_;
  end

  assign _zz_137_ = _zz_238_[11];
  always @ (*) begin
    _zz_138_[19] = _zz_137_;
    _zz_138_[18] = _zz_137_;
    _zz_138_[17] = _zz_137_;
    _zz_138_[16] = _zz_137_;
    _zz_138_[15] = _zz_137_;
    _zz_138_[14] = _zz_137_;
    _zz_138_[13] = _zz_137_;
    _zz_138_[12] = _zz_137_;
    _zz_138_[11] = _zz_137_;
    _zz_138_[10] = _zz_137_;
    _zz_138_[9] = _zz_137_;
    _zz_138_[8] = _zz_137_;
    _zz_138_[7] = _zz_137_;
    _zz_138_[6] = _zz_137_;
    _zz_138_[5] = _zz_137_;
    _zz_138_[4] = _zz_137_;
    _zz_138_[3] = _zz_137_;
    _zz_138_[2] = _zz_137_;
    _zz_138_[1] = _zz_137_;
    _zz_138_[0] = _zz_137_;
  end

  always @ (*) begin
    case(execute_SRC2_CTRL)
      `Src2CtrlEnum_defaultEncoding_RS : begin
        _zz_139_ = execute_RS2;
      end
      `Src2CtrlEnum_defaultEncoding_IMI : begin
        _zz_139_ = {_zz_136_,execute_INSTRUCTION[31 : 20]};
      end
      `Src2CtrlEnum_defaultEncoding_IMS : begin
        _zz_139_ = {_zz_138_,{execute_INSTRUCTION[31 : 25],execute_INSTRUCTION[11 : 7]}};
      end
      default : begin
        _zz_139_ = _zz_36_;
      end
    endcase
  end

  assign _zz_38_ = _zz_139_;
  assign execute_SrcPlugin_addSub = _zz_239_;
  assign execute_SrcPlugin_less = ((execute_SRC1[31] == execute_SRC2[31]) ? execute_SrcPlugin_addSub[31] : (execute_SRC_LESS_UNSIGNED ? execute_SRC2[31] : execute_SRC1[31]));
  assign _zz_35_ = execute_SrcPlugin_addSub;
  assign _zz_34_ = execute_SrcPlugin_addSub;
  assign _zz_33_ = execute_SrcPlugin_less;
  assign execute_FullBarrelShifterPlugin_amplitude = execute_SRC2[4 : 0];
  always @ (*) begin
    _zz_140_[0] = execute_SRC1[31];
    _zz_140_[1] = execute_SRC1[30];
    _zz_140_[2] = execute_SRC1[29];
    _zz_140_[3] = execute_SRC1[28];
    _zz_140_[4] = execute_SRC1[27];
    _zz_140_[5] = execute_SRC1[26];
    _zz_140_[6] = execute_SRC1[25];
    _zz_140_[7] = execute_SRC1[24];
    _zz_140_[8] = execute_SRC1[23];
    _zz_140_[9] = execute_SRC1[22];
    _zz_140_[10] = execute_SRC1[21];
    _zz_140_[11] = execute_SRC1[20];
    _zz_140_[12] = execute_SRC1[19];
    _zz_140_[13] = execute_SRC1[18];
    _zz_140_[14] = execute_SRC1[17];
    _zz_140_[15] = execute_SRC1[16];
    _zz_140_[16] = execute_SRC1[15];
    _zz_140_[17] = execute_SRC1[14];
    _zz_140_[18] = execute_SRC1[13];
    _zz_140_[19] = execute_SRC1[12];
    _zz_140_[20] = execute_SRC1[11];
    _zz_140_[21] = execute_SRC1[10];
    _zz_140_[22] = execute_SRC1[9];
    _zz_140_[23] = execute_SRC1[8];
    _zz_140_[24] = execute_SRC1[7];
    _zz_140_[25] = execute_SRC1[6];
    _zz_140_[26] = execute_SRC1[5];
    _zz_140_[27] = execute_SRC1[4];
    _zz_140_[28] = execute_SRC1[3];
    _zz_140_[29] = execute_SRC1[2];
    _zz_140_[30] = execute_SRC1[1];
    _zz_140_[31] = execute_SRC1[0];
  end

  assign execute_FullBarrelShifterPlugin_reversed = ((execute_SHIFT_CTRL == `ShiftCtrlEnum_defaultEncoding_SLL_1) ? _zz_140_ : execute_SRC1);
  assign _zz_31_ = _zz_248_;
  always @ (*) begin
    _zz_141_[0] = execute_SHIFT_RIGHT[31];
    _zz_141_[1] = execute_SHIFT_RIGHT[30];
    _zz_141_[2] = execute_SHIFT_RIGHT[29];
    _zz_141_[3] = execute_SHIFT_RIGHT[28];
    _zz_141_[4] = execute_SHIFT_RIGHT[27];
    _zz_141_[5] = execute_SHIFT_RIGHT[26];
    _zz_141_[6] = execute_SHIFT_RIGHT[25];
    _zz_141_[7] = execute_SHIFT_RIGHT[24];
    _zz_141_[8] = execute_SHIFT_RIGHT[23];
    _zz_141_[9] = execute_SHIFT_RIGHT[22];
    _zz_141_[10] = execute_SHIFT_RIGHT[21];
    _zz_141_[11] = execute_SHIFT_RIGHT[20];
    _zz_141_[12] = execute_SHIFT_RIGHT[19];
    _zz_141_[13] = execute_SHIFT_RIGHT[18];
    _zz_141_[14] = execute_SHIFT_RIGHT[17];
    _zz_141_[15] = execute_SHIFT_RIGHT[16];
    _zz_141_[16] = execute_SHIFT_RIGHT[15];
    _zz_141_[17] = execute_SHIFT_RIGHT[14];
    _zz_141_[18] = execute_SHIFT_RIGHT[13];
    _zz_141_[19] = execute_SHIFT_RIGHT[12];
    _zz_141_[20] = execute_SHIFT_RIGHT[11];
    _zz_141_[21] = execute_SHIFT_RIGHT[10];
    _zz_141_[22] = execute_SHIFT_RIGHT[9];
    _zz_141_[23] = execute_SHIFT_RIGHT[8];
    _zz_141_[24] = execute_SHIFT_RIGHT[7];
    _zz_141_[25] = execute_SHIFT_RIGHT[6];
    _zz_141_[26] = execute_SHIFT_RIGHT[5];
    _zz_141_[27] = execute_SHIFT_RIGHT[4];
    _zz_141_[28] = execute_SHIFT_RIGHT[3];
    _zz_141_[29] = execute_SHIFT_RIGHT[2];
    _zz_141_[30] = execute_SHIFT_RIGHT[1];
    _zz_141_[31] = execute_SHIFT_RIGHT[0];
  end

  always @ (*) begin
    _zz_142_ = 1'b0;
    _zz_143_ = 1'b0;
    if((writeBack_arbitration_isValid && writeBack_REGFILE_WRITE_VALID))begin
      if((1'b0 || (! 1'b1)))begin
        if(_zz_147_)begin
          _zz_142_ = 1'b1;
        end
        if(_zz_148_)begin
          _zz_143_ = 1'b1;
        end
      end
    end
    if((memory_arbitration_isValid && memory_REGFILE_WRITE_VALID))begin
      if((1'b0 || (! memory_BYPASSABLE_MEMORY_STAGE)))begin
        if(_zz_149_)begin
          _zz_142_ = 1'b1;
        end
        if(_zz_150_)begin
          _zz_143_ = 1'b1;
        end
      end
    end
    if((execute_arbitration_isValid && execute_REGFILE_WRITE_VALID))begin
      if((1'b0 || (! execute_BYPASSABLE_EXECUTE_STAGE)))begin
        if(_zz_151_)begin
          _zz_142_ = 1'b1;
        end
        if(_zz_152_)begin
          _zz_143_ = 1'b1;
        end
      end
    end
    if((! decode_RS1_USE))begin
      _zz_142_ = 1'b0;
    end
    if((! decode_RS2_USE))begin
      _zz_143_ = 1'b0;
    end
  end

  assign _zz_147_ = (writeBack_INSTRUCTION[11 : 7] == decode_INSTRUCTION[19 : 15]);
  assign _zz_148_ = (writeBack_INSTRUCTION[11 : 7] == decode_INSTRUCTION[24 : 20]);
  assign _zz_149_ = (memory_INSTRUCTION[11 : 7] == decode_INSTRUCTION[19 : 15]);
  assign _zz_150_ = (memory_INSTRUCTION[11 : 7] == decode_INSTRUCTION[24 : 20]);
  assign _zz_151_ = (execute_INSTRUCTION[11 : 7] == decode_INSTRUCTION[19 : 15]);
  assign _zz_152_ = (execute_INSTRUCTION[11 : 7] == decode_INSTRUCTION[24 : 20]);
  assign CsrPlugin_misa_base = (2'b01);
  assign CsrPlugin_misa_extensions = (26'b00000000000000000001000010);
  assign CsrPlugin_mtvec = (32'b10000000000000000000000000000000);
  assign decode_exception_agregat_valid = (_zz_87_ || decodeExceptionPort_valid);
  assign _zz_153_ = {decodeExceptionPort_valid,_zz_87_};
  assign _zz_154_ = _zz_250_[1];
  assign _zz_155_ = _zz_154_;
  assign decode_exception_agregat_payload_code = _zz_182_;
  assign decode_exception_agregat_payload_badAddr = _zz_183_;
  always @ (*) begin
    CsrPlugin_exceptionPortCtrl_exceptionValids_decode = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode;
    if(decode_exception_agregat_valid)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_decode = 1'b1;
    end
    if(decode_arbitration_isFlushed)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_decode = 1'b0;
    end
  end

  always @ (*) begin
    CsrPlugin_exceptionPortCtrl_exceptionValids_memory = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory;
    if(memory_arbitration_isFlushed)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_memory = 1'b0;
    end
  end

  always @ (*) begin
    CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack = CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack;
    if(writeBack_arbitration_isFlushed)begin
      CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack = 1'b0;
    end
  end

  assign CsrPlugin_interruptRequest = ((((CsrPlugin_mip_MSIP && CsrPlugin_mie_MSIE) || (CsrPlugin_mip_MEIP && CsrPlugin_mie_MEIE)) || (CsrPlugin_mip_MTIP && CsrPlugin_mie_MTIE)) && CsrPlugin_mstatus_MIE);
  assign CsrPlugin_interrupt = (CsrPlugin_interruptRequest && 1'b1);
  assign CsrPlugin_exception = (CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack && 1'b1);
  assign CsrPlugin_writeBackWasWfi = 1'b0;
  always @ (*) begin
    CsrPlugin_pipelineLiberator_done = ((! ((execute_arbitration_isValid || memory_arbitration_isValid) || writeBack_arbitration_isValid)) && IBusCachedPlugin_injector_nextPcCalc_3);
    if(((CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory) || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack))begin
      CsrPlugin_pipelineLiberator_done = 1'b0;
    end
  end

  assign CsrPlugin_interruptCode = ((CsrPlugin_mip_MEIP && CsrPlugin_mie_MEIE) ? (4'b1011) : _zz_253_);
  assign CsrPlugin_interruptJump = (CsrPlugin_interrupt && CsrPlugin_pipelineLiberator_done);
  assign contextSwitching = _zz_89_;
  assign _zz_27_ = (! (((decode_INSTRUCTION[14 : 13] == (2'b01)) && (decode_INSTRUCTION[19 : 15] == (5'b00000))) || ((decode_INSTRUCTION[14 : 13] == (2'b11)) && (decode_INSTRUCTION[19 : 15] == (5'b00000)))));
  assign _zz_26_ = (decode_INSTRUCTION[13 : 7] != (7'b0100000));
  always @ (*) begin
    execute_CsrPlugin_illegalAccess = (execute_arbitration_isValid && execute_IS_CSR);
    execute_CsrPlugin_readData = (32'b00000000000000000000000000000000);
    case(execute_CsrPlugin_csrAddress)
      12'b001100000000 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[12 : 11] = CsrPlugin_mstatus_MPP;
        execute_CsrPlugin_readData[7 : 7] = CsrPlugin_mstatus_MPIE;
        execute_CsrPlugin_readData[3 : 3] = CsrPlugin_mstatus_MIE;
      end
      12'b001101000001 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[31 : 0] = CsrPlugin_mepc;
      end
      12'b001101000100 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[11 : 11] = CsrPlugin_mip_MEIP;
        execute_CsrPlugin_readData[7 : 7] = CsrPlugin_mip_MTIP;
        execute_CsrPlugin_readData[3 : 3] = CsrPlugin_mip_MSIP;
      end
      12'b001101000011 : begin
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
        execute_CsrPlugin_readData[31 : 0] = CsrPlugin_mbadaddr;
      end
      12'b001100000100 : begin
        execute_CsrPlugin_illegalAccess = 1'b0;
        execute_CsrPlugin_readData[11 : 11] = CsrPlugin_mie_MEIE;
        execute_CsrPlugin_readData[7 : 7] = CsrPlugin_mie_MTIE;
        execute_CsrPlugin_readData[3 : 3] = CsrPlugin_mie_MSIE;
      end
      12'b001101000010 : begin
        if(execute_CSR_READ_OPCODE)begin
          execute_CsrPlugin_illegalAccess = 1'b0;
        end
        execute_CsrPlugin_readData[31 : 31] = CsrPlugin_mcause_interrupt;
        execute_CsrPlugin_readData[3 : 0] = CsrPlugin_mcause_exceptionCode;
      end
      default : begin
      end
    endcase
    if((_zz_91_ < execute_CsrPlugin_csrAddress[9 : 8]))begin
      execute_CsrPlugin_illegalAccess = 1'b1;
    end
  end

  assign execute_CsrPlugin_writeSrc = (execute_INSTRUCTION[14] ? _zz_255_ : execute_SRC1);
  always @ (*) begin
    case(_zz_207_)
      1'b0 : begin
        execute_CsrPlugin_writeData = execute_CsrPlugin_writeSrc;
      end
      default : begin
        execute_CsrPlugin_writeData = (execute_INSTRUCTION[12] ? (memory_REGFILE_WRITE_DATA & (~ execute_CsrPlugin_writeSrc)) : (memory_REGFILE_WRITE_DATA | execute_CsrPlugin_writeSrc));
      end
    endcase
  end

  assign execute_CsrPlugin_writeInstruction = ((execute_arbitration_isValid && execute_IS_CSR) && execute_CSR_WRITE_OPCODE);
  assign execute_CsrPlugin_readInstruction = ((execute_arbitration_isValid && execute_IS_CSR) && execute_CSR_READ_OPCODE);
  assign execute_CsrPlugin_writeEnable = (execute_CsrPlugin_writeInstruction && execute_CsrPlugin_readDataRegValid);
  assign execute_CsrPlugin_readEnable = (execute_CsrPlugin_readInstruction && (! execute_CsrPlugin_readDataRegValid));
  assign execute_CsrPlugin_csrAddress = execute_INSTRUCTION[31 : 20];
  assign execute_BranchPlugin_eq = (execute_SRC1 == execute_SRC2);
  assign _zz_156_ = execute_INSTRUCTION[14 : 12];
  always @ (*) begin
    if((_zz_156_ == (3'b000))) begin
        _zz_157_ = execute_BranchPlugin_eq;
    end else if((_zz_156_ == (3'b001))) begin
        _zz_157_ = (! execute_BranchPlugin_eq);
    end else if((((_zz_156_ & (3'b101)) == (3'b101)))) begin
        _zz_157_ = (! execute_SRC_LESS);
    end else begin
        _zz_157_ = execute_SRC_LESS;
    end
  end

  always @ (*) begin
    case(execute_BRANCH_CTRL)
      `BranchCtrlEnum_defaultEncoding_INC : begin
        _zz_158_ = 1'b0;
      end
      `BranchCtrlEnum_defaultEncoding_JAL : begin
        _zz_158_ = 1'b1;
      end
      `BranchCtrlEnum_defaultEncoding_JALR : begin
        _zz_158_ = 1'b1;
      end
      default : begin
        _zz_158_ = _zz_157_;
      end
    endcase
  end

  assign _zz_25_ = _zz_158_;
  assign execute_BranchPlugin_branch_src1 = ((execute_BRANCH_CTRL == `BranchCtrlEnum_defaultEncoding_JALR) ? execute_RS1 : execute_PC);
  assign _zz_159_ = _zz_256_[19];
  always @ (*) begin
    _zz_160_[10] = _zz_159_;
    _zz_160_[9] = _zz_159_;
    _zz_160_[8] = _zz_159_;
    _zz_160_[7] = _zz_159_;
    _zz_160_[6] = _zz_159_;
    _zz_160_[5] = _zz_159_;
    _zz_160_[4] = _zz_159_;
    _zz_160_[3] = _zz_159_;
    _zz_160_[2] = _zz_159_;
    _zz_160_[1] = _zz_159_;
    _zz_160_[0] = _zz_159_;
  end

  assign _zz_161_ = _zz_257_[11];
  always @ (*) begin
    _zz_162_[19] = _zz_161_;
    _zz_162_[18] = _zz_161_;
    _zz_162_[17] = _zz_161_;
    _zz_162_[16] = _zz_161_;
    _zz_162_[15] = _zz_161_;
    _zz_162_[14] = _zz_161_;
    _zz_162_[13] = _zz_161_;
    _zz_162_[12] = _zz_161_;
    _zz_162_[11] = _zz_161_;
    _zz_162_[10] = _zz_161_;
    _zz_162_[9] = _zz_161_;
    _zz_162_[8] = _zz_161_;
    _zz_162_[7] = _zz_161_;
    _zz_162_[6] = _zz_161_;
    _zz_162_[5] = _zz_161_;
    _zz_162_[4] = _zz_161_;
    _zz_162_[3] = _zz_161_;
    _zz_162_[2] = _zz_161_;
    _zz_162_[1] = _zz_161_;
    _zz_162_[0] = _zz_161_;
  end

  assign _zz_163_ = _zz_258_[11];
  always @ (*) begin
    _zz_164_[18] = _zz_163_;
    _zz_164_[17] = _zz_163_;
    _zz_164_[16] = _zz_163_;
    _zz_164_[15] = _zz_163_;
    _zz_164_[14] = _zz_163_;
    _zz_164_[13] = _zz_163_;
    _zz_164_[12] = _zz_163_;
    _zz_164_[11] = _zz_163_;
    _zz_164_[10] = _zz_163_;
    _zz_164_[9] = _zz_163_;
    _zz_164_[8] = _zz_163_;
    _zz_164_[7] = _zz_163_;
    _zz_164_[6] = _zz_163_;
    _zz_164_[5] = _zz_163_;
    _zz_164_[4] = _zz_163_;
    _zz_164_[3] = _zz_163_;
    _zz_164_[2] = _zz_163_;
    _zz_164_[1] = _zz_163_;
    _zz_164_[0] = _zz_163_;
  end

  always @ (*) begin
    case(execute_BRANCH_CTRL)
      `BranchCtrlEnum_defaultEncoding_JAL : begin
        _zz_165_ = {{_zz_160_,{{{execute_INSTRUCTION[31],execute_INSTRUCTION[19 : 12]},execute_INSTRUCTION[20]},execute_INSTRUCTION[30 : 21]}},1'b0};
      end
      `BranchCtrlEnum_defaultEncoding_JALR : begin
        _zz_165_ = {_zz_162_,execute_INSTRUCTION[31 : 20]};
      end
      default : begin
        _zz_165_ = {{_zz_164_,{{{execute_INSTRUCTION[31],execute_INSTRUCTION[7]},execute_INSTRUCTION[30 : 25]},execute_INSTRUCTION[11 : 8]}},1'b0};
      end
    endcase
  end

  assign execute_BranchPlugin_branch_src2 = _zz_165_;
  assign execute_BranchPlugin_branchAdder = (execute_BranchPlugin_branch_src1 + execute_BranchPlugin_branch_src2);
  assign _zz_23_ = {execute_BranchPlugin_branchAdder[31 : 1],((execute_BRANCH_CTRL == `BranchCtrlEnum_defaultEncoding_JALR) ? 1'b0 : execute_BranchPlugin_branchAdder[0])};
  assign _zz_22_ = (execute_PC + (32'b00000000000000000000000000000100));
  assign execute_BranchPlugin_predictionMissmatch = ((((execute_PREDICTION_CONTEXT_hit && (! execute_PREDICTION_CONTEXT_hazard)) && execute_PREDICTION_CONTEXT_line_branchWish[1]) != execute_BRANCH_DO) || (execute_BRANCH_DO && (execute_PREDICTION_CONTEXT_line_target != execute_BRANCH_CALC)));
  assign _zz_84_ = execute_PC;
  assign _zz_92_ = (execute_arbitration_isFiring && execute_BranchPlugin_predictionMissmatch);
  assign _zz_93_ = (execute_BRANCH_DO ? execute_BRANCH_CALC : execute_NEXT_PC2);
  assign execute_exception_agregat_valid = ((execute_arbitration_isValid && execute_BRANCH_DO) && (execute_BRANCH_CALC[1 : 0] != (2'b00)));
  assign execute_exception_agregat_payload_code = (4'b0000);
  assign execute_exception_agregat_payload_badAddr = execute_BRANCH_CALC;
  assign _zz_21_ = decode_ENV_CTRL;
  assign _zz_19_ = _zz_56_;
  assign _zz_28_ = decode_to_execute_ENV_CTRL;
  assign _zz_18_ = decode_SRC1_CTRL;
  assign _zz_16_ = _zz_55_;
  assign _zz_39_ = decode_to_execute_SRC1_CTRL;
  assign _zz_15_ = decode_SRC2_CTRL;
  assign _zz_13_ = _zz_62_;
  assign _zz_37_ = decode_to_execute_SRC2_CTRL;
  assign _zz_12_ = decode_BRANCH_CTRL;
  assign _zz_10_ = _zz_57_;
  assign _zz_24_ = decode_to_execute_BRANCH_CTRL;
  assign _zz_9_ = decode_ALU_CTRL;
  assign _zz_7_ = _zz_51_;
  assign _zz_41_ = decode_to_execute_ALU_CTRL;
  assign _zz_6_ = decode_ALU_BITWISE_CTRL;
  assign _zz_4_ = _zz_50_;
  assign _zz_43_ = decode_to_execute_ALU_BITWISE_CTRL;
  assign _zz_3_ = decode_SHIFT_CTRL;
  assign _zz_1_ = _zz_52_;
  assign _zz_32_ = decode_to_execute_SHIFT_CTRL;
  assign decode_arbitration_isFlushed = (((decode_arbitration_flushAll || execute_arbitration_flushAll) || memory_arbitration_flushAll) || writeBack_arbitration_flushAll);
  assign execute_arbitration_isFlushed = ((execute_arbitration_flushAll || memory_arbitration_flushAll) || writeBack_arbitration_flushAll);
  assign memory_arbitration_isFlushed = (memory_arbitration_flushAll || writeBack_arbitration_flushAll);
  assign writeBack_arbitration_isFlushed = writeBack_arbitration_flushAll;
  assign decode_arbitration_isStuckByOthers = (decode_arbitration_haltByOther || (((1'b0 || execute_arbitration_isStuck) || memory_arbitration_isStuck) || writeBack_arbitration_isStuck));
  assign decode_arbitration_isStuck = (decode_arbitration_haltItself || decode_arbitration_isStuckByOthers);
  assign decode_arbitration_isMoving = ((! decode_arbitration_isStuck) && (! decode_arbitration_removeIt));
  assign decode_arbitration_isFiring = ((decode_arbitration_isValid && (! decode_arbitration_isStuck)) && (! decode_arbitration_removeIt));
  assign execute_arbitration_isStuckByOthers = (execute_arbitration_haltByOther || ((1'b0 || memory_arbitration_isStuck) || writeBack_arbitration_isStuck));
  assign execute_arbitration_isStuck = (execute_arbitration_haltItself || execute_arbitration_isStuckByOthers);
  assign execute_arbitration_isMoving = ((! execute_arbitration_isStuck) && (! execute_arbitration_removeIt));
  assign execute_arbitration_isFiring = ((execute_arbitration_isValid && (! execute_arbitration_isStuck)) && (! execute_arbitration_removeIt));
  assign memory_arbitration_isStuckByOthers = (memory_arbitration_haltByOther || (1'b0 || writeBack_arbitration_isStuck));
  assign memory_arbitration_isStuck = (memory_arbitration_haltItself || memory_arbitration_isStuckByOthers);
  assign memory_arbitration_isMoving = ((! memory_arbitration_isStuck) && (! memory_arbitration_removeIt));
  assign memory_arbitration_isFiring = ((memory_arbitration_isValid && (! memory_arbitration_isStuck)) && (! memory_arbitration_removeIt));
  assign writeBack_arbitration_isStuckByOthers = (writeBack_arbitration_haltByOther || 1'b0);
  assign writeBack_arbitration_isStuck = (writeBack_arbitration_haltItself || writeBack_arbitration_isStuckByOthers);
  assign writeBack_arbitration_isMoving = ((! writeBack_arbitration_isStuck) && (! writeBack_arbitration_removeIt));
  assign writeBack_arbitration_isFiring = ((writeBack_arbitration_isValid && (! writeBack_arbitration_isStuck)) && (! writeBack_arbitration_removeIt));
  always @ (posedge clk or posedge reset) begin
    if (reset) begin
      _zz_91_ <= (2'b11);
      IBusCachedPlugin_fetchPc_pcReg <= (32'b10000000000000000000000000000000);
      IBusCachedPlugin_fetchPc_inc <= 1'b0;
      _zz_99_ <= 1'b0;
      _zz_101_ <= 1'b0;
      _zz_106_ <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_valids_0 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_0 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_1 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_2 <= 1'b0;
      IBusCachedPlugin_injector_nextPcCalc_3 <= 1'b0;
      IBusCachedPlugin_injector_decodeRemoved <= 1'b0;
      _zz_132_ <= 1'b1;
      _zz_144_ <= 1'b0;
      CsrPlugin_mstatus_MIE <= 1'b0;
      CsrPlugin_mstatus_MPIE <= 1'b0;
      CsrPlugin_mstatus_MPP <= (2'b11);
      CsrPlugin_mip_MEIP <= 1'b0;
      CsrPlugin_mip_MTIP <= 1'b0;
      CsrPlugin_mip_MSIP <= 1'b0;
      CsrPlugin_mie_MEIE <= 1'b0;
      CsrPlugin_mie_MTIE <= 1'b0;
      CsrPlugin_mie_MSIE <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory <= 1'b0;
      CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack <= 1'b0;
      execute_arbitration_isValid <= 1'b0;
      memory_arbitration_isValid <= 1'b0;
      writeBack_arbitration_isValid <= 1'b0;
      memory_to_writeBack_REGFILE_WRITE_DATA <= (32'b00000000000000000000000000000000);
      memory_to_writeBack_INSTRUCTION <= (32'b00000000000000000000000000000000);
    end else begin
      if(IBusCachedPlugin_fetchPc_predictionPcLoad_valid)begin
        IBusCachedPlugin_fetchPc_inc <= 1'b0;
      end
      if(IBusCachedPlugin_jump_pcLoad_valid)begin
        IBusCachedPlugin_fetchPc_inc <= 1'b0;
      end
      if(_zz_205_)begin
        IBusCachedPlugin_fetchPc_inc <= 1'b1;
      end
      if(IBusCachedPlugin_fetchPc_samplePcNext)begin
        IBusCachedPlugin_fetchPc_pcReg <= IBusCachedPlugin_fetchPc_pc;
      end
      _zz_99_ <= 1'b1;
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        _zz_101_ <= 1'b0;
      end
      if(IBusCachedPlugin_iBusRsp_input_ready)begin
        _zz_101_ <= IBusCachedPlugin_iBusRsp_input_valid;
      end
      if(_zz_104_)begin
        _zz_106_ <= (IBusCachedPlugin_iBusRsp_inputPipeline_0_valid && _zz_103_);
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        _zz_106_ <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_valids_0 <= 1'b0;
      end
      if((! (! IBusCachedPlugin_iBusRsp_inputPipeline_0_ready)))begin
        IBusCachedPlugin_injector_nextPcCalc_valids_0 <= 1'b1;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_0 <= 1'b0;
      end
      if((! (! IBusCachedPlugin_1_ready)))begin
        IBusCachedPlugin_injector_nextPcCalc_0 <= IBusCachedPlugin_injector_nextPcCalc_valids_0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_0 <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_1 <= 1'b0;
      end
      if((! execute_arbitration_isStuck))begin
        IBusCachedPlugin_injector_nextPcCalc_1 <= IBusCachedPlugin_injector_nextPcCalc_0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_1 <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_2 <= 1'b0;
      end
      if((! memory_arbitration_isStuck))begin
        IBusCachedPlugin_injector_nextPcCalc_2 <= IBusCachedPlugin_injector_nextPcCalc_1;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_2 <= 1'b0;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_3 <= 1'b0;
      end
      if((! writeBack_arbitration_isStuck))begin
        IBusCachedPlugin_injector_nextPcCalc_3 <= IBusCachedPlugin_injector_nextPcCalc_2;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_nextPcCalc_3 <= 1'b0;
      end
      if(decode_arbitration_removeIt)begin
        IBusCachedPlugin_injector_decodeRemoved <= 1'b1;
      end
      if((IBusCachedPlugin_jump_pcLoad_valid || _zz_83_))begin
        IBusCachedPlugin_injector_decodeRemoved <= 1'b0;
      end
      _zz_132_ <= 1'b0;
      _zz_144_ <= (_zz_45_ && writeBack_arbitration_isFiring);
      CsrPlugin_mip_MEIP <= externalInterrupt;
      CsrPlugin_mip_MTIP <= timerInterrupt;
      if((! decode_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode <= 1'b0;
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_decode <= CsrPlugin_exceptionPortCtrl_exceptionValids_decode;
      end
      if((! execute_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute <= (CsrPlugin_exceptionPortCtrl_exceptionValids_decode && (! decode_arbitration_isStuck));
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute <= CsrPlugin_exceptionPortCtrl_exceptionValids_execute;
      end
      if((! memory_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory <= (CsrPlugin_exceptionPortCtrl_exceptionValids_execute && (! execute_arbitration_isStuck));
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory <= CsrPlugin_exceptionPortCtrl_exceptionValids_memory;
      end
      if((! writeBack_arbitration_isStuck))begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack <= (CsrPlugin_exceptionPortCtrl_exceptionValids_memory && (! memory_arbitration_isStuck));
      end else begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack <= CsrPlugin_exceptionPortCtrl_exceptionValids_writeBack;
      end
      if(_zz_202_)begin
        CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack <= 1'b0;
        CsrPlugin_mstatus_MIE <= 1'b0;
        CsrPlugin_mstatus_MPIE <= CsrPlugin_mstatus_MIE;
        CsrPlugin_mstatus_MPP <= _zz_91_;
      end
      if(_zz_203_)begin
        if(! _zz_204_) begin
          CsrPlugin_mstatus_MIE <= CsrPlugin_mstatus_MPIE;
          _zz_91_ <= CsrPlugin_mstatus_MPP;
        end
      end
      if((! writeBack_arbitration_isStuck))begin
        memory_to_writeBack_INSTRUCTION <= memory_INSTRUCTION;
      end
      if((! writeBack_arbitration_isStuck))begin
        memory_to_writeBack_REGFILE_WRITE_DATA <= _zz_29_;
      end
      if(((! execute_arbitration_isStuck) || execute_arbitration_removeIt))begin
        execute_arbitration_isValid <= 1'b0;
      end
      if(((! decode_arbitration_isStuck) && (! decode_arbitration_removeIt)))begin
        execute_arbitration_isValid <= decode_arbitration_isValid;
      end
      if(((! memory_arbitration_isStuck) || memory_arbitration_removeIt))begin
        memory_arbitration_isValid <= 1'b0;
      end
      if(((! execute_arbitration_isStuck) && (! execute_arbitration_removeIt)))begin
        memory_arbitration_isValid <= execute_arbitration_isValid;
      end
      if(((! writeBack_arbitration_isStuck) || writeBack_arbitration_removeIt))begin
        writeBack_arbitration_isValid <= 1'b0;
      end
      if(((! memory_arbitration_isStuck) && (! memory_arbitration_removeIt)))begin
        writeBack_arbitration_isValid <= memory_arbitration_isValid;
      end
      case(execute_CsrPlugin_csrAddress)
        12'b001100000000 : begin
          if(execute_CsrPlugin_writeEnable)begin
            CsrPlugin_mstatus_MPP <= execute_CsrPlugin_writeData[12 : 11];
            CsrPlugin_mstatus_MPIE <= _zz_259_[0];
            CsrPlugin_mstatus_MIE <= _zz_260_[0];
          end
        end
        12'b001101000001 : begin
        end
        12'b001101000100 : begin
          if(execute_CsrPlugin_writeEnable)begin
            CsrPlugin_mip_MSIP <= _zz_261_[0];
          end
        end
        12'b001101000011 : begin
        end
        12'b001100000100 : begin
          if(execute_CsrPlugin_writeEnable)begin
            CsrPlugin_mie_MEIE <= _zz_262_[0];
            CsrPlugin_mie_MTIE <= _zz_263_[0];
            CsrPlugin_mie_MSIE <= _zz_264_[0];
          end
        end
        12'b001101000010 : begin
        end
        default : begin
        end
      endcase
    end
  end

  always @ (posedge clk) begin
    if(IBusCachedPlugin_iBusRsp_input_ready)begin
      _zz_102_ <= IBusCachedPlugin_iBusRsp_input_payload;
    end
    if(_zz_104_)begin
      _zz_107_ <= IBusCachedPlugin_iBusRsp_inputPipeline_0_payload;
    end
    if(IBusCachedPlugin_iBusRsp_inputPipeline_0_ready)begin
      IBusCachedPlugin_predictor_historyWriteLast_valid <= IBusCachedPlugin_predictor_historyWrite_valid;
      IBusCachedPlugin_predictor_historyWriteLast_payload_address <= IBusCachedPlugin_predictor_historyWrite_payload_address;
      IBusCachedPlugin_predictor_historyWriteLast_payload_data_source <= IBusCachedPlugin_predictor_historyWrite_payload_data_source;
      IBusCachedPlugin_predictor_historyWriteLast_payload_data_branchWish <= IBusCachedPlugin_predictor_historyWrite_payload_data_branchWish;
      IBusCachedPlugin_predictor_historyWriteLast_payload_data_target <= IBusCachedPlugin_predictor_historyWrite_payload_data_target;
    end
    if(IBusCachedPlugin_1_ready)begin
      IBusCachedPlugin_predictor_fetchContext_regNextWhen_hazard <= IBusCachedPlugin_predictor_fetchContext_hazard;
      IBusCachedPlugin_predictor_fetchContext_regNextWhen_hit <= IBusCachedPlugin_predictor_fetchContext_hit;
      IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_source <= IBusCachedPlugin_predictor_fetchContext_line_source;
      IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_branchWish <= IBusCachedPlugin_predictor_fetchContext_line_branchWish;
      IBusCachedPlugin_predictor_fetchContext_regNextWhen_line_target <= IBusCachedPlugin_predictor_fetchContext_line_target;
    end
`ifndef SYNTHESIS
    if(!(! (((dBus_rsp_ready && memory_MEMORY_ENABLE) && memory_arbitration_isValid) && memory_arbitration_isStuck))) begin
      $display("ERROR DBusSimplePlugin doesn't allow memory stage stall when read happend");
    end
`endif
`ifndef SYNTHESIS
    if(!(! (((writeBack_arbitration_isValid && writeBack_MEMORY_ENABLE) && (! writeBack_INSTRUCTION[5])) && writeBack_arbitration_isStuck))) begin
      $display("ERROR DBusSimplePlugin doesn't allow writeback stage stall when read happend");
    end
`endif
    _zz_145_ <= _zz_44_[11 : 7];
    _zz_146_ <= _zz_67_;
    CsrPlugin_mcycle <= (CsrPlugin_mcycle + (64'b0000000000000000000000000000000000000000000000000000000000000001));
    if(writeBack_arbitration_isFiring)begin
      CsrPlugin_minstret <= (CsrPlugin_minstret + (64'b0000000000000000000000000000000000000000000000000000000000000001));
    end
    if(decode_exception_agregat_valid)begin
      if((! (((1'b0 || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_execute) || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory) || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack)))begin
        CsrPlugin_exceptionPortCtrl_exceptionContext_code <= decode_exception_agregat_payload_code;
        CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr <= decode_exception_agregat_payload_badAddr;
      end
    end
    if(execute_exception_agregat_valid)begin
      if((! ((1'b0 || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_memory) || CsrPlugin_exceptionPortCtrl_exceptionValidsRegs_writeBack)))begin
        CsrPlugin_exceptionPortCtrl_exceptionContext_code <= execute_exception_agregat_payload_code;
        CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr <= execute_exception_agregat_payload_badAddr;
      end
    end
    if(_zz_202_)begin
      CsrPlugin_mepc <= writeBack_PC;
      CsrPlugin_mcause_interrupt <= CsrPlugin_interruptJump;
      CsrPlugin_mcause_exceptionCode <= CsrPlugin_interruptCode;
    end
    CsrPlugin_exception_regNext <= CsrPlugin_exception;
    if(CsrPlugin_exception_regNext)begin
      CsrPlugin_mbadaddr <= CsrPlugin_exceptionPortCtrl_exceptionContext_badAddr;
      CsrPlugin_mcause_exceptionCode <= CsrPlugin_exceptionPortCtrl_exceptionContext_code;
    end
    if(execute_arbitration_isValid)begin
      execute_CsrPlugin_readDataRegValid <= 1'b1;
    end
    if((! execute_arbitration_isStuck))begin
      execute_CsrPlugin_readDataRegValid <= 1'b0;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_ENV_CTRL <= _zz_20_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_BYPASSABLE_EXECUTE_STAGE <= decode_BYPASSABLE_EXECUTE_STAGE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_RS2 <= decode_RS2;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC_USE_SUB_LESS <= decode_SRC_USE_SUB_LESS;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_IS_CSR <= decode_IS_CSR;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_MEMORY_ENABLE <= decode_MEMORY_ENABLE;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MEMORY_ENABLE <= execute_MEMORY_ENABLE;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MEMORY_ENABLE <= memory_MEMORY_ENABLE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_BYPASSABLE_MEMORY_STAGE <= decode_BYPASSABLE_MEMORY_STAGE;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_BYPASSABLE_MEMORY_STAGE <= execute_BYPASSABLE_MEMORY_STAGE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_RS1 <= decode_RS1;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_CSR_WRITE_OPCODE <= decode_CSR_WRITE_OPCODE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_CSR_READ_OPCODE <= decode_CSR_READ_OPCODE;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_REGFILE_WRITE_VALID <= decode_REGFILE_WRITE_VALID;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_REGFILE_WRITE_VALID <= execute_REGFILE_WRITE_VALID;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_REGFILE_WRITE_VALID <= memory_REGFILE_WRITE_VALID;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC_LESS_UNSIGNED <= decode_SRC_LESS_UNSIGNED;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC1_CTRL <= _zz_17_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_FORMAL_PC_NEXT <= _zz_79_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_FORMAL_PC_NEXT <= _zz_78_;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_FORMAL_PC_NEXT <= memory_FORMAL_PC_NEXT;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_INSTRUCTION <= decode_INSTRUCTION;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_INSTRUCTION <= execute_INSTRUCTION;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_PC <= decode_PC;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_PC <= _zz_36_;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_PC <= memory_PC;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_REGFILE_WRITE_DATA <= _zz_30_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SRC2_CTRL <= _zz_14_;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_MEMORY_ADDRESS_LOW <= execute_MEMORY_ADDRESS_LOW;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MEMORY_ADDRESS_LOW <= memory_MEMORY_ADDRESS_LOW;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_FLUSH_ALL <= decode_FLUSH_ALL;
    end
    if((! memory_arbitration_isStuck))begin
      execute_to_memory_FLUSH_ALL <= execute_FLUSH_ALL;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_BRANCH_CTRL <= _zz_11_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_ALU_CTRL <= _zz_8_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_ALU_BITWISE_CTRL <= _zz_5_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_SHIFT_CTRL <= _zz_2_;
    end
    if((! execute_arbitration_isStuck))begin
      decode_to_execute_PREDICTION_CONTEXT_hazard <= decode_PREDICTION_CONTEXT_hazard;
      decode_to_execute_PREDICTION_CONTEXT_hit <= decode_PREDICTION_CONTEXT_hit;
      decode_to_execute_PREDICTION_CONTEXT_line_source <= decode_PREDICTION_CONTEXT_line_source;
      decode_to_execute_PREDICTION_CONTEXT_line_branchWish <= decode_PREDICTION_CONTEXT_line_branchWish;
      decode_to_execute_PREDICTION_CONTEXT_line_target <= decode_PREDICTION_CONTEXT_line_target;
    end
    if((! writeBack_arbitration_isStuck))begin
      memory_to_writeBack_MEMORY_READ_DATA <= memory_MEMORY_READ_DATA;
    end
    case(execute_CsrPlugin_csrAddress)
      12'b001100000000 : begin
      end
      12'b001101000001 : begin
        if(execute_CsrPlugin_writeEnable)begin
          CsrPlugin_mepc <= execute_CsrPlugin_writeData[31 : 0];
        end
      end
      12'b001101000100 : begin
      end
      12'b001101000011 : begin
      end
      12'b001100000100 : begin
      end
      12'b001101000010 : begin
      end
      default : begin
      end
    endcase
  end

endmodule

