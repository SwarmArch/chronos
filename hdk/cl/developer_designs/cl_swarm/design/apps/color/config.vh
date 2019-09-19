
parameter APP_NAME = "color";
parameter RISCV = 0;

parameter ARG_WIDTH = 80;

parameter RW_WIDTH = 128;
parameter DATA_WIDTH = 32;

parameter RW_BASE_ADDR = 20;
parameter OFFSET_BASE_ADDR = 12;
parameter NEIGHBOR_BASE_ADDR = 16;
 

parameter LOG_N_SUB_TYPES = 1;


`define RO_WORKER color_worker
`define RW_WORKER color_rw

parameter N_CORES = 0;
