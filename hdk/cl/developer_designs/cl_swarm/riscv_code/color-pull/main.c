const int ADDR_BASE_DATA         = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET  = 3 << 2;
const int ADDR_BASE_NEIGHBORS    = 4 << 2;
const int ADDR_BASE_INITLIST     = 9 << 2;
const int ADDR_BASE_SCRATCH      =10 << 2;
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
   while(enq_start + n_child < numV) {
     if (n_child == 7) {
         enq_task_arg2(ENQUEUER_TASK, next_ts, hint, enq_start + 7, 0);
         break;
     }
     uint nextV = initlist[enq_start + n_child];
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
       enq_task_arg1(ENQ_NEIGHBOR_TASK, ts, vid, enq_start +6);
       eo_end = eo_begin + 6;
   }

   for (int i = eo_begin; i < eo_end; i++) {
      uint neighbor = edge_neighbors[i];
      enq_task_arg1(READ_COLOR_TASK, ts, neighbor, vid);
   }
   enq_task_arg0(CALC_COLOR_TASK, ts+1, 1 << 24 | vid);
}

void read_color_task(uint ts, uint neighbor, uint vid, uint arg1) {
   uint color = colors[neighbor];
   if (color != 0xffffffff) {
      enq_task_arg2(UPDATE_COLOR_TASK, ts, 1 << 24 | vid, color, neighbor);
   }
}

void update_color_task(uint ts, uint vid, uint color, uint neighbor) {
    vid = vid & 0xffffff;
   if (color < 32) {
      uint vec = scratch[vid*4];
      undo_log_write(&(scratch[vid*4]), vec);
      vec = vec | ( 1<<color);
      scratch[vid*4] = vec;
      //enq_task_arg0(7, ts, neighbor*100 + color);
   } // else todo
}

void calc_color_task(uint ts, uint vid, uint arg0, uint arg1) {
   // find first unset bit;
   vid = vid & 0xffffff;
   uint bit = 0;
   uint vec = scratch[vid*4];
   while (vec & 1) {
      vec >>= 1;
      bit++;
   }
   enq_task_arg1(WRITE_COLOR_TASK, ts, vid ,bit);

}

void write_color_task(uint ts, uint vid, uint color, uint arg1) {

   undo_log_write(&(colors[vid]), colors[vid]);
   colors[vid] = color;
}

void main() {
   init();

   colors = (uint*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
   edge_offset  =(uint*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   edge_neighbors  =(uint*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;
   scratch  =(uint*) ((*(int *)(ADDR_BASE_SCRATCH))<<2);
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
        case ENQ_NEIGHBOR_TASK:
           enq_neighbor_task(ts, hint, arg0, arg1);
           break;
        case READ_COLOR_TASK:
           read_color_task(ts, hint, arg0, arg1);
           break;
        case UPDATE_COLOR_TASK:
           update_color_task(ts, hint, arg0, arg1);
           break;
        case CALC_COLOR_TASK:
           calc_color_task(ts, hint, arg0, arg1);
           break;
        case WRITE_COLOR_TASK:
           write_color_task(ts, hint, arg0, arg1);
           break;
      }
      finish_task();
   }
}

void exit(int a) {
}
