#include "silo_gen.h"

const int n_warehouses = 1;
const int n_districts_per_warehouse = 10;
const int n_districts = n_warehouses * n_districts_per_warehouse;
const int num_customers_per_district = 3000;
const int num_items = 100000;
const int num_tx = 1000;

// Warehouse and Distric tables are simple arrays.


warehouse_ro warehouses[n_warehouses];
district_ro districts_ro[n_districts];
district_rw districts_rw[n_districts];

// {bucket_size, num_buckets}
table_info tbl_cust_ro = {8, 8, sizeof(customer_ro), 0};
table_info tbl_cust_rw = {8, 8, sizeof(customer_rw), 0};
table_info tbl_order = {8, 8, sizeof(order), 0};
table_info tbl_order_line = {8, 14, sizeof(order_line), 0};
table_info tbl_item = {8, 9, sizeof(item), 0};
table_info tbl_stock = {8, 12, sizeof(stock), 0};
fifo_table_info tbl_new_order = {0, 65536, sizeof(new_order), 0};
fifo_table_info tbl_history = {0, 65536, sizeof(history), 0};

uint32_t* tx_offset;
std::vector<uint32_t> tx_data;

uint64_t headers[64];

void initialize_table(table_info* table) {
   int num_entries = (1<<(table->log_bucket_size + table->log_num_buckets));
   table->table_base = (uint8_t*) malloc(table->record_size * num_entries);
   for (int i=0;i<num_entries;i++) {
      *((uint32_t*) (table->table_base + i*table->record_size)) = ~0;
   }
}
void initialize_fifo(fifo_table_info* fifo) {
   fifo->fifo_base = ((uint8_t*) malloc(fifo->record_size * fifo->num_records));
   fifo->addr_pointer = ((uint32_t*) malloc(32*2));
   fifo->addr_pointer[0] = 0;
   fifo->addr_pointer[1] = 0;
}
void insert_fifo_record(fifo_table_info* fifo, void* value) {
   uint8_t* rec_begin = (fifo->fifo_base + fifo->addr_pointer[0]* fifo->record_size);
   memcpy( (void*) rec_begin, value, fifo->record_size);
   fifo->addr_pointer[0]++;
   if (fifo->addr_pointer[0] == fifo->num_records) fifo->addr_pointer[0] = 0;

}

void insert_record(table_info* table, void* value) {
   uint32_t key = *((uint32_t*)(value));
   int hash = hash_key(key);
   int offset = hash & ( (1<<table->log_bucket_size)-1);
   int bucket = (hash >> table->log_bucket_size) & ( (1<<table->log_num_buckets)-1);

   uint32_t bucket_size_bytes = size_of_field(1<<(table->log_bucket_size) , table->record_size);
   //printf("%lx: %8x %d %d \n", key, hash, offset, bucket);
   while(true) {
      uint8_t* rec_begin = (table->table_base +  bucket_size_bytes*bucket + offset* table->record_size);
      uint32_t rec_key = *(uint32_t*) (rec_begin);
      if (rec_key == ~0u) {
         memcpy( (void*) rec_begin, value, table->record_size);
         break;
      } else {
         offset++;
         //printf("\t %d %lx\n", index, rec_key);
         if (offset == (1<<table->log_bucket_size)) offset = 0;
      }
   }
}


void initialize_warehouse() {
   for (int i=0;i<n_warehouses;i++) {
      warehouses[i].w_tax = RandomNumber(0,2000);
   }
}
void initialize_districts() {
   for (int i=0;i<n_warehouses;i++) {
      for (int j=0;j<n_warehouses * n_districts_per_warehouse;j++) {
         int index = i*n_districts_per_warehouse + j;
         districts_ro[index].d_tax = RandomNumber(0,2000);
         printf("d tax %d\n", districts_ro[index].d_tax);
         districts_rw[index].d_next_o_id = 3001;
         districts_rw[index].d_ytd = 30000;
      }
   }
}
void initialize_customers() {
   printf("Initializing Customers\n");
   initialize_table(&tbl_cust_ro);
   initialize_table(&tbl_cust_rw);
   for (int w=0;w<n_warehouses;w++) {
      for (int d=0;d<n_warehouses * n_districts_per_warehouse;d++) {
         for (int c=1;c<=3000;c++) {
            customer_ro ro;
            customer_rw rw;
            ro.c_id = c;
            ro.c_d_id = d;
            ro.c_w_id = w;
            ro.c_discount = RandomNumber(0,2000);
            insert_record(&tbl_cust_ro, &ro);

            rw.c_id = c;
            rw.c_d_id = d;
            rw.c_w_id = w;
            rw.c_balance = -10;
            rw.c_ytd_payment = 10;
            rw.c_payment_cnt = 1;
            rw.c_delivery_cnt = 0;

            insert_record(&tbl_cust_rw, &rw);
         }
      }
   }
}

void initialize_order() {

   printf("Initializing Orders\n");
   initialize_table(&tbl_order);
   initialize_table(&tbl_order_line);
   initialize_fifo(&tbl_new_order);

   int* c_ids = (int*) malloc(sizeof(int)*3000);
   for (int w=0;w<n_warehouses;w++) {
      for (int d=0;d<n_warehouses * n_districts_per_warehouse;d++) {
         // shuffle customer ids
         for (int i=0;i<3000;i++) c_ids[i] = i+1;
         for (int i=0;i<2999;i++) {
            int j= RandomNumber(i, 3000);
            int t = c_ids[j]; c_ids[j] = c_ids[i]; c_ids[i]  = t;
         }
         for (int c=1;c<=3000;c++) {
            order o_entry;
            o_entry.o_id = c;
            o_entry.o_d_id = d;
            o_entry.o_w_id = w;
            o_entry.o_c_id = c_ids[c-1];
            if (c<2101) o_entry.o_carrier_id = RandomNumber(1,10);
            else o_entry.o_carrier_id = 0;
            o_entry.o_ol_cnt = RandomNumber(5,15);
            o_entry.o_all_local = 1;
            insert_record(&tbl_order, &o_entry);

            if (c>=2101) {
               new_order no;
               no.no_w_id = w;
               no.no_d_id = d;
               no.no_o_id = c;
               insert_fifo_record(&tbl_new_order, &no);
            }

            if (c>= 2101) {
               // insert to new order
            }
            for (int l = 1; l<= o_entry.o_ol_cnt;l++) {
               order_line ol;
               ol.ol_o_id = c;
               ol.ol_d_id = d;
               ol.ol_w_id = w;
               ol.ol_number = l;
               ol.ol_i_id = RandomNumber(1, 100000);
               ol.ol_supply_w_id = w;
               ol.ol_quantity = 5;
               ol.ol_amount = (c<2101) ? 0 : RandomNumber(1, 999999);

               insert_record(&tbl_order_line, &ol);
            }

         }

      }
   }

}

void initialize_item() {
   initialize_table(&tbl_item);
   for (int i=1;i<=num_items;i++){
      item it;
      it.i_id = i;
      it.i_price = RandomNumber(100,10000);
      insert_record(&tbl_item, &it);
   }
}

void initialize_stock() {
   initialize_table(&tbl_stock);
   for (int w=0;w<n_warehouses;w++) {
      for (int i=1;i<=num_items;i++){
         stock s;
         s.s_i_id = i;
         s.s_quantity = RandomNumber(10, 100);
         s.s_w_id = w;
         s.s_ytd = 0;
         s.s_order_cnt = 0;
         s.s_remote_cnt = 0;
         insert_record(&tbl_stock, &s);
      }
   }
}

void generate_tx() {
   tx_offset = (uint32_t*) malloc((num_tx+1)*4);
   for (int t=0;t<num_tx;t++) {
      int rnd = RandomNumber(1,100);
      tx_offset[t] = tx_data.size();
      //printf("%d %d\n", t, tx_data.size());
      if (rnd <=100) {
         // new order
         tx_info_new_order tx;
         tx.tx_type = 0;
         tx.w_id = (n_warehouses==1)?0 : RandomNumber(0, n_warehouses-1);
         tx.d_id = RandomNumber(0, n_districts_per_warehouse);
         tx.c_id = NonUniformRandom(1023, 259, 1, num_customers_per_district);
         tx.num_items = RandomNumber(5,15);
         tx_data.push_back( *((uint32_t*) &tx));
         for (int i=0;i<tx.num_items;i++) {
            tx_info_new_order_item tx_item;
            tx_item.i_id = NonUniformRandom(8191, 7911, 1, num_items);
            tx_item.i_qty = RandomNumber(1, 10);
            if (n_warehouses==1) {
               tx_item.i_s_wid = tx.w_id;
            } else {
               do {
                  tx_item.i_s_wid = RandomNumber(0, n_warehouses-1);
               } while (tx_item.i_s_wid == tx.w_id);
            }
            tx_data.push_back( *((uint32_t*) &tx_item));
         }
      } else {
         // TODO
      }


   }
   tx_offset[num_tx] = tx_data.size();
}

void fill_table(table_info* tbl, uint32_t start_index, uint32_t* data, uint32_t base) {
   printf(" %d %d %d\n", start_index, tbl->log_num_buckets, tbl->record_size);
   data[start_index] = ( (tbl->log_bucket_size << 24) | (tbl->log_num_buckets << 16) | (tbl->record_size));
   data[start_index+1] = base;

   uint32_t bucket_size_bytes = size_of_field(1<<(tbl->log_bucket_size) , tbl->record_size);
   uint32_t tbl_size = bucket_size_bytes * (1<< tbl->log_num_buckets) /4;

   memcpy((void*) (&data[base]), (void*) tbl->table_base, tbl_size*4);
}
uint32_t tbl_size(table_info* tbl) {
   uint32_t bucket_size_bytes = size_of_field(1<<(tbl->log_bucket_size) , tbl->record_size);
   return bucket_size_bytes * (1<< tbl->log_num_buckets) /4;
}


void write_output(FILE* fp) {

   // base address in out file
   uint32_t cur_loc = 32;
   uint32_t base_tx_offset = cur_loc;
   uint32_t size_tx_offset = size_of_field(num_tx+1, 1);

   cur_loc += size_tx_offset;

   uint32_t base_tx_data = cur_loc;
   uint32_t size_tx_data = size_of_field(tx_data.size(), 1);
   cur_loc += size_tx_data;

   uint32_t base_warehouse = cur_loc;
   uint32_t size_warehouse = size_of_field(n_warehouses, sizeof(warehouse_ro)) / 4;
   cur_loc += size_warehouse;

   uint32_t base_district_ro = cur_loc;
   uint32_t size_district_ro = size_of_field(n_districts_per_warehouse * n_warehouses, sizeof(district_ro)) / 4;
   cur_loc += size_district_ro;
   uint32_t base_district_rw = cur_loc;
   uint32_t size_district_rw = size_of_field(n_districts_per_warehouse * n_warehouses, sizeof(district_rw)) / 4;
   cur_loc += size_district_rw;

   uint32_t base_cust_ro = cur_loc;
   uint32_t size_cust_ro = tbl_size(&tbl_cust_ro);
   cur_loc += size_cust_ro;

   uint32_t base_cust_rw = cur_loc;
   uint32_t size_cust_rw = tbl_size(&tbl_cust_rw);
   cur_loc += size_cust_rw;

   uint32_t base_order = cur_loc;
   uint32_t size_order = tbl_size(&tbl_order);
   cur_loc += size_order;

   uint32_t base_order_line = cur_loc;
   uint32_t size_order_line = tbl_size(&tbl_order_line);
   cur_loc += size_order_line;

   uint32_t base_item = cur_loc;
   uint32_t size_item = tbl_size(&tbl_item);
   cur_loc += size_item;

   uint32_t base_stock = cur_loc;
   uint32_t size_stock = tbl_size(&tbl_stock);
   cur_loc += size_stock;

   uint32_t base_new_order = cur_loc;
   uint32_t size_new_order = size_of_field(tbl_new_order.num_records, tbl_new_order.record_size)/4;
   cur_loc += size_new_order;
   uint32_t new_order_ptr = cur_loc; cur_loc += size_of_field(2,4)/4;

   uint32_t base_history = cur_loc;
   uint32_t size_history = size_of_field(tbl_history.num_records, tbl_history.record_size)/4;
   cur_loc += size_history;
   uint32_t history_ptr = cur_loc; cur_loc += size_of_field(2,4)/4;

   uint32_t base_end = cur_loc;

   uint32_t* data = (uint32_t*) calloc(base_end, sizeof(uint32_t));
   data[0] = 0xdead;
   data[1] = num_tx;
   data[2] = base_tx_offset;
   data[3] = base_tx_data;


   data[4] = n_warehouses;
   data[5] = sizeof(warehouse_ro);
   data[6] = base_warehouse;
   data[7] = n_districts_per_warehouse;
   data[8] = sizeof(district_ro);
   data[9] = sizeof(district_rw);
   data[10] = base_district_ro;
   data[11] = base_district_rw;

   fill_table(&tbl_cust_ro, 12, data, base_cust_ro);
   fill_table(&tbl_cust_rw, 14, data, base_cust_rw);
   fill_table(&tbl_order,   16, data, base_order);
   fill_table(&tbl_order_line, 18, data, base_order_line);
   fill_table(&tbl_item ,   20, data, base_item);
   fill_table(&tbl_stock,   22, data, base_stock);

   memcpy((void*) (&data[base_warehouse]), (void*) warehouses, size_warehouse*4);
   memcpy((void*) (&data[base_district_ro]), (void*) districts_ro, size_district_ro*4);
   memcpy((void*) (&data[base_district_rw]), (void*) districts_rw, size_district_rw*4);

   data[23] = base_new_order;
   data[24] = (tbl_new_order.num_records << 16 | tbl_new_order.record_size);
   data[25] = new_order_ptr;
   memcpy((void*) (&data[base_new_order]), (void*) tbl_new_order.fifo_base, size_new_order *4);
   data[new_order_ptr] = tbl_new_order.addr_pointer[0];
   data[new_order_ptr + 1] = tbl_new_order.addr_pointer[1];
   printf("%d %d\n", data[new_order_ptr], data[new_order_ptr + 1]);

   data[26] = base_history;
   data[27] = (tbl_history.num_records << 16 | tbl_history.record_size);
   data[28] = history_ptr;
   data[history_ptr] = 0;
   data[history_ptr + 1] = 0;
   // histroy table is not initialized;

   data[29] = base_end;

   for (int i=0;i<30;i++) {
      printf("header %d: %x\n", i, data[i]);
   }

   for (int i=0;i<=num_tx;i++) data[base_tx_offset + i] = tx_offset[i];
   for (int i=0;i<=tx_data.size();i++) data[base_tx_data + i] = tx_data[i];
   fwrite(data, 4, base_end, fp);
   //for (int i=0;i<base_end;i++) {
   //   fprintf(fp, "%08x\n", data[i]);
   //}

}

int main(int argc, char *argv[]) {

// load init data for all tables
srand(0);
initialize_warehouse();
initialize_districts();
initialize_customers();
initialize_order();
initialize_item();
initialize_stock();
generate_tx();

FILE* fo = fopen("silo_tx", "wb");
write_output(fo);
fclose(fo);

/*
int warehouse_base;
int district_ro_base, district_rw_base;
int customer_ro_base, customer_rw_base;

// headers


headers[4] = n_districts_per_warehouse;
headers[5] = sizeof(district_ro);
headers[6] = district_ro_base;
headers[7] = sizeof(district_rw);
headers[8] = district_rw_base;

headers[9] = log_cust_table_bucket_size;
headers[10] = log_cust_table_num_buckets;
headers[11] = sizeof(customer_ro);
headers[12] = customer_ro_base;
headers[13] = sizeof(customer_rw);
headers[14] = customer_rw_base;
*/



}
