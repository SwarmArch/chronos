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

#ifndef HEADER
#define HEADER

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <fpga_dma.h>
#include <utils/lcd.h>

#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
#include <poll.h>
#include <assert.h>

#define LOG_SPLITTERS_PER_CHUNK           4
#define ADDR_BASE_SPILL                   (1<<30)
#define LOG_SPLITTER_STACK_SIZE           14
#define LOG_SPLITTER_STACK_ENTRY_WIDTH    4
#define LOG_SPLITTER_CHUNK_WIDTH           (7 - 3 + 3)
#define LOG_SPLITTER_ENTRIES     (LOG_SPLITTER_STACK_SIZE + LOG_SPLITTERS_PER_CHUNK)

#define LOG_PER_TILE_SPILL_SCRATCHPAD_SIZE_BYTES (LOG_SPLITTER_ENTRIES - 3)
#define LOG_PER_TILE_SPILL_STACK_SIZE_BYTES (LOG_SPLITTER_STACK_SIZE + LOG_SPLITTER_STACK_ENTRY_WIDTH -3)
#define LOG_PER_TILE_SPILL_TASK_SIZE_BYTES (LOG_SPLITTER_ENTRIES + LOG_SPLITTER_CHUNK_WIDTH)

#define STACK_PTR_ADDR_OFFSET 0
#define STACK_BASE_OFFSET (64)
#define SCRATCHPAD_BASE_OFFSET (STACK_BASE_OFFSET + (1<<LOG_PER_TILE_SPILL_STACK_SIZE_BYTES))
#define SCRATCHPAD_END_OFFSET (SCRATCHPAD_BASE_OFFSET + (1<<LOG_PER_TILE_SPILL_SCRATCHPAD_SIZE_BYTES))
#define SPILL_TASK_BASE_OFFSET (1<<LOG_PER_TILE_SPILL_TASK_SIZE_BYTES)

#define TOTAL_SPILL_ALLOCATION (SPILL_TASK_BASE_OFFSET*2)


#define ID_ALL_CORES              32
#define ID_ALL_APP_CORES         33
#define ID_COAL_AND_SPLITTER      34

#define ID_GLOBAL                 48

#define OCL_TASK_ENQ_ARGS         0x1c // set the args of the task to be enqueued next
#define OCL_TASK_ENQ_OBJECT         0x14 // set the object of the task to be enqueued next
#define OCL_TASK_ENQ_TTYPE        0x18 // set the ttype of the task to be enqueued next
#define OCL_TASK_ENQ              0x10 // Enq task with ts (wdata)
#define OCL_ACCESS_MEM_SET_MSB    0x24 // set bits [63:32] of mem addr
#define OCL_ACCESS_MEM_SET_LSB    0x28 // set bits [31: 0] of mem addr
#define OCL_ACCESS_MEM            0x20
#define OCL_TASK_ENQ_ARG_WORD     0x2c
#define OCL_CUR_CYCLE_MSB         0x30
#define OCL_CUR_CYCLE_LSB         0x34
#define OCL_LAST_MEM_LATENCY      0x38
#define OCL_L2_DEBUG              0x3c
#define OCL_DONE                  0x40

#define OCL_PARAM_N_TILES             0x50
#define OCL_PARAM_LOG_TQ_HEAP_STAGES  0x54
#define OCL_PARAM_LOG_TQ_SIZE         0x58
#define OCL_PARAM_LOG_CQ_SIZE         0x5c
#define OCL_PARAM_APP_ID              0x60
#define OCL_PARAM_LOG_SPILL_Q_SIZE    0x64
#define OCL_PARAM_NO_ROLLBACK         0x68
#define OCL_PARAM_LOG_READY_LIST_SIZE 0x6c
#define OCL_PARAM_LOG_L2_BANKS        0x70
#define OCL_PARAM_N_CORES             0x74

#define CORE_START                0xa0 //  wdata - bitmap of which cores are activated
#define CORE_N_DEQUEUES           0xb0
#define CORE_NUM_ENQ              0xc0
#define CORE_NUM_DEQ              0xc4
#define CORE_STATE                0xc8
#define CORE_PC                   0xcc

#define CORE_QUERY_STATE          0x10
#define CORE_STATE_STATS          0x14
#define CORE_AP_STATE_STATS       0x18
#define CORE_HEADER_TOP           0xa4

#define SSSP_BASE_EDGE_OFFSET     0x20
#define SSSP_BASE_DIST            0x24
#define SSSP_BASE_NEIGHBORS       0x28
#define SSSP_OBJECT                 0x30
#define SSSP_TS                   0x34
#define SSSP_STATE_STATS_BEGIN    0x40
#define CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD 0x40

#define CORE_DEBUG_WORD           0x48

#define COAL_STACK_PTR           0x80

#define SPILL_BASE_TASKS         0x60
#define SPILL_BASE_STACK         0x64
#define SPILL_BASE_SCRATCHPAD    0x68
#define SPILL_ADDR_STACK_PTR     0x6c

#define TASK_UNIT_SET_STAT_ID      0x0c
#define TASK_UNIT_CAPACITY         0x10
#define TASK_UNIT_N_TASKS          0x14
#define TASK_UNIT_N_TIED_TASKS     0x18
#define TASK_UNIT_STALL            0x20
#define TASK_UNIT_START            0x24
#define TASK_UNIT_PRE_ENQ_BUF      0x28
#define TASK_UNIT_SPILL_THRESHOLD  0x30
#define TASK_UNIT_CLEAN_THRESHOLD  0x34
#define TASK_UNIT_SPILL_SIZE       0x38
#define TASK_UNIT_THROTTLE_MARGIN  0x3c
#define TASK_UNIT_TIED_CAPACITY    0x40
#define TASK_UNIT_LVT              0x44

#define TASK_UNIT_STAT_AVG_TASKS   0x48
#define TASK_UNIT_STAT_AVG_HEAP_UTIL   0x4c

// if start_mask == 0, increment tx id by start_inc
#define TASK_UNIT_IS_TRANSACTIONAL          0x50
#define TASK_UNIT_GLOBAL_RELABEL_START_MASK 0x54
#define TASK_UNIT_GLOBAL_RELABEL_START_INC  0x58
#define TX_ID_OFFSET_BITS  8

#define TASK_UNIT_STAT_N_UNTIED_ENQ           0x60
#define TASK_UNIT_STAT_N_TIED_ENQ_ACK         0x64
#define TASK_UNIT_STAT_N_TIED_ENQ_NACK        0x68
#define TASK_UNIT_STAT_N_DEQ_TASK             0x70
#define TASK_UNIT_STAT_N_SPLITTER_DEQ         0x74
#define TASK_UNIT_STAT_N_DEQ_MISMATCH         0x78
#define TASK_UNIT_STAT_N_CUT_TIES_MATCH       0x80
#define TASK_UNIT_STAT_N_CUT_TIES_MISMATCH    0x84
#define TASK_UNIT_STAT_N_CUT_TIES_COM_ABO     0x88
#define TASK_UNIT_STAT_N_COMMIT_TIED          0x90
#define TASK_UNIT_STAT_N_COMMIT_UNTIED        0x94
#define TASK_UNIT_STAT_N_COMMIT_MISMATCH      0x98
#define TASK_UNIT_STAT_N_ABORT_CHILD_DEQ      0xa0
#define TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ  0xa4
#define TASK_UNIT_STAT_N_ABORT_CHILD_MISMATCH 0xa8
#define TASK_UNIT_STAT_N_ABORT_TASK           0xb0
#define TASK_UNIT_STAT_N_HEAP_ENQ             0xb4
#define TASK_UNIT_STAT_N_HEAP_DEQ             0xb8
#define TASK_UNIT_STAT_N_HEAP_REPLACE         0xbc
#define TASK_UNIT_STAT_N_COAL_CHILD           0xc0
#define TASK_UNIT_STAT_N_OVERFLOW             0xc4
#define TASK_UNIT_STAT_N_CYCLES_DEQ_VALID     0xc8

#define TASK_UNIT_HEAP_OP_STAT_READ           0xcc

#define TASK_UNIT_STATE_STATS                 0xd0
#define TASK_UNIT_MISC_DEBUG                  0xf4
#define TASK_UNIT_ALT_DEBUG                   0xf8

#define TASK_UNIT_PRODUCER_THRESHOLD          0x34
#define TASK_UNIT_SPILL_CHECK_LIMIT          0x5c

#define TSB_LOG_N_TILES            0x10
#define TSB_HASH_KEY               0x14
#define TSB_ENTRY_VALID            0x20

#define CQ_SIZE                0x10
#define CQ_STATE               0x14
#define CQ_USE_TS_CACHE        0x1c
#define CQ_LOOKUP_ENTRY        0x18
#define CQ_LOOKUP_STATE        0x20
#define CQ_LOOKUP_OBJECT         0x24
#define CQ_LOOKUP_MODE         0x2c
#define CQ_GVT_TS              0x30
#define CQ_GVT_TB              0x34
#define CQ_MAX_VT_POS          0x38
#define CQ_DEQ_TASK_TS         0x3c

#define CQ_STATE_STATS            0x40
#define CQ_STAT_N_RESOURCE_ABORTS 0x60
#define CQ_STAT_N_GVT_ABORTS      0x64
#define CQ_IGNORE_GVT_TB          0x68
#define CQ_STAT_N_IDLE_CQ_FULL    0x70
#define CQ_STAT_N_IDLE_CC_FULL    0x74
#define CQ_STAT_N_IDLE_NO_TASK    0x78
#define CQ_STAT_CYCLES_IN_RESOURCE_ABORT    0x80
#define CQ_STAT_CYCLES_IN_GVT_ABORT         0x84
#define CQ_CUM_OCC_LSB         0x88
#define CQ_CUM_OCC_MSB         0x8c

#define CQ_LOOKUP_TS              0x90
#define CQ_LOOKUP_TB              0x94
#define CQ_N_GVT_GOING_BACK       0x98

#define CQ_DEQ_TASK_STATS               0xb0
#define CQ_COMMIT_TASK_STATS            0xb4

#define CQ_N_TASK_NO_CONFLICT           0xc0
#define CQ_N_TASK_CONFLICT_MITIGATED    0xc4
#define CQ_N_TASK_CONFLICT_MISS         0xc8
#define CQ_N_TASK_REAL_CONFLICT         0xcc

#define CQ_N_CUM_COMMIT_CYCLES_H  0xd0
#define CQ_N_CUM_COMMIT_CYCLES_L  0xd4
#define CQ_N_CUM_ABORT_CYCLES_H  0xd8
#define CQ_N_CUM_ABORT_CYCLES_L  0xdc

#define SERIALIZER_N_THREADS 0x10
#define SERIALIZER_ARVALID 0x20
#define SERIALIZER_READY_LIST 0x24
#define SERIALIZER_REG_VALID 0x28
#define SERIALIZER_CAN_TAKE_REQ_0 0x30
#define SERIALIZER_CAN_TAKE_REQ_1 0x34
#define SERIALIZER_CAN_TAKE_REQ_2 0x38
#define SERIALIZER_CAN_TAKE_REQ_3 0x3c
#define SERIALIZER_SIZE_CONTROL 0x40
#define SERIALIZER_CQ_STALL_COUNT 0x44
#define SERIALIZER_STAT 0x80
#define SERIALIZER_DEBUG_WORD 0x50
#define SERIALIZER_S_OBJECT 0x54
#define SERIALIZER_N_MAX_RUNNING_TASKS 0x60

#define L2_FLUSH          0x10
#define L2_READ_HITS      0x20
#define L2_READ_MISSES    0x24
#define L2_WRITE_HITS     0x28
#define L2_WRITE_MISSES   0x2c
#define L2_EVICTIONS      0x30

#define L2_RETRY_STALL     0x34
#define L2_RETRY_NOT_EMPTY 0x38
#define L2_RETRY_COUNT     0x3c
#define L2_STALL_IN        0x40
#define L2_DEBUG_WORD      0x50

#define L2_LOG_BVALID        0x14
#define L2_CIRCULATE_ON_STALL 0x18

#define DEBUG_CAPACITY    0xf0 // For any component that does logging

#define MEM_XBAR_NUM_CTRL 0x10
#define MEM_XBAR_RATE_CTRL 0x14

#define RISCV_ID 256

int log_sssp_core(pci_bar_handle_t pci_bar_handle, int fd, int cid, FILE* fw);
int log_task_unit(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_cq(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_cache(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_splitter(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_coalescer(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_riscv(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_ddr(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_serializer(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_ro_stage(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_rw_stage(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
int log_undo_log(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char*, uint32_t);
void write_task_unit_log(unsigned char* log_buffer, FILE* fw, uint32_t log_size, uint32_t tile_id);

void init_params();
void pci_poke(uint32_t tile, uint32_t comp, uint32_t addr, uint32_t data);
void pci_peek(uint32_t tile, uint32_t comp, uint32_t addr, uint32_t* data);
void task_unit_stats(uint32_t tile, uint32_t);
void serializer_stats(uint32_t tile, uint32_t);
void cq_stats (uint32_t tile, uint32_t);
void core_stats (uint32_t tile, uint32_t);
extern pci_bar_handle_t pci_bar_handle;
void dma_write(unsigned char* write_buffer, uint32_t write_len, size_t write_addr);

void loop_debuggin_spec(uint32_t iters);
void loop_debuggin_nonspec(uint32_t iters);

extern uint32_t N_TILES;
extern uint32_t ID_OCL_SLAVE;
extern uint32_t N_SSSP_CORES;
extern uint32_t N_CORES;

extern uint32_t ID_SPLITTER;
extern uint32_t ID_COALESCER;
extern uint32_t ID_UNDO_LOG;
extern uint32_t ID_TASK_UNIT;
extern uint32_t ID_L2;
extern uint32_t ID_MEM_ARB;
extern uint32_t ID_PCI_ARB;
extern uint32_t ID_TSB;
extern uint32_t ID_CQ;
extern uint32_t ID_LAST;
extern uint32_t LOG_TQ_SIZE, LOG_CQ_SIZE;
extern uint32_t TQ_STAGES, SPILLQ_STAGES;
extern uint32_t NO_ROLLBACK;

/*
 * pci_vendor_id and pci_device_id values below are Amazon's and avaliable to use for a given FPGA slot.
 * Users may replace these with their own if allocated to them by PCI SIG
 */
extern uint16_t pci_vendor_id; /* Amazon PCI Vendor ID */
extern uint16_t pci_device_id; /* PCI Device ID preassigned by Amazon for F1 applications */
#define APP_DMA_TEST 0
#define APP_SSSP 1
#define APP_DES 2
#define APP_ASTAR 3
#define APP_COLOR 4
#define APP_MAXFLOW 5
#define APP_SILO 6
#define APP_LAST 7

typedef struct {
   uint excess;
   uint counter_min_height;
   uint height;
   uint visited;
   // flows of outgoing neighbors. This is in node_prop because
   // it is modified by tasks that access src node
   int flow[12];
} maxflow_node_prop_t;

typedef struct {
   uint dest;
   uint capacity;
} maxflow_edge_prop_t;

typedef struct {
   short color;
   short degree;
   short scratch;
   short ncp;
   short ndp;
   uint eo_begin;
} color_node_prop_t;
#endif
