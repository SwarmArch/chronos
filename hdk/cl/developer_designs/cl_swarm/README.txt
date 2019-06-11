
The directory contains all code for Chronos, an FPGA Acceleration framework for
ordered applictions.

Directory Structure
===================

i) build/   
This directory all synthesis scripts

ii) design/  
All RTL design files go here. The top module is contained in cl_swarm.sv


design/config.sv contains all generic configuration information (eg: number of tiles,
queue sizes etc..)

All individual applications are in design/apps/.
Each app consist of a separate .sv file for each core type along with a
config.vh file for applicaton-specific configuration
(eg: how many of each core type per tile).

To configure/change the currently running application, 
run:

cd design
./scripts/gen_cores.py <app_name>

This script would read the corresponding config.vh and generate several RTL
files (gen_core_spec.vh and gen_core_spec_tile.vh) required for
synthesis and simulation.

iii) hls/ 

HLS versions of astar and sssp

iv) riscv_code/ 

code for all applications with risc-v variants

v) software/

Runtime code that will program the FPGA, transfer the data, and collect and
analyze and performance results.

vi) tools/

Contains miscelleaneous tools. One such tool, 'graph_gen' is used to generate
test inputs (and do format conversion of existing inputs) for graph algorithms.

vii) verif/

RTL verification code and scripts.



Getting started - A tutorial on configuring and running sssp.
=============================================================

Step 1: Configure number of tiles and other queue sizes in design/config.sv
For this example, we will build a single tile system with the default
parameters.


Step 2: Configure Chronos to use sssp

We will build an 8 cores/tile sssp system. This is specified in
design/apps/sssp/config.vh

run the following to generate the sssp cores

cd design
./scripts/gen_cores.py sssp

Step 3: Test graph generation

We will use the vivado RTL simulator to verify our design works correctly by
running sssp on a small graph. First to generate such a graph we need to run the
graph_gen tool.

( $CL_DIR = hdk/cl/developer_design/cl_swarm)

cd $CL_DIR/tools/graph_gen/
make
./graph_gen sssp 1 4

This would generate a 4x4 mesh graph random weights. (grid_4x4.sssp).

Step 4: RTL Simulation

4.1) First, compile the design with Vivado simulator. Our testbench is in
(verif/tests/test_swarm)

cd $CL_DIR/verif/scripts/
make TEST=test_swarm compile

This would create a folder verif/sim/test_swarm.
4.2) Now We need to copy over input file into this folder before running the simulation.

cp $CL_DIR/tools/graph_gen/grid_4x4.sssp
$CL_DIR/verif/sim/test_swarm/input_graph

(The testbench expects input file be named 'input_graph')

4.3) Now run the simulation

cd $CL_DIR/verif/scripts/
make TEST=test_swarm run

If all goes well, you will see the testbench completing with 0 errors


Step 5: Synthesis

TODO
