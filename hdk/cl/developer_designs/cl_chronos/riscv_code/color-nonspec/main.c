#include "../include/chronos.h"

const int ADDR_BASE_DATA         = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET  = 3 << 2;
const int ADDR_BASE_NEIGHBORS    = 4 << 2;
const int ADDR_BASE_SCRATCH      = 7 << 2;
const int ADDR_NUMV              = 1 << 2;

#define ENQUEUER_TASK  0
#define CALC_IN_DEGREE_TASK 1
#define CALC_COLOR_TASK  2
#define RECEIVE_COLOR_TASK 3

typedef unsigned int uint;

uint* colors;
uint* edge_offset;
uint* edge_neighbors;

uint* scratch;
uint numV;

void enqueuer_task(uint ts, uint locale, uint enq_start, uint arg1) {
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
       colors[vid*4] = bit;
   } else {
       bit = colors[vid*4];
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


void main() {
   chronos_init();

   colors = (uint*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
   edge_offset  =(uint*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   edge_neighbors  =(uint*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;
   scratch  =(uint*) ((*(int *)(ADDR_BASE_SCRATCH))<<2);
   numV  =*(uint *)(ADDR_NUMV) ;

   while (1) {
      uint ttype, ts, locale, arg0, arg1;
      deq_task(&ttype, &ts, &locale, &arg0, &arg1);
      switch(ttype) {
        case ENQUEUER_TASK:
           enqueuer_task(ts, locale, arg0, arg1);
           break;
        case CALC_IN_DEGREE_TASK:
           calc_in_degree_task(ts, locale, arg0, arg1);
           break;
        case CALC_COLOR_TASK:
           calc_color_task(ts, locale, arg0, arg1);
           break;
        case RECEIVE_COLOR_TASK:
           receive_color_task(ts, locale, arg0, arg1);
           break;
        default:
           break;
      }
      finish_task();
   }
}

