
#include <random>
#include <stdio.h>
#include <string.h>
#include <vector>

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;

struct warehouse_ro {
   uint32_t w_tax;
};

struct district_ro {
   uint32_t d_tax;
   char addr[16];
};

struct district_rw {
   uint32_t d_next_o_id;
   uint32_t d_ytd;
};

struct customer_ro {
   uint32_t c_id;
   uint16_t c_d_id;
   uint16_t c_w_id;
   uint32_t c_since;
   char c_credit[2];
   uint32_t c_credit_lim;
   uint32_t c_discount;
   char c_string_data[128];

};

struct customer_rw {
   uint32_t c_id;
   uint16_t c_d_id;
   uint16_t c_w_id;
   uint32_t c_balance;
   uint32_t c_ytd_payment;
   uint32_t c_payment_cnt;
   uint32_t c_delivery_cnt;

   char c_data [450]; // to fit into a cache line
};

struct order{
   uint32_t o_id;
   uint16_t o_d_id;
   uint16_t o_w_id;
   uint32_t o_c_id;
   uint32_t o_entry_d;
   uint8_t o_carrier_id;
   uint8_t o_ol_cnt;
   uint8_t o_all_local;
   uint8_t __padding__;
};

struct order_line {
   uint32_t ol_o_id;
   uint8_t ol_d_id;
   uint8_t ol_w_id;
   uint16_t ol_number;
   uint32_t ol_i_id;
   uint8_t ol_supply_w_id;
   uint8_t ol_quantity;
   uint16_t ol_amount;
   uint32_t ol_delivery_d;
   char ol_dist_info[24];
};

struct item {
   uint64_t i_id;
   uint32_t i_im_id;
   uint32_t i_price;
   char i_name[24];
   char i_data[50];
};

struct stock {
   uint32_t s_i_id;
   uint32_t s_w_id;
   uint32_t s_quantity;
   uint32_t s_order_cnt;
   uint32_t s_remote_cnt;
   uint32_t s_ytd;
};

struct new_order {
   uint32_t no_o_id;
   uint16_t no_d_id;
   uint16_t no_w_id;
};

struct history {
   uint32_t h_c_id;
   uint8_t h_c_d_id;
   uint8_t h_c_w_id;
   uint8_t h_d_id;
   uint8_t h_w_id;
   uint32_t h_date;
   uint32_t h_amount;
   char h_data[24];
};

struct table_info {
   uint8_t log_bucket_size;
   uint8_t log_num_buckets;
   uint16_t record_size; // in bytes
   uint8_t* table_base;
};

struct fifo_table_info {
   uint8_t* fifo_base;
   uint32_t num_records;
   uint32_t record_size;
   uint32_t* addr_pointer;
};

struct tx_info_new_order {
   uint32_t tx_type : 4;
   uint32_t w_id : 4;
   uint32_t d_id : 4;
   uint32_t num_items : 4;
   uint32_t c_id : 16;
};
struct tx_info_new_order_item {
   uint32_t i_id : 24;
   uint32_t i_qty : 4;
   uint32_t i_s_wid: 4;
};

int size_of_field(int items, int size_of_item){ // in bytes
	const int CACHE_LINE_SIZE = 64;
	return ( (items * size_of_item + CACHE_LINE_SIZE-1) /CACHE_LINE_SIZE) * CACHE_LINE_SIZE ;
}


int RandomNumber(int min, int max)
{
 // [0, UINT64_MAX] -> (int) [min, max]
 int n = rand();
 int m = n % (max - min + 1);
 return min + (int) m;
}

int NonUniformRandom(int A, int C, int min, int max)
{
 return (((RandomNumber(0, A) | RandomNumber(min, max)) + C) % (max - min + 1)) + min;
}

uint32_t hash_key(uint64_t n) {
   uint64_t keys[] = {
      0xc4252fd6603203fb,
      0xfefae1023d6b9a9c,
      0x0893b429cbaf5d40,
      0x6c6c879263afbf12,
      0xf48f43292cfc43ea,
      0xe507f16207d988d4,
      0x53b8d2ce4617aedc,
      0xfd90b3aab6ff29f9,
      0xc12fd5f186b3f1f8,
      0x01b1aea4969b64f5,
      0xa12054b1736114ae,
      0xb6c529dc77f8b0c1,
      0x6f84e59ea4eed11b,
      0x90b2164ec5cf15b1,
      0xa19b2cfe4d52b2bf,
      0x34600bf45aa01757,
      0x94f792e4a1194f17,
      0x10f09caa15236041,
      0x14671d0687a34ba3,
      0xa751612471d0cf7c,
      0xe02b122ca229c1ea,
      0x245254ca073f0f9e,
      0x452fa5913c57a950,
      0x190a4e5464c93b9b,
      0x4c50401e2bfde441,
      0x87a1574db57af256,
      0x780e947ecd296aa1,
      0x3b613b6038cd96e9,
      0x2b0404f313141694,
      0x8c10327698ae241e,
      0x615735a1abebb2c7,
      0x925e0a83aa85e054
   };
   unsigned int res = 0;
   for (int i=0;i<32;i++) {
      uint64_t t = (keys[i] & n);
      int bits = 0;
      while (t!=0) {
         if (t&1) bits++;
         t >>=1;
      }
      if (bits &1)
      res |= (1<<i);
   }
   return res;

}
