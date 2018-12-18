# Amazon FPGA Hardware Development Kit
#
# Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#    http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions and
# limitations under the License.

package require tar

## Do not edit $TOP
set TOP top_sp

## Replace with the name of your module
set CL_MODULE tile

#################################################
## Command-line Arguments
#################################################
set timestamp           [lindex $argv  0]
set strategy            [lindex $argv  1]
set hdk_version         [lindex $argv  2]
set shell_version       [lindex $argv  3]
set device_id           [lindex $argv  4]
set vendor_id           [lindex $argv  5]
set subsystem_id        [lindex $argv  6]
set subsystem_vendor_id [lindex $argv  7]
set clock_recipe_a      [lindex $argv  8]
set clock_recipe_b      [lindex $argv  9]
set clock_recipe_c      [lindex $argv 10]
set uram_option         [lindex $argv 11]
set notify_via_sns      [lindex $argv 12]

#################################################
## Generate CL_routed.dcp (Done by User)
#################################################
puts "AWS FPGA Scripts";
puts "Creating Design Checkpoint from Custom Logic source code";
puts "HDK Version:            $hdk_version";
puts "Shell Version:          $shell_version";
puts "Vivado Script Name:     $argv0";
puts "Strategy:               $strategy";
puts "PCI Device ID           $device_id";
puts "PCI Vendor ID           $vendor_id";
puts "PCI Subsystem ID        $subsystem_id";
puts "PCI Subsystem Vendor ID $subsystem_vendor_id";
puts "Clock Recipe A:         $clock_recipe_a";
puts "Clock Recipe B:         $clock_recipe_b";
puts "Clock Recipe C:         $clock_recipe_c";
puts "URAM option:            $uram_option";
puts "Notify when done:       $notify_via_sns";

#checking if CL_DIR env variable exists
if { [info exists ::env(CL_DIR)] } {
        set CL_DIR $::env(CL_DIR)
        puts "Using CL directory $CL_DIR";
} else {
        puts "Error: CL_DIR environment variable not defined ! ";
        puts "Use export CL_DIR=Your_Design_Root_Directory"
        exit 2
}

#checking if HDK_SHELL_DIR env variable exists
if { [info exists ::env(HDK_SHELL_DIR)] } {
        set HDK_SHELL_DIR $::env(HDK_SHELL_DIR)
        puts "Using Shell directory $HDK_SHELL_DIR";
} else {
        puts "Error: HDK_SHELL_DIR environment variable not defined ! ";
        puts "Run the hdk_setup.sh script from the root directory of aws-fpga";
        exit 2
}

#checking if HDK_SHELL_DESIGN_DIR env variable exists
if { [info exists ::env(HDK_SHELL_DESIGN_DIR)] } {
        set HDK_SHELL_DESIGN_DIR $::env(HDK_SHELL_DESIGN_DIR)
        puts "Using Shell design directory $HDK_SHELL_DESIGN_DIR";
} else {
        puts "Error: HDK_SHELL_DESIGN_DIR environment variable not defined ! ";
        puts "Run the hdk_setup.sh script from the root directory of aws-fpga";
        exit 2
}

##################################################
### Output Directories used by step_user.tcl
##################################################
set implDir   $CL_DIR/build/checkpoints
set rptDir    $CL_DIR/build/reports
set cacheDir  $HDK_SHELL_DESIGN_DIR/cache/ddr4_phy

puts "All reports and intermediate results will be time stamped with $timestamp";

set_msg_config -id {Chipscope 16-3} -suppress
set_msg_config -string {AXI_QUAD_SPI} -suppress

# Suppress Warnings
# These are to avoid warning messages that may not be real issues. A developer
# may comment them out if they wish to see more information from warning
# messages.
set_msg_config -id {Common 17-55}        -suppress
set_msg_config -id {Vivado 12-4739}      -suppress
set_msg_config -id {Constraints 18-4866} -suppress
set_msg_config -id {IP_Flow 19-2162}     -suppress
set_msg_config -id {Route 35-328}        -suppress
set_msg_config -id {Vivado 12-1008}      -suppress
set_msg_config -id {Vivado 12-508}       -suppress
set_msg_config -id {filemgmt 56-12}      -suppress
set_msg_config -id {DRC CKLD-1}          -suppress
set_msg_config -id {DRC CKLD-2}          -suppress
set_msg_config -id {IP_Flow 19-2248}     -suppress
set_msg_config -id {Vivado 12-1580}      -suppress
set_msg_config -id {Constraints 18-550}  -suppress
set_msg_config -id {Synth 8-3295}        -suppress
set_msg_config -id {Synth 8-3321}        -suppress
set_msg_config -id {Synth 8-3331}        -suppress
set_msg_config -id {Synth 8-3332}        -suppress
set_msg_config -id {Synth 8-6014}        -suppress
set_msg_config -id {Timing 38-436}       -suppress
set_msg_config -id {DRC REQP-1853}       -suppress
set_msg_config -id {Synth 8-350}         -suppress
set_msg_config -id {Synth 8-3848}        -suppress
set_msg_config -id {Synth 8-3917}        -suppress

puts "AWS FPGA: ([clock format [clock seconds] -format %T]) Calling the encrypt.tcl.";

# Check that an email address has been set, else unset notify_via_sns

if {[string compare $notify_via_sns "1"] == 0} {
  if {![info exists env(EMAIL)]} {
    puts "AWS FPGA: ([clock format [clock seconds] -format %T]) EMAIL variable empty!  Completition notification will *not* be sent!";
    set notify_via_sns 0;
  } else {
    puts "AWS FPGA: ([clock format [clock seconds] -format %T]) EMAIL address for completion notification set to $env(EMAIL).";
  }
}

##################################################
### Strategy options 
##################################################
switch $strategy {
    "BASIC" {
        puts "BASIC strategy."
        source $HDK_SHELL_DIR/build/scripts/strategy_BASIC.tcl
    }
    "EXPLORE" {
        puts "EXPLORE strategy."
        source $HDK_SHELL_DIR/build/scripts/strategy_EXPLORE.tcl
    }
    "TIMING" {
        puts "TIMING strategy."
        source $HDK_SHELL_DIR/build/scripts/strategy_TIMING.tcl
    }
    "CONGESTION" {
        puts "CONGESTION strategy."
        source $HDK_SHELL_DIR/build/scripts/strategy_CONGESTION.tcl
    }
    "DEFAULT" {
        puts "DEFAULT strategy."
        source $HDK_SHELL_DIR/build/scripts/strategy_DEFAULT.tcl
    }
    default {
        puts "$strategy is NOT a valid strategy. Defaulting to strategy DEFAULT."
        source $HDK_SHELL_DIR/build/scripts/strategy_DEFAULT.tcl
    }
}

# imitate encrypt.tcl without actually encrypting
set HDK_SHELL_DESIGN_DIR $::env(HDK_SHELL_DESIGN_DIR)
set CL_DIR $::env(CL_DIR)
set TARGET_DIR $CL_DIR/build/src_post_encryption
set UNUSED_TEMPLATES_DIR $HDK_SHELL_DESIGN_DIR/interfaces
exec rm -f $TARGET_DIR/*
file copy -force {*}[glob -nocomplain -- $CL_DIR/design/*.{v,sv,vh}]  $TARGET_DIR 
file copy -force {*}[glob -nocomplain -- $CL_DIR/design/apps/sssp_hls/*.{v,sv,vh}]  $TARGET_DIR 
file copy -force {*}[glob -nocomplain -- $CL_DIR/design/apps/sssp/*.{v,sv,vh}]  $TARGET_DIR 
file copy -force {*}[glob -nocomplain -- $CL_DIR/design/apps/des/*.{v,sv,vh}]  $TARGET_DIR 
file copy -force {*}[glob -nocomplain -- $CL_DIR/design/apps/astar/*.{v,sv,vh,dat}]  $TARGET_DIR 
file copy -force {*}[glob -nocomplain -- $CL_DIR/design/apps/riscv/*.{v,sv,vh,dat}]  $TARGET_DIR 
file copy -force {*}[glob -nocomplain -- $UNUSED_TEMPLATES_DIR/*.inc]  $TARGET_DIR 

#Set the Device Type: Closest to vu9p but supported in vivado webpack
proc DEVICE_TYPE {} {
    return xcku3p-ffva676-2-i
}

#Procedure for running various implementation steps (impl_step)
source $HDK_SHELL_DIR/build/scripts/step_user.tcl -notrace

#####################################################################
#imported from synth_*.tcl

########################################
## Generate clocks based on Recipe 
########################################

puts "AWS FPGA: ([clock format [clock seconds] -format %T]) Calling aws_gen_clk_constraints.tcl to generate clock constraints from developer's specified recipe.";

source $HDK_SHELL_DIR/build/scripts/aws_gen_clk_constraints.tcl

##################################################
### CL XPR OOC Synthesis
##################################################
#Param needed to avoid clock name collisions
set_param sta.enableAutoGenClkNamePersistence 0
set CL_MODULE $CL_MODULE

create_project -in_memory -part [DEVICE_TYPE] -force

########################################
## Generate clocks based on Recipe 
########################################

puts "AWS FPGA: ([clock format [clock seconds] -format %T]) Calling aws_gen_clk_constraints.tcl to generate clock constraints from developer's specified recipe.";

source $HDK_SHELL_DIR/build/scripts/aws_gen_clk_constraints.tcl

#############################
## Read design files
#############################

#Convenience to set the root of the RTL directory
set ENC_SRC_DIR $CL_DIR/build/src_post_encryption

puts "AWS FPGA: ([clock format [clock seconds] -format %T]) Reading developer's Custom Logic files post encryption.";

#---- User would replace this section -----

# Reading the .sv and .v files, as proper designs would not require
# reading .v, .vh, nor .inc files

read_verilog -sv [glob $ENC_SRC_DIR/*.sv]
read_verilog  [glob $ENC_SRC_DIR/*.v]

#---- End of section replaced by User ----

puts "AWS FPGA: Reading AWS Shell design";

#Read AWS Design files
read_verilog [ list \
  $HDK_SHELL_DESIGN_DIR/lib/lib_pipe.sv \
  $HDK_SHELL_DESIGN_DIR/lib/bram_2rw.sv \
  $HDK_SHELL_DESIGN_DIR/lib/flop_fifo.sv \
  $HDK_SHELL_DESIGN_DIR/sh_ddr/synth/sync.v \
  $HDK_SHELL_DESIGN_DIR/sh_ddr/synth/flop_ccf.sv \
  $HDK_SHELL_DESIGN_DIR/sh_ddr/synth/ccf_ctl.v \
  $HDK_SHELL_DESIGN_DIR/sh_ddr/synth/mgt_acc_axl.sv  \
  $HDK_SHELL_DESIGN_DIR/sh_ddr/synth/mgt_gen_axl.sv  \
  $HDK_SHELL_DESIGN_DIR/sh_ddr/synth/sh_ddr.sv \
  $HDK_SHELL_DESIGN_DIR/interfaces/cl_ports.vh 
]

puts "AWS FPGA: Reading IP blocks";

#Read DDR IP
read_ip [ list \
  $HDK_SHELL_DESIGN_DIR/ip/ddr4_core/ddr4_core.xci 
]

#Read IP for axi register slices
read_ip [ list \
  $HDK_SHELL_DESIGN_DIR/ip/src_register_slice/src_register_slice.xci \
  $HDK_SHELL_DESIGN_DIR/ip/dest_register_slice/dest_register_slice.xci \
  $HDK_SHELL_DESIGN_DIR/ip/axi_clock_converter_0/axi_clock_converter_0.xci \
  $HDK_SHELL_DESIGN_DIR/ip/axi_register_slice/axi_register_slice.xci \
  $HDK_SHELL_DESIGN_DIR/ip/axi_register_slice_light/axi_register_slice_light.xci
]

# Additional IP's that might be needed if using the DDR
#read_bd [ list \
# $HDK_SHELL_DESIGN_DIR/ip/ddr4_core/ddr4_core.xci \
# $HDK_SHELL_DESIGN_DIR/ip/cl_axi_interconnect/cl_axi_interconnect.bd
#]

puts "AWS FPGA: Reading AWS constraints";

#Read all the constraints
#
#  cl_clocks_aws.xdc  - AWS auto-generated clock constraint.   ***DO NOT MODIFY***
#  cl_ddr.xdc         - AWS provided DDR pin constraints.      ***DO NOT MODIFY***
#  cl_synth_user.xdc  - Developer synthesis constraints.
read_xdc [ list \
   $CL_DIR/build/constraints/cl_clocks_aws.xdc \
   $HDK_SHELL_DIR/build/constraints/cl_ddr.xdc \
   $HDK_SHELL_DIR/build/constraints/cl_synth_aws.xdc \
   $CL_DIR/build/constraints/cl_synth_user.xdc
]

#Do not propagate local clock constraints for clocks generated in the SH
set_property USED_IN {synthesis implementation OUT_OF_CONTEXT} [get_files cl_clocks_aws.xdc]
set_property PROCESSING_ORDER EARLY  [get_files cl_clocks_aws.xdc]

########################
# CL Synthesis
########################
puts "AWS FPGA: ([clock format [clock seconds] -format %T]) Start design synthesis.";

# Not in original. increase in high-end machines
set_param general.maxThreads 1

update_compile_order -fileset sources_1
puts "\nRunning synth_design for $CL_MODULE $CL_DIR/build/scripts \[[clock format [clock seconds] -format {%a %b %d %H:%M:%S %Y}]\]"
eval [concat synth_design -top $CL_MODULE -verilog_define XSDB_SLV_DIS -part [DEVICE_TYPE] -mode out_of_context $synth_options -directive $synth_directive]

set failval [catch {exec grep "FAIL" failfast.csv}]
if { $failval==0 } {
  puts "AWS FPGA: FATAL ERROR--Resource utilization error; check failfast.csv for details"
  exit 1
}

puts "AWS FPGA: ([clock format [clock seconds] -format %T]) writing post synth checkpoint.";
write_checkpoint -force $CL_DIR/build/checkpoints/${timestamp}.CL.post_synth.dcp

report_utilization -hierarchical

close_project
#Set param back to default value
set_param sta.enableAutoGenClkNamePersistence 1
