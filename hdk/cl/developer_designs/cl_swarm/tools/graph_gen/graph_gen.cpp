#define MAGIC_OP 0xdead
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdlib.h>
#include <tuple>
#include <utility>
#include <vector>
#include <set>
#include <map>
#include <unordered_set>
#include <queue>
#include <random>
#include <numeric>

struct Node {
   uint32_t vid;
   uint32_t dist;
   uint32_t bucket;
};

struct NodeSort {
   uint32_t vid;
   uint32_t degree;
};
struct degree_sort {
   bool operator() (const NodeSort &a, const NodeSort &b) const {
      int a_deg = (a.degree > 255) ? 255 : a.degree;
      int b_deg = (b.degree > 255) ? 255 : b.degree;
      bool ret = (a_deg > b_deg) ||
                  ( (a_deg == b_deg) && (a.vid < b.vid)) ;
      //printf(" (%d %d), (%d,%d) %d\n", a.degree, a.vid, b.degree, b.vid, ret);
      return ret;
   }
};

#define APP_SSSP 0
#define APP_COLOR 1
#define APP_MAXFLOW 2
const double EarthRadius_cm = 637100000.0;

struct Vertex;

struct Adj {
   uint32_t n;
   uint32_t d_cm; // edge weight
   uint32_t index; // index of the reverse edge
};

struct Vertex {
   double lat, lon;  // in RADIANS
   std::vector<Adj> adj;
};

Vertex* graph;
uint32_t numV;
uint32_t numE;
uint32_t startNode;

uint32_t* csr_offset;
Adj* csr_neighbors;
uint32_t* csr_dist;


uint64_t dist(const Vertex* src, const Vertex* dst) {
   // Use the haversine formula to compute the great-angle radians
   double latS = std::sin(src->lat - dst->lat);
   double lonS = std::sin(src->lon - dst->lon);
   double a = latS*latS + lonS*lonS*std::cos(src->lat)*std::cos(dst->lat);
   double c = 2*std::atan2(std::sqrt(a), std::sqrt(1-a));

   uint64_t d_cm = c*EarthRadius_cm;
   return d_cm;
}

void LoadGraphGR(const char* file) {
   // DIMACS
   std::ifstream f;
   std::string s;
   f.open(file, std::ios::binary);
   if (!f.is_open()) {
      printf("ERROR: Could not open input file\n");
      exit(1);
   }
   int n =0;
   while(!f.eof()) {
      std::getline(f, s);
      if (s.c_str()[0]=='c') continue;
      if (s.c_str()[0]=='p') {
         sscanf(s.c_str(), "%*s %*s %d %d\n", &numV, &numE);
         graph = new Vertex[numV];
      }
      if (s.c_str()[0]=='a') {
         uint32_t src, dest, w;
         sscanf(s.c_str(), "%*s %d %d %d\n", &src, &dest, &w);
         Adj a = {dest-1,w};
         graph[src-1].adj.push_back(a);
      }

      n++;
   }
   printf("n %d %d %d\n",n, numV, numE);

}
void LoadGraphEdges(const char* file) {
   std::ifstream f;
   std::string s;
   f.open(file, std::ios::binary);
   if (!f.is_open()) {
      printf("ERROR: Could not open input file\n");
      exit(1);
   }
   int n =0;
   numV = 1157828; // hack: com-youtube
   graph = new Vertex[numV];
   while(!f.eof()) {
      std::getline(f, s);
      if (s.c_str()[0]=='E') continue;
      else {
         uint32_t src, dest;
         sscanf(s.c_str(), "%d %d\n", &src, &dest);
         //printf("%d %d\n", src, dest);
         Adj a = {dest-1,0};
         graph[src-1].adj.push_back(a);
      }

      n++;
   }
   printf("%d %d\n", numV, numE);

}
void LoadGraph(const char* file) {
   const uint32_t MAGIC_NUMBER = 0x150842A7 + 0; // increment every time you change the file format
   std::ifstream f;
   f.open(file, std::ios::binary);
   if (!f.is_open()) {
      printf("ERROR: Could not open input file\n");
      exit(1);
   }

   auto readU = [&]() -> uint32_t {
      union U {
         uint32_t val;
         char bytes[sizeof(uint32_t)];
      };
      U u;
      f.read(u.bytes, sizeof(uint32_t));
      // assert(!f.fail());
      return u.val;
   };

   auto readD = [&]() -> double {
      union U {
         double val;
         char bytes[sizeof(double)];
      };
      U u;
      f.read(u.bytes, sizeof(double));
      // assert(!f.fail());
      return u.val;
   };

   uint32_t magic = readU();
   if (magic != MAGIC_NUMBER) {
      printf("ERROR: Wrong input file format (magic number %d, expected %d)\n",
            magic, MAGIC_NUMBER);
      exit(1);
   }

   numV = readU();
   printf("Reading %d nodes...\n", numV);

   graph = new Vertex[numV];
   uint32_t i = 0;
   while (i < numV) {
      graph[i].lat = readD();
      graph[i].lon = readD();
      uint32_t n = readU();
      graph[i].adj.resize(n);
      for (uint32_t j = 0; j < n; j++) graph[i].adj[j].n = readU();
      for (uint32_t j = 0; j < n; j++) graph[i].adj[j].d_cm = readD()*EarthRadius_cm;
      i++;

   }

   f.get();
   // assert(f.eof());

#if 0
   // Print graph
   for (uint32_t i = 0; i < numV; i++) {
      printf("%6d: %7f %7f", i, graph[i].lat, graph[i].lon);
      for (auto a: graph[i].adj) printf(" %5ld %7f", a.n-graph, a.d);
      printf("\n");
   }
#endif

}

void GenerateGridGraph(uint32_t n) {
   numV = n*n;
   numE = 2 * n * (n-1) ;
   graph = new Vertex[numV];
   bool debug = false;
   srand(0);
   for (uint32_t i=0;i<n;i++){
      for (uint32_t j=0;j<n;j++){
         uint32_t vid = i*n+j;
         if (i < n-1) {
            Adj e;
            e.n = (vid+n);
            e.d_cm = rand() % 10;
            graph[vid].adj.push_back(e);
            if(debug) printf("%d->%d %d\n", vid, e.n, e.d_cm);
         }
         if (j < n-1) {
            Adj e;
            e.n = (vid+1);
            e.d_cm = rand() % 10;
            graph[vid].adj.push_back(e);
            if(debug) printf("%d->%d %d\n", vid, e.n, e.d_cm);
         }
      }
   }
}

// code copied from suvinay's maxflow graph generator
void choose_k(int to, std::vector<int>* vec, int k, int seed) {
    std::vector<int> numbers;
    numbers.resize(to);
    std::iota(numbers.begin(), numbers.end(), 0);   // Populate numbers from 0 to (to-1)
    //std::shuffle(numbers.begin(), numbers.end(), std::mt19937{std::random_device{}()}); // Shuffle them
    std::shuffle(numbers.begin(), numbers.end(), std::default_random_engine(seed));
    std::copy_n(numbers.begin(), k, vec->begin()); // Copy the first k in the shuffled array to vec
    return;
}
void addEdge(uint32_t from, uint32_t to, uint32_t cap) {
    // Push edge to _graph[node]
    Adj adj_from = {to, cap, graph[to].adj.size()};
    graph[from].adj.push_back(adj_from);

    // Insert the reverse edge (residual graph)
    Adj adj_to = {from, 0, graph[from].adj.size()-1};
    graph[to].adj.push_back(adj_to);
}

void GenerateGridGraphMaxflow(uint32_t n) {
   srand(42);
   numV = n*n + 2;
   const int num_connections = 2;
   const int MAX_CAPACITY = 10;
   const int MIN_CAPACITY = 1;
   graph = new Vertex[numV];
   uint32_t i, j;
   for (i = 0; i < n - 1; ++i) {
      for (j = 0; j < n; ++j) {
         std::vector<int> connections;
         connections.resize(num_connections);
         choose_k(n, &connections, num_connections, rand());
         for (auto &x : connections) {
            uint32_t capacity = static_cast<uint32_t>(
                  rand() % (MAX_CAPACITY - MIN_CAPACITY) + MIN_CAPACITY);
            addEdge(i*n+j, (i+1)*n+x, capacity);
            //printf("a %d %d %d\n", i * n + j, (i + 1) * n + x, capacity);
         }
      }
   }
   for (i = 0; i < n; ++i) {
      uint32_t capacity = static_cast<uint32_t>
         (rand() % (MAX_CAPACITY - MIN_CAPACITY) + MIN_CAPACITY);
      addEdge(n*n, i, capacity);
   }

   for (i = 0; i < n; ++i) {
      uint32_t capacity = static_cast<uint32_t>
         (rand() % (MAX_CAPACITY - MIN_CAPACITY) + MIN_CAPACITY);
      addEdge((n - 1) * n + i, n*n + 1, capacity);
   }
}

std::set<uint32_t>* edges;
void makeUndirectional() {

   edges = new std::set<uint32_t>[numV];
   for (uint32_t i = 0; i < numV; i++) {
      for (uint32_t a=0;a<graph[i].adj.size();a++){
         int n = graph[i].adj[a].n;
         //         printf("%d %d\n",i,n);
         edges[i].insert(n);
         edges[n].insert(i);
      }

   }

   for (uint32_t i = 0; i < numV; i++) {
      graph[i].adj.clear();
      for (uint32_t n: edges[i]) {
         Adj a;
         a.n = n;
         a.d_cm = 0;
         graph[i].adj.push_back(a);
      }

   }



}

void ConvertToCSR() {
   numE = 0;
   for (uint32_t i = 0; i < numV; i++) numE += graph[i].adj.size();
   printf("Read %d nodes, %d adjacencies\n", numV, numE);

   csr_offset = (uint32_t*)(malloc (sizeof(uint32_t) * (numV+1)));
   csr_neighbors = (Adj*)(malloc (sizeof(Adj) * (numE)));
   csr_dist = (uint32_t*)(malloc (sizeof(uint32_t) * numV));
   numE = 0;
   for (uint32_t i=0;i<numV;i++){
      csr_offset[i] = numE;
      for (uint32_t a=0;a<graph[i].adj.size();a++){
         csr_neighbors[numE++] = graph[i].adj[a];
      }
      csr_dist[i] = ~0;
   }
   csr_offset[numV] = numE;

}

struct compare_node {
   bool operator() (const Node &a, const Node &b) const {
      return a.bucket > b.bucket;
   }
};
void ComputeReference(){
   uint32_t  delta = 1;
   printf("Compute Reference\n");
   std::priority_queue<Node, std::vector<Node>, compare_node> pq;

    // cache flush
#if 0
    const int size = 20*1024*1024;
    char *c = (char *) malloc(size);
    for (int i=0;i<0xff;i++) {
       // printf("%d\n", i);

        for (int j=0;j<size;j++)
            c[j] = i*j;
    }
#endif
   uint32_t max_pq_size = 0;
   int edges_traversed = 0;

   clock_t t = clock();
   Node v = {startNode, 0, 0};
   pq.push(v);
   while(!pq.empty()){
      Node n = pq.top();
      uint32_t vid = n.vid;
      uint32_t dist = n.dist;
      //printf(" %d %d\n", vid, dist);
      pq.pop();
      max_pq_size = pq.size() < max_pq_size ?  max_pq_size : pq.size();
      edges_traversed++;
      if (csr_dist[vid] > dist) {
         csr_dist[vid] = dist;

         uint32_t ngh = csr_offset[vid];
         uint32_t nghEnd = csr_offset[vid+1];

         while(ngh != nghEnd) {
            Adj a = csr_neighbors[ngh++];
            Node e = {a.n, dist +  a.d_cm, (dist+a.d_cm)/delta};
            pq.push(e);
         }
      }
   }
   t = clock() -t;
   printf("Time taken :%f msec\n", ((float)t * 1000)/CLOCKS_PER_SEC);
   printf("Node %d dist:%d\n", numV -1, csr_dist[numV-1]);
   printf("Max PQ size %d\n", max_pq_size);
   printf("edges traversed %d\n", edges_traversed);
}

int size_of_field(int items, int size_of_item){
	const int CACHE_LINE_SIZE = 64;
	return ( (items * size_of_item + CACHE_LINE_SIZE-1) /CACHE_LINE_SIZE) * CACHE_LINE_SIZE / 4;
}


void WriteOutput(FILE* fp) {
   // all offsets are in units of uint32_t. i.e 16 per cache line

   int SIZE_DIST =((numV+15)/16)*16;
   int SIZE_EDGE_OFFSET =( (numV+1 +15)/ 16) * 16;
   int SIZE_NEIGHBORS =(( (numE* 8)+ 63)/64 ) * 16;
   int SIZE_GROUND_TRUTH =((numV+15)/16)*16;

   int BASE_DIST = 16;
   int BASE_EDGE_OFFSET = BASE_DIST + SIZE_DIST;
   int BASE_NEIGHBORS = BASE_EDGE_OFFSET + SIZE_EDGE_OFFSET;
   int BASE_GROUND_TRUTH = BASE_NEIGHBORS + SIZE_NEIGHBORS;

   int BASE_END = BASE_GROUND_TRUTH + SIZE_GROUND_TRUTH;

   uint32_t* data = (uint32_t*) calloc(BASE_END, sizeof(uint32_t));

   data[0] = MAGIC_OP;
   data[1] = numV;
   data[2] = numE;
   data[3] = BASE_EDGE_OFFSET;
   data[4] = BASE_NEIGHBORS;
   data[5] = BASE_DIST;
   data[6] = BASE_GROUND_TRUTH;
   data[7] = startNode;
   data[8] = BASE_END;

   for (int i=0;i<9;i++) {
      printf("header %d: %d\n", i, data[i]);
   }

   uint32_t max_int = 0xFFFFFFFF;
   for (uint32_t i=0;i<numV;i++) {
      data[BASE_EDGE_OFFSET +i] = csr_offset[i];
      data[BASE_DIST+i] = max_int;
      data[BASE_GROUND_TRUTH +i] = csr_dist[i];
      //printf("gt %d %d\n", i, csr_dist[i]);
   }
   data[BASE_EDGE_OFFSET +numV] = csr_offset[numV];

   for (uint32_t i=0;i<numE;i++) {
      data[ BASE_NEIGHBORS +2*i ] = csr_neighbors[i].n;
      data[ BASE_NEIGHBORS +2*i+1] = csr_neighbors[i].d_cm;
   }

   printf("Writing file \n");
   for (int i=0;i<BASE_END;i++) {
      fprintf(fp, "%08x\n", data[i]);
   }
   fclose(fp);

   free(data);

}
void WriteOutputColor(FILE* fp) {
   // all offsets are in units of uint32_t. i.e 16 per cache line
   int SIZE_DIST =((numV+15)/16)*16;
   int SIZE_EDGE_OFFSET =( (numV+1 +15)/ 16) * 16;
   int SIZE_NEIGHBORS =(( (numE)+ 15)/ 16 ) * 16;
   int SIZE_GROUND_TRUTH =((numV+15)/16)*16;
   int SIZE_INITLIST = ((numV+15)/16)*16;
   int SIZE_SCRATCH = size_of_field(numV, 16);
   int SIZE_JOIN_CNT = size_of_field(numV, 4);

   int BASE_DIST = 16;
   int BASE_EDGE_OFFSET = BASE_DIST + SIZE_DIST;
   int BASE_NEIGHBORS = BASE_EDGE_OFFSET + SIZE_EDGE_OFFSET;
   int BASE_INITLIST = BASE_NEIGHBORS + SIZE_NEIGHBORS;
   int BASE_SCRATCH = BASE_INITLIST + SIZE_INITLIST;
   int BASE_JOIN_CNT = BASE_SCRATCH + SIZE_SCRATCH;
   int BASE_GROUND_TRUTH = BASE_JOIN_CNT + SIZE_JOIN_CNT;
   int BASE_END = BASE_GROUND_TRUTH + SIZE_GROUND_TRUTH;

   uint32_t* data = (uint32_t*) calloc(BASE_END, sizeof(uint32_t));

   data[0] = MAGIC_OP;
   data[1] = numV;
   data[2] = numE;
   data[3] = BASE_EDGE_OFFSET;
   data[4] = BASE_NEIGHBORS;
   data[5] = BASE_DIST;
   data[6] = BASE_GROUND_TRUTH;
   data[7] = startNode;
   data[8] = BASE_END;
   data[9] = BASE_INITLIST;
   data[10] = BASE_SCRATCH;
   data[11] = BASE_JOIN_CNT;

   for (int i=0;i<12;i++) {
      printf("header %d: %d\n", i, data[i]);
   }
   //todo ground truth

   uint32_t max_int = 0xFFFFFFFF;
   for (uint32_t i=0;i<numV;i++) {
      data[BASE_EDGE_OFFSET +i] = csr_offset[i];
      data[BASE_DIST+i] = max_int;
      data[BASE_GROUND_TRUTH +i] = csr_dist[i];
      for (int j=0;j<4;j++) {
         data[BASE_SCRATCH +i * 4 + j] = 0;
      }
      //printf("gt %d %d\n", i, csr_dist[i]);
   }
   data[BASE_EDGE_OFFSET +numV] = csr_offset[numV];

   for (uint32_t i=0;i<numE;i++) {
      data[ BASE_NEIGHBORS +i ] = csr_neighbors[i].n;
   }
   // sort by degree
   std::vector< NodeSort > vec;
   for (unsigned int i=0;i<numV;i++) {
      uint32_t degree = csr_offset[i+1] - csr_offset[i];
      NodeSort n = {i, degree};
      vec.push_back(n);
   }
   std::sort(vec.begin(), vec.end(), degree_sort());
   for (uint32_t i =0;i<numV;i++) {
      //if (i < 100) printf("%d %d\n", vec[i].vid, vec[i].degree);
      data[BASE_INITLIST + i] = vec[i].vid;
   }
   for (uint32_t i=0;i<numV;i++) {
      uint32_t vid = vec[i].vid;
      uint64_t vec = 0;
      for (uint32_t j=csr_offset[vid]; j< csr_offset[vid+1]; j++) {
         uint32_t neighbor = csr_neighbors[j].n;
         //printf("\t%d neighbor %x\n", neighbor, csr_dist[neighbor]);
         if (csr_dist[neighbor] != ~0) {
            vec = vec | ( 1<<csr_dist[neighbor]);
         }
      }
      int bit = 0;
      while(vec & 1) {
         vec >>=1;
         bit++;
      }
      csr_dist[vid] = bit;
      data[BASE_GROUND_TRUTH + vid] = bit;
      //if (bit > 28) printf("vid %d color %d\n", vid, bit);
   }

   printf("Writing file \n");
   for (int i=0;i<BASE_END;i++) {
      fprintf(fp, "%08x\n", data[i]);
   }
   fclose(fp);

   free(data);

}

void WriteOutputMaxflow(FILE* fp) {
   // all offsets are in units of uint32_t. i.e 16 per cache line
   // dist = {height, excess, counter, active, visited, min_neighbor_height,
   // flow[10]}
   int SIZE_DIST = size_of_field(numV, 64);
   int SIZE_EDGE_OFFSET = size_of_field(numV+1, 4);
   int SIZE_NEIGHBORS = size_of_field(numE, 16) ;
   int SIZE_GROUND_TRUTH =size_of_field(numV, 4); // redundant

   int BASE_DIST = 16;
   int BASE_EDGE_OFFSET = BASE_DIST + SIZE_DIST;
   int BASE_NEIGHBORS = BASE_EDGE_OFFSET + SIZE_EDGE_OFFSET;
   int BASE_GROUND_TRUTH = BASE_NEIGHBORS + SIZE_NEIGHBORS;
   int BASE_END = BASE_GROUND_TRUTH + SIZE_GROUND_TRUTH;

   uint32_t* data = (uint32_t*) calloc(BASE_END, sizeof(uint32_t));

   startNode = numV-2;
   uint32_t endNode = numV-1;
   uint32_t log_global_relabel_interval = (int) (round(log2(numV))); // closest_power_of_2(numV)
   if (log_global_relabel_interval < 5) log_global_relabel_interval = 5;

   data[0] = MAGIC_OP;
   data[1] = numV;
   data[2] = numE;
   data[3] = BASE_EDGE_OFFSET;
   data[4] = BASE_NEIGHBORS;
   data[5] = BASE_DIST;
   data[6] = BASE_GROUND_TRUTH;
   data[7] = startNode;
   data[8] = BASE_END;
   data[9] = endNode;
   data[10] = log_global_relabel_interval;


   for (int i=0;i<11;i++) {
      printf("header %d: %d\n", i, data[i]);
   }
   //todo ground truth

   uint32_t max_int = 0xFFFFFFFF;
   for (uint32_t i=0;i<numV;i++) {
      data[BASE_EDGE_OFFSET +i] = csr_offset[i];
      data[BASE_GROUND_TRUTH +i] = csr_dist[i];
      if (csr_offset[i+1] - csr_offset[i] > 10) {
        printf("Node %d n_edges %d\n", i, csr_offset[i+1]-csr_offset[i]);
      }
      for (int j=0;j<16;j++) {
         data[BASE_DIST +i * 4 + j] = 0;
      }
   }
   data[BASE_EDGE_OFFSET +numV] = csr_offset[numV];

   // startNode excess
   uint32_t startNodeExcess= 0;
   for (Adj e : graph[startNode].adj) {
      startNodeExcess += e.d_cm;
   }
   data[BASE_DIST + startNode*16 +0 ] = numV; // height
   data[BASE_DIST + startNode*16 +1 ] = startNodeExcess;
   data[BASE_DIST + startNode*16 +2 ] = csr_offset[startNode+1] - csr_offset[startNode];
   data[BASE_DIST + startNode*16 +3 ] = 1;
   data[BASE_DIST + endNode*16 +3 ] = 1;
   printf("StartNodeExcess %d\n", startNodeExcess);

   for (uint32_t i=0;i<numE;i++) {
      data[ BASE_NEIGHBORS +i*4 ] = csr_neighbors[i].n;
      data[ BASE_NEIGHBORS +i*4+1 ] = csr_neighbors[i].d_cm;
      data[ BASE_NEIGHBORS +i*4+2 ] = csr_neighbors[i].index;
   }
   printf("Writing file \n");
   for (int i=0;i<BASE_END;i++) {
      fprintf(fp, "%08x\n", data[i]);
   }
   fclose(fp);

   free(data);

}

void WriteDimacs(FILE* fp) {
   // all offsets are in units of uint32_t. i.e 16 per cache line

   fprintf(fp, "p sp %d %d\n", numV, numE);

   for (uint32_t i=0;i<numV;i++){
      for (uint32_t a=0;a<graph[i].adj.size();a++){
          Adj e = graph[i].adj[a];
          fprintf(fp, "a %d %d %d\n", i + 1, e.n + 1, e.d_cm);
      }
   }
}
void WriteEdgesFile(FILE *fp) {
   // for use in coloring
   fprintf(fp, "EdgeArray");
   for (uint32_t i=0;i<numV;i++){
      for (uint32_t a=0;a<graph[i].adj.size();a++){
          Adj e = graph[i].adj[a];
          fprintf(fp, "%d %d\n", i + 1, e.n + 1);
      }
   }

}

int main(int argc, char *argv[]) {

   int type = 0;
   // 0 - load from file .bin format
   // 1 - grid graph
   int app = APP_SSSP;
   char out_file[50];
   char dimacs_file[50];
   char edgesFile[50];
   if (argc > 1) {
      type = atoi(argv[1]);
   }
   char ext[50];
   sprintf(ext, "%s", "sssp");
   if (argc > 3) {
      if (strcmp(argv[3], "color") ==0) {
         app = APP_COLOR;
         sprintf(ext, "%s", "color");
      }
      if (strcmp(argv[3], "flow") ==0) {
         app = APP_MAXFLOW;
         sprintf(ext, "%s", "flow");
      }
   }

   if (type == 0) {
      // astar type
      LoadGraph(argv[2]);
      int strStart = 0;
      // strip out filename from path
      for (uint32_t i=0;i<strlen(argv[2]);i++) {
         if (argv[2][i] == '/') strStart = i+1;
      }
      sprintf(out_file, "%s.%s", argv[2] +strStart, ext);
   } else if (type == 1) {
      int n = 4;
      if (argc>2) n = atoi(argv[2]);
      if (app==APP_MAXFLOW) {
         GenerateGridGraphMaxflow(n);
      } else {
         GenerateGridGraph(n);
      }
      sprintf(out_file, "grid_%dx%d.%s", n,n, ext);
      sprintf(dimacs_file, "grid_%dx%d.dimacs", n,n);
   }  else if (type == 2) {
      LoadGraphGR(argv[2]);
      int strStart = 0;
      // strip out filename from path
      for (uint32_t i=0;i<strlen(argv[2]);i++) {
         if (argv[2][i] == '/') strStart = i+1;
      }
      sprintf(out_file, "%s.%s", argv[2] +strStart, ext);
      sprintf(edgesFile, "%s.edges", argv[2] +strStart);
   }  else if (type == 3) {
      // coloring type : eg: com-youtube
      LoadGraphEdges(argv[2]);
      int strStart = 0;
      // strip out filename from path
      for (uint32_t i=0;i<strlen(argv[2]);i++) {
         if (argv[2][i] == '/') strStart = i+1;
      }
      sprintf(out_file, "%s.%s", argv[2] +strStart, ext);
   }
   if (app == APP_COLOR) {
      makeUndirectional();
   }

   ConvertToCSR();

   startNode = 0;
   if (app == APP_SSSP) {
      ComputeReference();
   }

   FILE* fp;
   FILE* fpd;
   fp = fopen(out_file, "w");
   printf("Writing file %s %p\n", out_file, fp);
   //fpd = fopen(dimacs_file, "w");
   //WriteDimacs(fpd);
   //fpd = fopen(edgesFile, "w");
   //WriteEdgesFile(fpd);
   //fclose(fpd);
   if (app == APP_SSSP) {
      WriteOutput(fp);
   } else if (app == APP_COLOR) {
      WriteOutputColor(fp);
   } else if (app == APP_MAXFLOW) {
      WriteOutputMaxflow(fp);
   }
   return 0;
}
