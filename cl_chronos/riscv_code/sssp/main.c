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
      uint ttype, ts, object;
      deq_task_arg0(&ttype, &ts, &object);
      switch(ttype){
          case VISIT_NODE_TASK:
              visit_node_task(ts, object);
              break;
          default:
              break;
      }

      finish_task();
   }
}

