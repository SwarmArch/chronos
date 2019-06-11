This repo contains Chronos, an FPGA Framework to accelerate ordered
applications, on the Amazon AWS FPGA platform.

All Chronos specific code is in hdk/cl/developer_designs/cl_swarm/. 
Refer to the README file there for instructions on how to build and run Chronos. 

Setting up the environment
==========================

We recommend using the Amazon AWS instances with the AWS FPGA Developer AMI
(https://aws.amazon.com/marketplace/pp/B06VVYBLZZ) for all development work. 

Currently we are using r1.4xlarge instances for synthesis/simulation and f1.2xlarge
instance for FPGA testing.


To configure enviroment variable for synthesis/simulation:

source hdk_setup.sh
(cd hdk/cl/developer_designs/cl_swarm; export CL_DIR=$(pwd))

To configure enviroment for FPGA testing:

source sdk_setup.sh
