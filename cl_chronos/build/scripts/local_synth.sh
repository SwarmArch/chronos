#!/bin/sh
if [ "$#" -ne 1 ]; then
   echo "Usage: local_synth.sh module" >&2
   exit 1
fi
./aws_build_dcp_from_cl.sh -ignore_memory_requirement -foreground -script local_synth.tcl -module $1 

