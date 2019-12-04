/** $lic$
 * Copyright (C) 2014-2019 by Massachusetts Institute of Technology
 *
 * This file is part of the Chronos FPGA Acceleration Framework.
 *
 * Chronos is free software; you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, version 2.
 *
 * If you use this framework in your research, we request that you reference
 * the Chronos paper ("Chronos: Efficient Speculative Parallelism for
 * Accelerators", Abeydeera and Sanchez, ASPLOS-25, March 2020), and that
 * you send us a citation of your work.
 *
 * Chronos is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */


// CL_SH_ID0
// - PCIe Vendor/Device ID Values
//    31:16: PCIe Device ID
//    15: 0: PCIe Vendor ID
//    - A Vendor ID value of 0x8086 is not valid.
//    - If using a Vendor ID value of 0x1D0F (Amazon) then valid
//      values for Device ID's are in the range of 0xF000 - 0xF0FF.
//    - A Vendor/Device ID of 0 (zero) is not valid.
`define CL_SH_ID0       32'hF000_1D0F

// CL_SH_ID1
// - PCIe Subsystem/Subsystem Vendor ID Values
//    31:16: PCIe Subsystem ID
//    15: 0: PCIe Subsystem Vendor ID
// - A PCIe Subsystem/Subsystem Vendor ID of 0 (zero) is not valid
`define CL_SH_ID1       32'h1D51_FEDD


