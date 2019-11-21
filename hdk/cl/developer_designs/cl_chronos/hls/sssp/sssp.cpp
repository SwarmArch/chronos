/*******************************************************************************
Vendor: Xilinx
Associated Filename: array_io.c
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
#include "sssp.h"

#include "math.h"
#include <string.h>
//#define BURST  // Slightly better. (avg. task length reduces by 3)


void sssp_hls (task_t task_in, hls::stream<task_t>* task_out, ap_uint<32>* l1, hls::stream<undo_log_t>* undo_log_entry) {
#pragma HLS PIPELINE II=15 enable_flush rewind
#pragma HLS INTERFACE axis port=undo_log_entry
#pragma HLS DATA_PACK variable=undo_log_entry
#pragma HLS INTERFACE m_axi depth=1000 port=l1
#pragma HLS DATA_PACK variable=task_in
#pragma HLS INTERFACE axis port=task_out
#pragma HLS DATA_PACK variable=task_out

	// HLS Does not support 64-bit addr
	// https://forums.xilinx.com/t5/Vivado-High-Level-Synthesis-HLS/Simple-question-how-to-get-64bit-addresses-on-ALL-AXI-busses/td-p/669669

	int i;

	static ap_uint<1> initialized = 0;
	static ap_uint<32> base_offset;
	static ap_uint<32> base_neighbor;
	static ap_uint<32> base_dist;

#ifdef BURST
	ap_uint<32> edge_buf[16];
#endif

	if (!initialized) {
		initialized = 1;
		base_offset = l1[3];
		base_neighbor = l1[4];
		base_dist = l1[5];
		//printf("base %d %d\n", base_offset, base_neighbor);
	}

	ap_uint<32> vid = task_in.hint;

	ap_uint<32> cur_dist = l1[base_dist + vid];
	if (task_in.ts < cur_dist ) {

		l1[base_dist +vid] = task_in.ts;

		ap_uint<32> offset_begin = l1[base_offset + vid];
		ap_uint<32> offset_end = l1[base_offset + vid+1];

#ifdef BURST
		memcpy(edge_buf, (const ap_uint<32>*) (l1 + (base_neighbor + offset_begin*2)), 4*2*(offset_end - offset_begin));
		for (i=0; i < offset_end-offset_begin; i++) {
			task_t child = {task_in.ts + edge_buf[i*2+1], edge_buf[i*2], 0, 0};
			task_out->write(child);
		}
#else
		for (i=offset_begin; i < offset_end; i++) {
			ap_uint<32> neighbor = l1[base_neighbor + i*2];
			ap_uint<32> weight = l1[base_neighbor + i*2+1];

			task_t child = {task_in.ts + weight, neighbor, 0, 0};
			task_out->write(child);
		}
#endif
		undo_log_t ulog;
		ulog.addr = (base_dist + vid) << 2;
		ulog.data = cur_dist;
		undo_log_entry->write(ulog);
	}


}











