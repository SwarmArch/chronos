
#include "header.h"

uint32_t last_gvt_ts[] = {0, 0, 0, 0};
uint32_t last_gvt_tb[] = {0, 0, 0, 0};

uint32_t arid_cycle[65536] = {0};

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
   struct msg_type_t deq_task, overflow_task, enq_task, coal_child, deq_max;
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
        unsigned int enq_locale = buf[i*16 + 5];
        unsigned int deq_ts = buf[i*16+12];
        unsigned int deq_locale = buf[i*16+13];

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
        fill_msg_type( &deq_max        , buf[i*16 +12]);
        if (!commit_n_abort_child) {
            fill_msg_type( &abort_child    , buf[i*16 +11]);
        } else {
            fill_msg_type( &commit_task    , buf[i*16 +11]);
        }


         if (enq_task.valid & enq_task.ready) {
             if (NON_SPEC) {

                fprintf(fw,"[%6d][%10u][] (%4d:%4d:%5d) task_enqueue slot:%4d ts:%6x locale:%6x ttype:%1d arg0:%5d arg1:%8x\n",
                   seq, cycle,
                 //  gvt_ts, gvt_tb,
                   n_tasks, n_tied_tasks, heap_capacity,
                   enq_task.slot, enq_ts, enq_locale, enq_ttype,
                   deq_locale, deq_ts);
             } else {
                fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) task_enqueue slot:%4d ts:%6x locale:%6x ttype:%1d arg0:%8x arg1:%4x tied:%d \n",
     //resp:(ack:%d tile:%2d tsb:%2d)
                   seq, cycle,
                   gvt_ts, gvt_tb,
                   n_tasks, n_tied_tasks, heap_capacity,
                   enq_task.slot, enq_ts, enq_locale, enq_ttype, deq_locale, deq_ts,
                   enq_task.tied
       //            resp_ack,resp_tile_id, resp_tsb_id
                ) ;
             }
         }

         if (deq_max.valid) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) deq_max      slot:%4d tied:%d heap_cap:%4d\n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               deq_max.slot, deq_max.tied, deq_locale>>16);
         }
         if (coal_child.valid & coal_child.ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) coal_child   slot:%4d ts:%4d locale:%6d ttype:%1d (%6x)\n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               coal_child.slot, enq_ts, enq_locale, enq_ttype, enq_locale);
         }
         if (overflow_task.valid & overflow_task.ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) overflow     slot:%4d ts:%4d locale:%6d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               overflow_task.slot, buf[i*16+9], buf[i*16+10]) ;
         }
         if (deq_task.valid & deq_task.ready ) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) task_deq     slot:%4d ts:%4d locale:%6d cq_slot %2d, epoch:%3d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               deq_task.slot, deq_ts, deq_locale, deq_task.epoch_1, deq_task.epoch_2) ;
         }
         if (splitter_deq_valid & splitter_deq_ready) {
            fprintf(fw,"[%6d][%10u][%6u:%10u] (%4d:%4d:%5d) splitter_deq slot:%4d ts:%4d locale:%6d cq_slot %2d, epoch:%3d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               n_tasks, n_tied_tasks, heap_capacity,
               deq_task.slot, deq_ts, deq_locale, deq_task.epoch_1, deq_task.epoch_2) ;
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
int log_undo_log(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (DEBUG_CAPACITY), &log_size );
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (CQ_GVT_TS), &gvt );
   printf("Undo log size %d gvt %d\n", log_size, gvt);
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

           unsigned int awaddr = buf[i*16 + 5];
           unsigned int wdata = buf[i*16 + 4];

           unsigned int undo_log_addr = buf[i*16+8];
           unsigned int undo_log_data = buf[i*16+7];
           unsigned int undo_log_id = buf[i*16+6] >> 28;
           unsigned int undo_log_cq_slot = (buf[i*16+6] >> 21) & 0x7f;
           unsigned int undo_log_valid = (buf[i*16+6] >> 20) & 0x1;

           unsigned int restore_arvalid = (buf[i*16+3] >> 28) & 0xf;
           unsigned int restore_rvalid = (buf[i*16+3] >> 24) & 0xf;
           unsigned int restore_cq_slot = (buf[i*16+3] >> 16) & 0x7f;

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

int log_cache(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID_L2) {

   uint32_t log_size;
   fpga_pci_peek(pci_bar_handle, (ID_L2 << 8) + (DEBUG_CAPACITY), &log_size );
   printf("Cache log size %d\n", log_size);
   if (log_size > 17000) {
       if (log_size <34000) log_size -= 16384;
       else return 1;
   }

   unsigned int read_offset = 0;
   unsigned int read_len = log_size * 64;
   unsigned int rc;
   uint64_t cl_addr = (1L<<36) + (ID_L2 << 20);
   while (read_offset < read_len) {
      rc = pread(fd,
            log_buffer,// + read_offset,
            (read_len - read_offset) > 512 ? 512 :(read_len - read_offset),
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

            unsigned int index = (addr >> 6) & 0x7ff;
            unsigned int tag = (addr >> 15);

            unsigned int wstrb_l = buf[i*16+5];
            unsigned int wstrb_h = buf[i*16+6];

            unsigned int lru_prio[4];
            unsigned int tag_rdata[4];
            unsigned int tag_dirty[4];
            unsigned int tag_state[4];
            for (int j=0;j<4;j++) {
                unsigned int word = buf[i*16+7+j];
                lru_prio[j] = word & 0x3;
                tag_dirty[j] = (word >> 2) & 1;
                tag_rdata[j] = (word >> 3) & 0x1ffff;
                tag_state[j] = (word >> 20) & 3;
            }

            unsigned int m_awaddr = buf[i*16+11];
            unsigned int write_buf_mshr_valid = buf[i*16+12] & 0xffff;
            unsigned int m_awid = (buf[i*16+12] >> 16) & 0x1fff;
            unsigned int write_buf_match = (buf[i*16+12] >> 29) & 0x1;
            unsigned int m_awready = (buf[i*16+12] >> 30) & 0x1;
            unsigned int m_awvalid = (buf[i*16+12] >> 31) & 0x1;

            unsigned int m_bid = (buf[i*16+13] >> 0) & 0x3fff;
            unsigned int m_bready = (buf[i*16+13] >> 14) & 1;
            unsigned int m_bvalid = (buf[i*16+13] >> 15) & 1;
            unsigned int m_rid = (buf[i*16+13] >> 16) & 0xff;
            unsigned int m_arid = (buf[i*16+13] >> 24) & 0xff;

            unsigned int m_rready = (buf[i*16+14] >> 0) & 0x1;
            unsigned int m_rvalid = (buf[i*16+14] >> 1) & 0x1;
            unsigned int m_arready = (buf[i*16+14] >> 2) & 0x1;
            unsigned int m_arvalid = (buf[i*16+14] >> 3) & 0x1;
            unsigned int mshr_next = (buf[i*16+14] >> 4) & 0xf;
            unsigned int rdata_fifo_size = (buf[i*16+14] >> 8) & 0xff;

            fprintf(fw, "[%6d][%10u][%2x:%2x] %s %s %1d %2d %8llx"
                    "(tag:%4x index:%3x) %2d wstrb:%8x_%8x"
                   // "| (%d %2d %d %d) (%d %2d %d %d) (%d %2d %d %d) (%d %2d %d %d)"
                    "| %1d%1d %8llx %4x | %1d%1d%1d%1d %2d %2d | %2d %d %3d \n",
                    seq, cycle, id >> 8, id & 0xff,  ops[op],
                    hit ? "H": "M",
                    retry, repl_way,
                    addr, tag, index,
                    repl_tag,
                    wstrb_h, wstrb_l,
                  //  tag_state[0], tag_rdata[0], tag_dirty[0], lru_prio[0],
                  //  tag_state[1], tag_rdata[1], tag_dirty[1], lru_prio[1],
                  //  tag_state[2], tag_rdata[2], tag_dirty[2], lru_prio[2],
                  //  tag_state[3], tag_rdata[3], tag_dirty[3], lru_prio[3],
                    m_awvalid, m_awready, m_awaddr, write_buf_mshr_valid,
                    m_arvalid, m_arready, m_rvalid, m_rready,
                    m_arid, m_rid, mshr_next, m_bvalid, rdata_fifo_size

                );
       }
   }
   return 0;
}

last_coal_id =-1;
coal_id_seq =0;

int log_splitter(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID_SPLITTER) {

    uint32_t log_size;
    fpga_pci_peek(pci_bar_handle, (ID_SPLITTER << 8) + (DEBUG_CAPACITY), &log_size );
    printf("Splitter log size %d\n", log_size);
    if (log_size > 17000) return 1;


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
            unsigned int state = buf[i*16+4] & 0xff;
            unsigned int heap_size = (buf[i*16+4] >> 8) & 0xffff;

            unsigned int rdata_locale = buf[i*16+6] >> 4;
            unsigned int rdata_ts = buf[i*16+5] >> 4;
            unsigned int rdata_ttype = buf[i*16+5] & 0xf;

            if (state == 6) {
                rdata_locale = 0;
                rdata_ts = 0;
                rdata_ttype = 0;
            }

            unsigned int lvt = buf[i*16+9];
            unsigned int s_task_locale = buf[i*16+10];
            unsigned int s_task_ts = buf[i*16+11];

            if (last_coal_id != coal_id) {
                last_coal_id = coal_id;
                coal_id_seq = 0;
            } else {
                coal_id_seq++;
            }

            fprintf(fw, "[%6d][%12u][%x] [%8d]  [%d] coal_id:%4x entry:%8x heap:%2d (%8x %8d)"
                      " rdata: (%2x %8d %8d)\n",
                    seq, cycle,
                    state, lvt, coal_id_seq, coal_id,  scratchpad_entry,
                    heap_size, s_task_locale, s_task_ts,
                    rdata_ttype, rdata_ts, rdata_locale
                   );
        }
    }
    fflush(fw);
    return 0;
}

int log_coalescer(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID_COALESCER) {

    uint32_t log_size;
    fpga_pci_peek(pci_bar_handle, (ID_COALESCER << 8) + (DEBUG_CAPACITY), &log_size );
    printf("coalescer log size %d\n", log_size);
    if (log_size > 17000) return 1;

    unsigned int read_offset = 0;
    unsigned int read_len = log_size * 64;
    unsigned int rc;
    uint64_t cl_addr = (1L<<36) + (ID_COALESCER << 20);
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

            unsigned int bready = (buf[i*16+2] >> 0) & 0x1;
            unsigned int bvalid = (buf[i*16+2] >> 1) & 0x1;
            unsigned int arready = (buf[i*16+2] >> 2) & 0x1;
            unsigned int arvalid = (buf[i*16+2] >> 3) & 0x1;
            unsigned int wready = (buf[i*16+2] >> 4) & 0x1;
            unsigned int wvalid = (buf[i*16+2] >> 5) & 0x1;
            unsigned int awready = (buf[i*16+2] >> 6) & 0x1;
            unsigned int awvalid = (buf[i*16+2] >> 7) & 0x1;

            unsigned int state = (buf[i*16+2] >> 8) & 0xf;
            unsigned int coal_child_fifo = (buf[i*16+2] >> 12) & 0xff;
            unsigned int spill_fifo = (buf[i*16+2] >> 20) & 0x7ff;

            unsigned int stack_ptr = (buf[i*16+3] >> 0) & 0xffff;
            unsigned int stack_ptr_awid = (buf[i*16+3] >> 16) & 0xffff;
            unsigned int coal_id = (buf[i*16+4] >> 0) & 0xffff;
            unsigned int bid = (buf[i*16+4] >> 16) & 0xffff;
            unsigned int wid = (buf[i*16+5] >> 0) & 0xffff;
            unsigned int awid = (buf[i*16+5] >> 16) & 0xffff;
            unsigned int awaddr = (buf[i*16+6]);

            unsigned int wdata_ts = buf[i*16+7] >> 4;
            unsigned int wdata_locale = buf[i*16+8] >> 4;
            unsigned int wdata_ttype = buf[i*16+7] & 0xf;
            if (awvalid & awready) {
                fprintf(fw, "[%6d][%12u][%x] [%4x %4x] fifo[%3d %4d] awvalid %d%d id:%4x addr:%8x\n",
                        seq, cycle, state, stack_ptr, coal_id,
                        coal_child_fifo, spill_fifo,
                        awvalid, awready, awid, awaddr
                       );
            }
            if (wvalid & wready) {
                fprintf(fw, "[%6d][%12u][%x] [%4x %4x] fifo[%3d %4d]  wvalid %d%d id:%4x data:(%x %8d %8d) sp_awid:%d\n",
                        seq, cycle, state, stack_ptr, coal_id,
                        coal_child_fifo, spill_fifo,
                        wvalid, wready, wid,
                        //buf[i*16+7], buf[i*16+8], buf[i*16+9], buf[i*16+10]
                        wdata_ttype, wdata_ts, wdata_locale, stack_ptr_awid
                       );
            }
            if (bvalid & bready) {
                fprintf(fw, "[%6d][%12u][%x] [%4x %4x] fifo[%3d %4d]  bvalid %d%d id:%4x sp_awid:%d\n",
                        seq, cycle, state, stack_ptr, coal_id,
                        coal_child_fifo, spill_fifo,
                        bvalid, bready, bid, stack_ptr_awid
                       );
            }
        }
    }
    fflush(fw);
    return 0;
}

int log_cq(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID_CQ) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID_CQ << 8) + (DEBUG_CAPACITY), &log_size );
   fpga_pci_peek(pci_bar_handle,  (ID_CQ << 8) + (CQ_GVT_TS), &gvt );
   printf("CQ log size %d gvt %d\n", log_size, gvt);
   if (log_size > 17000) {
       if (log_size <34000) {
            log_size -= 16384;
            printf("CQ log size %d gvt %d\n", log_size, gvt);
       }
       else return 1;
   }
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
            (read_len - read_offset) > 512 ? 512 : (read_len-read_offset),
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
        fprintf(fw, " \t \t %x %x %x %x\n", buf[i*16], buf[i*16+1], buf[i*16+14], buf[i*16+11]);
        unsigned int gvt_ts = buf[i*16+10];
        unsigned int gvt_tb = buf[i*16+11];

        unsigned int abort_ts_check_task = buf[i*16+2] & 1;
        unsigned int ts_check_id = (buf[i*16+2] >> 1) & 0x7f;
        unsigned int check_ts = (buf[i*16+2] >> 8) ;

        unsigned int n_resource_aborts = (buf[i*16+3] >> 0) & 0x1ffffff ;
        unsigned int state = (buf[i*16+3] >> 25) & 0xf ;
        unsigned int to_tq_abort_valid = buf[i*16+3] >> 31;
        unsigned int in_resource_abort = (buf[i*16+3] >> 30 & 1);
        unsigned int to_tq_abort_ready = (buf[i*16+3] >> 29 & 1);

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
        unsigned int undo_task_slot = buf[i*16 + 9] >> 23 & 0x7f;
        unsigned int undo_task_ttype = buf[i*16 + 9] >> 19 & 0xf;
        unsigned int undo_task_locale = buf[i*16 + 9] & 0x7ffff;
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
            fprintf(fw,"[%6d][%10u][%6d:%10u] [%d:%3d,%3d] to_tq_abort ready:%d resource:%d \n",
               seq, cycle,
               gvt_ts, gvt_tb,
               gvt_task_slot_valid, gvt_task_slot, max_vt_slot,
               to_tq_abort_ready, in_resource_abort
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
               undo_task_slot, undo_task_locale, undo_task_ttype,
               undo_task_ready
               );

         }
         if (in_resource_abort) {
             fprintf(fw, "[%6d] in_resource_abort %d %8x state:%d (abort:%d check_id:%3d ts:%d) count:%d \n",
             seq, n_resource_aborts, buf[i*16+2],  state,
             abort_ts_check_task, ts_check_id, check_ts, n_resource_aborts);
         }
    }
   fflush(fw);

   return 0;
}

int log_ddr(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (N_TILES << 16) | (ID_GLOBAL << 8) | (DEBUG_CAPACITY), &log_size );
   printf("DDR log size %d gvt %d\n", log_size, 0);
   fprintf(fw, "DDR log size %d gvt %d\n", log_size, 0);
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
               (read_len - read_offset) > 512 ? 512 : (read_len-read_offset),
               cl_addr);
       read_offset += rc;

       unsigned int* buf = (unsigned int*) log_buffer;
       for (int i=0;i<rc/64;i++) {
           unsigned int seq = buf[i*16 + 0];
           unsigned int cycle = buf[i*16 + 1];

           unsigned int bready = (buf[i*16+2] >> 0) & 0x1;
           unsigned int bvalid = (buf[i*16+2] >> 1) & 0x1;
           unsigned int rready = (buf[i*16+2] >> 2) & 0x1;
           unsigned int rvalid = (buf[i*16+2] >> 3) & 0x1;
           unsigned int arready = (buf[i*16+2] >> 4) & 0x1;
           unsigned int arvalid = (buf[i*16+2] >> 5) & 0x1;
           unsigned int wready = (buf[i*16+2] >> 6) & 0x1;
           unsigned int wvalid = (buf[i*16+2] >> 7) & 0x1;
           unsigned int awready = (buf[i*16+2] >> 8) & 0x1;
           unsigned int awvalid = (buf[i*16+2] >> 9) & 0x1;

           unsigned int bresp = (buf[i*16+2] >> 10) & 0x3;
           unsigned int rresp = (buf[i*16+2] >> 12) & 0x3;
           unsigned int wlast = (buf[i*16+2] >> 14) & 0x1;
           unsigned int rlast = (buf[i*16+2] >> 15) & 0x1;

           unsigned int rdata = buf[i*16+4];
           unsigned int wdata = buf[i*16+5];
           unsigned int araddr = buf[i*16 + 6];
           unsigned int awaddr = buf[i*16 + 7];

           unsigned int bid = (buf[i*16+8] >> 0) & 0xffff;
           unsigned int rid = (buf[i*16+8] >> 16) & 0xffff;
           unsigned int wid = (buf[i*16+9] >> 0) & 0xffff;
           unsigned int awid = (buf[i*16+9] >> 16) & 0xffff;
           unsigned int arid = (buf[i*16+10] >> 0) & 0xffff;

           unsigned int pci_bready = (buf[i*16+10] >> 16) & 0x1;
           unsigned int pci_bvalid = (buf[i*16+10] >> 17) & 0x1;
           unsigned int pci_rready = (buf[i*16+10] >> 18) & 0x1;
           unsigned int pci_rvalid = (buf[i*16+10] >> 19) & 0x1;
           unsigned int pci_arready = (buf[i*16+10] >> 20) & 0x1;
           unsigned int pci_arvalid = (buf[i*16+10] >> 21) & 0x1;
           unsigned int pci_wready = (buf[i*16+10] >> 22) & 0x1;
           unsigned int pci_wvalid = (buf[i*16+10] >> 23) & 0x1;
           unsigned int pci_awready = (buf[i*16+10] >> 24) & 0x1;
           unsigned int pci_awvalid = (buf[i*16+10] >> 25) & 0x1;
           unsigned int pci_rlast = (buf[i*16+10] >> 26) & 0x1;
           unsigned int pci_wlast = (buf[i*16+10] >> 27) & 0x1;
           unsigned int pci_awsize = (buf[i*16+10] >> 28) & 0xf;

           unsigned int pci_araddr = buf[i*16 + 11];
           unsigned int pci_awaddr = buf[i*16 + 12];

           unsigned int pci_rid = (buf[i*16+13] >> 0) & 0xffff;
           unsigned int pci_arid = (buf[i*16+13] >> 16) & 0xffff;
           unsigned int pci_bid = (buf[i*16+14] >> 0) & 0xffff;
           unsigned int pci_wid = (buf[i*16+14] >> 16) & 0xffff;
           unsigned int pci_awid = (buf[i*16+15] >> 0) & 0xffff;
           unsigned int pci_arlen = (buf[i*16+15] >> 16) & 0xff;
           unsigned int pci_awlen = (buf[i*16+15] >> 24) & 0xff;

           bool f = false;
           uint32_t last_awid;
           if (arvalid) {
               fprintf(fw,"[%6d][%10u][%d%d] arvalid addr:%8x id:%4x (%1x:%1x:%2x) \n",
                       seq, cycle,
                       arvalid, arready,
                       araddr, arid,
                       (arid >> 10) & 0xf, (arid >> 8) & 1, arid & 0xff
                      );
               if(arready) arid_cycle[arid] = cycle;
               f = true;
           }
           if (awvalid) {
               fprintf(fw,"[%6d][%10u][%d%d] awvalid addr:%8x id:%4x (%x:%1x:%2x)\n",
                       seq, cycle,
                       awvalid, awready,
                       awaddr, awid,
                       (awid >> 10) & 0xf, (awid >> 8) & 1, awid & 0xff
                      );
               f = true;
           }
           if (wvalid) {
               fprintf(fw,"[%6d][%10u][%d%d]  wvalid data:%8x id:%4x (%x:%1x:%2x)   last awid:%4x mismatch:%d\n",
                       seq, cycle,
                       wvalid, wready,
                       wdata, wid,
                       (wid >> 10) & 0xf, (wid >> 8) & 1, wid & 0xff,
                       last_awid, (last_awid != wid)
                      );
               f = true;
               if (last_awid != wid)
               printf("[%6d][%10u][%d%d]  wvalid data:%8x id:%4x (%x:%1x:%2x)   last awid:%4x mismatch:%d\n",
                       seq, cycle,
                       wvalid, wready,
                       wdata, wid,
                       (wid >> 10) & 0xf, (wid >> 8) & 1, wid & 0xff,
                       last_awid, (last_awid != wid)
                      );
           }
           if (awvalid & awready) last_awid = awid;
           if (rvalid) {
               fprintf(fw,"[%6d][%10u][%d%d]  rvalid data:%8x id:%4x resp:%d delay:%d\n",
                       seq, cycle,
                       rvalid, rready,
                       rdata, rid, rresp,
                       cycle - arid_cycle[rid]
                      );
               f = true;
           }
           if (bvalid) {
               fprintf(fw,"[%6d][%10u][%d%d]  bvalid          id:%4x resp:%d\n",
                       seq, cycle,
                       bvalid, bready,
                       bid, bresp
                      );
               f = true;
           }
           if (pci_awvalid) {
               fprintf(fw,"[%6d][%10u]\t[%d%d] pci_awvalid addr:%8x id:%4x len:%d size:%d\n",
                       seq, cycle,
                       pci_awvalid, pci_awready,
                       pci_awaddr, pci_awid, pci_awlen, pci_awsize
                      );
               f = true;
           }
           if (pci_arvalid) {
               fprintf(fw,"[%6d][%10u]\t[%d%d] pci_arvalid addr:%8x id:%4x len:%d \n",
                       seq, cycle,
                       pci_arvalid, pci_arready,
                       pci_araddr, pci_arid, pci_arlen
                      );
               f = true;
           }
           if (pci_wvalid) {
               fprintf(fw,"[%6d][%10u]\t[%d%d] pci_wvalid id:%4x last:%d\n",
                       seq, cycle,
                       pci_wvalid, pci_wready,
                       pci_wid, pci_wlast
                      );
               f = true;
           }
           if (pci_bvalid) {
               fprintf(fw,"[%6d][%10u]\t[%d%d] pci_bvalid id:%4x\n",
                       seq, cycle,
                       pci_bvalid, pci_bready,
                       pci_bid
                      );
               f = true;
           }
           if (pci_rvalid) {
               fprintf(fw,"[%6d][%10u]\t[%d%d] pci_rvalid id:%4x\n",
                       seq, cycle,
                       pci_rvalid, pci_rready,
                       pci_rid
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

int log_rw_stage(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (DEBUG_CAPACITY), &log_size );
   //fpga_pci_peek(pci_bar_handle,  (ID << 8) + (CQ_GVT_TS), &gvt );
   printf("RW Stage log size %d \n", log_size);
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

           unsigned int out_locale = buf[i*16+2] ;
           unsigned int out_ts = buf[i*16+3] ;
           unsigned int out_object = buf[i*16+4] ;
           unsigned int araddr = buf[i*16+5] ;

           unsigned int in_locale = buf[i*16+6] ;
           unsigned int in_ts = buf[i*16+7] ;

           unsigned int in_ttype = (buf[i*16+8] >> 0) & 0xf;
           unsigned int rid = (buf[i*16+8] >> 4) & 0xfff;
           unsigned int in_thread = (buf[i*16+8] >> 16) & 0xff;
           unsigned int in_cq_slot = (buf[i*16+8] >> 24) & 0xff;

           unsigned int out_thread = (buf[i*16+9] >> 0) & 0xffff;
           unsigned int out_fifo_occ = (buf[i*16+9] >> 16) & 0xff;
           unsigned int rready = (buf[i*16+9] >> 24) & 0x1;
           unsigned int rvalid = (buf[i*16+9] >> 25) & 0x1;
           unsigned int arready = (buf[i*16+9] >> 26) & 0x1;
           unsigned int arvalid = (buf[i*16+9] >> 27) & 0x1;
           unsigned int task_out_ready = (buf[i*16+9] >> 28) & 0x1;
           unsigned int task_out_valid = (buf[i*16+9] >> 29) & 0x1;
           unsigned int task_in_ready = (buf[i*16+9] >> 30) & 0x1;
           unsigned int task_in_valid = (buf[i*16+9] >> 31) & 0x1;

           bool f = false;
           if (task_in_valid & task_in_ready) {
               fprintf(fw,"[%6d][%10u] [%2x] task_in ts:%5d locale:%5d slot %d ttype:%d | fifo:%2d\n",
                   seq, cycle,
                   in_thread,
                   in_ts, in_locale, in_cq_slot, in_ttype, out_fifo_occ
                      );
               f = true;
           }

           if (task_out_valid & task_out_valid) {
               fprintf(fw,"[%6d][%10u] [%2x] task_out ts:%5d locale:%5d data:%10d | fifo:%2d\n",
                   seq, cycle,
                   out_thread,
                   out_ts, out_locale, out_object, out_fifo_occ

                      );
               f = true;
           }

/*
           if (task_out_valid & task_out_valid) {
               fprintf(fw,"[%6d][%10u] [%2x] task_out ts:%5x locale:%5d | ex:%d cm:(%d %d) h:%d v:%x f:(%d %d) eo:%d \n",
                   seq, cycle,
                   out_thread,
                   out_ts, out_locale, buf[i*16+10], buf[i*16+11] & 0xff, buf[i*16+11] >> 24, buf[i*16+12],
                   buf[i*16+13], buf[i*16+14], buf[i*16+15], out_object
                      );
               f = true;
           }


           if (arvalid == 3) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] arvalid %8x rem_word %8x \n",
                       seq, cycle,
                       thread_fifo_occ, thread_id,
                       arid, remaining_words
                      );
               f = true;
           }
           if (rvalid == 3) {
               fprintf(fw,"[%6d][%10u] [%8x %8x]  rvalid %8x \n",
                       seq, cycle,
                       thread_fifo_occ, thread_id,
                       rid
                      );
               f = true;
           }
 */
           /*
               fprintf(fw,"[%6d][%10u] (%d%d%d%d) (%d) (%2x %2x %2x %2x) | (%8x %8x) (%8x %8x - %8x %8x)\n",
                       seq, cycle,
                       task_in_valid, task_out_valid, arvalid, rvalid,
                       out_last,
                       thread_fifo_occ, thread_id, rid, arid,
                       in_task_0 >> 4, in_task_1 >> 4,
                       out_task_0 >> 4, out_task_1 >> 4, out_data_0, out_data_1
                      );
            */
       }

   }
   fflush(fw);
   return 0;
}


int log_ro_stage(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (DEBUG_CAPACITY), &log_size );
   //fpga_pci_peek(pci_bar_handle,  (ID << 8) + (CQ_GVT_TS), &gvt );
   printf("RO Stage log size %d \n", log_size);
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

           unsigned int mem_locale = buf[i*16+2] ;
           unsigned int mem_ts = buf[i*16+3] ;
           unsigned int non_mem_locale = buf[i*16+4] ;
           unsigned int non_mem_ts = buf[i*16+5] ;
           unsigned int non_mem_cq_slot = (buf[i*16+6] >> 0) & 0xff ;
           unsigned int mem_cq_slot = (buf[i*16+6] >> 8) & 0xff ;
           unsigned int non_mem_ttype = (buf[i*16+6] >> 16) & 0xf ;
           unsigned int mem_ttype = (buf[i*16+6] >> 20) & 0xf ;
           unsigned int non_mem_subtype = (buf[i*16+6] >> 24) & 0xf ;
           unsigned int mem_subtype = (buf[i*16+6] >> 28) & 0xf ;
           unsigned int out_locale = buf[i*16+7] ;
           unsigned int out_ts = buf[i*16+8] ;

           unsigned int s_finish_task_ready = (buf[i*16+9] >>0) & 1;
           unsigned int s_out_ready_untied = (buf[i*16+9] >>1) & 1;
           unsigned int s_out_ready_tied = (buf[i*16+9] >>2) & 1;
           unsigned int s_arready = (buf[i*16+9] >>3) & 1;
           unsigned int s_arvalid = (buf[i*16+9] >>4) & 0xf;
           unsigned int s_out_child_untied = (buf[i*16+9] >>8) & 0xf;
           unsigned int s_out_task_is_child = (buf[i*16+9] >>12) & 0xf;
           unsigned int s_out_valid = (buf[i*16+9] >>16) & 0xf;
           unsigned int sched_task_aborted = (buf[i*16+9] >>20) & 0xf;
           unsigned int task_in_ready = (buf[i*16+9] >>24) & 0xf;
           unsigned int task_in_valid = (buf[i*16+9] >>28) & 0xf;

           unsigned int out_ttype = (buf[i*16+10] >>0) & 0xf;
           unsigned int out_child_id = (buf[i*16+10] >>4) & 0xf;
           unsigned int gvt_task_slot = (buf[i*16+10] >>16) & 0xff;
           unsigned int gvt_task_slot_valid = (buf[i*16+10] >>24) & 0x1;
           unsigned int non_mem_task_finish = (buf[i*16+10] >>25) & 0x1;
           unsigned int non_mem_subtype_valid = (buf[i*16+10] >>26) & 0x1;
           unsigned int mem_subtype_valid = (buf[i*16+10] >>27) & 0x1;
           unsigned int rready = (buf[i*16+10] >> 28) & 0x1;
           unsigned int rvalid = (buf[i*16+10] >> 29) & 0x1;
           unsigned int arready = (buf[i*16+10] >> 30) & 0x1;
           unsigned int arvalid = (buf[i*16+10] >> 31) & 0x1;

           unsigned int out_fifo_occ = buf[i*16+11] ;

           unsigned int thread_fifo_occ =  (buf[i*16+12] >> 0) & 0xff ;
           unsigned int thread_id =        (buf[i*16+12] >> 8) & 0xff;
           unsigned int rid =        (buf[i*16+12] >> 16) & 0xff;
           unsigned int arid =        (buf[i*16+12] >> 24) & 0xff;

           unsigned int rid_mshr_valid_words = (buf[i*16+13] );

           unsigned int remaining_words = (buf[i*16+14])& 0xf00fffff;
           unsigned int out_data_word_valid = (buf[i*16+14] >> 20) & 0x3;
           unsigned int rid_thread = (buf[i*16+14] >> 23) & 0x1f;
           unsigned int remaining_words_cur_rid = (buf[i*16+14] >> 28);

           bool f = false;
           if (mem_subtype_valid) {
               fprintf(fw,"[%6d][%10u] [%2x][%1d%1d%1d%1d] mem task_in subtype:%d ts:%5d locale:%5d slot %d fifo:%8x\n",
                   seq, cycle,
                   thread_id,
                   s_arready, s_out_ready_untied, s_out_ready_tied, s_finish_task_ready,
                   mem_subtype, mem_ts, mem_locale, mem_cq_slot,
                   out_fifo_occ
                      );
               f = true;
           }

           if (non_mem_subtype_valid | (task_in_ready & 0x8)) {
               fprintf(fw,"[%6d][%10u] [%2x][%1d%1d%1d%1d][%d %x%x] non-mem task_in subtype:%d ts:%5d locale:%5d slot %d finish:%d ab:%x - child: valid:%x untied:%x id:%d %d %d rem:%2x %x %x\n",
                   seq, cycle,
                   thread_id,
                   s_arready, s_out_ready_untied, s_out_ready_tied, s_finish_task_ready,
                   non_mem_subtype_valid, task_in_valid, task_in_ready,
                   non_mem_subtype, non_mem_ts, non_mem_locale, non_mem_cq_slot, non_mem_task_finish, sched_task_aborted,
                   s_out_task_is_child, s_out_child_untied, out_child_id,
                   out_ts, out_locale,
                   rid_thread, out_data_word_valid, remaining_words_cur_rid
                  );
               f = true;
           }


           if (arvalid & arready) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] arvalid %8x rem_word %8x \n",
                       seq, cycle,
                       thread_fifo_occ, thread_id,
                       arid, remaining_words
                      );
               f = true;
           }
           if (rvalid & rready) {
               fprintf(fw,"[%6d][%10u] [%8x %8x]  rvalid %8x \n",
                       seq, cycle,
                       thread_fifo_occ, thread_id,
                       rid
                      );
               f = true;
           }

           /*
               fprintf(fw,"[%6d][%10u] (%d%d%d%d) (%d) (%2x %2x %2x %2x) | (%8x %8x) (%8x %8x - %8x %8x)\n",
                       seq, cycle,
                       task_in_valid, task_out_valid, arvalid, rvalid,
                       out_last,
                       thread_fifo_occ, thread_id, rid, arid,
                       in_task_0 >> 4, in_task_1 >> 4,
                       out_task_0 >> 4, out_task_1 >> 4, out_data_0, out_data_1
                      );
            */
       }

   }
   fflush(fw);
   return 0;
}

int log_serializer(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (DEBUG_CAPACITY), &log_size );
   //fpga_pci_peek(pci_bar_handle,  (ID << 8) + (CQ_GVT_TS), &gvt );
   printf("Serializer log size %d \n", log_size);
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

           unsigned int free_list_size = (buf[i*16+11] >> 6) & 0x3f;
           unsigned int s_thread = (buf[i*16+11] >> 0) & 0x3f;

           unsigned int s_arvalid = (buf[i*16+10] >> 16) & 0xffff;
           unsigned int s_rvalid = (buf[i*16+10] >> 0) & 0xffff;

           unsigned int s_rdata_locale = (buf[i*16+9]);
           unsigned int s_rdata_ts = (buf[i*16+8]);

           unsigned int s_cq_slot = (buf[i*16+7] >> 25) & 0x7f;
           unsigned int s_rdata_ttype = (buf[i*16+7] >> 21) & 0xf;
           unsigned int finished_task_valid = (buf[i*16+7] >> 20) & 0x1;
           unsigned int finished_task_thread = (buf[i*16+7] >> 14) & 0x3f;

           unsigned int ready_list_valid = (buf[i*16+6]);
           unsigned int ready_list_conflict = (buf[i*16+5]);

           unsigned int m_ts = (buf[i*16+4]);
           unsigned int m_locale = (buf[i*16+3]);

           unsigned int m_ttype = (buf[i*16+2] >> 28) & 0xf;
           unsigned int m_cq_slot = (buf[i*16+2] >> 21) & 0x7f;
           unsigned int m_valid = (buf[i*16+2] >> 20) & 1;
           unsigned int m_ready = (buf[i*16+2] >> 19) & 1;
           unsigned int finished_task_locale_match = (buf[i*16+2] >> 3) & 0xffff;
           bool f = false;
           if (finished_task_valid) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] [%2d] finished_task thread:%2x locale_match:%8x\n",
                       seq, cycle,
                       ready_list_valid, ready_list_conflict,
                       free_list_size,
                       finished_task_thread, finished_task_locale_match
                      );
               f = true;
           }

           if (s_rvalid > 0) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] [%2d] s_ rvalid:%4x ttype:%x ts:%8d locale:%8d slot:%d thread:%d\n",
                       seq, cycle,
                       ready_list_valid, ready_list_conflict,
                       free_list_size,
                       s_rvalid, s_rdata_ttype, s_rdata_ts, s_rdata_locale, s_cq_slot, s_thread
                      );
               f = true;
           }

           if (m_valid & m_ready) {
               fprintf(fw,"[%6d][%10u] [%8x %8x] [%2d] m_ ttype:%x ts:%8d locale:%8d slot:%d\n",
                       seq, cycle,
                       ready_list_valid, ready_list_conflict,
                       free_list_size,
                       m_ttype, m_ts, m_locale, m_cq_slot
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
           unsigned int rvalid = buf[i*16 + 2] >> 5 & 1;
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

           unsigned int finish_task_valid = buf[i*16 + 2] >> 21 & 1;
           unsigned int finish_task_ready = buf[i*16 + 2] >> 20 & 1;
           unsigned int dbus_cmd_size = buf[i*16 +  2] >> 22 & 3;

           unsigned int wstrb_0 = buf[i*16+13];
           unsigned int wstrb_1 = buf[i*16+14];

           //printf(" \t \t %x %x %x %x\n", buf[i*16], buf[i*16+1], buf[i*16+14], buf[i*16+11]);
           if (seq == -1) {
               continue;
           }
            if (dbus_cmd_valid) {
               fprintf(fw,"[%6d][%10u][%08x][%d] req %d%d wr:%d addr:%08x data:%08x size:%d\n",
                  seq, cycle, pc, state,
                  dbus_cmd_valid, dbus_cmd_ready,
                  dbus_cmd_wr,
                  dbus_cmd_addr,
                  dbus_cmd_data,
                  dbus_cmd_size
                  );
            }
             if (dbus_rsp_valid) {
                fprintf(fw,"[%6d][%10u][%08x][%d] rsp %d data:%08x\n",
                   seq, cycle, pc, state,
                   dbus_rsp_valid,
                   dbus_rsp_data
                   );
             }
             if (awvalid) fprintf(fw, "[%6d][%10u][%08x] awvalid %08x %d\n",
                     seq, cycle, pc, awaddr, awid);
             if (wvalid) fprintf(fw, "[%6d][%10u][%08x] wvalid %08x wstrb:%8x_%8x\n",
                     seq, cycle, pc, wdata, wstrb_1, wstrb_0);
             if (awready) fprintf(fw, "[%6d][%10u][%08x] awready\n", seq, cycle, pc);
             if (bvalid) fprintf(fw, "[%6d][%10u][%08x][%d] bvalid id:%d %d\n", seq, cycle, pc, state, bid);
             //if (bready) fprintf(fw, "[%6d][%10u][%08x] bready\n", seq, cycle, pc);
             if (wready) fprintf(fw, "[%6d][%10u][%08x] wready\n", seq, cycle, pc);
             if (arvalid) fprintf(fw, "[%6d][%10u][%08x][%d] arvalid\n", seq, cycle, pc, state);
             if (rvalid) fprintf(fw, "[%6d][%10u][%08x][%d]  rvalid\n", seq, cycle, pc, state);
             if (finish_task_valid) fprintf(fw, "[%6d][%10u][%08x][%d] [%d%d] finish_task_valid\n",
                     seq, cycle, pc, state, finish_task_valid, finish_task_ready);
        }
   }
    fflush(fw);
   return 0;
}

void serializer_stats(uint32_t tile, uint32_t ID_SERIALIZER) {
    uint32_t no_task =0;
    uint32_t cq_stall = 0;
    uint32_t task_issued = 0;
    uint32_t task_not_accepted = 0;
    uint32_t no_thread = 0;
    uint32_t cr_full = 0;

    uint32_t cr_full_all = 0;

    pci_peek(tile, ID_SERIALIZER, SERIALIZER_STAT + 0 ,&no_task);
    pci_peek(tile, ID_SERIALIZER, SERIALIZER_STAT + 4 ,&cq_stall);
    pci_peek(tile, ID_SERIALIZER, SERIALIZER_STAT + 8 ,&task_issued);
    pci_peek(tile, ID_SERIALIZER, SERIALIZER_STAT + 12 ,&task_not_accepted);
    pci_peek(tile, ID_SERIALIZER, SERIALIZER_STAT + 16 ,&no_thread);
    pci_peek(tile, ID_SERIALIZER, SERIALIZER_STAT + 20 ,&cr_full);

    pci_peek(tile, ID_SERIALIZER, SERIALIZER_STAT + 24 ,&cr_full_all);

    printf("no_task  : %9d cq_stall: %9d task_issued   : %9d\n", no_task, cq_stall, task_issued);
    printf("no_thread: %9d cr_full : %9d task_not_taken: %9d\n", no_thread, cr_full, task_not_accepted);
    printf("cr_full_all %9d\n", cr_full_all);


}

void task_unit_stats(uint32_t tile, uint32_t tot_cycles) {

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
    pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_N_CYCLES_DEQ_VALID
            ,&n_cycles_deq_valid);
    uint32_t avg_tasks;
    uint32_t avg_heap_util;
    pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_AVG_TASKS, &avg_tasks);
    pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_STAT_AVG_HEAP_UTIL, &avg_heap_util);
    printf("Cum Tasks:%10d heap_util:%10d\n", avg_tasks, avg_heap_util);
    if (tot_cycles > 0) {
        printf("avg Tasks:%5.2f heap_util:%5.2f\n",
                ((avg_tasks +0.0) / tot_cycles)*65536,
                ((avg_heap_util +0.0) / tot_cycles)*65536);
    }

    uint32_t heap_op_stats[8];
    uint32_t total_heap_ops=0;
    for (int i=1;i<8;i++) {
        pci_poke(tile, ID_TASK_UNIT, TASK_UNIT_SET_STAT_ID, i);
        pci_peek(tile, ID_TASK_UNIT, TASK_UNIT_HEAP_OP_STAT_READ, &heap_op_stats[i]);
        total_heap_ops += heap_op_stats[i];
    }
    printf("heap     enq:%9d  deq:%9d  replace:%9d\n", heap_op_stats[1], heap_op_stats[2], heap_op_stats[3]);
    printf("heap deq_max:%9d +enq:%9d +replace:%9d\n", heap_op_stats[4], heap_op_stats[5], heap_op_stats[7]);
    printf("Total heap ops: %d\n", total_heap_ops);

    printf("cycles deq_valid:%9d\n", n_cycles_deq_valid);

    // RW_Read stats;
    /*
    uint32_t rw_read_stats[10] = {0};
    uint32_t rw_write_stats[10] = {0};
    uint32_t ro_stats[10] = {0};
    for (int i=0;i<10;i++) {
        pci_peek(tile, 1, 0x80 + (i*4), &(rw_read_stats[i]));
        pci_peek(tile, 2, 0x80 + (i*4), &(rw_write_stats[i]));
        pci_peek(tile, 3, 0x80 + (i*4), &(ro_stats[i]));
    }
    for (int i=0;i<10;i++) {
        printf("%2x: %9d %9d %9d\n", 0x80 + (i*4),
                rw_read_stats[i], rw_write_stats[i], ro_stats[i] );
    }
    */

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
    /*
    for (int i=0;i<16;i++) {
        pci_poke(tile, ID_CQ, CQ_LOOKUP_ENTRY, i);
        pci_peek(tile, ID_CQ, CQ_DEQ_TASK_STATS, &ttype_stat_deq);
        pci_peek(tile, ID_CQ, CQ_COMMIT_TASK_STATS, &ttype_stat_commit);
        printf("ttype:%d deq:%9d commit:%9d\n",i, ttype_stat_deq, ttype_stat_commit);

    }*/

    uint32_t conflict_none, conflict_bypassed, conflict_miss, conflict_real;
    pci_peek(tile, ID_CQ, CQ_N_TASK_NO_CONFLICT, &conflict_none);
    pci_peek(tile, ID_CQ, CQ_N_TASK_CONFLICT_MITIGATED, &conflict_bypassed);
    pci_peek(tile, ID_CQ, CQ_N_TASK_CONFLICT_MISS, &conflict_miss);
    pci_peek(tile, ID_CQ, CQ_N_TASK_REAL_CONFLICT, &conflict_real);

    printf("conflict none:%d bypass:%d miss:%d real:%d\n", conflict_none, conflict_bypassed, conflict_miss, conflict_real);

    // calculate CQ cycle breakdown;
    if (0 & tot_cycles>0) {
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

        uint32_t commit_cycles_h, commit_cycles_l;
        uint32_t abort_cycles_h, abort_cycles_l;
        pci_peek(tile, ID_CQ, CQ_N_CUM_COMMIT_CYCLES_H, &commit_cycles_h);
        pci_peek(tile, ID_CQ, CQ_N_CUM_COMMIT_CYCLES_L, &commit_cycles_l);
        pci_peek(tile, ID_CQ, CQ_N_CUM_ABORT_CYCLES_H, &abort_cycles_h);
        pci_peek(tile, ID_CQ, CQ_N_CUM_ABORT_CYCLES_L, &abort_cycles_l);
        uint64_t commit_cycles = commit_cycles_h;
        commit_cycles = (commit_cycles << 32) + commit_cycles_l;
        uint64_t abort_cycles = abort_cycles_h;
        abort_cycles = (abort_cycles << 32) + abort_cycles_l;

        printf("cum commit_cycles:%15ld cum_abort_cycles:%15ld\n",
                commit_cycles, abort_cycles
                );

    }

    uint32_t occ_lsb, occ_msb;
    pci_peek(tile, ID_CQ, CQ_CUM_OCC_LSB, &occ_lsb);
    pci_peek(tile, ID_CQ, CQ_CUM_OCC_MSB , &occ_msb);
    double avg_occ = (occ_lsb + 0.0)/tot_cycles;
    avg_occ *= (1<<LOG_CQ_SIZE);
    printf("CQ occ (%10d %10d) , %5f\n", occ_msb, occ_lsb,
            avg_occ);


    return;
    pci_poke(tile, ID_CQ, CQ_LOOKUP_MODE , 1);
    for (int i=0;i<128;i++) {
        uint32_t ts,tb, state, locale;
        pci_poke(tile, ID_CQ, CQ_LOOKUP_ENTRY, i);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_STATE, &state);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_TS, &ts);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_TB, &tb);
        pci_peek(tile, ID_CQ, CQ_LOOKUP_LOCALE, &locale);
        printf(" (%3d: %2d %5d:%10u %8x)", i, state,ts,tb, locale);
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
    /*
    const int NON_IDLE_TIME_INDEX = 79;
    const int SUM_INDEX = 80;
    const int MEM_STALL_INDEX = 81;
    const int ENQ_STALL_INDEX = 82;
    const int CQ_STALL_INDEX = 83;
    const int USEFUL_WORK_INDEX = 84;
    uint32_t core_state_stats[20][128];
    uint32_t wrapper_state_stats[20][8];
    for (int i=0;i<=N_SSSP_CORES;i++) {
        uint32_t sum_all = 0;
        uint32_t mem_stall =0;
        uint32_t enq_stall = 0;
        for (int j=0;j<64;j++) {
            pci_poke(tile, i+1, CORE_QUERY_STATE , j);
            pci_peek(tile, i+1, CORE_AP_STATE_STATS , &(core_state_stats[i][j]));
            if (j<8) pci_peek(tile, i+1, CORE_STATE_STATS , &(wrapper_state_stats[i][j]));
            sum_all += core_state_stats[i][j];
        }
        core_state_stats[i][NON_IDLE_TIME_INDEX] = sum_all - core_state_stats[i][0];
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
    for (int j=0;j<8;j++) {
        printf("W%d:", j);
        for (int i=0;i<N_SSSP_CORES;i++) {
            printf("%10d ", wrapper_state_stats[i][j]);
        }
        printf("\n");
    }
    */
}

int log_pci(pci_bar_handle_t pci_bar_handle, int fd, FILE* fw, unsigned char* log_buffer, uint32_t ID) {

   uint32_t log_size;
   uint32_t gvt;
   fpga_pci_peek(pci_bar_handle,  (ID << 8) + (DEBUG_CAPACITY), &log_size );
   printf("PCI log size %d %x \n", log_size, ID);
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


           unsigned int arready = (buf[i*16+2] >> 0) & 1;
           unsigned int arvalid = (buf[i*16+2] >> 1) & 1;
           unsigned int wready = (buf[i*16+2] >> 2) & 1;
           unsigned int wvalid = (buf[i*16+2] >> 3) & 1;
           unsigned int awready = (buf[i*16+2] >> 4) & 1;
           unsigned int awvalid = (buf[i*16+2] >> 5) & 1;
           unsigned int arsize = (buf[i*16+2] >> 6) & 0xf;
           unsigned int arlen = (buf[i*16+2] >> 10) & 0xff;
           unsigned int awsize = (buf[i*16+2] >> 18) & 0xf;
           unsigned int awlen = (buf[i*16+2] >> 22) & 0xff;
           unsigned int wlast = (buf[i*16+2] >> 30) & 0x1;
           unsigned int wdata = buf[i*16+3] ;
           unsigned int wid = buf[i*16+4] ;
           unsigned int awid = buf[i*16+5] ;
           unsigned int arid = buf[i*16+6] ;
           unsigned int araddr = buf[i*16+7] ;
           unsigned int awaddr = buf[i*16+8] ;
           unsigned int wstrb_1 = buf[i*16+9];
           unsigned int wstrb_2 = buf[i*16+10];
           if (awvalid) {
               fprintf(fw,"[%6d][%10u] awvalid [%1d%1d] size:%3d  len:%4d addr:%8x id:%8x\n",
                       seq, cycle,
                       awvalid, awready,
                       awsize, awlen, awaddr, awid
                      );
           }
           if (wvalid) {
               fprintf(fw,"[%6d][%10u]  wvalid [%1d%1d] wlast:%1d  wdata:%8x wid:%8x wstrb:%08x_%08x\n",
                       seq, cycle,
                       wvalid, wready,
                       wlast, wdata, wid,
                       wstrb_1, wstrb_2
                      );
           }

       }

   }
   fflush(fw);
   return 0;
}

