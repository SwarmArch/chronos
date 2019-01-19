const int ADDR_BASE_DATA         = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET  = 3 << 2;
const int ADDR_BASE_NEIGHBORS    = 4 << 2;
const int ADDR_BASE_INITLIST     = 9 << 2;
const int ADDR_BASE_SCRATCH      =10 << 2;
const int ADDR_BASE_JOIN_COUNTER =11 << 2;
const int ADDR_NUMV              = 1 << 2;

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

#define ENQUEUER_TASK  0
#define CALC_IN_DEGREE_TASK 1
#define CALC_COLOR_TASK  2
#define RECEIVE_COLOR_TASK 3

typedef unsigned int uint;

uint* colors;
uint* edge_offset;
uint* edge_neighbors;

uint* scratch;
uint* initlist;
uint* join_counter;
uint numV;

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
void enqueuer_task(uint ts, uint hint, uint enq_start, uint arg1) {
   int n_child = 0;
   uint next_ts;
   for (int i=0; i<numV; i++) {
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
   join_counter[vid] += in_degree;
   //enq_task_arg2(6, 0, vid, in_degree, in_degree);
   if (join_counter[vid] == 0) {
      enq_task_arg0(CALC_COLOR_TASK, 0, vid);
   }
}
void calc_color_task(uint ts, uint vid, uint arg0, uint arg1) {
   // find first unset bit;
   uint bit = 0;
   uint vec = scratch[vid*4];
   while (vec & 1) {
      vec >>= 1;
      bit++;
   }
   colors[vid] = bit;
   uint eo_begin = edge_offset[vid];
   uint eo_end = edge_offset[vid+1];
   uint deg = eo_end - eo_begin;

   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i];
      uint neighbor_deg = edge_offset[neighbor+1] - edge_offset[neighbor];
      if ( (neighbor_deg < deg) || ((neighbor_deg == deg) & neighbor > vid)) {
         enq_task_arg2(RECEIVE_COLOR_TASK, ts, neighbor, bit, vid);
      }
   }

}


void receive_color_task(uint ts, uint vid, uint color, uint neighbor) {

   uint vec;
   if (color < 32) {
      vec = scratch[vid*4];
      vec = vec | ( 1<<color);
      scratch[vid*4] = vec;
   } // else todo
   //if (vid > 320) {

   //}
   join_counter[vid]--;
   if (join_counter[vid] ==0) {
      enq_task_arg0(CALC_COLOR_TASK, 0, vid);
   }
   //enq_task_arg2(8, ts, vid, join_counter[vid], vec);
}


void main() {
   init();

   colors = (uint*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
   edge_offset  =(uint*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   edge_neighbors  =(uint*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;
   scratch  =(uint*) ((*(int *)(ADDR_BASE_SCRATCH))<<2);
   join_counter  =(uint*) ((*(int *)(ADDR_BASE_JOIN_COUNTER))<<2);
   initlist  =(uint*) ((*(int *)(ADDR_BASE_INITLIST))<<2) ;
   numV  =*(uint *)(ADDR_NUMV) ;

   while (1) {
      uint ts = *(volatile uint *)(ADDR_DEQ_TASK);
      uint hint = *(volatile uint *)(ADDR_DEQ_TASK_HINT);
      uint ttype = *(volatile uint *)(ADDR_DEQ_TASK_TTYPE);
      uint arg0 = *(volatile uint *)(ADDR_DEQ_TASK_ARG0);
      uint arg1 = *(volatile uint *)(ADDR_DEQ_TASK_ARG1);
      switch(ttype) {
        case ENQUEUER_TASK:
           enqueuer_task(ts, hint, arg0, arg1);
           break;
        case CALC_IN_DEGREE_TASK:
           calc_in_degree_task(ts, hint, arg0, arg1);
           break;
        case CALC_COLOR_TASK:
           calc_color_task(ts, hint, arg0, arg1);
           break;
        case RECEIVE_COLOR_TASK:
           receive_color_task(ts, hint, arg0, arg1);
           break;
      }
      finish_task();
   }
}

void exit(int a) {
}
