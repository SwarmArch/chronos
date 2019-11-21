#include "../include/chronos.h"

const int ADDR_BASE_DATA         = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET  = 3 << 2;
const int ADDR_BASE_NEIGHBORS    = 4 << 2;
const int ADDR_BASE_INITLIST     = 9 << 2;
const int ADDR_BASE_SCRATCH      = 7 << 2;
const int ADDR_NUMV              = 1 << 2;

#define ENQUEUER_TASK  0
#define ENQ_NEIGHBOR_TASK 1
#define READ_COLOR_TASK 2
#define UPDATE_COLOR_TASK 3
#define CALC_COLOR_TASK 4
#define WRITE_COLOR_TASK 5

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
     enq_task_arg1(ENQ_NEIGHBOR_TASK, next_ts, nextV, 0);
     n_child++;
   }
}

void enq_neighbor_task(uint ts, uint vid, uint enq_start, uint arg1) {
   uint eo_begin = edge_offset[vid] + enq_start;
   uint eo_end = edge_offset[vid+1];
   if (eo_end > eo_begin + 6) {
       enq_task_arg1(ENQ_NEIGHBOR_TASK, ts, vid , enq_start +6);
       eo_end = eo_begin + 6;
   }

   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i];
      enq_task_arg1(READ_COLOR_TASK, ts, neighbor, vid);
   }
   enq_task_arg0(CALC_COLOR_TASK, ts+1, 1 << 24 | vid);
}

void read_color_task(uint ts, uint neighbor, uint vid, uint arg1) {
   neighbor = neighbor & 0x7fffffff;
   uint color = colors[neighbor*4];
   if (color != 0xffffffff) {
      enq_task_arg2(UPDATE_COLOR_TASK, ts, 1 << 24 | vid, color, neighbor);
   }
}

void update_color_task(uint ts, uint vid, uint color, uint neighbor) {
   vid = vid & 0xffffff;
   if (color < 32) {
      uint vec = scratch[vid*2];
      undo_log_write(&(scratch[vid*2]), vec);
      vec = vec | ( 1<<color);
      scratch[vid*2] = vec;
   } // else todo
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
   enq_task_arg1(WRITE_COLOR_TASK, ts, vid  ,bit);

}

void write_color_task(uint ts, uint vid, uint color, uint arg1) {

   undo_log_write(&(colors[vid*4]), colors[vid*4]);
   colors[vid*4] = color;
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
        case ENQ_NEIGHBOR_TASK:
           enq_neighbor_task(ts, object, arg0, arg1);
           break;
        case READ_COLOR_TASK:
           read_color_task(ts, object, arg0, arg1);
           break;
        case UPDATE_COLOR_TASK:
           update_color_task(ts, object, arg0, arg1);
           break;
        case CALC_COLOR_TASK:
           calc_color_task(ts, object, arg0, arg1);
           break;
        case WRITE_COLOR_TASK:
           write_color_task(ts, object, arg0, arg1);
           break;
      }
      finish_task();
   }
}

