#include "silo.h"

uint32_t num_tx;
uint32_t* tx_offset;
uint32_t* tx_data;

uint32_t n_warehouses;
uint32_t size_warehouse_ro;
warehouse_ro* warehouses;
uint32_t n_districts_per_warehouse;
uint32_t size_district_ro;
uint32_t size_district_rw;
district_ro* districts_ro;
district_rw* districts_rw;

__attribute__((align(64))) fifo_table_info tbl_new_order;

table_info tbl_cust_ro;
table_info tbl_cust_rw;
table_info tbl_order;
table_info tbl_order_line;
table_info tbl_item;
table_info tbl_stock;


#define TX_ENQUEUER_TASK  0
#define NEW_ORDER_UPDATE_DISTRICT 1
#define NEW_ORDER_INSERT_NEW_ORDER 2
#define NEW_ORDER_INSERT_ORDER 3
#define NEW_ORDER_ENQ_OL_CNT 4
#define NEW_ORDER_UPDATE_STOCK 5
#define NEW_ORDER_INSERT_ORDER_LINE 6

#define LOCALE_DISTRICT (1<<20)
#define LOCALE_NEW_ORDER (2<<20)
#define LOCALE_ORDER (3<<20)
#define LOCALE_STOCK (4<<20)
#define LOCALE_ORDER_LINE (5<<20)

uint32_t* chronos_mem = 0;


// gets a ptr into a data structure in chronos memory located
// starting at word 'offset'
void* chronos_ptr(int offset) {
   uint32_t addr = chronos_mem[offset];
   printf("chronos_ptr %x\n", addr);
   return (void*) &chronos_mem[addr];
}


void fill_tbl_header(struct table_info* tbl, int offset) {
   uint32_t word_1 = chronos_mem[offset];
   tbl->log_bucket_size = word_1 >> 24;
   tbl->log_num_buckets = (word_1 >> 16) & 0xff;
   tbl->record_size = word_1 & 0xffff;
   tbl->table_base = chronos_mem[offset+1];
}

void get_bucket(table_info* tbl, uint32_t pkey, uint32_t* bucket, uint32_t* offset) {
   uint32_t hash = hash_key(pkey);
   *bucket = (hash >> tbl->log_bucket_size) & ( (1<<tbl->log_num_buckets)-1);
   *offset = hash & ( (1<<tbl->log_bucket_size)-1);
}

void* find_record(table_info* tbl, uint32_t pkey, uint32_t bucket, uint32_t offset) {
   uint32_t bucket_size_bytes = size_of_field(1<<(tbl->log_bucket_size) , tbl->record_size);

   uint32_t bucket_begin = tbl->table_base + bucket_size_bytes * bucket/4;
   while(true) {
      uint32_t addr = bucket_begin + tbl->record_size*offset/4;
      uint32_t cmpkey = chronos_mem[addr];
      //printf("\t %d %lx %lx %d\n", offset, pkey, cmpkey, addr);
      if ((cmpkey == pkey) || (cmpkey == ~0)) {
         return (void *) &chronos_mem[addr];
      } else {
         offset++;
         if (offset == (1<<tbl->log_bucket_size)) offset = 0;
      }
   }
}

void* get_record(table_info* tbl, uint32_t pkey){
   uint32_t bucket, offset;
   get_bucket(tbl, pkey, &bucket, &offset);
   return find_record(tbl, pkey, bucket, offset);
}

void tx_enqueuer_task(uint32_t ts, uint32_t locale, uint32_t start) {
   if (start + 7 < num_tx) {
      //enq_task_arg1(TX_ENQUEUER_TASK, (start+7)<<8, locale, start+7);
   }
   int end = start+7; if (num_tx < end) end = num_tx;
   for (int i=start;i<end;i++) {
      struct tx_info_new_order* tx_info = (tx_info_new_order*) (&tx_data[tx_offset[i]]);
      //printf("offset %d %d %x\n", i, tx_offset[i], tx_data[tx_offset[i]]);
      enq_task_arg2(NEW_ORDER_UPDATE_DISTRICT, (i<<8), LOCALE_DISTRICT | (tx_info->d_id << 4) , i,
            *(uint32_t*) tx_info);
   }
}

void new_order_update_district(uint32_t ts, uint32_t locale, uint32_t tx_id, uint32_t _tx_info) {
   uint32_t d = (locale >> 4) & 0xf;
   uint32_t d_next_o_id = districts_rw[d].d_next_o_id++;
   printf("\td_next_o_id %d %d\n", d, d_next_o_id);
   enq_task_arg2(NEW_ORDER_INSERT_NEW_ORDER, ts, LOCALE_NEW_ORDER, _tx_info, d_next_o_id);
   // get bucket id for order
   order o;
   tx_info_new_order tx_info = *(tx_info_new_order* ) &_tx_info;
   o.o_d_id = tx_info.d_id;
   o.o_w_id = tx_info.w_id;
   o.o_id = d_next_o_id;
   uint32_t pkey = *(uint32_t*) &o;

   uint32_t bucket, offset;
   get_bucket(&tbl_order, pkey, &bucket, &offset);
   enq_task_arg2(NEW_ORDER_INSERT_ORDER, ts, LOCALE_ORDER | (bucket << 4), pkey,
         (offset << 16) | tx_info.c_id);

   // enq ol_cnt enqueuers
   for (int i=0;i<tx_info.num_items;i+=4) {
      enq_task_arg2(NEW_ORDER_ENQ_OL_CNT, ts, locale /* RO */, tx_id,
            (i << 24) | d_next_o_id );
   }

}


void new_order_insert_new_order(uint32_t ts, uint32_t locale, uint32_t _tx_info, uint32_t o_id) {
   struct new_order* fifo = (struct new_order*) tbl_new_order.fifo_base;
   struct tx_info_new_order tx_info = *(tx_info_new_order* ) &_tx_info;
   struct new_order n = {o_id, tx_info.d_id, tx_info.w_id};
   fifo[tbl_new_order.wr_ptr] = n;
   tbl_new_order.wr_ptr++;
}

void new_order_insert_order(uint32_t ts, uint32_t locale, uint32_t pkey, uint32_t offset_cid) {
   // find start of bucket data
   uint32_t offset = offset_cid >> 16;
   uint32_t bucket = (locale >> 4) & 0xffff;
   order* order_ptr = (order*) find_record(&tbl_order, pkey, bucket, offset);

   uint32_t* o_int_ptr = (uint32_t*) order_ptr;
   o_int_ptr[0] = pkey;
   order_ptr->o_c_id = (offset_cid & 0xffff);
   printf("\tinsert_order %d %d %d %d\n", tbl_order.table_base, bucket, offset, order_ptr->o_c_id);

}


void new_order_item_enqueuer(uint32_t ts, uint32_t locale, uint32_t tx_id, uint32_t index_o_id) {
   uint32_t offset = tx_offset[tx_id];
   uint32_t start_index = (index_o_id >> 24);
   struct tx_info_new_order* tx_info = (tx_info_new_order*) (&tx_data[offset]);
   int end_index = start_index + 4;
   if (end_index > tx_info->num_items) end_index = tx_info->num_items;
   for (int i = start_index; i<end_index;i++) {
      struct tx_info_new_order_item* tx_item = (tx_info_new_order_item*) (&tx_data[offset+i]+1);

      // Read item price
      uint32_t pkey = tx_item->i_id;
      item* item_ptr = (item*) get_record(&tbl_item, pkey);
      printf("\titem %d %d %d\n", i, pkey, item_ptr->i_price);


      // Enq update stock task
      stock s;
      s.s_i_id = tx_item->i_id;
      s.s_w_id = tx_item->i_s_wid;
      uint32_t stock_pkey = *(uint32_t*) &s;
      uint32_t bucket, offset;
      get_bucket(&tbl_stock, stock_pkey, &bucket, &offset);
      enq_task_arg2(NEW_ORDER_UPDATE_STOCK, ts + i, LOCALE_STOCK | (bucket << 4), stock_pkey,
            (offset << 16) | tx_item->i_qty );


      // insert order line
      order_line ol;
      ol.ol_o_id = (index_o_id & 0xffffff);
      ol.ol_number = i;
      ol.ol_w_id = tx_info->w_id;
      ol.ol_d_id = tx_info->d_id;
      uint32_t ol_pkey = *(uint32_t*) &ol;
      uint32_t amt = tx_item->i_qty * item_ptr->i_price;
      get_bucket(&tbl_order_line, ol_pkey, &bucket, &offset);
      enq_task_arg3(NEW_ORDER_INSERT_ORDER_LINE, ts + i, LOCALE_ORDER_LINE | (bucket << 4), ol_pkey,
            (offset << 24 ) | tx_item->i_id,
            (tx_item->i_s_wid << 24 ) | (tx_item->i_qty << 16) | amt);

   }

}

void new_order_update_stock(uint32_t ts, uint32_t locale, uint32_t pkey, uint32_t offset_quantity) {
   uint32_t offset = offset_quantity >> 16;
   uint32_t bucket = (locale >> 4) & 0xffff;

   uint32_t qty = offset_quantity & 0xffff;

   stock* stock_ptr = (stock*) find_record(&tbl_stock, pkey, bucket, offset);
   printf("\t stock %d %d\n", stock_ptr->s_i_id, stock_ptr->s_quantity);

   stock_ptr->s_ytd++;
   int new_qty = (stock_ptr->s_quantity - qty);
   if (new_qty < 10) new_qty += 91;
   stock_ptr->s_quantity = new_qty;
   // TODO To update s_remote_cnt need to pass in o_wid
}

void new_order_insert_order_line(uint32_t ts, uint32_t locale, uint32_t pkey, uint32_t offset_i_id,
      uint32_t wid_qty_amt) {

   uint32_t offset = offset_i_id >> 24;
   uint32_t bucket = (locale >> 4) & 0xffff;
   order_line* order_line_ptr = (order_line*) find_record(&tbl_order_line, pkey, bucket, offset);

   uint32_t* o_int_ptr = (uint32_t*) order_line_ptr;
   o_int_ptr[0] = pkey;
   order_line_ptr->ol_supply_w_id = (wid_qty_amt >> 24);
   order_line_ptr->ol_i_id = offset_i_id & 0xffffff;
   order_line_ptr->ol_quantity = (wid_qty_amt >> 16) & 0xff;
   order_line_ptr->ol_amount = wid_qty_amt & 0xffff;
   printf("\tinsert_order_line %d %d %d %d\n",
      tbl_order_line.table_base, bucket, offset, order_line_ptr->ol_i_id);
   order_line* p1 = (order_line*) get_record(&tbl_order_line, pkey);
   printf("\t %d\n", p1->ol_i_id);
}


int main() {
   chronos_init();

#ifndef RISCV
   // Simulator code
   const char* fname = "../../tools/silo_gen/silo_tx";
   FILE* fp = fopen(fname, "rb");
   // obtain file size:
   fseek (fp , 0 , SEEK_END);
   long lSize = ftell (fp);
   printf("File %p size %ld\n", fp, lSize);
   rewind (fp);
   chronos_mem = (uint32_t*) malloc(lSize);
   fread( (void*) chronos_mem, 1, lSize, fp);
   enq_task_arg1(TX_ENQUEUER_TASK, 0, 0, 0);
#endif

   // Dereference the pointers to array base addresses.
   // ( The '<<2' is because graph_gen writes the word number, not the byte)

   num_tx = chronos_mem[1];
   tx_offset = (uint32_t*) chronos_ptr(2);
   tx_data  = (uint32_t*) chronos_ptr(3);
   n_warehouses = chronos_mem[4];
   size_warehouse_ro = chronos_mem[5];
   warehouses = (warehouse_ro*) chronos_ptr(6);
   n_districts_per_warehouse = chronos_mem[7];
   size_district_ro = chronos_mem[8];
   size_district_rw = chronos_mem[9];
   districts_ro = (district_ro*) chronos_ptr(10);
   districts_rw = (district_rw*) chronos_ptr(11);

   tbl_new_order.fifo_base =  chronos_ptr(24);
   tbl_new_order.num_records = chronos_mem[25] >> 16;
   tbl_new_order.record_size = chronos_mem[25] & 0xffff;
   tbl_new_order.wr_ptr = chronos_mem[chronos_mem[26]];
   tbl_new_order.rd_ptr = chronos_mem[chronos_mem[26]+1];

   fill_tbl_header(&tbl_cust_ro, 12);
   fill_tbl_header(&tbl_cust_rw, 14);
   fill_tbl_header(&tbl_order, 16);
   fill_tbl_header(&tbl_order_line, 18);
   fill_tbl_header(&tbl_item, 20);
   fill_tbl_header(&tbl_stock, 22);

   printf("new order wr_ptr %d, rd_ptr %d\n",
         tbl_new_order.wr_ptr, tbl_new_order.rd_ptr);
   printf("order %d %d %d\n", tbl_order.log_bucket_size, tbl_order.log_num_buckets, tbl_order.record_size);

   uint ttype, ts, locale, arg0, arg1, arg2;
   while (1) {
      deq_task_arg3(&ttype, &ts, &locale, &arg0, &arg1, &arg2);
      if (ttype == -1) break;
      switch(ttype){
          case TX_ENQUEUER_TASK:
              tx_enqueuer_task(ts, locale, arg0);
              break;
          case NEW_ORDER_UPDATE_DISTRICT:
              new_order_update_district(ts, locale, arg0, arg1);
              break;
          case NEW_ORDER_INSERT_NEW_ORDER:
              new_order_insert_new_order(ts, locale, arg0, arg1);
              break;
          case NEW_ORDER_INSERT_ORDER:
              new_order_insert_order(ts, locale, arg0, arg1);
              break;
          case NEW_ORDER_ENQ_OL_CNT:
              new_order_item_enqueuer(ts, locale, arg0, arg1);
              break;
          case NEW_ORDER_UPDATE_STOCK:
              new_order_update_stock(ts, locale, arg0, arg1);
              break;
          case NEW_ORDER_INSERT_ORDER_LINE:
              new_order_insert_order_line(ts, locale, arg0, arg1, arg2);
              break;

          default:
              break;
      }

      finish_task();
   }
   return 0;
}

