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

source aws_setup.sh
## install DMA drivers
# (https://github.com/aws/aws-fpga/blob/master/sdk/linux_kernel_drivers/xdma/xdma_install.md)
sudo rmmod xocl 
sudo yum install kernel kernel-devel
cd aws-fpga/sdk/linux_kernel_drivers/xdma/
make
sudo make install
sudo modprobe xdma
