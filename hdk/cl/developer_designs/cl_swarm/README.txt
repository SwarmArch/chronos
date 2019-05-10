
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

<TODO>



