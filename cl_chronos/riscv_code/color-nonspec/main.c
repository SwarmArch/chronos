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


// This version initializes the in-degree of a node in a single task.
// This is hard to implement with the current pipeline, because it requires
// keeping track of a register across memory iterations.

#ifndef RISCV
#include "../include/simulator.h"
#else
#include "../include/chronos.h"
#endif

#ifdef RISCV
void printf(...) {
}
#endif

typedef struct {
   short color;
   short degree;
   short scratch;
   short ncp;
   short ndp;
   uint eo_begin;
} color_node_prop_t;

uint32_t* chronos_mem = 0;
void* chronos_ptr(int offset) {
   uint32_t addr = chronos_mem[offset];
   printf("chronos_ptr %x\n", addr);
   return (void*) &chronos_mem[addr];
}

const int ADDR_BASE_DATA         = 5;
const int ADDR_BASE_EDGE_OFFSET  = 3;
const int ADDR_BASE_NEIGHBORS    = 4;
const int ADDR_BASE_SCRATCH      = 7;
const int ADDR_NUMV              = 1;

#define ENQUEUER_TASK  0
#define CALC_IN_DEGREE_TASK 1
#define CALC_COLOR_TASK  2
#define RECEIVE_COLOR_TASK 3

typedef unsigned int uint;

color_node_prop_t* data;
uint* edge_offset;
uint* edge_neighbors;

uint* scratch;
uint numV;

void enqueuer_task(uint ts, uint object, uint enq_start, uint arg1) {
   int n_child = 0;
   uint next_ts;
   uint enq_end = enq_start + 17;
   if (enq_end > numV) enq_end = numV;
   if (enq_end < numV) {
     enq_task_arg1(ENQUEUER_TASK, /*unordered*/ 0, enq_start << 16, enq_end);
   }
   for (int i=enq_start; i<enq_end; i++) {
     enq_task_arg0(CALC_IN_DEGREE_TASK, /*unordered*/ 0, i);
   }
}

void calc_in_degree_task(uint ts, uint vid, uint arg0, uint arg1) {

   // Identify safe nodes. A node can be colored if it does not have any
   // neighbors with a priority greater than itself
   uint eo_begin = edge_offset[vid];
   uint eo_end = edge_offset[vid+1];
   uint deg = eo_end - eo_begin;
   uint in_degree =0;
   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i];
      uint neighbor_deg = edge_offset[neighbor+1] - edge_offset[neighbor];
      if ( (neighbor_deg > deg) || ((neighbor_deg == deg) & neighbor < vid)) {
         in_degree++;
      }
   }
   // A receive_color task tagetted to this could have been executed
   // before join_counter was set.
   uint cur_counter = scratch[vid*2+1];
   cur_counter += in_degree;
   scratch[vid*2+1] = cur_counter;
   if (cur_counter ==0) {
      enq_task_arg1(CALC_COLOR_TASK, 0, vid, 0);
   }
}
void calc_color_task(uint ts, uint vid, uint enq_start, uint arg1) {
   // find first unset bit;
   uint bit = 0;
   if (enq_start == 0) {
       uint vec = scratch[vid*2];
       while (vec & 1) {
          vec >>= 1;
          bit++;
       }
       data[vid].color = bit;
   } else {
       bit = data[vid].color;
   }
   uint eo_begin = edge_offset[vid];
   uint eo_end = edge_offset[vid+1];
   uint deg = eo_end - eo_begin;

   uint enq_end = enq_start + 17;
   if (enq_end > deg) enq_end = deg;
   if (enq_end < deg) {
     enq_task_arg1(CALC_COLOR_TASK, 0, vid, enq_end);
   }

   for (int i = eo_begin + enq_start; i < eo_begin + enq_end; i++) {
      uint neighbor = edge_neighbors[i];
      uint neighbor_deg = edge_offset[neighbor+1] - edge_offset[neighbor];
      if ( (neighbor_deg < deg) || ((neighbor_deg == deg) & neighbor > vid)) {
         enq_task_arg2(RECEIVE_COLOR_TASK, 0, neighbor, bit, vid);
      }
   }

}


void receive_color_task(uint ts, uint vid, uint color, uint neighbor) {

   uint vec;
   if (color < 32) {
      vec = scratch[vid*2];
      vec = vec | ( 1<<color);
      scratch[vid*2] = vec;
   } // else todo
   uint counter = scratch[vid*2+1];
   counter--;
   scratch[vid*2+1] = counter;
   if (counter ==0) {
      enq_task_arg1(CALC_COLOR_TASK, 1, vid, 0);
   }
}


int main(int argc, char** argv) {
   chronos_init();

#ifndef RISCV
   // Simulator code

   if (argc <2) {
       printf("usage: color_sim in_file\n");
       exit(0);
   }

   //const char* fname = "../../tools/silo_gen/silo_tx";
   char* fname = argv[1];
   FILE* fp = fopen(fname, "rb");
   // obtain file size:
   fseek (fp , 0 , SEEK_END);
   long lSize = ftell (fp);
   printf("File %p size %ld\n", fp, lSize);
   rewind (fp);
   chronos_mem = (uint32_t*) malloc(lSize);
   fread( (void*) chronos_mem, 1, lSize, fp);
   enq_task_arg1(ENQUEUER_TASK, 0, 0x20000, 0);
#else
#endif
   data = (color_node_prop_t*) chronos_ptr(ADDR_BASE_DATA);
   edge_offset = (uint32_t*) chronos_ptr(ADDR_BASE_EDGE_OFFSET);
   edge_neighbors = (uint32_t*) chronos_ptr(ADDR_BASE_NEIGHBORS);
   scratch  =(uint32_t*) chronos_ptr(ADDR_BASE_SCRATCH);
   numV  = chronos_mem[ADDR_NUMV];

   printf("numV %d\n", numV);

   while (1) {
      uint ttype, ts, object, arg0, arg1;
      deq_task_arg2(&ttype, &ts, &object, &arg0, &arg1);
#ifndef RISCV
      if (ttype == -1) break;
#endif
      switch(ttype) {
        case ENQUEUER_TASK:
           enqueuer_task(ts, object, arg0, arg1);
           break;
        case CALC_IN_DEGREE_TASK:
           calc_in_degree_task(ts, object, arg0, arg1);
           break;
        case CALC_COLOR_TASK:
           calc_color_task(ts, object, arg0, arg1);
           break;
        case RECEIVE_COLOR_TASK:
           receive_color_task(ts, object, arg0, arg1);
           break;
        default:
           break;
      }
      finish_task();
   }
#ifndef RISCV
    printf("Verifying..\n");
    color_node_prop_t* c_nodes =
               (color_node_prop_t *) chronos_ptr(ADDR_BASE_DATA);
    uint32_t* csr_ref_color = (uint32_t*) chronos_ptr(6);
    uint32_t num_errors = 0;
           FILE* fc = fopen("color_verif", "w");
           for (int i=0;i<numV;i++) {
               uint32_t eo_begin =c_nodes[i].eo_begin;
               uint32_t eo_end =eo_begin + c_nodes[i].degree;
               uint32_t i_deg = eo_end - eo_begin;
               uint32_t i_color = c_nodes[i].color;

                // read_join_counter and scratch;
               uint32_t bitmap = c_nodes[i].scratch;
               uint32_t join_counter = c_nodes[i].ndp;

               fprintf(fc,"i=%d d=%d c=%d bitmap=%8x counter=(%d %d) ref:%d\n",
                       i, i_deg, i_color,
                       bitmap,
                        join_counter, c_nodes[i].ncp,
                        csr_ref_color[i]);
               bool error = (i_color != csr_ref_color[i]);
               uint32_t join_cnt = 0;
               for (int j=eo_begin;j<eo_end;j++) {
                    uint32_t n = edge_neighbors[j];
                    uint32_t n_deg = c_nodes[n].degree;
                    uint32_t n_color = c_nodes[n].color;
                    fprintf(fc,"\tn=%d d=%d c=%d r=%d\n",n, n_deg, n_color, csr_ref_color[n]);
                    if (i_color == n_color) {
                        fprintf(fc,"\t ERROR:Neighbor has same color\n");
                    }
                    if (n_deg > i_deg || ((n_deg == i_deg) & (n<i))) join_cnt++;
               }
               fprintf(fc,"\tjoin_cnt=%d\n", join_cnt);
               if (error) num_errors++;
               if ( error & (num_errors < 10) )
                   printf("Error at vid:%3d color:%5d\n",
                           i, c_nodes[i].color);

           }
           printf("Total Errors %d / %d\n", num_errors, numV);

#endif

}

