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

-define VIVADO_SIM
-define ROM_INIT_PATH="${CL_ROOT}/design/apps/astar"

-sourcelibext .v
-sourcelibext .sv
-sourcelibext .svh

-sourcelibdir ${CL_ROOT}/../common/design
-sourcelibdir ${CL_ROOT}/design
-sourcelibdir ${CL_ROOT}/verif/sv
-sourcelibdir ${SH_LIB_DIR}
-sourcelibdir ${SH_INF_DIR}
-sourcelibdir ${SH_SH_DIR}
--sourcelibdir ${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim
-sourcelibdir ${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/hdl
-sourcelibdir ${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/sim

-include ${CL_ROOT}/../common/design
-include ${CL_ROOT}/verif/sv
-include ${CL_ROOT}/design/apps/astar
--include ${SH_LIB_DIR}
--include ${SH_INF_DIR}
--include ${HDK_COMMON_DIR}/verif/include
--include ${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_0/sim
--include ${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_0/hdl/verilog
--include ${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice/hdl
--include ${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice_light/hdl
--include ${CL_ROOT}/design/axi_crossbar_0
--include ${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ipshared/7e3a/hdl
--include ${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim

# ${CL_ROOT}/../common/design/cl_common_defines.vh
# ${CL_ROOT}/design/cl_swarm_defines.vh
${CL_ROOT}/design/config.sv
${CL_ROOT}/design/interface.sv
${CL_ROOT}/verif/tests/mem_ctrl.sv
${CL_ROOT}/design/util.sv
${CL_ROOT}/design/pci_arbiter.sv
${CL_ROOT}/design/l2.sv
${CL_ROOT}/design/task_unit.sv
${CL_ROOT}/design/task_unit_unordered.sv
${CL_ROOT}/design/task_unit_nonspec.sv
${CL_ROOT}/design/cq_slice.sv
${CL_ROOT}/design/axi_decoder.sv
${CL_ROOT}/design/axi_pipe.sv
${CL_ROOT}/design/conflict_serializer.sv
${CL_ROOT}/design/undo_log.sv
${CL_ROOT}/design/tsb.sv
${CL_ROOT}/design/child_manager.sv
${CL_ROOT}/design/min_heap.sv
${CL_ROOT}/design/read_rw.sv
${CL_ROOT}/design/write_rw.sv
${CL_ROOT}/design/read_only_stage.sv
${CL_ROOT}/design/axi_xbar.sv
${CL_ROOT}/design/task_xbar.sv
${CL_ROOT}/design/ocl_slave.sv
${CL_ROOT}/design/ocl_arbiter.sv
${CL_ROOT}/design/gvt_arbiter.sv
${CL_ROOT}/design/mem_arbiter.sv
${CL_ROOT}/design/tile.sv
${CL_ROOT}/design/core.sv
#${CL_ROOT}/design/sssp_core.sv
#${CL_ROOT}/design/des_core.sv
#${CL_ROOT}/design/des_enqueuer.sv
${CL_ROOT}/design/coalescer.sv
${CL_ROOT}/design/splitter.sv
${CL_ROOT}/design/l2_arbiter.sv
${CL_ROOT}/design/VexRiscv.v
${CL_ROOT}/design/apps/sssp_hls/sssp_hls.v
${CL_ROOT}/design/apps/sssp_hls/sssp_hls_l1_V_m_axi.v
${CL_ROOT}/design/apps/sssp/sssp_core.sv
${CL_ROOT}/design/apps/des/des_core.sv
${CL_ROOT}/design/apps/des/des_enqueuer.sv
${CL_ROOT}/design/apps/astar/astar.sv
# ${CL_ROOT}/design/apps/astar/visit_vertex.sv
${CL_ROOT}/design/apps/riscv/riscv_core.sv
${CL_ROOT}/design/apps/maxflow/maxflow.sv
${CL_ROOT}/design/apps/color/color.sv
${CL_ROOT}/design/cl_swarm.sv

-f ${HDK_COMMON_DIR}/verif/tb/filelists/tb.${SIMULATOR}.f
-f ${CL_ROOT}/design/apps/astar/astar.f

${HDK_SHELL_DESIGN_DIR}/ip/axi_clock_converter_0/sim/axi_clock_converter_0.v
${HDK_SHELL_DESIGN_DIR}/ip/dest_register_slice/sim/dest_register_slice.v
${HDK_SHELL_DESIGN_DIR}/ip/src_register_slice/sim/src_register_slice.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice/sim/axi_register_slice.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice_light/sim/axi_register_slice_light.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ipshared/9909/hdl/axi_data_fifo_v2_1_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ipshared/c631/hdl/axi_crossbar_v2_1_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ip/cl_axi_interconnect_xbar_0/sim/cl_axi_interconnect_xbar_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ip/cl_axi_interconnect_s00_regslice_0/sim/cl_axi_interconnect_s00_regslice_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ip/cl_axi_interconnect_s01_regslice_0/sim/cl_axi_interconnect_s01_regslice_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ip/cl_axi_interconnect_m00_regslice_0/sim/cl_axi_interconnect_m00_regslice_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ip/cl_axi_interconnect_m01_regslice_0/sim/cl_axi_interconnect_m01_regslice_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ip/cl_axi_interconnect_m02_regslice_0/sim/cl_axi_interconnect_m02_regslice_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/ip/cl_axi_interconnect_m03_regslice_0/sim/cl_axi_interconnect_m03_regslice_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_axi_interconnect/sim/cl_axi_interconnect.v
${HDK_SHELL_DESIGN_DIR}/ip/dest_register_slice/hdl/axi_register_slice_v2_1_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_clock_converter_0/hdl/axi_clock_converter_v2_1_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_clock_converter_0/hdl/fifo_generator_v13_2_rfs.v

${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_bi_delay.sv
${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_db_delay_model.sv
${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_db_dly_dir.sv
${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_dir_detect.sv
${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_rcd_model.sv
${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_rank.sv
${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_dimm.sv
${HDK_COMMON_DIR}/verif/models/ddr4_rdimm_wrapper/ddr4_rdimm_wrapper.sv 
${SH_LIB_DIR}/bram_2rw.sv
${SH_LIB_DIR}/flop_fifo.sv
${SH_LIB_DIR}/lib_pipe.sv
${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim/mgt_gen_axl.sv
${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim/ccf_ctl.v
${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim/mgt_acc_axl.sv
${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim/sync.v
${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim/flop_ccf.sv
${HDK_SHELL_DESIGN_DIR}/sh_ddr/sim/sh_ddr.sv
${TEST_NAME}
