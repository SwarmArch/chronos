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

// Matches the task structure of the pipelined color

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
   uint32_t scratch;
   short ncp;
   short ndp;
   uint32_t eo_begin;
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

#define ENQ_TASK  0
#define SEND_DEGREE_TASK 1
#define RECEIVE_DEGREE_TASK  2
#define RECEIVE_COLOR_TASK 3

typedef unsigned int uint;

color_node_prop_t* data;
uint* edge_offset;
uint* edge_neighbors;

uint* scratch;
uint numV;
uint enq_limit;

void enqueuer_task(uint ts, uint object, uint enq_start, uint arg1) {
   int n_child = 0;
   uint next_ts;
   uint enq_end = enq_start + enq_limit;
   if (enq_end > numV) enq_end = numV;
   if (enq_end < numV) {
     enq_task_arg1(ENQUEUER_TASK, /*unordered*/ 0, enq_end, enq_end);
   }
   for (int i=enq_start; i<enq_end; i++) {
     enq_task_arg0(SEND_DEGREE_TASK, /*unordered*/ 0, i);
   }
}

void send_degree_task(uint ts, uint vid, uint arg0, uint arg1) {
    printf("\t ndp:%2d ncp:%2d\n", data[vid].ndp, data[vid].ncp);
    uint32_t enq_start = arg0;
    if (data[vid].degree == 0) {
        data[vid].color = 0;
    } else {
        uint32_t eo_begin = data[vid].eo_begin + enq_start;
        uint32_t eo_end = data[vid].eo_begin + data[vid].degree;
        printf("\t%d %d %d\n", eo_begin, enq_limit, eo_end);
        if ((eo_begin + enq_limit) < eo_end) {
            eo_end = eo_begin + enq_limit;
            enq_task_arg1(SEND_DEGREE_TASK, 0, vid, enq_start + enq_limit);
        }
        for (int i=eo_begin; i<eo_end; i++) {
            uint32_t neighbor = edge_neighbors[i];
            enq_task_arg2(RECEIVE_DEGREE_TASK, 0, neighbor, (data[vid].degree << 16), vid);
        }
    }
}

void receive_degree_task(uint ts, uint vid, uint arg0, uint neighbor) {
    printf("\t ndp:%2d ncp:%2d\n", data[vid].ndp, data[vid].ncp);
    data[vid].ndp -= 1;
    uint32_t neighbor_deg = arg0 >> 16;
    uint32_t deg = data[vid].degree;
    if ( (neighbor_deg > deg) || ( (neighbor_deg == deg) & (neighbor < vid))) {
        data[vid].ncp += 1;
    }
    uint32_t enq_start = arg0 & 0xffff;

    if ( (data[vid].ndp == 0) && (data[vid].ncp == 0)) {


        uint color = 0;
        uint vec = data[vid].scratch;
        while (vec & 1) {
          vec >>= 1;
          color++;
        }
        data[vid].color = color;

        uint32_t eo_begin = data[vid].eo_begin + enq_start;
        uint32_t eo_end = data[vid].eo_begin + data[vid].degree;
        if ((eo_begin + enq_limit) < eo_end) {
            eo_end = eo_begin + enq_limit;
            enq_task_arg1(RECEIVE_COLOR_TASK, 0, vid,
                    (data[vid].degree << 16) | (enq_start + enq_limit));
        }
        for (int i=eo_begin; i<eo_end; i++) {
            uint32_t neighbor = edge_neighbors[i];
            enq_task_arg3(RECEIVE_COLOR_TASK, 0, neighbor, data[vid].degree << 16, vid, color);
        }
    }
}

void receive_color_task(uint ts, uint vid, uint degree_start, uint neighbor, uint color) {

    printf("\t ndp:%2d ncp:%2d\n", data[vid].ndp, data[vid].ncp);
    uint32_t enq_start = degree_start & 0xffff;
    if (enq_start == 0) {
        uint32_t neighbor_deg = degree_start >> 16;
        uint32_t deg = data[vid].degree;
        if ( (neighbor_deg > deg) || ( (neighbor_deg == deg) & (neighbor < vid))) {
            data[vid].ncp -= 1;
            data[vid].scratch |= (1 << color);
            data[vid].color = color;
            if ( (data[vid].ndp == 0) && (data[vid].ncp == 0)) {

            } else {
                return;
            }
        } else {
            return;
        }
    }

    color = 0;
    uint vec = data[vid].scratch;
    while (vec & 1) {
      vec >>= 1;
      color++;
    }
    data[vid].color = color;

    uint32_t eo_begin = data[vid].eo_begin + enq_start;
    uint32_t eo_end = data[vid].eo_begin + data[vid].degree;
    if ((eo_begin + enq_limit) < eo_end) {
        eo_end = eo_begin + enq_limit;
        enq_task_arg1(RECEIVE_COLOR_TASK, 0, vid, enq_start + enq_limit);
    }
    for (int i=eo_begin; i<eo_end; i++) {
        uint32_t neighbor = edge_neighbors[i];
        enq_task_arg3(RECEIVE_COLOR_TASK, 0, neighbor, data[vid].degree << 16, vid, color);
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
   enq_limit  = chronos_mem[9];

   printf("numV %d\n", numV);

   while (1) {
      uint ttype, ts, object, arg0, arg1, arg2;
      deq_task_arg3(&ttype, &ts, &object, &arg0, &arg1, &arg2);
#ifndef RISCV
      if (ttype == -1) break;
#endif
      switch(ttype) {
        case ENQUEUER_TASK:
           enqueuer_task(ts, object, arg0, arg1);
           break;
        case SEND_DEGREE_TASK:
           send_degree_task(ts, object, arg0, arg1);
           break;
        case RECEIVE_DEGREE_TASK:
           receive_degree_task(ts, object, arg0, arg1);
           break;
        case RECEIVE_COLOR_TASK:
           receive_color_task(ts, object, arg0, arg1, arg2);
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

