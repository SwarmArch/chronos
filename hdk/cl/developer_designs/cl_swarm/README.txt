
The directory contains all code for Chronos, an FPGA Acceleration framework for
ordered applictions.

Contents:
1. Directory Structure
2. Getting started - A tutorial on configuring and running sssp
3. Chronos software interface
4. Debugging Chronos
5. September 2019 update changelog

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

   ( $CL_DIR = hdk/cl/developer_design/cl_swarm)
   cd $CL_DIR/design
   ./scripts/gen_cores.py sssp

Step 3: Test graph generation

   We will use the vivado RTL simulator to verify our design works correctly by
   running sssp on a small graph. First to generate such a graph we need to run the
   graph_gen tool.


   cd $CL_DIR/tools/graph_gen/
   make
   ./graph_gen sssp grid 4

   This would generate a 4x4 grid graph with random weights. (grid_4x4.sssp).

Step 4: RTL Simulation

   4.1) First, compile the design with Vivado simulator. Our testbench is in
   (verif/tests/test_swarm)

   cd $CL_DIR/verif/scripts/
   make TEST=test_swarm compile

   This would create a directory verif/sim/test_swarm.

   4.2) Now, we need to copy the input file into this directory before running the simulation.

   cp $CL_DIR/tools/graph_gen/grid_4x4.sssp $CL_DIR/verif/sim/test_swarm/input_graph

   (The testbench expects the input file be named 'input_graph')

   4.3) Now run the simulation

   cd $CL_DIR/verif/scripts/
   make TEST=test_swarm run

   If all goes well, you will see the testbench completing with 0 errors

Step 5: Synthesis

   cd $CL_DIR/build/scripts/
   ./aws_build_dcp_from_cl.sh

   This would launch a vivado synthesis/ place-and-route job. The output of this
   process is a placed-and-routed design placed in
   $CL_DIR/build/checkpoints/to_aws/<timestamp>.Developer_CL.tar 

   Refer to the following document for a detailed account on how to generate a
   runnable FPGA image from the placed-and-routed design.
   https://github.com/aws/aws-fpga/blob/master/hdk/README.md#step3

   However, I will breifly summarize the steps here

   First, copy the design file to a location in Amazon S3.

   aws s3 cp $CL_DIR/build/checkpoints/to_aws/<timestamp>.Developer_CL.tar
      <location_in_s3>.tar 

   Create the FPGA image

   ~/bin/aws ec2 create-fpga-image --name <name> --input-storage-location
   Bucket=<s3_bucket_name>,Key=<location_in_s3> --logs-storage-location
   Bucket=<s3_bucket_name> ,Key=<temp_location_in_s3>

   Running this command would generate an Amazon Image ID which we can load
   into the FPGA.

Step 6: Running sssp on the FPGA

   (Note this step has to be done on an f1.2x AWS instance)

   6.1) Setup the environment
      at repo-root
      source sdk_setup.sh
   6.2) Load the generated image into the FPGA
      sudo fpga-load-local-image -S 0 -I <fgpa_image_id>
      (I've noted that sometimes, this command needed to be run twice the first
      time after the instance is booted up)
      
   6.3) Build and run the runtime program that will transfer the input graph to the FPGA,
   collect the results and analyze performance
      cd $CL_DIR/software/runtime
      make
      ./test_swarm sssp grid_4x4.sssp


Notes on Chronos software interface
===================================

Software communicates with a Chronos FPGA instance through two main interfaces
provided by the AWS Shell. 

1. OCL (Not sure what this stands for) is a 32-bit register access interface. 

   This interface is used to set runtime configuration values (eg. number of tiles,
   queue sizes) as well as read hardware counters.

   THe 32-bit OCL address has the follwing mapping (in verilog style): 
   {8'h 0, 8'h{tile_id}, 8'h{component_id}, 8'h{component_register}. 

   Refer to $CL_DIR/design/addr_map.vh for the complete list of component IDs and
   registers, but as an
   example the current task unit utilization of tile 2 can be read by reading:
   {8'h 0, 8'2, 8'h{ID_TASK_UNIT}, 8'h14}. 

   (The ID_TASK_UNIT would depend on number of cores in the tile).

   In the software runtime code ($CL_DIR/software/runtime/test_swarm.c),
   the helper function pci_peek, pci_poke is to read and write to these registers. 

   Each tile contains a special component, 'OCL_SLAVE' which exposes 
   a register interface to do the following (among others):
      i) read current current cycle number
      ii) read hardware configuration parametes (specified at build time)
      iii) enqueue initial tasks
      iv) read arbitrary memory addresses. 
      iV) check if the program has completed.


2. A DMA interface to transfer data to and from the FPGA


   In the software runtime code ($CL_DIR/software/runtime/test_swarm.c),
   the helper function dma_write is used to write to the FPGA memory.

   (
   NOTE: I've sometimes had trouble transferring data back from the FPGA to the host
   CPU using the DMA mechanism. Hence the software runtime uses the OCL mem read
   mechanism to read completed data (eg: final distance for each node in sssp).

   Although this is slower than DMA reads, I've found it to be more reliable.
   )


Debugging Chronos
=================

Several Chronos components can be configured to log important events to an
on-chip circular buffer (at-speed). 
For example the task queue logs task_enq, task_deq, task_commit, task_abort
events. Refer to each component's .sv file for the full list. 

This logging uses a lot of on-chip RAM, and therefore is not enabled by
default. Refer to config.sv on how to enable. 

The contents of this log can be read through the DMA interface by reading from a
specific address that is beyond the 64GB DDR size. 

Concretely, reading from the address 
( (1<<36) | (t << 28) | (comp << 20 )) will read the log of tile 't' and
component 'comp'. 


SEPTEMBER RELEASE CHANGELOG
===========================

This release includes 3 major updates.
1) Fix several performance bugs in task spilling mechanism. As a result, spilling
throughput should be greatly increased.

2) RISCV code for each application now makes use of a library of common
operations (enq_task, deq_task, undo_log_write, etc..), located in
"riscv_code/include/chronos.h". Application developers should not be required
to explicitly perform accesses to Chronos hardware registers anymore.

3) Pipelined cores: A new template for specifying Chronos tasks in hardware.
Tasks coded with this template are higher throughput, takes less area, and
requires less lines of coding than writing specialized cores for each task.

All five existing applications have already been mapped to this template,
each proving around ~2X speedup. To try it out, add the 'pipe' option to the
gen_cores script. 
e.g,: To generate pipelined sssp cores, run './scripts/gen_cores sssp pipe' at
step 2 in the tutorial above.

This template requires each task be mapped to a read-write
(RW) portion followed by a read-only (RO) portion. The RW portion can only
access the data belonging to the task's locale, while the RO portion can read
any arbitrary read-only data.

e.g,: For SSSP, the RW portion corresponds to reading current distance to the
node, and then updating it. The RO portion reads the offsets, neighbors and
creates new tasks. See 'design/apps/sssp/sssp_pipe.sv' for more documentation.
