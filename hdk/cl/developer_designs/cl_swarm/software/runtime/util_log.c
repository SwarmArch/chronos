
#include "header.h"
int log_sssp_core(pci_bar_handle_t pci_bar_handle, int fd, int cid, FILE* fw) {

   uint32_t log_size;
   fpga_pci_peek(pci_bar_handle, (cid << 8) + (DEBUG_CAPACITY), &log_size );
   printf("Core %d log size %d\n", cid, log_size);
   if (log_size > 17000) return 1;

   unsigned char* log_buffer;
   log_buffer = (unsigned char *)malloc(log_size*64);

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (cid << 20);
   while (read_offset < read_len) {
      if (read_offset != 0) {
         printf("Partial read by driver, trying again with remainder of buffer (%u bytes)\n",
               read_len - read_offset);
      }
      rc = pread(fd,
            log_buffer + read_offset,
            read_len - read_offset,
            cl_addr);
      read_offset += rc;
   }
   unsigned int* buf = (unsigned int*) log_buffer;
   for (int i=0;i<log_size;i++) {
        unsigned int seq = buf[i*16 + 0];
        unsigned int cycle = buf[i*16 + 1];
        unsigned int ts = buf[i*16 + 2];
        unsigned int vid = buf[i*16 + 3];
        unsigned int bit = buf[i*16 + 4]  >> 31;
        unsigned int cur_dist = buf[i*16+4] & 0x7fff;
        if (bit)
            fprintf(fw,"[%6d][%10u] dequeue_task: ts:%d vid:%d \t\tcur:dist %d\n",
                    seq, cycle, ts, vid, cur_dist);
        else
            fprintf(fw,"[%6d][%10u]\t enqueue_task: ts:%d vid:%d\n",seq, cycle, ts, vid);
   }
   return 0;
}

uint32_t last_gvt_ts[] = {0, 0, 0, 0};
uint32_t last_gvt_tb[] = {0, 0, 0, 0};

int log_task_unit(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID_TASK_UNIT) {

   uint32_t log_size;
   uint32_t gvt;
   uint32_t ID_CQ = ID_TASK_UNIT + 5; // Hack
   fpga_pci_peek(pci_bar_handle,  (ID_TASK_UNIT << 8) + (DEBUG_CAPACITY), &log_size );
   fpga_pci_peek(pci_bar_handle,  (ID_CQ << 8) + (CQ_GVT_TS), &gvt );
   printf("Task unit log size %d gvt %d\n", log_size, gvt);
   if (log_size > 17000) return 1;
   // if (log_size > 100) log_size -= 100;
   //unsigned char* log_buffer;
   //log_buffer = (unsigned char *)malloc(log_size*64);

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (ID_TASK_UNIT << 20);
   while (read_offset < read_len) {
      rc = pread(fd,
            log_buffer,// + read_offset,
            // keep Tx size under 64*64 to prevent shell timeouts
            (read_len - read_offset) > 3200 ? 3200 : (read_len-read_offset),
            cl_addr);
      read_offset += rc;
      write_task_unit_log(log_buffer, fw, rc/64, ID_TASK_UNIT >> 8);
   }

   //write_task_unit_log(log_buffer, fw, log_size);
   return 0;
}

struct msg_type_t {
   int valid;
   int ready;
   int tied;
   int slot;
   int epoch_1;
   int epoch_2;
};

void fill_msg_type(struct msg_type_t * msg, unsigned int data) {
   msg->valid = (data >> 31) & 0x1;
   msg->ready = (data >> 30) & 0x1;
   msg->tied = (data >> 29) & 0x1;
   msg->slot = (data >> 16) & 0x1fff;
   msg->epoch_1 = (data >> 8) & 0xff;
   msg->epoch_2 = (data >> 0) & 0xff;
}

void write_task_unit_log(unsigned char* log_buffer, FILE* fw, uint32_t log_size, uint32_t tile_id) {
   unsigned int* buf = (unsigned int*) log_buffer;
   struct msg_type_t commit_task, abort_child, abort_task, cut_ties;
   struct msg_type_t deq_task, overflow_task, enq_task, coal_child;
   for (int i=0;i<log_size ;i++) {
        unsigned int seq = buf[i*16 + 0];
        unsigned int cycle = buf[i*16 + 1];
        //fprintf(fw, " \t \t %x %8x %8x %8x %8x %8x %8x %8x\n",
        //        buf[i*16], buf[i*16+1], buf[i*16+2], buf[i*16+3],
        //        buf[i*16+4], buf[i*16+5], buf[i*16+6], buf[i*16+7]);

        //fprintf(fw,"%d %d %d\n",i, seq, cycle);
        if (seq == -1) {
            continue;
        }
        unsigned int n_tasks, n_tied_tasks, heap_capacity;
        n_tasks = buf[i*16 + 2] & 0xffff;
        n_tied_tasks = buf[i*16 + 2] >> 16;
        heap_capacity = buf[i*16 + 3] & 0xffff;


        uint32_t splitter_deq_ready = (buf[i*16 + 3] >> 16) & 0x1;
        uint32_t splitter_deq_valid = (buf[i*16 + 3] >> 17) & 0x1;
        uint32_t enq_task_n_coal_child = (buf[i*16 + 3] >> 18) & 0x1;
        uint32_t commit_n_abort_child = (buf[i*16 + 3] >> 19) & 0x1;
        uint32_t resp_tsb_id = (buf[i*16 + 3] >> 20) & 0xf;
        uint32_t resp_tile_id = (buf[i*16 + 3] >> 24) & 0x7;
        uint32_t resp_ack = (buf[i*16 + 3] >> 27) & 0x1;
        uint32_t enq_ttype = (buf[i*16 + 3] >> 28) & 0xf;

        unsigned int enq_ts = buf[i*16 + 4];
        unsigned int enq_hint = buf[i*16 + 5];
        unsigned int deq_ts = buf[i*16+12];
        unsigned int deq_hint = buf[i*16+13];

        unsigned int gvt_ts = buf[i*16+14];
        unsigned int gvt_tb = buf[i*16+15];
        if ( (gvt_ts < last_gvt_ts[tile_id]) ||
                ((gvt_ts == last_gvt_ts[tile_id]) & (gvt_tb < last_gvt_tb[tile_id]))) {
            fprintf (fw,"GVT going back\n");
        }
        last_gvt_ts[tile_id] = gvt_ts;
        last_gvt_tb[tile_id] = gvt_tb;

        enq_task.valid = 0;
        coal_child.valid = 0;
        abort_child.valid = 0;
        commit_task.valid = 0;
        if (!enq_task_n_coal_child) {
            fill_msg_type( &coal_child     , buf[i*16 + 6]);
        } else {
            fill_msg_type( &enq_task       , buf[i*16 + 6]);
        }
        fill_msg_type( &overflow_task  , buf[i*16 + 7]);
        fill_msg_type( &deq_task       , buf[i*16 + 8]);
        fill_msg_type( &cut_ties       , buf[i*16 + 9]);
        fill_msg_type( &abort_task     , buf[i*16 +10]);
        if (!commit_n_abort_child) {
            fill_msg_type( &abort_child    , buf[i*16 +11]);
        } else {
            fill_msg_type( &commit_task    , buf[i*16 +11]);
        }


         if (enq_task.valid & enq_task.ready) {
             if (NON_SPEC) {

                fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) task_enqueue slot:%4d ts:%8x hint:%4x ttype:%1d arg0:%4d\n",
                   seq, cycle,
                   gvt_ts, gvt_tb,
                   n_tasks, n_tied_tasks, heap_capacity,
                   enq_task.slot, enq_ts, enq_hint, enq_ttype, deq_hint);
             } else {
                fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) task_enqueue slot:%4d ts:%8x hint:%4x ttype:%1d arg0:%4d arg1:%4d tied:%d epoch:%3d\n",
     //resp:(ack:%d tile:%2d tsb:%2d)
                   seq, cycle,
                   gvt_ts, gvt_tb,
                   n_tasks, n_tied_tasks, heap_capacity,
                   enq_task.slot, enq_ts, enq_hint, enq_ttype, deq_hint, deq_ts,
                   enq_task.tied, enq_task.epoch_1
       //            resp_ack,resp_tile_id, resp_tsb_id
                ) ;
             }
         }

         if (coal_child.valid & coal_child.ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) coal_child   slot:%4d ts:%4x hint:%4x \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               coal_child.slot, enq_ts, enq_hint);
         }
         if (overflow_task.valid & overflow_task.ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) overflow     slot:%4d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               overflow_task.slot) ;
         }
         if (deq_task.valid & deq_task.ready  ) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) task_deq     slot:%4d ts:%4x hint:%4d cq_slot %2d, epoch:%3d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               deq_task.slot, deq_ts, deq_hint, deq_task.epoch_1, deq_task.epoch_2) ;
         }
         if (splitter_deq_valid & splitter_deq_ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) splitter_deq slot:%4d hint:%4x cq_slot %2d, epoch:%3d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               deq_task.slot, deq_hint, deq_task.epoch_1, deq_task.epoch_2) ;
         }
         if (cut_ties.valid & cut_ties.ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) cut_ties     slot:%4d epoch:(%3d,%3d) tied:%1d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               cut_ties.slot, cut_ties.epoch_1, cut_ties.epoch_2, cut_ties.tied) ;
         }
         if (abort_task.valid & abort_task.ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) abort_task   slot:%4d epoch:(%3d,%3d) tied:%1d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               abort_task.slot, abort_task.epoch_1, abort_task.epoch_2, abort_task.tied) ;
         }
         if (abort_child.valid & abort_child.ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) abort_child  slot:%4d epoch:(%3d,%3d) tied:%1d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               abort_child.slot, abort_child.epoch_1, abort_child.epoch_2, abort_child.tied) ;
             if (abort_child.epoch_1 != abort_child.epoch_2) {
                fprintf(fw," abort child mismatch\n");
             }
         }
         if (commit_task.valid & commit_task.ready &!NON_SPEC) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) commit_task  slot:%4d epoch:(%3d,%3d) tied:%1d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               commit_task.slot, commit_task.epoch_1, commit_task.epoch_2, commit_task.tied) ;
             if (commit_task.epoch_1 != commit_task.epoch_2) {
                fprintf(fw," commit task mismatch\n");
             }
         }

   }

}

int log_cache(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, uint32_t ID_L2) {

   uint32_t log_size;
   fpga_pci_peek(pci_bar_handle, (ID_L2 << 8) + (DEBUG_CAPACITY), &log_size );
   printf("Cache log size %d\n", log_size);
   if (log_size > 17000) return 1;

   unsigned char* log_buffer;
   log_buffer = (unsigned char *)malloc(log_size*64);

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (ID_L2 << 20);
   while (read_offset < read_len) {
      rc = pread(fd,
            log_buffer,// + read_offset,
            (read_len - read_offset) > 3200 ? 3200 :(read_len - read_offset),
            cl_addr);
      read_offset += rc;
       const char *ops[8];
       ops[0] = "NONE ";
       ops[1] = "READ ";
       ops[2] = "WRITE";
       ops[3] = "EVICT";
       ops[4] = "RESPR";
       ops[5] = "RESPW";
       ops[6] = "FLUSH";
       ops[7] = "ERROR";
       unsigned int* buf = (unsigned int*) log_buffer;
       for (int i=0;i<rc/64;i++) {
            unsigned int seq = buf[i*16 + 0];
            unsigned int cycle = buf[i*16 + 1];
            unsigned int repl_tag = buf[i*16 + 2];

            unsigned int repl_way = (buf[i*16+3] >> 2) & 0x3;
            unsigned int hit = (buf[i*16+3] >> 4) & 0x1;
            unsigned int retry = (buf[i*16+3] >> 5) & 0x1;
            unsigned int op = (buf[i*16+3] >> 6) & 0x7;

            unsigned int addr_l = (buf[i*16+3]) >> 9;
            unsigned int addr_h = (buf[i*16+4]) & 0x7ff;
            unsigned long long addr = (addr_h << 23) + addr_l;
            unsigned int id = (buf[i*16+4] >> 11);

            unsigned int index = (addr >> 6) & 0x3ff;
            unsigned int tag = (addr >> 16);

            unsigned int wstrb_l = buf[i*16+5];
            unsigned int wstrb_h = buf[i*16+6];

            fprintf(fw, "[%6d][%12u][%2d:%2d] %s %s %1d %2d %8llx (tag:%5x index:%3x)  %6x wstrb:%8x_%8x \n",
                    seq, cycle, id >> 4, id & 0xf,  ops[op],
                    hit ? "H": "M",
                    retry, repl_way,
                    addr, tag, index,
                    repl_tag,
                    wstrb_h, wstrb_l
                );
       }
   }
   free(log_buffer);
   return 0;
}

int log_splitter(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, uint32_t ID_SPLITTER) {

    uint32_t log_size;
    fpga_pci_peek(pci_bar_handle, (ID_SPLITTER << 8) + (DEBUG_CAPACITY), &log_size );
    printf("Splitter log size %d\n", log_size);
    if (log_size > 17000) return 1;

    unsigned char* log_buffer;
    log_buffer = (unsigned char *)malloc(log_size*64);

    unsigned int read_offset = 0;
    unsigned int read_len = log_size * 64;
    unsigned int rc;
    uint64_t cl_addr = (1L<<36) + (ID_SPLITTER << 20);
    while (read_offset < read_len) {
        rc = pread(fd,
                log_buffer,// + read_offset,
                (read_len - read_offset) > 512 ? 512 : (read_len-read_offset),
                cl_addr);
        read_offset += rc;
        unsigned int* buf = (unsigned int*) log_buffer;
        for (int i=0;i<rc/64;i++) {
            unsigned int seq = buf[i*16 + 0];
            unsigned int cycle = buf[i*16 + 1];
            unsigned int scratchpad_entry = buf[i*16+2] & 0xffff;
            unsigned int coal_id = buf[i*16+2]>>16;
            unsigned int num_deq = buf[i*16+3];

            fprintf(fw, "[%6d][%12u][%6d] coal_id:%4x entry:%8x \n",
                    seq, cycle,
                    num_deq, coal_id,  scratchpad_entry
                   );
        }
    }
    free(log_buffer);
    return 0;
}

int log_cq(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID_CQ) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID_CQ << 8) + (DEBUG_CAPACITY), &log_size );
   fpga_pci_peek(pci_bar_handle,  (ID_CQ << 8) + (CQ_GVT_TS), &gvt );
   printf("CQ log size %d gvt %d\n", log_size, gvt);
   if (log_size > 17000) return 1;
   // if (log_size > 100) log_size -= 100;
   //unsigned char* log_buffer;
   //log_buffer = (unsigned char *)malloc(log_size*64);

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (ID_CQ << 20);
   while (read_offset < read_len) {
      rc = pread(fd,
            log_buffer + read_offset,
            // keep Tx size under 64*64 to prevent shell timeouts
            (read_len - read_offset) > 3200 ? 3200 : (read_len-read_offset),
            cl_addr);
      read_offset += rc;
   }

   //write_task_unit_log(log_buffer, fw, log_size);
   unsigned int* buf = (unsigned int*) log_buffer;
   for (int i=0;i<log_size ;i++) {
        unsigned int seq = buf[i*16 + 0];
        unsigned int cycle = buf[i*16 + 1];

        unsigned int start_task_valid = buf[i*16 + 6] >> 31 & 1;
        unsigned int start_task_ready = buf[i*16 + 6] >> 30 & 1;
        unsigned int start_task_core = buf[i*16 + 6] >> 24 & 0x3f;
        unsigned int start_task_slot = buf[i*16 + 6] >> 17 & 0x7f;
        //printf(" \t \t %x %x %x %x\n", buf[i*16], buf[i*16+1], buf[i*16+14], buf[i*16+11]);
        unsigned int gvt_ts = buf[i*16+10];
        unsigned int gvt_tb = buf[i*16+11];
        unsigned int abort_running_task = buf[i*16+2];
        unsigned int to_tq_abort_valid = buf[i*16+3] >> 31;
        unsigned int to_tq_resource_abort = (buf[i*16+3] >> 30 & 1);
        unsigned int gvt_task_slot_valid = buf[i*16+4] >> 31 & 1;
        unsigned int gvt_task_slot = buf[i*16+4] >> 24 & 0x7f;
        unsigned int abort_running_slot = buf[i*16+4] >> 17 & 0x7f;
        unsigned int max_vt_slot = buf[i*16+4] >> 10 & 0x7f;

        unsigned int finish_task_valid = buf[i*16 + 5] >> 31 & 1;
        unsigned int finish_task_ready = buf[i*16 + 5] >> 30 & 1;
        unsigned int finish_task_slot = buf[i*16 + 5] >> 23 & 0x7f;
        unsigned int finish_task_num_children = buf[i*16 + 5] >> 19 & 0xf;
        unsigned int finish_task_undo_log_write = buf[i*16 + 5] >> 18 & 0x1;

        unsigned int abort_children_valid = buf[i*16 + 7] >> 31 & 1;
        unsigned int abort_children_ready = buf[i*16 + 7] >> 30 & 1;
        unsigned int abort_children_slot = buf[i*16 + 7] >> 23 & 0x7f;
        unsigned int abort_children_children = buf[i*16 + 7] >> 19 & 0xf;

        unsigned int cut_ties_valid = buf[i*16 + 8] >> 31 & 1;
        unsigned int cut_ties_ready = buf[i*16 + 8] >> 30 & 1;
        unsigned int cut_ties_slot = buf[i*16 + 8] >> 23 & 0x7f;
        unsigned int cut_ties_children = buf[i*16 + 8] >> 19 & 0xf;

        unsigned int undo_task_valid = buf[i*16 + 9] >> 31 & 1;
        unsigned int undo_task_ready = buf[i*16 + 9] >> 30 & 1;
        unsigned int undo_task_slot = buf[i*16 + 9] >> 24 & 0x3f;
        unsigned int undo_task_ttype = buf[i*16 + 9] >> 20 & 0xf;
        unsigned int undo_task_hint = buf[i*16 + 9] & 0xfffff;
        if (seq == -1) {
            continue;
        }
         if (start_task_valid & start_task_ready) {
            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] start_task   slot:%4d core:%4d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               start_task_slot, start_task_core);
         }
         if (finish_task_valid & finish_task_ready) {
            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] finish_task  slot:%4d children:%2d undo_log:%d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               finish_task_slot, finish_task_num_children,
               finish_task_undo_log_write
               );
         }
         if (to_tq_abort_valid) {
            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] to_tq_abort resource:%d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               to_tq_resource_abort
               );
         }
         if (abort_running_task) {
            int bit_set = 0;
            int cnt =0;
            unsigned int copy = abort_running_task;
            while (copy) {
                if (copy & 0x1) {
                    bit_set = cnt;
                    break;
                }
                copy = copy >> 1;
                cnt ++;
            }

            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] abort_running_task %8x %2d slot:%4d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               abort_running_task, bit_set, abort_running_slot
               );
         }
         if (abort_children_valid & abort_children_ready) {
            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] abort_children slot%4d %d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               abort_children_slot, abort_children_children
               );

         }
         if (cut_ties_valid & cut_ties_ready) {
            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] cut_ties slot%4d %d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               cut_ties_slot, cut_ties_children
               );

         }
         if (undo_task_valid) {
            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] out_task slot%4d %d ttype:%d %d\n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               undo_task_slot, undo_task_hint, undo_task_ttype,
               undo_task_ready
               );

         }
    }
   fflush(fw);

   return 0;
}

int log_undo_log(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (DEBUG_CAPACITY), &log_size );
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (CQ_GVT_TS), &gvt );
   printf("Undo log size %d gvt %d\n", log_size, gvt);
   fprintf(fw, "Undo log size %d gvt %d\n", log_size, gvt);
   if (log_size > 17000) return 1;
   // if (log_size > 100) log_size -= 100;
   //unsigned char* log_buffer;
   //log_buffer = (unsigned char *)malloc(log_size*64);

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (ID << 20);
   while (read_offset < read_len) {
       rc = pread(fd,
               log_buffer,// + read_offset,
               // keep Tx size under 64*64 to prevent shell timeouts
               (read_len - read_offset) > 3200 ? 3200 : (read_len-read_offset),
               cl_addr);
       read_offset += rc;

       unsigned int* buf = (unsigned int*) log_buffer;
       for (int i=0;i<rc/64;i++) {
           unsigned int seq = buf[i*16 + 0];
           unsigned int cycle = buf[i*16 + 1];

           unsigned int awaddr = buf[i*16 + 4];
           unsigned int wdata = buf[i*16 + 5];

           unsigned int undo_log_addr = buf[i*16+8];
           unsigned int undo_log_data = buf[i*16+7];
           unsigned int undo_log_id = buf[i*16+6] >> 28;
           unsigned int undo_log_cq_slot = (buf[i*16+6] >> 21) & 0x7f;
           unsigned int undo_log_valid = (buf[i*16+6] >> 20) & 0x1;

           unsigned int restore_arvalid = (buf[i*16+3] >> 28) & 0xf;
           unsigned int restore_rvalid = (buf[i*16+3] >> 24) & 0xf;
           unsigned int restore_cq_slot = (buf[i*16+3] >> 16) & 0x3f;

           unsigned int awvalid = (buf[i*16+3] >> 15) & 0x1;
           unsigned int awready = (buf[i*16+3] >> 14) & 0x1;
           unsigned int awid = (buf[i*16+3]) & 0x3fff;

           unsigned int bid = (buf[i*16+2] >> 16) & 0xffff;
           unsigned int bvalid = (buf[i*16+2] >> 15) & 0x1;
           unsigned int bready = (buf[i*16+2] >> 14) & 0x1;
           unsigned int restore_ack_thread = (buf[i*16+2] >> 8) & 0x3f;
           unsigned int restore_done_valid = (buf[i*16+2] >> 4) & 0xf;
           unsigned int restore_done_ready = (buf[i*16+2] ) & 0xf;
           bool f = false;
           if (undo_log_valid) {
               fprintf(fw,"[%6d][%10u] undo_log_valid addr:%8x data:%8x id:%x cq_slot:%d\n",
                       seq, cycle, undo_log_addr, undo_log_data, undo_log_id, undo_log_cq_slot
                      );
               f = true;
           }

           if (bvalid & bready) {
               fprintf(fw,"[%6d][%10u] bvalid id:%4x\n",
                       seq, cycle, bid
                      );
               f = true;
           }

           if (restore_rvalid > 0) {
               fprintf(fw,"[%6d][%10u] restore rvalid:%x slot:%4d\n",
                       seq, cycle, restore_rvalid, restore_cq_slot
                      );
               f = true;
           }
           if (restore_done_valid > 0) {
               fprintf(fw,"[%6d][%10u] restore_ack valid:%x ready:%x thread:%4x\n",
                       seq, cycle, restore_done_valid, restore_done_ready, restore_ack_thread
                      );
               f = true;
           }
           if (awvalid) {
               fprintf(fw,"[%6d][%10u] awvalid %d%d addr:%8x data:%8x\n",
                       seq, cycle, awvalid, awready,
                       awaddr, wdata
                      );
               f = true;
           }
           if (!f) {
               fprintf(fw,"[%6d][%10u] %8x %8x %8x %8x %8x %8x\n",
                       seq, cycle,
                       buf[i*16+2], buf[i*16+3],
                       buf[i*16+4], buf[i*16+5],
                       buf[i*16+6], buf[i*16+7]
                      );

           }
       }

   }

   fflush(fw);
   return 0;
}

int log_serializer(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (DEBUG_CAPACITY), &log_size );
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (CQ_GVT_TS), &gvt );
   printf("Serializer log size %d gvt %d\n", log_size, gvt);
   if (log_size > 17000) return 1;
   // if (log_size > 100) log_size -= 100;
   //unsigned char* log_buffer;
   //log_buffer = (unsigned char *)malloc(log_size*64);

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (ID << 20);
   while (read_offset < read_len) {
       rc = pread(fd,
               log_buffer,// + read_offset,
               // keep Tx size under 64*64 to prevent shell timeouts
               (read_len - read_offset) > 3200 ? 3200 : (read_len-read_offset),
               cl_addr);
       read_offset += rc;

       unsigned int* buf = (unsigned int*) log_buffer;
       for (int i=0;i<rc/64;i++) {
           unsigned int seq = buf[i*16 + 0];
           unsigned int cycle = buf[i*16 + 1];

           unsigned int s_arvalid = (buf[i*16+10] >> 16) & 0xffff;
           unsigned int s_rvalid = (buf[i*16+10] >> 0) & 0xffff;

           unsigned int s_rdata_hint = (buf[i*16+9]);
           unsigned int s_rdata_ts = (buf[i*16+8]);

           unsigned int s_cq_slot = (buf[i*16+7] >> 25) & 0x3f;
           unsigned int s_rdata_ttype = (buf[i*16+7] >> 21) & 0xf;
           unsigned int finished_task_valid = (buf[i*16+7] >> 20) & 0x1;
           unsigned int finished_task_core = (buf[i*16+7] >> 15) & 0x1f;

           unsigned int ready_list_valid = (buf[i*16+6]);
           unsigned int ready_list_conflict = (buf[i*16+5]);

           unsigned int m_ts = (buf[i*16+4]);
           unsigned int m_hint = (buf[i*16+3]);

           unsigned int m_ttype = (buf[i*16+2] >> 28) & 0xf;
           unsigned int m_cq_slot = (buf[i*16+2] >> 21) & 0x3f;
           unsigned int m_valid = (buf[i*16+2] >> 20) & 1;
           unsigned int m_ready = (buf[i*16+2] >> 19) & 1;
           unsigned int finished_task_hint_match = (buf[i*16+2] >> 3) & 0xffff;
           bool f = false;
           if (finished_task_valid) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] finished_task core:%2x hint_match:%8x\n",
                       seq, cycle,
                       ready_list_valid, ready_list_conflict,
                       finished_task_core, finished_task_hint_match
                      );
               f = true;
           }

           if (s_rvalid > 0) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] s_ rvalid:%4x ttype:%x ts:%8x hint:%8x slot:%d\n",
                       seq, cycle,
                       ready_list_valid, ready_list_conflict,
                       s_rvalid, s_rdata_ttype, s_rdata_ts, s_rdata_hint, s_cq_slot
                      );
               f = true;
           }

           if (m_valid & m_ready) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] m_ ttype:%x ts:%8x hint:%8x slot:%d\n",
                       seq, cycle,
                       ready_list_valid, ready_list_conflict,
                       m_ttype, m_ts, m_hint, m_cq_slot
                      );
               f = true;
           }
           if (!f) {
               fprintf(fw,"[%6d][%10u] %8x %8x %8x %8x %8x %8x %8x %8x %8x %8x\n",
                       seq, cycle,
                       buf[i*16+2], buf[i*16+3],
                       buf[i*16+4], buf[i*16+5],
                       buf[i*16+6], buf[i*16+7],
                       buf[i*16+8], buf[i*16+9],
                       buf[i*16+10], buf[i*16+11]
                      );

           }
       }

   }
   fflush(fw);
   return 0;
}

int log_riscv(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID_CORE) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID_CORE << 8) + (DEBUG_CAPACITY), &log_size );
   fpga_pci_peek(pci_bar_handle,  (ID_CORE << 8) + (CQ_GVT_TS), &gvt );
   printf("Risc log size %d gvt %d\n", log_size, gvt);
   if (log_size > 17000) return 1;
   // if (log_size > 100) log_size -= 100;
   //unsigned char* log_buffer;
   //log_buffer = (unsigned char *)malloc(log_size*64);

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (ID_CORE << 20);
   while (read_offset < read_len) {
      rc = pread(fd,
            log_buffer,// + read_offset,
            // keep Tx size under 64*64 to prevent shell timeouts
            (read_len - read_offset) > 3200 ? 3200 : (read_len-read_offset),
            cl_addr);
      read_offset += rc;

      unsigned int* buf = (unsigned int*) log_buffer;
      for (int i=0;i<rc/64 ;i++) {
           unsigned int seq = buf[i*16 + 0];
           unsigned int cycle = buf[i*16 + 1];

           unsigned int state = buf[i*16 + 2] >> 12 & 0xf;
           unsigned int awvalid = buf[i*16 + 2] >> 11 & 1;
           unsigned int awready = buf[i*16 + 2] >> 10 & 1;
           unsigned int wvalid = buf[i*16 + 2] >> 9 & 1;
           unsigned int wready = buf[i*16 + 2] >> 8 & 1;
           unsigned int arvalid = buf[i*16 + 2] >> 7 & 1;
           //unsigned int arready = buf[i*16 + 2] >> 6 & 1;
           //unsigned int rvalid = buf[i*16 + 2] >> 5 & 1;
           //unsigned int rrready = buf[i*16 + 2] >> 4 & 1;
           unsigned int bvalid = buf[i*16 + 2] >> 3 & 1;
           unsigned int bready = buf[i*16 + 2] >> 2 & 1;
           //unsigned int rlast = buf[i*16 + 2] >> 1 & 1;
           //unsigned int wlast = buf[i*16 + 2] >> 0 & 1;

           unsigned int awid = buf[i*16 + 8] >> 16;
           unsigned int bid = buf[i*16 + 7] & 0xffff;
           unsigned int awaddr = buf[i*16 + 6];
           unsigned int wdata = buf[i*16 + 5];

           unsigned int pc = buf[i*16 + 12];
           unsigned int dbus_cmd_addr = buf[i*16 + 11];
           unsigned int dbus_cmd_data = buf[i*16 + 10];
           unsigned int dbus_rsp_data = buf[i*16 +  9];
           unsigned int dbus_cmd_valid = buf[i*16 +  2] >> 19 & 1;
           unsigned int dbus_cmd_ready = buf[i*16 +  2] >> 18 & 1;
           unsigned int dbus_cmd_wr = buf[i*16 +  2] >> 17 & 1;
           unsigned int dbus_rsp_valid = buf[i*16 +  2] >> 16 & 1;


           //printf(" \t \t %x %x %x %x\n", buf[i*16], buf[i*16+1], buf[i*16+14], buf[i*16+11]);
           if (seq == -1) {
               continue;
           }
            if (dbus_cmd_valid) {
               fprintf(fw,"[%6d][%10u][%08x][%d] req %d%d wr:%d addr:%08x data:%08x\n",
                  seq, cycle, pc, state,
                  dbus_cmd_valid, dbus_cmd_ready,
                  dbus_cmd_wr,
                  dbus_cmd_addr,
                  dbus_cmd_data
                  );
            }
             if (dbus_rsp_valid) {
                fprintf(fw,"[%6d][%10u][%08x] rsp %d data:%08x\n",
                   seq, cycle, pc,
                   dbus_rsp_valid,
                   dbus_rsp_data
                   );
             }
             if (awvalid) fprintf(fw, "[%6d][%10u][%08x] awvalid %08x %d\n",
                     seq, cycle, pc, awaddr, awid);
             if (wvalid) fprintf(fw, "[%6d][%10u][%08x] wvalid %08x \n",
                     seq, cycle, pc, wdata);
             if (awready) fprintf(fw, "[%6d][%10u][%08x] awready\n", seq, cycle, pc);
             if (bvalid) fprintf(fw, "[%6d][%10u][%08x] bvalid %d\n", seq, cycle, pc, bid);
             //if (bready) fprintf(fw, "[%6d][%10u][%08x] bready\n", seq, cycle, pc);
             if (wready) fprintf(fw, "[%6d][%10u][%08x] wready\n", seq, cycle, pc);
             if (arvalid) fprintf(fw, "[%6d][%10u][%08x] arvalid\n", seq, cycle, pc);
        }
   }

   return 0;
}

void task_unit_stats(uint32_t tile) {

    printf("Tile %d stats:\n",tile);

uint32_t stat_TASK_UNIT_STAT_N_UNTIED_ENQ          =0 ;
uint32_t stat_TASK_UNIT_STAT_N_TIED_ENQ_ACK        =0 ;
uint32_t stat_TASK_UNIT_STAT_N_TIED_ENQ_NACK       =0 ;
uint32_t stat_TASK_UNIT_STAT_N_DEQ_TASK            =0 ;
uint32_t stat_TASK_UNIT_STAT_N_SPLITTER_DEQ        =0 ;
uint32_t stat_TASK_UNIT_STAT_N_DEQ_MISMATCH        =0 ;
uint32_t stat_TASK_UNIT_STAT_N_CUT_TIES_MATCH      =0 ;
uint32_t stat_TASK_UNIT_STAT_N_CUT_TIES_MISMATCH   =0 ;
uint32_t stat_TASK_UNIT_STAT_N_CUT_TIES_COM_ABO    =0 ;
uint32_t stat_TASK_UNIT_STAT_N_COMMIT_TIED         =0 ;
uint32_t stat_TASK_UNIT_STAT_N_COMMIT_UNTIED       =0 ;
uint32_t stat_TASK_UNIT_STAT_N_COMMIT_MISMATCH     =0 ;
uint32_t stat_TASK_UNIT_STAT_N_ABORT_CHILD_DEQ     =0 ;
uint32_t stat_TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ =0 ;
uint32_t stat_TASK_UNIT_STAT_N_ABORT_CHILD_MISMATCH=0 ;
uint32_t stat_TASK_UNIT_STAT_N_ABORT_TASK          =0 ;
uint32_t stat_TASK_UNIT_STAT_N_COAL_CHILD          =0 ;
uint32_t stat_TASK_UNIT_STAT_N_OVERFLOW            =0 ;


pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_UNTIED_ENQ           ,&stat_TASK_UNIT_STAT_N_UNTIED_ENQ          );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_TIED_ENQ_ACK         ,&stat_TASK_UNIT_STAT_N_TIED_ENQ_ACK        );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_TIED_ENQ_NACK        ,&stat_TASK_UNIT_STAT_N_TIED_ENQ_NACK       );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_DEQ_TASK             ,&stat_TASK_UNIT_STAT_N_DEQ_TASK            );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_SPLITTER_DEQ         ,&stat_TASK_UNIT_STAT_N_SPLITTER_DEQ        );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_DEQ_MISMATCH         ,&stat_TASK_UNIT_STAT_N_DEQ_MISMATCH        );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_CUT_TIES_MATCH       ,&stat_TASK_UNIT_STAT_N_CUT_TIES_MATCH      );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_CUT_TIES_MISMATCH    ,&stat_TASK_UNIT_STAT_N_CUT_TIES_MISMATCH   );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_CUT_TIES_COM_ABO     ,&stat_TASK_UNIT_STAT_N_CUT_TIES_COM_ABO    );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_COMMIT_TIED          ,&stat_TASK_UNIT_STAT_N_COMMIT_TIED         );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_COMMIT_UNTIED        ,&stat_TASK_UNIT_STAT_N_COMMIT_UNTIED       );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_COMMIT_MISMATCH      ,&stat_TASK_UNIT_STAT_N_COMMIT_MISMATCH     );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_ABORT_CHILD_DEQ      ,&stat_TASK_UNIT_STAT_N_ABORT_CHILD_DEQ     );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ  ,&stat_TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_ABORT_CHILD_MISMATCH ,&stat_TASK_UNIT_STAT_N_ABORT_CHILD_MISMATCH);
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_ABORT_TASK           ,&stat_TASK_UNIT_STAT_N_ABORT_TASK          );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_COAL_CHILD           ,&stat_TASK_UNIT_STAT_N_COAL_CHILD          );
pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_OVERFLOW             ,&stat_TASK_UNIT_STAT_N_OVERFLOW            );

if (NON_SPEC) {
printf("STAT_N_UNTIED_ENQ           %9d\n",stat_TASK_UNIT_STAT_N_UNTIED_ENQ          );
printf("STAT_N_DEQ_TASK             %9d\n",stat_TASK_UNIT_STAT_N_DEQ_TASK            );
printf("STAT_N_COAL_CHILD           %9d\n",stat_TASK_UNIT_STAT_N_COAL_CHILD          );
printf("STAT_N_OVERFLOW             %9d\n",stat_TASK_UNIT_STAT_N_OVERFLOW            );
} else {
printf("STAT_N_UNTIED_ENQ           %9d\n",stat_TASK_UNIT_STAT_N_UNTIED_ENQ          );
printf("STAT_N_TIED_ENQ_ACK         %9d\n",stat_TASK_UNIT_STAT_N_TIED_ENQ_ACK        );
printf("STAT_N_TIED_ENQ_NACK        %9d\n",stat_TASK_UNIT_STAT_N_TIED_ENQ_NACK       );
printf("STAT_N_DEQ_TASK             %9d\n",stat_TASK_UNIT_STAT_N_DEQ_TASK            );
printf("STAT_N_SPLITTER_DEQ         %9d\n",stat_TASK_UNIT_STAT_N_SPLITTER_DEQ        );
printf("STAT_N_DEQ_MISMATCH         %9d\n",stat_TASK_UNIT_STAT_N_DEQ_MISMATCH        );
printf("STAT_N_CUT_TIES_MATCH       %9d\n",stat_TASK_UNIT_STAT_N_CUT_TIES_MATCH      );
printf("STAT_N_CUT_TIES_MISMATCH    %9d\n",stat_TASK_UNIT_STAT_N_CUT_TIES_MISMATCH   );
printf("STAT_N_CUT_TIES_COM_ABO     %9d\n",stat_TASK_UNIT_STAT_N_CUT_TIES_COM_ABO    );
printf("STAT_N_COMMIT_TIED          %9d\n",stat_TASK_UNIT_STAT_N_COMMIT_TIED         );
printf("STAT_N_COMMIT_UNTIED        %9d\n",stat_TASK_UNIT_STAT_N_COMMIT_UNTIED       );
printf("STAT_N_COMMIT_MISMATCH      %9d\n",stat_TASK_UNIT_STAT_N_COMMIT_MISMATCH     );
printf("STAT_N_ABORT_CHILD_DEQ      %9d\n",stat_TASK_UNIT_STAT_N_ABORT_CHILD_DEQ     );
printf("STAT_N_ABORT_CHILD_NOT_DEQ  %9d\n",stat_TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ );
printf("STAT_N_ABORT_CHILD_MISMATCH %9d\n",stat_TASK_UNIT_STAT_N_ABORT_CHILD_MISMATCH);
printf("STAT_N_ABORT_TASK           %9d\n",stat_TASK_UNIT_STAT_N_ABORT_TASK          );
printf("STAT_N_COAL_CHILD           %9d\n",stat_TASK_UNIT_STAT_N_COAL_CHILD          );
printf("STAT_N_OVERFLOW             %9d\n",stat_TASK_UNIT_STAT_N_OVERFLOW            );
}
    uint32_t state_stats[8] = {0};
    for (int i=0;i<8;i++) {
        pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STATE_STATS + (i*4) ,&(state_stats[i])            );
        printf("state:%d %10u    ", i, state_stats[i]);
        if ( (i%4==3)) printf("\n");
    }

    // TODO: Count spills
    uint32_t heap_enq = (stat_TASK_UNIT_STAT_N_UNTIED_ENQ +
                         stat_TASK_UNIT_STAT_N_TIED_ENQ_ACK +
                         stat_TASK_UNIT_STAT_N_ABORT_TASK);
    uint32_t heap_deq_abort = (stat_TASK_UNIT_STAT_N_DEQ_TASK +
                               stat_TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ);

    printf("Heap enq: %d, deq+abort %d\n", heap_enq, heap_deq_abort);

    // All tied tasks should have been untied, aborted or committed while tied
    printf("Tied_Enq :%d, %d\n", stat_TASK_UNIT_STAT_N_TIED_ENQ_ACK,
                    stat_TASK_UNIT_STAT_N_CUT_TIES_MATCH +
                    stat_TASK_UNIT_STAT_N_COMMIT_TIED +
                    stat_TASK_UNIT_STAT_N_ABORT_CHILD_DEQ +
                    stat_TASK_UNIT_STAT_N_ABORT_CHILD_NOT_DEQ -
                    stat_TASK_UNIT_STAT_N_CUT_TIES_COM_ABO);

    uint32_t n_cycles_deq_valid;
    pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_CYCLES_DEQ_VALID,&n_cycles_deq_valid);
    printf("cycles deq_valid:%9d\n", n_cycles_deq_valid);

}

void cq_stats (uint32_t tile, uint32_t tot_cycles) {
    printf("CQ stats \n");
    uint32_t state_stats[8] = {0};
    for (int i=0;i<8;i++) {
        pci_peek(tile, ID_CQ, CQ_STATE_STATS + (i*4) ,&(state_stats[i])            );
        printf("state:%d %10u    ", i, state_stats[i]);
        if ( (i%4==3)) printf("\n");
    }
    uint32_t resource_aborts, gvt_aborts;
    uint32_t cycles_in_resource_aborts;
    uint32_t cycles_in_gvt_aborts;

    pci_peek(tile, ID_CQ, CQ_STAT_N_RESOURCE_ABORTS ,&resource_aborts            );
    pci_peek(tile, ID_CQ, CQ_STAT_N_GVT_ABORTS ,&gvt_aborts            );
    pci_peek(tile, ID_CQ, CQ_STAT_CYCLES_IN_RESOURCE_ABORT, &cycles_in_resource_aborts );
    pci_peek(tile, ID_CQ, CQ_STAT_CYCLES_IN_GVT_ABORT, &cycles_in_gvt_aborts   );
    uint32_t idle_cq_full, idle_cc_full, idle_no_task;
    pci_peek(tile, ID_CQ, CQ_STAT_N_IDLE_CC_FULL ,&idle_cc_full            );
    pci_peek(tile, ID_CQ, CQ_STAT_N_IDLE_CQ_FULL ,&idle_cq_full            );
    pci_peek(tile, ID_CQ, CQ_STAT_N_IDLE_NO_TASK ,&idle_no_task            );
    printf("aborts: resource:%d, gvt:%d\n", resource_aborts, gvt_aborts);
    printf("cycles in aborts: resource:%d, gvt:%d\n", cycles_in_resource_aborts, cycles_in_gvt_aborts);

    printf("stall cycles: cq_full: %8d, cc_full: %8d, no_task: %8d\n",
               idle_cq_full, idle_cc_full, idle_no_task);

    uint32_t ttype_stat_deq, ttype_stat_commit;
    for (int i=0;i<5;i++) {
        pci_poke(tile, ID_CQ, CQ_LOOKUP_ENTRY, i);
        pci_peek(tile, ID_CQ, CQ_DEQ_TASK_STATS, &ttype_stat_deq);
        pci_peek(tile, ID_CQ, CQ_COMMIT_TASK_STATS, &ttype_stat_commit);
        printf("ttype:%d deq:%9d commit:%9d\n",i, ttype_stat_deq, ttype_stat_commit);

    }

    uint32_t conflict_none, conflict_bypassed, conflict_miss, conflict_real;
    pci_peek(tile, ID_CQ, CQ_N_TASK_NO_CONFLICT, &conflict_none);
    pci_peek(tile, ID_CQ, CQ_N_TASK_CONFLICT_MITIGATED, &conflict_bypassed);
    pci_peek(tile, ID_CQ, CQ_N_TASK_CONFLICT_MISS, &conflict_miss);
    pci_peek(tile, ID_CQ, CQ_N_TASK_REAL_CONFLICT, &conflict_real);

    printf("conflict none:%d bypass:%d miss:%d real:%d\n", conflict_none, conflict_bypassed, conflict_miss, conflict_real);

    // calculate CQ cycle breakdown;
    if (tot_cycles>0) {
        uint32_t n_deq_task;
        uint32_t n_abort_task;
        pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_DEQ_TASK, &n_deq_task);
        pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_ABORT_TASK, &n_abort_task);

        uint32_t useful_work = (n_deq_task - n_abort_task) *2;
        uint32_t aborted_work = (n_abort_task)*2 +
            state_stats[2] + state_stats[3] + state_stats[4];
        uint32_t conflict_checks = state_stats[1];
        uint32_t cq_stall = idle_cq_full;
        uint32_t no_core = idle_cc_full + (state_stats[5] - n_deq_task);
        uint32_t no_task = tot_cycles - useful_work - aborted_work - conflict_checks -
                cq_stall - no_core;

        printf("useful work:      %9d\n", useful_work);
        printf("aborted work:     %9d\n", aborted_work);
        printf("conflict checks:  %9d\n", conflict_checks);
        printf("stall_cq:         %9d\n", cq_stall);
        printf("stall_no_core:    %9d\n", no_core);
        printf("stall_no_task:    %9d\n", no_task);
    }

    return;
    pci_poke(tile, ID_CQ, CQ_LOOKUP_MODE , 1);
    for (int i=0;i<64;i++) {
        uint32_t ts,tb, state, hint;
        pci_poke(tile, ID_CQ, CQ_LOOKUP_ENTRY, i);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_STATE, &state);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_TS, &ts);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_TB, &tb);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_HINT, &hint);
        printf(" (%2d: %2d %5d:%10u %8x)", i, state,ts,tb, hint);
        if ( (i%2 == 1)) printf("\n");
    }

    uint32_t deq_task_ts, tq_lvt, max_vt_pos;
    pci_peek(tile, ID_CQ, CQ_DEQ_TASK_TS, &deq_task_ts);
    pci_peek(tile, ID_CQ, CQ_MAX_VT_POS, &max_vt_pos);
    pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_LVT, &tq_lvt);
    printf("\t deq_task_ts %6d tq_lvt:%6d, max_vt_pos:%d\n", deq_task_ts, tq_lvt, max_vt_pos);
    pci_poke(tile, ID_CQ, CQ_LOOKUP_MODE , 0);

}

uint32_t maxflow_wait_states[] = {2, 9, 11, 13, 19, 22, 25, 29, 31, 33, 48, 51, 59, 65, 67, 69, 71, 73};
uint32_t maxflow_enq_states[] = {5, 6, 7, 20, 23, 35, 46, 57, 74};
void core_stats(uint32_t tile, uint32_t tot_cycles) {
    const int SUM_INDEX = 80;
    const int MEM_STALL_INDEX = 81;
    const int ENQ_STALL_INDEX = 82;
    const int CQ_STALL_INDEX = 83;
    const int USEFUL_WORK_INDEX = 84;
    uint32_t core_state_stats[16][128];
    for (int i=0;i<=N_SSSP_CORES;i++) {
        uint32_t sum_all = 0;
        uint32_t mem_stall =0;
        uint32_t enq_stall = 0;
        for (int j=0;j<128;j++) {
            pci_poke(tile, i+1, CORE_QUERY_STATE , j);
            pci_peek(tile, i+1, CORE_AP_STATE_STATS , &(core_state_stats[i][j]));
            sum_all += core_state_stats[i][j];
        }
        core_state_stats[i][SUM_INDEX] = sum_all;
        for (int k=0;k<18;k++) {
            mem_stall += core_state_stats[i][maxflow_wait_states[k]];
        }
        core_state_stats[i][MEM_STALL_INDEX] = mem_stall;
        for (int k=0;k<9;k++) {
            enq_stall += core_state_stats[i][maxflow_enq_states[k]];
        }
        uint32_t num_enq;
        pci_peek(tile, i+1, CORE_NUM_ENQ , &num_enq);
        core_state_stats[i][ENQ_STALL_INDEX] = enq_stall - num_enq;
        core_state_stats[i][CQ_STALL_INDEX] =
            // adjust for cycles spent while reading stats.
            core_state_stats[i][0] - (sum_all - tot_cycles);
        core_state_stats[i][USEFUL_WORK_INDEX] = tot_cycles -
            core_state_stats[i][MEM_STALL_INDEX] -
            core_state_stats[i][ENQ_STALL_INDEX] -
            core_state_stats[i][CQ_STALL_INDEX];


    }
    printf("Tile %d core state stats\n", tile);
    for (int j=0;j<85;j++) {
        printf("%2d:", j);
        for (int i=0;i<N_SSSP_CORES;i++) {
            printf("%10d ", core_state_stats[i][j]);
        }
        printf("\n");
    }

}

