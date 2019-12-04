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

/*******************************************************************************
Vendor: Xilinx
Associated Filename: array_io_test.c
Purpose: Vivado HLS tutorial example
Device: All
Revision History: March 1, 2013 - initial release

*******************************************************************************
Copyright 2008 - 2013 Xilinx, Inc. All rights reserved.

This file contains confidential and proprietary information of Xilinx, Inc. and
is protected under U.S. and international copyright and other intellectual
property laws.

DISCLAIMER
This disclaimer is not a license and does not grant any rights to the materials
distributed herewith. Except as otherwise provided in a valid license issued to
you by Xilinx, and to the maximum extent permitted by applicable law:
(1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND WITH ALL FAULTS, AND XILINX
HEREBY DISCLAIMS ALL WARRANTIES AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY,
INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-INFRINGEMENT, OR
FITNESS FOR ANY PARTICULAR PURPOSE; and (2) Xilinx shall not be liable (whether
in contract or tort, including negligence, or under any other theory of
liability) for any loss or damage of any kind or nature related to, arising under
or in connection with these materials, including for any direct, or any indirect,
special, incidental, or consequential loss or damage (including loss of data,
profits, goodwill, or any type of loss or damage suffered as a result of any
action brought by a third party) even if such damage or loss was reasonably
foreseeable or Xilinx had been advised of the possibility of the same.

CRITICAL APPLICATIONS
Xilinx products are not designed or intended to be fail-safe, or for use in any
application requiring fail-safe performance, such as life-support or safety
devices or systems, Class III medical devices, nuclear facilities, applications
related to the deployment of airbags, or any other applications that could lead
to death, personal injury, or severe property or environmental damage
(individually and collectively, "Critical Applications"). Customer asresultes the
sole risk and liability of any use of Xilinx products in Critical Applications,
subject only to applicable laws and regulations governing limitations on product
liability.

THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS PART OF THIS FILE AT
ALL TIMES.

*******************************************************************************/
#include "astar.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdlib.h>
#include <vector>
#include "queue"


const double EarthRadius_m = 6371000.0;

struct Vertex;

struct Adj {
    uint32_t n;
    uint64_t d_m;
};

struct Vertex {
    double lat, lon;  // in RADIANS
    std::vector<Adj> adj;

    // Ephemeral state (used during search)
    uint32_t prev; // nullptr if not visited (not in closed set)
    uint64_t currentF;
};

struct Task {
	uint32_t ts;
	uint32_t fScore;
	uint32_t vertex;
	uint32_t parent;
};

struct compare_node {
	bool operator() (const Task &a, const Task &b) const {
		return a.ts > b.ts;
	}
};

Vertex* graph;
uint32_t numNodes;
uint32_t numEdges;
uint32_t startNode;
uint32_t destNode;
uint32_t actDist;
std::string graph_name = "monaco";

uint32_t readU (std::ifstream& f){
      union U {
          uint32_t val;
          char bytes[sizeof(uint32_t)];
      };
      U u;
      f.read(u.bytes, sizeof(uint32_t));
      assert(!f.fail());
      return u.val;
  };
double readD (std::ifstream& f){
    union U {
        double val;
        char bytes[sizeof(double)];
    };
    U u;
    f.read(u.bytes, sizeof(double));
    assert(!f.fail());
    return u.val;
};

void LoadGraph(const char* file) {
    const uint32_t MAGIC_NUMBER = 0x150842A7 + 0;  // increment every time you change the file format
    std::ifstream f;
    f.open(file, std::ios::binary);
    if (!f.is_open()) {
        printf("ERROR: Could not open input file\n");
        exit(1);
    }

    uint32_t magic = readU(f);
    if (magic != MAGIC_NUMBER) {
        printf("ERROR: Wrong input file format (magic number %d, expected %d)\n",
                magic, MAGIC_NUMBER);
        exit(1);
    }

    numNodes = readU(f);
    printf("Reading %d nodes...\n", numNodes);

    graph = new Vertex[numNodes];
    uint32_t i = 0;
    while (i < numNodes) {
        graph[i].lat = readD(f);
        graph[i].lon = readD(f);
        uint32_t n = readU(f);
        graph[i].adj.resize(n);
        for (uint32_t j = 0; j < n; j++) graph[i].adj[j].n = readU(f);
        for (uint32_t j = 0; j < n; j++) graph[i].adj[j].d_m = readD(f)*EarthRadius_m;

        graph[i].currentF = ~0;
        graph[i].prev = 0;
		i++;
    }

    f.get();
    assert(f.eof());

#if 1
    FILE* fout = fopen("fout","w");
    // Print graph
    for (uint32_t i = 0; i < numNodes; i++) {
        fprintf(fout, "%6d: %7f %7f", i, graph[i].lat, graph[i].lon);
        for (int j= 0; j<graph[i].adj.size();j++) {
        	Adj a = graph[i].adj[j];
        	fprintf(fout, " %5ld %7f", a.n, a.d_m);
        }
        fprintf(fout, "\n");
    }
#endif

    uint64_t adjs = 0;
    for (uint32_t i = 0; i < numNodes; i++) adjs += graph[i].adj.size();
    printf("Read %d nodes, %ld adjacencies\n", numNodes, adjs);
    numEdges = adjs;

}

int size_of_field(int items, int size_of_item){
	const int CACHE_LINE_SIZE = 64;
	return ( (items * size_of_item + CACHE_LINE_SIZE-1) /CACHE_LINE_SIZE) * CACHE_LINE_SIZE / 4;
}

void WriteFile() {

	int SIZE_DATA = size_of_field(numNodes, 4);
	int SIZE_EDGE_OFFSET =size_of_field(numNodes + 1, 4);
	int SIZE_NEIGHBORS =size_of_field(numEdges, 8);
	int SIZE_LATLON =size_of_field(numNodes, 8);
	int SIZE_GROUND_TRUTH = size_of_field(numNodes, 4);

	int BASE_DATA = 16;
	int BASE_EDGE_OFFSET = BASE_DATA + SIZE_DATA;
	int BASE_NEIGHBORS = BASE_EDGE_OFFSET + SIZE_EDGE_OFFSET;
	int BASE_LATLON = BASE_NEIGHBORS + SIZE_NEIGHBORS;

	int BASE_GROUND_TRUTH = BASE_LATLON + SIZE_LATLON;
	int BASE_END = BASE_GROUND_TRUTH + SIZE_GROUND_TRUTH;
	uint32_t* data = (uint32_t*) calloc(BASE_END, sizeof(uint32_t));

	data[0] = 0;
	data[1] = numNodes;
	data[2] = numEdges;
	data[3] = BASE_EDGE_OFFSET;
	data[4] = BASE_NEIGHBORS;
	data[5] = BASE_DATA;
	data[6] = BASE_LATLON;
	data[7] = startNode;
	data[8] = destNode;
	data[9] = BASE_GROUND_TRUTH;
	data[10] = BASE_END;


	for (int i=0;i<numNodes;i++) {
		fp_t fp_lat = graph[i].lat;
		fp_t fp_lon = graph[i].lon;
	}

	for (int i=0;i<=10;i++) {
		printf("header %d: %d\n", i, data[i]);
	}
	uint64_t fp_factor = (1<<28)*2l;
	uint32_t offset = 0;
	for (int i=0;i<numNodes;i++) {
		data[BASE_EDGE_OFFSET + i] = offset;
		for (int j= 0; j<graph[i].adj.size();j++) {
			Adj a = graph[i].adj[j];
			data[BASE_NEIGHBORS + (offset*2)  ] = a.n;
			data[BASE_NEIGHBORS + (offset*2)+1] = a.d_m;
			offset++;
			//printf(" %5ld %7f", a.n, a.d_m);
		}
		data[BASE_DATA+i] = ~0;
		data[BASE_GROUND_TRUTH+i] = graph[i].currentF;
		//printf("% d  %d\n", i, graph[i].currentF);
		fp_t lat = graph[i].lat;
		fp_t lon = graph[i].lon;

		uint32_t d_lat = lat.to_double() *fp_factor;
		uint32_t d_lon = lon.to_double() * fp_factor;
		//if (i==destNode)
		printf("%d lat lon %.10f %.10f %x %x\n",i,lat.to_float(), lon.to_float(), d_lat, d_lon);

		data[BASE_LATLON + (i*2)  ] = d_lat;
		data[BASE_LATLON + (i*2)+1] = d_lon;
	}
	data[BASE_EDGE_OFFSET + numNodes] = offset;

	data[11] = data[BASE_LATLON + (destNode*2)];
	data[12] = data[BASE_LATLON + (destNode*2 + 1)];


	char out_name[100];
	sprintf(out_name,"%s_%d_%d.csr", graph_name.c_str(), startNode, destNode);
	printf("Writing File %s\n", out_name);
	FILE* out_file = fopen(out_name, "w");
	for (int i=0;i<BASE_END;i++){
		fprintf(out_file, "%08x\n", data[i]);
	}
}

int main () {



	std::string in_file = graph_name+".bin";
	LoadGraph(in_file.c_str());
	startNode =  1*numNodes/10;
	destNode =  9*numNodes/10;
	//startNode = 12277337;
	//destNode = 11049603;
	startNode = 159;
	destNode = 1543;
	printf("Finding shortest path between nodes %d and %d\n", startNode, destNode);

	Vertex* source = &graph[startNode];
	Vertex* target = &graph[destNode];

	fp_t target_lat = target->lat;
	fp_t target_lon = target->lon;

	fp_t src_lat = source->lat;
	fp_t src_lon = source->lon;

	uint32_t init_dist;
	printf(" src: lat lon %f %f\n", source->lat, source->lon);
	astar_dist(src_lat, src_lon, target_lat, target_lon, &init_dist);
    std::priority_queue<Task, std::vector<Task>, compare_node> pq;

    Task init_task = { init_dist , 0, startNode, (uint32_t) (-1)};
    pq.push(init_task);

    printf("Init Dist %d\n", init_dist);

    int done = 0;

    while (!pq.empty()) {
    	Task t = pq.top();
    	pq.pop();
    	printf("Dequeue %d %d %d %d\n", t.ts, t.vertex, t.fScore, t.parent);
    	if (t.ts < graph[t.vertex].currentF) {
    		graph[t.vertex].prev = t.parent;
    		graph[t.vertex].currentF = t.ts;
    		if (t.vertex == destNode) {
    			actDist = t.fScore;
    			break;
    		}
			for (int i= 0; i<graph[t.vertex].adj.size();i++){
				Adj neighbor = graph[t.vertex].adj[i];
				Vertex* n = &graph[neighbor.n];
				uint32_t nFScore = t.fScore + (neighbor.d_m);
				uint32_t dist;
				astar_dist(n->lat, n->lon, target_lat, target_lon, &dist);
				//printf("\t\t lat: %x  %x %d\n", (uint32_t) (n->lat * (1<<30) * 2),(uint32_t) (n->lon * (1<<30) * 2) , dist );
				uint32_t nGScore = std::max(t.ts, nFScore + dist);
				Task enq = {nGScore, nFScore, neighbor.n, t.vertex};
				printf("\tenqueue %d %d %d dist:%d\n", enq.ts, enq.vertex, enq.fScore, dist);
				pq.push(enq);
			}
    	}
    }

    WriteFile();
	// Return 0 if the test passes
  return 0;
}
