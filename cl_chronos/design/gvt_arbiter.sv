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

import chronos::*;

module gvt_arbiter (
   input clk,
   input rstn,

   input vt_t [C_N_TILES-1:0] lvt,
   output vt_t gvt
);
// Tree of comparators
vt_t tree [$clog2(C_N_TILES):0][C_N_TILES-1:0];

genvar i,j;

generate 
for (i=0;i<C_N_TILES;i++) begin
   assign tree[$clog2(C_N_TILES)][i] = lvt[i];
end
endgenerate

generate
   for (i=$clog2(C_N_TILES)-1;i>=0;i--) begin
      for (j=0;j< 2**i;  j++) begin
         always_ff @(posedge clk) begin
            tree[i][j] <= (tree[i+1][j*2] < tree[i+1][j*2+1]) ? 
                                       tree[i+1][j*2] : tree[i+1][j*2+1];
         end
      end
   end
endgenerate


lib_pipe #(
   .WIDTH(TS_WIDTH + TB_WIDTH),
   .STAGES(2)
) GVT_PIPE (
   .clk(clk), 
   .rst_n(1'b1),
   
   .in_bus ( tree[0][0] ),
   .out_bus( gvt )
); 


endmodule
