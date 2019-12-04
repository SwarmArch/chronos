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
const int ADDR_BASE_DATA = 5 << 2;
const int ADDR_BASE_EDGE_OFFSET = 3 << 2;
const int ADDR_BASE_NEIGHBORS = 4 << 2;

const int ADDR_INIT_BASE_OFFSET = 8 << 2;
const int ADDR_INIT_BASE_NEIGHBORS = 9 << 2;

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


int* gate_state;
int* edge_offset;
int* edge_neighbors;

int* init_edge_neighbors;
int* init_edge_offset;

#define DES_TASK  0
#define ENQUEUER_TASK  1

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
        enq_task_arg2(DES_TASK, next_ts, comp, /*port */ 0, logicVal);
        n_child++;
        edge_offset++;

    }
}

__attribute__((always_inline))
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

__attribute__((always_inline))
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
    }

void main() {
    chronos_init();

    gate_state = (int*) ((*(int *) (ADDR_BASE_DATA))<<2) ;
    edge_offset  =(int*) ((*(int *)(ADDR_BASE_EDGE_OFFSET))<<2) ;
    edge_neighbors  =(int*) ((*(int *)(ADDR_BASE_NEIGHBORS))<<2) ;

    init_edge_neighbors  =(int*) ((*(int *)(ADDR_INIT_BASE_NEIGHBORS))<<2) ;
    init_edge_offset  =(int*) ((*(int *)(ADDR_INIT_BASE_OFFSET))<<2) ;

    while (1) {
        uint ttype, ts, object, arg0, arg1;
        deq_task_arg2(&ttype, &ts, &object, &arg0, &arg1);
        switch(ttype) {
            case DES_TASK:
                des_task(ts, object, arg0, arg1);
                break;
            case ENQUEUER_TASK:
                enqueuer_task(ts, object, arg0, arg1);
                break;
            default:
                break;
        }
        finish_task();
    }
}

