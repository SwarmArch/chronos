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


package des; 
typedef enum logic [2:0] { BUF, INV, NAND2, NOR2, AND2, OR2, XOR2, XNOR2 } gate_t;
typedef enum logic [1:0] { LOGIC_0 =0, LOGIC_1=1, LOGIC_X=2, LOGIC_Z=3 } logic_val_t; 
endpackage

import des::*;

module logic_eval (
   input logic_val_t p0,
   input logic_val_t p1,
   gate_t gate,
   
   output logic_val_t o
   
);

always_comb begin
   case (gate) 
      BUF: o = p0;
      INV: begin
         if (p0 == LOGIC_0) o = LOGIC_1;
         else if (p0 == LOGIC_1) o= LOGIC_0;
         else o = p0;
      end
      NAND2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) | (p1 == LOGIC_0)) o = LOGIC_1;
         else o = LOGIC_X;
      end
      NOR2: begin
         if ((p0 == LOGIC_1) | (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_1;
         else o = LOGIC_X;
      end
      AND2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) | (p1 == LOGIC_0)) o = LOGIC_0;
         else o = LOGIC_X;
      end
      OR2: begin
         if ((p0 == LOGIC_1) | (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_0;
         else o = LOGIC_X;
      end
      XOR2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_1) & (p1 == LOGIC_0)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_0;
         else o = LOGIC_X;
      end
      XNOR2: begin
         if ((p0 == LOGIC_1) & (p1 == LOGIC_1)) o = LOGIC_1;
         else if (( p0 == LOGIC_1) & (p1 == LOGIC_0)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_1)) o = LOGIC_0;
         else if (( p0 == LOGIC_0) & (p1 == LOGIC_0)) o = LOGIC_1;
         else o = LOGIC_X;
      end

   endcase

end

endmodule
