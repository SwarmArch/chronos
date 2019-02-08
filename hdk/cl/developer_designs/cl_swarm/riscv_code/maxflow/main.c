const int ADDR_BASE_DATA         = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET  = 3 << 2;
const int ADDR_BASE_NEIGHBORS    = 4 << 2;
const int ADDR_NUMV              = 1 << 2;
const int ADDR_LOG_GLOBAL_RELABEL_INTERVAL = 10 << 2;
const int ADDR_SRC_NODE = 7 << 2;
const int ADDR_SINK_NODE = 9 << 2;

const int ADDR_DEQ_TASK      = 0xc0000000;
const int ADDR_DEQ_TASK_HINT = 0xc0000004;
const int ADDR_DEQ_TASK_TTYPE= 0xc0000008;
const int ADDR_DEQ_TASK_ARG0 = 0xc000000c;
const int ADDR_DEQ_TASK_ARG1 = 0xc0000010;
const int ADDR_FINISH_TASK   = 0xc0000020;
const int ADDR_UNDO_LOG_ADDR = 0xc0000030;
const int ADDR_UNDO_LOG_DATA = 0xc0000034;
const int ADDR_CUR_CYCLE     = 0xc0000050;
const int ADDR_PRINTF        = 0xc0000040;
const int ADDR_TILE_ID       = 0xc0000060;
const int ADDR_CORE_ID       = 0xc0000064;

const int TX_ID_OFFSET_BITS = 8;

#define DISCHARGE_START_TASK  0
#define DISCHARGE_START_TASK_CONT  5
#define GET_HEIGHT_TASK 1
#define PUSH_FROM_TASK 2
#define PUSH_TO_TASK 3
#define GLOBAL_RELABEL_VISIT_TASK 4


#define RO_OFFSET (1<<31)
//#define RO_OFFSET 0

typedef unsigned int uint;

uint* edge_offset;

uint log_global_relabel_bits;
uint global_relabel_mask;

// if this bit is set in the ts, it corresponds to bfs starting from src
const int bfs_src_ts_bit = 11;

uint numV;

typedef struct {
   uint height;
   uint excess;
   uint counter;
   uint active;
   uint visited;
   uint min_neighbor_height;
   // flows of outgoing neighbors. This is in node_prop because
   // it is odified by tasks that access src node
   int flow[10];
} node_prop_t;
node_prop_t* node_prop;

typedef struct {
   uint dest;
   uint capacity;
   uint reverse_index; // in the destination's edge list
   uint __aligned__;
} edge_prop_t;
edge_prop_t* edge_neighbors;


void finish_task() {
   *(volatile int *)( ADDR_FINISH_TASK) = 0;
}

void enq_task_arg2(uint ttype, uint ts, uint hint, uint arg0, uint arg1){

     *(volatile int *)( ADDR_DEQ_TASK_HINT) = (hint);
     *(volatile int *)( ADDR_DEQ_TASK_TTYPE) = (ttype);
     *(volatile int *)( ADDR_DEQ_TASK_ARG0) = (arg0);
     *(volatile int *)( ADDR_DEQ_TASK_ARG1) = (arg1);
     *(volatile int *)( ADDR_DEQ_TASK) = ts;
}
void enq_task_arg1(uint ttype, uint ts, uint hint, uint arg0){

     *(volatile int *)( ADDR_DEQ_TASK_HINT) = (hint);
     *(volatile int *)( ADDR_DEQ_TASK_TTYPE) = (ttype);
     *(volatile int *)( ADDR_DEQ_TASK_ARG0) = (arg0);
     *(volatile int *)( ADDR_DEQ_TASK) = ts;
}
void enq_task_arg0(uint ttype, uint ts, uint hint){

     *(volatile int *)( ADDR_DEQ_TASK_HINT) = (hint);
     *(volatile int *)( ADDR_DEQ_TASK_TTYPE) = (ttype);
     *(volatile int *)( ADDR_DEQ_TASK) = ts;
}

void init() {

   //__asm__( "li a0, 0x80000000;");
   //__asm__( "csrw mtvec, a0;");
   __asm__( "li a0, 0x800;");
   __asm__( "csrw mie, a0;"); // external interrupts enabled
   __asm__( "csrr a0, mstatus;");
   __asm__( "ori a0, a0, 8;"); // interrupts enabled
   __asm__( "csrw mstatus, a0;");

}
void undo_log_write(uint* addr, uint data) {
   *(volatile int *)( ADDR_UNDO_LOG_ADDR) = (uint) addr;
   *(volatile int *)( ADDR_UNDO_LOG_DATA) = data;
}
void discharge_start_task(uint ts, uint vid, uint enq_start, uint arg1) {

   if ((ts & global_relabel_mask) == 0) {
      uint sink = *(uint *)(ADDR_SINK_NODE);
      uint src  = *(uint *)(ADDR_SRC_NODE);
      enq_task_arg1(GLOBAL_RELABEL_VISIT_TASK, ts, sink, 0);
      enq_task_arg1(GLOBAL_RELABEL_VISIT_TASK, ts | (1<<bfs_src_ts_bit), src, 0);
      // reenqueue the original task
      enq_task_arg1(DISCHARGE_START_TASK, ts, vid, 0);
      return;
   }
   uint eo_begin = edge_offset[vid];
   uint eo_end = edge_offset[vid+1];
   if (enq_start == 0 && (ts != 0x100) ) {
      undo_log_write(&(node_prop[vid].active), node_prop[vid].active);
      undo_log_write(&(node_prop[vid].counter), node_prop[vid].counter);
      undo_log_write(&(node_prop[vid].min_neighbor_height), node_prop[vid].min_neighbor_height);
      node_prop[vid].active = 0;
      node_prop[vid].counter = eo_end - eo_begin;
      node_prop[vid].min_neighbor_height = 2*numV;
   }

   eo_begin += enq_start;
   if (eo_end > eo_begin + 7) {
       enq_task_arg1(DISCHARGE_START_TASK_CONT, ts, vid, enq_start +7);
       eo_end = eo_begin + 7;
   }

   uint child_cnt = 0;
   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i].dest;
      enq_task_arg1(GET_HEIGHT_TASK, ts + child_cnt + enq_start, neighbor | RO_OFFSET , vid);
      child_cnt++;
   }
}

void get_height_task(uint ts, uint vid, uint src, uint arg1) {
   uint ht = node_prop[vid].height;
   enq_task_arg1(PUSH_FROM_TASK, ts, src, ht);
}

void push_from_task(uint ts, uint vid, uint neighbor_height, uint arg1) {
   // extract sender node index from timestamp
   uint push_to_index = ts & 0xf;
   uint h = node_prop[vid].height;
   // update counter
   uint counter = node_prop[vid].counter;
   undo_log_write(&(node_prop[vid].counter), counter);
   node_prop[vid].counter = --counter;

   int consider_for_relabelling = 1;
   int is_init_task = ((ts >> 4) == 0x10) ;
   if (h == neighbor_height+1 || is_init_task) {
      // do push
      uint eo_begin = edge_offset[vid];
      uint edge_capacity = edge_neighbors[eo_begin + push_to_index].capacity;
      int edge_flow = node_prop[vid].flow[push_to_index];
      uint excess = node_prop[vid].excess;
      //enq_task_arg2(9, ts, excess, edge_capacity, edge_flow);

      uint amt = excess;
      // min(excess, (cap-flow))
      if (amt > (edge_capacity - edge_flow)) amt = (edge_capacity - edge_flow);
      if (amt > 0) {
         undo_log_write(&(node_prop[vid].flow[push_to_index]), edge_flow);
         edge_flow += amt;
         node_prop[vid].flow[push_to_index] = edge_flow;
         undo_log_write(&(node_prop[vid].excess), excess);
         node_prop[vid].excess = excess - amt;
         uint reverse_index = edge_neighbors[eo_begin + push_to_index].reverse_index;
         enq_task_arg2(PUSH_TO_TASK, ts, edge_neighbors[eo_begin+push_to_index].dest, reverse_index, amt);
      }

      consider_for_relabelling = (edge_capacity > edge_flow)? 1 : 0;
   }
   uint current_min_neighbor_height;
   if (consider_for_relabelling) {
      // updater min neighbor height
      current_min_neighbor_height = node_prop[vid].min_neighbor_height;
      if (neighbor_height < current_min_neighbor_height) {
         undo_log_write(&(node_prop[vid].min_neighbor_height), current_min_neighbor_height);
         node_prop[vid].min_neighbor_height = neighbor_height;
         current_min_neighbor_height = neighbor_height;
      }
   }
   if (counter == 0) {
      // relabel
      // set height here itself; no need enqueing another task for it if
      // conflict detection is at node level
      if (node_prop[vid].excess > 0) {
         if (!consider_for_relabelling) {
            current_min_neighbor_height = node_prop[vid].min_neighbor_height;
         }
         undo_log_write(&(node_prop[vid].height), h);
         node_prop[vid].height = current_min_neighbor_height + 1;
         enq_task_arg2(DISCHARGE_START_TASK, ts, vid, 0, ts);

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
   excess += amt;

   if ((node_prop[vid].active == 0) && excess > 0) {
      undo_log_write(&(node_prop[vid].active), 0);
      node_prop[vid].active = 1;
      // Task unit should modify ts to a unique number
      enq_task_arg2(DISCHARGE_START_TASK, ts, vid, 0, ts);
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
            int cap = edge_neighbors[edge_offset[vid] + reverse_edge_id].capacity;
            int flow = node_prop[vid].flow[reverse_edge_id];
            if (cap <= flow) return;
         }

         undo_log_write(&(node_prop[vid].visited), visited);
         node_prop[vid].visited = iteration_no;
         undo_log_write(&(node_prop[vid].height), node_prop[vid].height);
         node_prop[vid].height = ts_height_bits + (is_src_bfs ? numV : 0) ;
      } else {
          return;
      }
   }

   uint eo_begin = edge_offset[vid];
   uint eo_end = edge_offset[vid+1];

   eo_begin += enq_start;
   if (eo_end > eo_begin + 7) {
       enq_task_arg2(GLOBAL_RELABEL_VISIT_TASK, ts, vid, enq_start +7, reverse_edge_id);
       eo_end = eo_begin + 7;
   }

   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i].dest;
      enq_task_arg2(GLOBAL_RELABEL_VISIT_TASK, ts + 1, neighbor, 0, edge_neighbors[i].reverse_index);
   }

}

void main() {
   init();

   node_prop = (node_prop_t*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
   edge_offset  =(uint*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   edge_neighbors  =(edge_prop_t*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;
   numV  = *(uint *)(ADDR_NUMV) ;
   // if more than 1 tile, host should adjust this field before sending it over
   // to the FPGA
   log_global_relabel_bits = *(uint *)(ADDR_LOG_GLOBAL_RELABEL_INTERVAL) ;
   global_relabel_mask = ((1<<(log_global_relabel_bits+4)) - 1 ) << (TX_ID_OFFSET_BITS-4);

   while (1) {
      uint ts = *(volatile uint *)(ADDR_DEQ_TASK);
      uint hint = *(volatile uint *)(ADDR_DEQ_TASK_HINT);
      uint ttype = *(volatile uint *)(ADDR_DEQ_TASK_TTYPE);
      uint arg0 = *(volatile uint *)(ADDR_DEQ_TASK_ARG0);
      uint arg1 = *(volatile uint *)(ADDR_DEQ_TASK_ARG1);
      switch(ttype) {
        case DISCHARGE_START_TASK:
        case DISCHARGE_START_TASK_CONT:
           discharge_start_task(ts, hint, arg0, arg1);
           break;
        case GET_HEIGHT_TASK:
           get_height_task(ts, hint, arg0, arg1);
           break;
        case PUSH_FROM_TASK:
           push_from_task(ts, hint, arg0, arg1);
           break;
        case PUSH_TO_TASK:
           push_to_task(ts, hint, arg0, arg1);
           break;
        case GLOBAL_RELABEL_VISIT_TASK:
           global_relabel_visit_task(ts, hint, arg0, arg1);
           break;
      }
      finish_task();
   }
}

void exit(int a) {
}
