
parameter APP_NAME = "maxflow";
parameter RISCV = 0;

parameter ARG_WIDTH = 96;

parameter RW_WIDTH = 512;
parameter DATA_WIDTH = 64;

parameter RW_BASE_ADDR = 20;
parameter OFFSET_BASE_ADDR = 12;
parameter NEIGHBOR_BASE_ADDR = 16;
 

parameter LOG_N_SUB_TYPES = 2;


`define RO_WORKER maxflow_worker
`define RW_WORKER maxflow_rw

parameter N_CORES = 0;
