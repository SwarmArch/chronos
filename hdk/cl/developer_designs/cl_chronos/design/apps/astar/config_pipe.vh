`define USE_PIPELINED_TEMPLATE

parameter APP_NAME = "astar";
parameter APP_ID = 2;
parameter RISCV = 0;

parameter ARG_WIDTH = 64;

parameter RW_WIDTH = 32;
parameter DATA_WIDTH = 64;


parameter LOG_N_SUB_TYPES = 2;

parameter RW_BASE_ADDR = 20;
parameter OFFSET_BASE_ADDR = 12;
parameter NEIGHBOR_BASE_ADDR = 16;

`define RO_WORKER astar_ro
`define RW_WORKER astar_rw

parameter N_CORES = 0;


