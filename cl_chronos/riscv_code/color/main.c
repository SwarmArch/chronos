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

#include "../include/chronos.h"

const int ADDR_BASE_DATA         = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET  = 3 << 2;
const int ADDR_BASE_NEIGHBORS    = 4 << 2;
const int ADDR_BASE_INITLIST     = 9 << 2;
const int ADDR_BASE_SCRATCH      = 7 << 2;
const int ADDR_NUMV              = 1 << 2;

#define ENQUEUER_TASK  0
#define CALC_COLOR_TASK  1
#define NOTIFY_NEIGHBORS_TASK 2
#define RECEIVE_COLOR_TASK 3

typedef unsigned int uint;

uint* colors;
uint* edge_offset;
uint* edge_neighbors;

uint* scratch;
uint* initlist;
uint numV;

void enqueuer_task(uint ts, uint object, uint enq_start, uint arg1) {
   int n_child = 0;
   uint next_ts;
   while(enq_start + n_child < numV) {
     if (n_child == 7) {
         enq_task_arg2(ENQUEUER_TASK, 0, object, enq_start + 7, 0);
         break;
     }
     uint nextV = enq_start + n_child;
     uint degree = edge_offset[nextV+1] - edge_offset[nextV];
     if (degree>255) degree = 255;
     next_ts = (255-degree) << 24 | nextV << 1;
     enq_task_arg0(CALC_COLOR_TASK, next_ts, nextV);
     n_child++;
   }
}

void calc_color_task(uint ts, uint vid, uint arg0, uint arg1) {
   // find first unset bit;
   vid = vid & 0xffffff;
   uint bit = 0;
   uint vec = scratch[vid*2];
   while (vec & 1) {
      vec >>= 1;
      bit++;
   }
   // color = bit
   enq_task_arg2(NOTIFY_NEIGHBORS_TASK, ts, (1<<24) | vid, bit, 0);

}

void notify_neighbors_task(uint ts, uint vid, uint color, uint enq_start) {
   vid = vid & 0xffffff;
   if (enq_start ==0) {
      undo_log_write(&(colors[vid*4]), colors[vid*4]);
      colors[vid*4] = color;
   }
   uint eo_begin = edge_offset[vid] + enq_start;
   uint eo_end = edge_offset[vid+1];
   uint degree = eo_end - eo_begin;
   if (eo_end > eo_begin + 6) {
       enq_task_arg1(NOTIFY_NEIGHBORS_TASK, ts, (1<<24) | vid, enq_start +6);
       eo_end = eo_begin + 6;
   }

   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i];
      uint n_deg = edge_offset[neighbor+1] - edge_offset[neighbor];
      if ( (n_deg < degree) || ((n_deg == degree) & neighbor > vid)) {
          enq_task_arg2(RECEIVE_COLOR_TASK, ts, neighbor, color, vid);
      }
   }
}

void receive_color_task(uint ts, uint vid, uint color, uint neighbor) {
   if (color < 32) {
      uint vec = scratch[vid*2];
      undo_log_write(&(scratch[vid*2]), vec);
      vec = vec | ( 1<<color);
      scratch[vid*2] = vec;
      //enq_task_arg0(7, ts, neighbor*100 + color);
   } // else todo
}


void main() {
   chronos_init();

   colors = (uint*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
   edge_offset  =(uint*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   edge_neighbors  =(uint*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;
   scratch  =(uint*) ((*(int *)(ADDR_BASE_SCRATCH))<<2);
   initlist  =(uint*) ((*(int *)(ADDR_BASE_INITLIST))<<2) ;
   numV  =*(uint *)(ADDR_NUMV) ;

   while (1) {
      uint ttype, ts, object, arg0, arg1;
      deq_task(&ttype, &ts, &object, &arg0, &arg1);
      switch(ttype) {
        case ENQUEUER_TASK:
           enqueuer_task(ts, object, arg0, arg1);
           break;
        case CALC_COLOR_TASK:
           calc_color_task(ts, object, arg0, arg1);
           break;
        case NOTIFY_NEIGHBORS_TASK:
           notify_neighbors_task(ts, object, arg0, arg1);
           break;
        case RECEIVE_COLOR_TASK:
           receive_color_task(ts, object, arg0, arg1);
           break;
      }
      finish_task();
   }
}

