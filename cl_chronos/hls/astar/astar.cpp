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
#include "astar.h"

#include "math.h"
#include "hls_math.h"
#include "fxp_sqrt.h"
#include "ap_fixed.h"
#include "hls_dsp.h"
#include <string.h>



void astar_dist (fp_t src_lat, fp_t src_lon, fp_t dst_lat, fp_t dst_lon, unsigned int* out) {
#pragma HLS pipeline II=2 enable_flush rewind

	fp_t xdiff = src_lat-dst_lat;
	fp_t ydiff = src_lon-dst_lon;
	fp_t latS = hls::sin(xdiff);
	fp_t lonS = hls::sin(ydiff);

	fp_t latSrcC = hls::cos(src_lat);
	fp_t latDstC = hls::cos(dst_lat);

	//printf("Src Lat %.12f \n", src_lat.to_float() );
	//printf("Sin %.12f %.12f \n", latS.to_float(), lonS.to_float());
	//printf("Cos %.12f %.12f \n", latSrcC.to_float(), latDstC.to_float());

	fp_t latS2 = latS*latS;
	fp_t lonS2 = lonS*lonS;
	fp_t C2    = latSrcC*latDstC;

	//printf("latS2 %.12f lonS2 %.12f C2: %.12f\n", latS2.to_float(), lonS2.to_float(), C2.to_float());

	ap_ufixed<64,8> a = latS*latS + lonS*lonS*latSrcC* latDstC;

	//printf("a %.15f \n", a.to_float() );
	a = a << 16;
	ap_ufixed<32,8> ua = a;
	ap_ufixed<32,2> uminusa = 1-(a>>16);
	ap_ufixed<32,8> sqrta_shift;
	ap_ufixed<32,2> sqrt_minus_a;
	ap_ufixed<32,2> sqrta;
	fxp_sqrt(sqrta_shift, ua);
	fxp_sqrt(sqrt_minus_a, uminusa);
	sqrta = sqrta_shift >> 8;
	//fp_t one_minus_a = 1-a;
	//fp_t sq2 = hls::sqrt(one_minus_a);
	//fp_t c = 2*hls::atan2(sq1, sq2);
	hls::atan2_input<32>::cartesian x;
	std::complex<ap_ufixed<32,2>> com(sqrta, sqrt_minus_a);
	x.cartesian = com;
	//hls::atan2_input<32>::cartesian y;
	//x.cartesian.imag() = ad;
	//x.cartesian.real() = sqrt_minus_a;

	//printf("sqrt(%.10f %.10f): %.10f sqrt(%.10f): %.10f\n",a.to_float(), ua.to_float(), sqrta.to_float(), uminusa.to_float(), sqrt_minus_a.to_float() );
	//printf("atan2(%0.10f, %0.10f)\n", x.cartesian.real().to_float(), x.cartesian.imag().to_float());

	hls::atan2_output<32>::phase atanX;



	hls::atan2<hls::CORDIC_FORMAT_RAD,32,32,hls::CORDIC_ROUND_TRUNCATE>(x, atanX);
	//printf("atan2 out %0.10f\n", atanX.phase.to_float());

	//*out = 2* atanX.phase * 6371000; // unit in m
	*out = 2* sqrta * 6371000; // unit in m

}










