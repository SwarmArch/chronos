const int ADDR_BASE_DATA = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET = 3 << 2;
const int ADDR_BASE_NEIGHBORS = 4 << 2;

const int ADDR_INIT_BASE_OFFSET = 8 << 2;
const int ADDR_INIT_BASE_NEIGHBORS = 9 << 2;

const int ADDR_DEQ_TASK = 0xc0000000;
const int ADDR_DEQ_TASK_HINT = 0xc0000004;
const int ADDR_DEQ_TASK_TTYPE = 0xc0000008;
const int ADDR_DEQ_TASK_ARG0 = 0xc000000c;
const int ADDR_DEQ_TASK_ARG1 = 0xc0000010;
const int ADDR_FINISH_TASK = 0xc0000020;
const int ADDR_UNDO_LOG_ADDR = 0xc0000030;
const int ADDR_UNDO_LOG_DATA = 0xc0000034;

#define BUF  0
#define INV 1
#define NAND2 2
#define NOR2 3
#define AND2 4
#define OR2 5
#define XOR2 6
#define XNOR2 7
const int LOGIC_0 = 0;
const int LOGIC_1 = 1;
const int LOGIC_X = 2;
const int LOGIC_Z = 3;

typedef unsigned int uint;

void finish_task() {
   *(volatile int *)( ADDR_FINISH_TASK) = 0;
}
inline void init() {

   //__asm__( "li a0, 0x80000000;");
   //__asm__( "csrw mtvec, a0;");
   __asm__( "li a0, 0x800;");
   __asm__( "csrw mie, a0;"); // external interrupts enabled
   __asm__( "csrr a0, mstatus;");
   __asm__( "ori a0, a0, 8;"); // interrupts enabled
   __asm__( "csrw mstatus, a0;");

   __asm__( "li gp, 0x7f000000 ");

}
void undo_log_write(uint* addr, uint data) {
   *(volatile int *)( ADDR_UNDO_LOG_ADDR) = (uint) addr;
   *(volatile int *)( ADDR_UNDO_LOG_DATA) = data;
}

void enq_task_arg2(uint ttype, uint ts, uint hint, uint arg0, uint arg1){

     *(volatile int *)( ADDR_DEQ_TASK_HINT) = (hint);
     *(volatile int *)( ADDR_DEQ_TASK_TTYPE) = (ttype);
     *(volatile int *)( ADDR_DEQ_TASK_ARG0) = (arg0);
     *(volatile int *)( ADDR_DEQ_TASK_ARG1) = (arg1);
     *(volatile int *)( ADDR_DEQ_TASK) = ts;
}

int* gate_state;
int* edge_offset;
int* edge_neighbors;

int* init_edge_neighbors;
int* init_edge_offset;

void enqueuer_task(uint ts, uint comp, uint enq_start, uint arg1) {

    int edge_offset = init_edge_offset[comp] + enq_start;
    int edge_offset_end = init_edge_offset[comp + 1];

    uint next_ts;
    int n_child = 0;
    while( edge_offset < edge_offset_end) {
        if (n_child == 7) {
            enq_task_arg2(1, next_ts, comp, enq_start + 7, 0);
            break;
        }

        uint next_event = init_edge_neighbors[edge_offset];
        next_ts = next_event & 0xffffff;
        uint logicVal = (next_event >> 24) & 0x3;
        enq_task_arg2(0, next_ts, comp, /*port */ 0, logicVal);
        n_child++;
        edge_offset++;

    }
    finish_task();
}

uint eval_gate(uint in0, uint in1, uint gate_type) {
    if (gate_type == BUF) {
            return in0;
    } else if (gate_type == INV) {
        if (in0 == LOGIC_0) return LOGIC_1;
        else if (in0 == LOGIC_1) return LOGIC_0;
        else return in0;
    } else if (gate_type == NAND2) {
        if ( (in0 == LOGIC_1) & (in1 == LOGIC_1)) return LOGIC_0;
        else if ( (in0 == LOGIC_0) | (in1 == LOGIC_0)) return LOGIC_1;
        else return LOGIC_X;
    } else if (gate_type == NOR2) {
        if ( (in0 == LOGIC_1) | (in1 == LOGIC_1)) return LOGIC_0;
        else if ( (in0 == LOGIC_0) & (in1 == LOGIC_0)) return LOGIC_1;
        else return LOGIC_X;
    } else if (gate_type == AND2) {
        if ( (in0 == LOGIC_1) & (in1 == LOGIC_1)) return LOGIC_1;
        else if ( (in0 == LOGIC_0) | (in1 == LOGIC_0)) return LOGIC_0;
        else return LOGIC_X;
    } else if (gate_type == OR2) {
        if ( (in0 == LOGIC_1) | (in1 == LOGIC_1)) return LOGIC_1;
        else if ( (in0 == LOGIC_0) & (in1 == LOGIC_0)) return LOGIC_0;
        else return LOGIC_X;
    } else if (gate_type == XOR2) {
        if ( (in0 == LOGIC_1) & (in1 == LOGIC_1)) return LOGIC_0;
        else if ( (in0 == LOGIC_1) & (in1 == LOGIC_0)) return LOGIC_1;
        else if ( (in0 == LOGIC_0) & (in1 == LOGIC_1)) return LOGIC_1;
        else if ( (in0 == LOGIC_0) & (in1 == LOGIC_0)) return LOGIC_0;
        else return LOGIC_X;
    } else if (gate_type == XNOR2) {
        if ( (in0 == LOGIC_1) & (in1 == LOGIC_1)) return LOGIC_1;
        else if ( (in0 == LOGIC_1) & (in1 == LOGIC_0)) return LOGIC_0;
        else if ( (in0 == LOGIC_0) & (in1 == LOGIC_1)) return LOGIC_0;
        else if ( (in0 == LOGIC_0) & (in1 == LOGIC_0)) return LOGIC_1;
        else return LOGIC_X;

    }
    return LOGIC_X;

}

void des_task(uint ts, uint comp, uint port, uint logicVal) {
    uint state = (uint) gate_state[comp];
    uint delay = state & 0xffff;
    uint gate_type = (state >> 16) & 0x7;
    uint input_1 = (state >> 20) & 0x3;
    uint input_0 = (state >> 22) & 0x3;
    uint cur_out = (state >> 24) & 0x3;
    if (port == 0) input_0 = logicVal;
    if (port == 1) input_1 = logicVal;
    uint new_out = eval_gate(input_0, input_1, gate_type);
    //enq_task_arg2(2, 10000 + comp*1000 + input_1*100 + input_0* 10 + gate_type,
    //            10000 + port * 100 + cur_out * 10 + new_out, 0,0);
    undo_log_write( &(gate_state[comp]), state);
    gate_state[comp] = (new_out << 24)
                            | (input_0 << 22)
                            | (input_1 << 20)
                            | (gate_type << 16)
                            | (delay );

    if (cur_out != new_out) {
      for (int i = edge_offset[comp]; i < edge_offset[comp+1]; i++) {
         uint neighbor = edge_neighbors[i] >> 1;
         uint port = edge_neighbors[i] & 1;
         enq_task_arg2(0, ts + delay, neighbor, port, new_out);

      }

    }
    finish_task();
}

void main() {
    init();

    gate_state = (int*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
    edge_offset  =(int*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
    edge_neighbors  =(int*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;

   init_edge_neighbors  =(int*) ((*(int *)(ADDR_INIT_BASE_NEIGHBORS))<<2) ;
   init_edge_offset  =(int*) ((*(int *)(ADDR_INIT_BASE_OFFSET))<<2) ;

   *(volatile int *)( ADDR_DEQ_TASK_TTYPE) = 0;

   while (1) {
      uint ts = *(volatile uint *)(ADDR_DEQ_TASK);
      uint hint = *(volatile uint *)(ADDR_DEQ_TASK_HINT);
      uint ttype = *(volatile uint *)(ADDR_DEQ_TASK_TTYPE);
      uint arg0 = *(volatile uint *)(ADDR_DEQ_TASK_ARG0);
      uint arg1 = *(volatile uint *)(ADDR_DEQ_TASK_ARG1);
      switch(ttype) {
        case 0:
           des_task(ts, hint, arg0, arg1);
           break;
        case 1:
           enqueuer_task(ts, hint, arg0, arg1);
           break;
        case 2:
           finish_task();
      }
      /*
      continue;
      unsigned int cur_dist = (unsigned int) dist[vid];
      if (cur_dist < ts) {
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

      finish_task(); */
   }
}

void exit(int a) {
}
