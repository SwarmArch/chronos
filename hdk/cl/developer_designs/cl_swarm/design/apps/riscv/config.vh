
parameter APP_NAME = "sssp";
parameter RISCV = 1;

parameter ARG_WIDTH = 64;

parameter N_CORES = 8;

// NOT NEEDED FOR RISCV, BUT REQUIRED TO AVOID BUILD FAILURES
parameter LOG_N_SUB_TYPES = 0;
parameter RW_WIDTH = 32;
parameter DATA_WIDTH = 32;
parameter RW_BASE_ADDR = 0;
parameter OFFSET_BASE_ADDR = 12;
parameter NEIGHBOR_BASE_ADDR = 16;
`define RO_WORKER sssp_worker
`define RW_WORKER sssp_rw
