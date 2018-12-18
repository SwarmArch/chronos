import swarm::*;

module gvt_arbiter (
   input clk,
   input rstn,

   input vt_t [N_TILES-1:0] lvt,
   output vt_t gvt
);
// Tree of comparators
vt_t tree [$clog2(N_TILES):0][N_TILES-1:0];

genvar i,j;

generate 
for (i=0;i<N_TILES;i++) begin
   assign tree[$clog2(N_TILES)][i] = lvt[i];
end
endgenerate

generate
   for (i=$clog2(N_TILES)-1;i>=0;i--) begin
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
