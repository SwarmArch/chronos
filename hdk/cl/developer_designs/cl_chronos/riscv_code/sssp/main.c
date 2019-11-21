
#include "../include/chronos.h"

// The location pointing to the base of each of the arrays
const int ADDR_BASE_DIST = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET = 3 << 2;
const int ADDR_BASE_NEIGHBORS = 4 << 2;

uint32_t* dist;
uint32_t* edge_offset;
uint32_t* edge_neighbors;

#define VISIT_NODE_TASK  0

void visit_node_task(uint ts, uint vid) {

      unsigned int cur_dist = (unsigned int) dist[vid];
      if (cur_dist <= ts) {
         return;
      }

      undo_log_write(&(dist[vid]), cur_dist);
      dist[vid] = ts;
      for (int i = edge_offset[vid]; i < edge_offset[vid+1]; i++) {
         int neighbor = edge_neighbors[i*2];
         int weight = edge_neighbors[i*2+1];

         enq_task_arg0(VISIT_NODE_TASK, ts + weight, neighbor);
      }
}


int main() {
   chronos_init();

   // Dereference the pointers to array base addresses.
   // ( The '<<2' is because graph_gen writes the word number, not the byte)
   dist = (uint32_t*) ((*(uint32_t *) (ADDR_BASE_DIST))<<2) ;
   edge_offset  =(uint32_t*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   edge_neighbors  =(uint32_t*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;

   while (1) {
      uint ttype, ts, locale;
      deq_task_arg0(&ttype, &ts, &locale);
      switch(ttype){
          case VISIT_NODE_TASK:
              visit_node_task(ts, locale);
              break;
          default:
              break;
      }

      finish_task();
   }
}

