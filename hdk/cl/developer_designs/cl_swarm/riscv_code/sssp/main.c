const int ADDR_BASE_DIST = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET = 3 << 2;
const int ADDR_BASE_NEIGHBORS = 4 << 2;

const int ADDR_DEQ_TASK = 0xc0000000;
const int ADDR_DEQ_TASK_HINT = 0xc0000004;
const int ADDR_DEQ_TASK_TTYPE = 0xc0000008;
const int ADDR_FINISH_TASK = 0xc0000020;
const int ADDR_UNDO_LOG_ADDR = 0xc0000030;
const int ADDR_UNDO_LOG_DATA = 0xc0000034;
const int ADDR_CUR_CYCLE = 0xc0000050;
const int ADDR_PRINTF = 0xc0000040;
const int ADDR_TILE_ID = 0xc0000060;
const int ADDR_CORE_ID = 0xc0000064;

typedef unsigned int uint;

void finish_task() {
   *(volatile int *)( ADDR_FINISH_TASK) = 0;
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

void main() {
   init();

   int* dist = (int*) ((*(int *) (ADDR_BASE_DIST))<<2) ;
   int* edge_offset  =(int*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
   int* edge_neighbors  =(int*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;

   *(volatile int *)( ADDR_DEQ_TASK_TTYPE) = 0;

   while (1) {
      uint cycle = *(volatile uint *)(ADDR_CORE_ID);
      *(volatile int *)( ADDR_PRINTF) = cycle;
      uint ts = *(volatile uint *)(ADDR_DEQ_TASK);
      uint vid = *(volatile uint *)(ADDR_DEQ_TASK_HINT);



      unsigned int cur_dist = (unsigned int) dist[vid];
      if (cur_dist <= ts) {
         finish_task();
         continue;
      }

      undo_log_write(&(dist[vid]), cur_dist);
      dist[vid] = ts;
      for (int i = edge_offset[vid]; i < edge_offset[vid+1]; i++) {
         int neighbor = edge_neighbors[i*2];
         int weight = edge_neighbors[i*2+1];

         *(volatile int *)( ADDR_DEQ_TASK_HINT) = (neighbor);
         *(volatile int *)( ADDR_DEQ_TASK) = (ts+weight);

      }

      finish_task();
   }
}

void exit(int a) {
}
