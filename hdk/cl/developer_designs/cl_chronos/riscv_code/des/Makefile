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

#VPATH = src:include:$(HDK_DIR)/common/software/src:$(HDK_DIR)/common/software/include

INCLUDES = -I$(SDK_DIR)/userspace/include

CC = riscv-none-embed-gcc
CFLAGS = -march=rv32i -mabi=ilp32 -T linker_script 


SRC = main.c 
OBJ = $(SRC:.c=.o)
BIN = main 

all: $(BIN) 

$(BIN): $(OBJ)
	$(CC) $(CFLAGS) -O3 -o $^ $(SRC)  
	riscv-none-embed-objdump -d main.o > main.dump
	riscv-none-embed-objcopy --output-target=ihex main.o main.hex

clean:
	rm -f *.o $(BIN)

