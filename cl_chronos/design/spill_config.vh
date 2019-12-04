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


   // Task Spilling parameters
   parameter LOG_TQ_SPILL_SIZE = 8;
   // Spilled tasks are organized into two hierachical levels. 8 Tasks go into
   // 1 splitter and 16 splitters go into one chunk. (Configurable below)
   // TODO: (find a better term than splitter; this is used for both the task type and
   // the 8 task set)

   // These four parameters are fixed at design time. Base addresses are
   // software configurable
   // Splitters are allocated in terms of chunks. A LIFO stack of free chunks is
   // maintained in memory by coalescer and splitter cores collaboratively. The
   // coalescer would pop one entry and store the 16 subsequent splitters 
   // into the space allocated for this chunk. When the splitter (core) finishes the 
   // last splitter (task) of a chunk, it is added to back on the stack.
   // The splitter core will not receive all splitter tasks of the same chunks
   // contiguously, hence it maintains a scratchpad of bit vectors to maintain
   // which tasks of which chunks are free.  
   parameter TASKS_PER_SPLITTER = 8;  
   parameter SPLITTERS_PER_CHUNK = 16;
`ifdef XILINX_SIMULATOR
   parameter LOG_SPLITTER_STACK_SIZE = 9; // max(16) - limited by stack entry width
`else
   parameter LOG_SPLITTER_STACK_SIZE = 12; // max(16) - limited by stack entry width
`endif
   parameter LOG_SPLITTER_STACK_ENTRY_WIDTH = 4; // 16-bit index
  
   // Derived:
   parameter LOG_SPLITTERS_PER_CHUNK = $clog2(SPLITTERS_PER_CHUNK); // 16-bit splitters
   parameter LOG_SPLITTER_CHUNK_WIDTH = $clog2(TQ_WIDTH) -3 + $clog2(TASKS_PER_SPLITTER);
   parameter LOG_SPLITTER_ENTRIES = (LOG_SPLITTER_STACK_SIZE + LOG_SPLITTERS_PER_CHUNK);

   // Memory requirement for each structure
   parameter LOG_PER_TILE_SPILL_SCRATCHPAD_SIZE_BYTES = (LOG_SPLITTER_ENTRIES - 3); // 8K
   parameter LOG_PER_TILE_SPILL_STACK_SIZE_BYTES = 
      LOG_SPLITTER_STACK_SIZE + LOG_SPLITTER_STACK_ENTRY_WIDTH - 3;  // 8K
   parameter LOG_PER_TILE_SPILL_TASK_SIZE_BYTES = 
      LOG_SPLITTER_ENTRIES + LOG_SPLITTER_CHUNK_WIDTH; // 8M
   // Tasks + Stack + Scratchpad + stack_ptr (8M + 8K + 8K + 64B) 

   parameter STACK_PTR_ADDR_OFFSET = 0;
   parameter STACK_BASE_OFFSET = 64;
   parameter SCRATCHPAD_BASE_OFFSET = STACK_BASE_OFFSET + (1<<(LOG_PER_TILE_SPILL_STACK_SIZE_BYTES));
   parameter SCRATCHPAD_END_OFFSET = SCRATCHPAD_BASE_OFFSET + 
         (1<<(LOG_PER_TILE_SPILL_SCRATCHPAD_SIZE_BYTES));
   parameter SPILL_TASK_BASE_OFFSET = 1<<(LOG_PER_TILE_SPILL_TASK_SIZE_BYTES); 
   
   parameter TOTAL_SPILL_ALLOCATION = SPILL_TASK_BASE_OFFSET * 2;

   
   
   // Default values for configurable parameters
   parameter SPILL_THRESHOLD = (2**LOG_TQ_SIZE) - 5; // Start coalescing when TQ size is this
