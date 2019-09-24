#include "../include/chronos.h"

const int ADDR_BASE_DATA         = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET  = 3 << 2;
const int ADDR_BASE_NEIGHBORS    = 4 << 2;
const int ADDR_NUMV              = 1 << 2;
const int ADDR_GLOBAL_RELABEL_MASK = 11 << 2;
const int ADDR_ITERATION_MASK = 12 << 2;
const int ADDR_ORDERED_EDGES = 13 << 2;
const int ADDR_SRC_NODE = 7 << 2;
const int ADDR_SINK_NODE = 9 << 2;

const int TX_ID_OFFSET_BITS = 8;

#define DISCHARGE_START_TASK  0
#define DISCHARGE_START_TASK_CONT  5
#define GET_HEIGHT_TASK 1
#define PUSH_FROM_TASK 2
#define PUSH_TO_TASK 3
#define GLOBAL_RELABEL_VISIT_TASK 4


uint* edge_offset;

uint log_global_relabel_bits;
uint global_relabel_mask;
uint ordered_edges;
uint iteration_mask;

uint src_node;
uint sink_node;

// if this bit is set in the ts, it corresponds to bfs starting from src
const int bfs_src_ts_bit = 11;

uint numV;

typedef struct {
   uint excess;
   uint counter_min_height;
   uint height;
   uint visited;
   // flows of outgoing neighbors. This is in node_prop because
   // it is modified by tasks that access src node
   int flow[12];
} node_prop_t;
node_prop_t* node_prop;

typedef struct {
   uint dest;
   uint capacity;
} edge_prop_t;
edge_prop_t* edge_neighbors;


void discharge_start_task(uint ts, uint vid, uint enq_start, uint arg1) {

   if ((ts & global_relabel_mask) == 0) {
      uint sink = *(uint *)(ADDR_SINK_NODE);
      uint src  = *(uint *)(ADDR_SRC_NODE);
      if ( ((ts >> 4) & 0xf) == 0) {
          // TILE_ID == 0
          enq_task_arg1(GLOBAL_RELABEL_VISIT_TASK, ts, sink, 0);
          enq_task_arg1(GLOBAL_RELABEL_VISIT_TASK, ts | (1<<bfs_src_ts_bit), src, 0);
      }
      // reenqueue the original task
      enq_task_arg1(DISCHARGE_START_TASK, ts, vid, 0);
      return;
   }
   uint eo_begin = edge_offset[vid];
   uint eo_end = edge_offset[vid+1];
   undo_log_write(&(node_prop[vid].counter_min_height),
           node_prop[vid].counter_min_height);
   node_prop[vid].counter_min_height = (eo_end - eo_begin) << 24 | (2*numV);

   eo_begin += enq_start;
   if (eo_end > eo_begin + 7) {
       enq_task_arg1(DISCHARGE_START_TASK_CONT, ts, vid, enq_start +7);
       eo_end = eo_begin + 7;
   }

   uint child_cnt = 0;
   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i].dest & 0xffffff;
      uint neighbor_ts = ts;
      if (ordered_edges) {
        neighbor_ts += (child_cnt + enq_start);
      }
      enq_task_arg2(GET_HEIGHT_TASK, neighbor_ts , neighbor,
              vid, child_cnt + enq_start);
      child_cnt++;
   }
}

void get_height_task(uint ts, uint vid, uint src, uint neighbor_id) {
   uint ht = node_prop[vid].height;
   enq_task_arg2(PUSH_FROM_TASK, ts, src, ht, neighbor_id);
}

void push_from_task(uint ts, uint vid, uint neighbor_height, uint neighbor_id) {
   // extract sender node index from timestamp
   uint push_to_index = neighbor_id;
   uint h = node_prop[vid].height;
   // update counter
   uint counter = node_prop[vid].counter_min_height ;
   undo_log_write(&(node_prop[vid].counter_min_height), counter);
   uint min_neighbor = counter & 0xffffff;
   counter = counter >> 24;

   int consider_for_relabelling = 1;
   int is_init_task = (vid == src_node);// ((ts >> 4) == 0x10) ;
   uint eo_begin = edge_offset[vid];
   int edge_capacity = edge_neighbors[eo_begin + push_to_index].capacity;
   int edge_flow = node_prop[vid].flow[push_to_index];
   if (h == neighbor_height+1 || is_init_task) {
      // do push
      uint excess = node_prop[vid].excess;
      //enq_task_arg2(7, ts, vid, edge_capacity, edge_flow);

      uint amt = excess;
      // min(excess, (cap-flow))
      if (amt > (edge_capacity - edge_flow)) amt = (edge_capacity - edge_flow);
      if (amt > 0) {
         uint reverse_index = edge_neighbors[eo_begin + push_to_index].dest >> 24;
         uint dest = edge_neighbors[eo_begin + push_to_index].dest & 0xffffff;
         undo_log_write(&(node_prop[vid].flow[push_to_index]), edge_flow);
         edge_flow += amt;
         node_prop[vid].flow[push_to_index] = edge_flow;
         undo_log_write(&(node_prop[vid].excess), excess);
         node_prop[vid].excess = excess - amt;
         enq_task_arg2(PUSH_TO_TASK, ts, dest, reverse_index, amt);
      }

   }
   counter--;
   consider_for_relabelling = (edge_capacity > edge_flow)? 1 : 0;
   uint current_min_neighbor_height;
   if (consider_for_relabelling) {
      if (neighbor_height < min_neighbor) {
        min_neighbor = neighbor_height;
      }
   }
   node_prop[vid].counter_min_height = counter << 24 | min_neighbor;
   if (counter == 0) {
      // relabel
      // set height here itself; no need enqueing another task for it if
      // conflict detection is at node level
      if (node_prop[vid].excess > 0) {
         node_prop[vid].height = min_neighbor + 1;
         enq_task_arg2(DISCHARGE_START_TASK, ts, vid, 0, ts);

      } else {

      }
      //enq_task_arg2(8, ts, vid, node_prop[vid].excess, node_prop[vid].height);

   }
}

void push_to_task(uint ts, uint vid, uint reverse_index, uint amt) {
   uint excess = node_prop[vid].excess;
   int flow = node_prop[vid].flow[reverse_index];

   undo_log_write(&(node_prop[vid].flow[reverse_index]), flow);
   node_prop[vid].flow[reverse_index] = flow - amt;
   undo_log_write(&(node_prop[vid].excess), excess);
   node_prop[vid].excess = excess + amt;
   //excess += amt;

   if (excess == 0 && (vid != src_node) && (vid != sink_node) ) {
      // Task unit should modify ts to a unique number
      enq_task_arg2(DISCHARGE_START_TASK, ts, vid, 0, ts);
   } else {
   }
}

void global_relabel_visit_task(uint ts, uint vid, uint enq_start, uint reverse_edge_id) {

   uint visited = node_prop[vid].visited;
   uint iteration_no = ts >> (TX_ID_OFFSET_BITS + log_global_relabel_bits);
   uint is_src_bfs = (ts >> (bfs_src_ts_bit) & 1);
   uint ts_height_bits = ts & (( 1<< bfs_src_ts_bit )-1);

   if (enq_start == 0) {
      if (visited < iteration_no) {
         // not visited so far this iteration
         //
         // exit if reverse edge is not residual but not if this is the first
         // node in the bfs
         if ( ts_height_bits > 0) {
            //int cap = edge_neighbors[edge_offset[vid] + reverse_edge_id].capacity;
            //int flow = node_prop[vid].flow[reverse_edge_id];
            //if (cap <= flow) return;
         }

         undo_log_write(&(node_prop[vid].visited), visited);
         node_prop[vid].visited = iteration_no;
         uint old_height = node_prop[vid].height;
         undo_log_write(&(node_prop[vid].height), old_height);
         uint new_height = ts_height_bits + (is_src_bfs ? numV : 0);
         if (new_height < old_height) {

            //enq_task_arg2(10, ts, vid, new_height, old_height);
         }

         node_prop[vid].height = new_height ;
      } else {
          return;
      }
   }

   uint eo_begin = edge_offset[vid];
   uint eo_end = edge_offset[vid+1];

   eo_begin += enq_start;
   if (eo_end > eo_begin + 7) {
       enq_task_arg2(GLOBAL_RELABEL_VISIT_TASK, ts, vid, enq_start +7, 0);
       eo_end = eo_begin + 7;
   }

   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i].dest & 0xffffff;
      uint reverse_index = edge_neighbors[i].dest >> 24;
      int cap = edge_neighbors[edge_offset[neighbor] + reverse_index].capacity;
      int flow = - (node_prop[vid].flow[i-eo_begin]);
      if (cap > flow) {
         enq_task_arg2(GLOBAL_RELABEL_VISIT_TASK, ts + 1,
                 neighbor, 0, 0);
      }
   }

}

void main() {
   chronos_init();

   node_prop = (node_prop_t*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
   edge_offset  =(uint*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   edge_neighbors  =(edge_prop_t*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;
   numV  = *(uint *)(ADDR_NUMV) ;
   src_node  = *(uint *)(ADDR_SRC_NODE) ;
   sink_node  = *(uint *)(ADDR_SINK_NODE) ;
   // if more than 1 tile, host should adjust this field before sending it over
   // to the FPGA
   log_global_relabel_bits = *(uint *)(10<<2);
   global_relabel_mask = *(uint *)(ADDR_GLOBAL_RELABEL_MASK) ;
   ordered_edges = *(uint *)(ADDR_ORDERED_EDGES) ;
   iteration_mask = *(uint *)(ADDR_ITERATION_MASK) ;

   global_relabel_mask = ((1<<(log_global_relabel_bits)) - 1 ) << (TX_ID_OFFSET_BITS);
   //global_relabel_mask = ~0;
   while (1) {
      uint ttype, ts, locale, arg0, arg1;
      deq_task(&ttype, &ts, &locale, &arg0, &arg1);
      switch(ttype) {
        case DISCHARGE_START_TASK:
        case DISCHARGE_START_TASK_CONT:
           discharge_start_task(ts, locale, arg0, arg1);
           break;
        case GET_HEIGHT_TASK:
           get_height_task(ts, locale, arg0, arg1);
           break;
        case PUSH_FROM_TASK:
           push_from_task(ts, locale, arg0, arg1);
           break;
        case PUSH_TO_TASK:
           push_to_task(ts, locale, arg0, arg1);
           break;
        case GLOBAL_RELABEL_VISIT_TASK:
           global_relabel_visit_task(ts, locale, arg0, arg1);
           break;
        default:
           break;
      }
      finish_task();
   }
}

