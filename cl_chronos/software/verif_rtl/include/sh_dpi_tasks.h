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

// Amazon FPGA Hardware Development Kit
//
// Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.

#ifndef SH_DPI_TASKS
#define SH_DPI_TASKS

#include <stdarg.h>

extern void sv_printf(char *msg);
extern void sv_map_host_memory(uint8_t *memory);

extern void cl_peek(uint64_t addr, uint32_t *data);
extern void cl_poke(uint64_t addr, uint32_t  data);
extern void sv_pause(uint32_t x);

void test_main(uint32_t *exit_code);

void host_memory_putc(uint64_t addr, uint8_t data)
{
  *(uint8_t *)addr = data;
}

//void host_memory_getc(uint64_t addr, uint8_t *data)
uint8_t host_memory_getc(uint64_t addr)
{
  return *(uint8_t *)addr;
}

void log_printf(const char *format, ...)
{
  static char sv_msg_buffer[256];
  va_list args;

  va_start(args, format);
  vsprintf(sv_msg_buffer, format, args);
  sv_printf(sv_msg_buffer);

  va_end(args);
}

#define LOW_32b(a)  ((uint32_t)((uint64_t)(a) & 0xffffffff))
#define HIGH_32b(a) ((uint32_t)(((uint64_t)(a)) >> 32L))

#endif
