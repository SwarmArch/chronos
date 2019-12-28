#include <queue>
#include <vector>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long uint64_t;

typedef unsigned int uint;

void finish_task() {
}

struct task {
   uint32_t ts;
   uint32_t ttype;
   uint32_t locale;
   uint32_t args[4];
};
struct compare_task {
   bool operator() (const task &a, const task &b) const {
      return a.ts > b.ts;
   }
};

std::priority_queue<task, std::vector<task>, compare_task > pq;

static inline void chronos_init() {


}

void undo_log_write(uint* addr, uint data) {
}

void enq_task_arg4(uint ttype, uint ts, uint locale, uint arg0, uint arg1, uint arg2, uint arg3){
   task t = {ts, ttype, locale, arg0, arg1, arg2, arg3};
   printf("\tEnq Task ts:%4x ttype:%2d locale:%6x args:(%4x %4x %4x %4x)\n",
         t.ts, t.ttype, locale, t.args[0], t.args[1], t.args[2], t.args[3]);
   pq.push(t);
}

void enq_task_arg0(uint ttype, uint ts, uint locale){
   enq_task_arg4(ttype, ts, locale, 0, 0, 0, 0);
}
void enq_task_arg1(uint ttype, uint ts, uint locale, uint arg0){
   enq_task_arg4(ttype, ts, locale, arg0, 0, 0, 0);
}
void enq_task_arg2(uint ttype, uint ts, uint locale, uint arg0, uint arg1){
   enq_task_arg4(ttype, ts, locale, arg0, arg1, 0, 0);
}
void enq_task_arg3(uint ttype, uint ts, uint locale, uint arg0, uint arg1, uint arg2){
   enq_task_arg4(ttype, ts, locale, arg0, arg1, arg2, 0);
}


void deq_task() {
   task t = pq.top();
   printf("Deq Task ts:%4x ttype:%2d locale:%6x args:(%8x %8x %4x %4x) \n",
         t.ts, t.ttype, t.locale, t.args[0], t.args[1], t.args[2], t.args[3]);
   pq.pop();
}
void deq_task_arg0(uint* ttype, uint* ts, uint* locale) {
   if (pq.empty()) {*ttype = -1; return;}
   task t = pq.top();
   *ttype = t.ttype; *ts = t.ts; *locale = t.locale;
   deq_task();
}
void deq_task_arg1(uint* ttype, uint* ts, uint* locale, uint* arg0) {
   if (pq.empty()) {*ttype = -1; return;}
   task t = pq.top();
   *ttype = t.ttype; *ts = t.ts; *locale = t.locale; *arg0 = t.args[0];
   deq_task();
}
void deq_task_arg2(uint* ttype, uint* ts, uint* locale, uint* arg0, uint* arg1) {
   if (pq.empty()) {*ttype = -1; return;}
   task t = pq.top();
   *ttype = t.ttype; *ts = t.ts; *locale = t.locale;
   *arg0 = t.args[0]; *arg1 = t.args[1];
   deq_task();
}
void deq_task_arg3(uint* ttype, uint* ts, uint* locale, uint* arg0, uint* arg1, uint* arg2) {
   if (pq.empty()) {*ttype = -1; return;}
   task t = pq.top();
   *ttype = t.ttype; *ts = t.ts; *locale = t.locale;
   *arg0 = t.args[0]; *arg1 = t.args[1]; *arg2 = t.args[2];
   deq_task();
}
void deq_task_arg4(uint* ttype, uint* ts, uint* locale, uint* arg0, uint* arg1, uint* arg2, uint* arg3) {
   if (pq.empty()) {*ttype = -1; return;}
   task t = pq.top();
   *ttype = t.ttype; *ts = t.ts; *locale = t.locale;
   *arg0 = t.args[0]; *arg1 = t.args[1]; *arg2 = t.args[2]; *arg3 = t.args[3];
   deq_task();
}


