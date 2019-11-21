
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
