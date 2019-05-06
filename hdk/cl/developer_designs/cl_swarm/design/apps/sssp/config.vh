
parameter APP_NAME = "sssp";
parameter RISCV = 0;

typedef logic [0:0] arg_t;
parameter ARG_WIDTH = 1;

parameter RW_ARSIZE = 2;
typedef logic [31:0] object_t; 

parameter RO_STAGES = 2;

parameter RW_BASE_ADDR = 20;
parameter OFFSET_BASE_ADDR = 12;
parameter NEIGHBOR_BASE_ADDR = 16;
 
parameter RO1_DATA_WIDTH = 64;
parameter RO2_DATA_WIDTH = 64;

typedef task_t ro1_in_t;

typedef struct packed {
   task_t            task_desc;
   logic [31:0]      eo_end;
   logic [31:0]      eo_begin;
} ro2_in_t;

typedef task_t ro2_out_t;
