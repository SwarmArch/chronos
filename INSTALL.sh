#!/bin/bash
if [ -e aws-fpga ] 
then
   echo "aws-fpga already exists. Not cloning.." 
else
   git clone https://github.com/aws/aws-fpga.git
fi 

if [ -e aws-fpga/hdk/cl/developer_designs/cl_chronos ] 
then
   echo "cl_chronos symling already exists. Not creating.." 
else
   ln -s cl_chronos aws-fpga/hdk/cl/developer_designs/cl_chronos 
   echo "Creating symlink aws_fpga/hdk/cl/developer_designs/cl_chronos" 
fi

## source aws_setup.sh
## TODO install DMA drivers
