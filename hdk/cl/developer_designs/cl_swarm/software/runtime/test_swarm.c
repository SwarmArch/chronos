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

#include "header.h"



/* use the stdout logger */
const struct logger *logger = &logger_stdout;

int dma_example(int slot_i);
/* Constants determined by the CL */
/* a set of register offsets; this CL has only one */
/* these register addresses should match the addresses in */
/* /aws-fpga/hdk/cl/examples/common/cl_common_defines.vh */


pci_bar_handle_t pci_bar_handle;
uint32_t N_TILES;
uint32_t ID_OCL_SLAVE;
uint32_t N_SSSP_CORES;
uint32_t N_CORES;

uint32_t ID_SPLITTER;
uint32_t ID_COALESCER;
uint32_t ID_UNDO_LOG;
uint32_t ID_TASK_UNIT;
uint32_t ID_L2;
uint32_t ID_MEM_ARB;
uint32_t ID_PCI_ARB;
uint32_t ID_TSB;
uint32_t ID_CQ;
uint32_t ID_CM;
uint32_t ID_SERIALIZER;
uint32_t ID_LAST;
uint32_t LOG_TQ_SIZE, LOG_CQ_SIZE;
uint32_t TQ_STAGES, SPILLQ_STAGES;
uint32_t NON_SPEC;
uint16_t pci_vendor_id = 0x1D0F; /* Amazon PCI Vendor ID */
uint16_t pci_device_id = 0xF000; /* PCI Device ID preassigned by Amazon for F1 applications */

/* Declaring the local functions */

int peek_poke_example(int slot, int pf_id, int bar_id);
int test_task_unit(int slot, int pf_id, int bar_id);
int test_sssp(int slot_id, int pf_id, int bar_id, FILE* fg, int);
int vled_example(int slot);

/* Declating auxilary house keeping functions */
int initialize_log(char* log_name);
int check_afi_ready(int slot);

FILE* fhex;
int write_fd;
int read_fd;

void pci_peek(uint32_t tile, uint32_t comp, uint32_t addr, uint32_t* data) {
    uint32_t ocl_addr = (tile << 16) + (comp << 8) + addr;
    int rc = fpga_pci_peek(pci_bar_handle, ocl_addr, data);

    if ( (rc != 0) |
            ( 1 & ( (*data == -1) & !((comp == ID_CQ) & (addr == CQ_GVT_TS)))) ) {
        //printf("Unable to read from OCL addr=%8x\n", ocl_addr);
        // exit(0);
    }
}
void pci_poke(uint32_t tile, uint32_t comp, uint32_t addr, uint32_t data) {
    uint32_t ocl_addr = (tile << 16) + (comp << 8) + addr;
    int rc = fpga_pci_poke(pci_bar_handle, ocl_addr, data);
    if (rc != 0) {
        printf("Unable to write to OCL addr=%8x, data=%d\n", ocl_addr, data);
        exit(0);
    }
}
void init_params() {

    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_N_TILES, &N_TILES);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_TQ_HEAP_STAGES, &TQ_STAGES);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_NON_SPEC, &NON_SPEC);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_TQ_SIZE, &LOG_TQ_SIZE);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_CQ_SIZE, &LOG_CQ_SIZE);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_N_SSSP_CORES, &N_SSSP_CORES);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_SPILL_Q_SIZE, &SPILLQ_STAGES);

    printf("%d tiles, %d cores each\n", N_TILES, N_SSSP_CORES);
    printf("Non spec %d\n", NON_SPEC);
    printf("TQ Size %d CQ Size %d\n", LOG_TQ_SIZE, LOG_CQ_SIZE);

    N_CORES             =       (N_SSSP_CORES + 1);

    ID_SPLITTER         =       N_CORES;
    ID_COALESCER        =       (N_CORES + 1);

    ID_UNDO_LOG         =       (N_CORES + 2);
    ID_TASK_UNIT        =       (N_CORES + 3);
    ID_L2               =       (N_CORES + 4);
    ID_MEM_ARB          =       (N_CORES + 5);
    ID_PCI_ARB          =       (N_CORES + 6);
    ID_TSB              =       (N_CORES + 7);
    ID_CQ               =       (N_CORES + 8);
    ID_CM               =       (N_CORES + 9);
    ID_SERIALIZER       =       (N_CORES + 10);
    ID_LAST             =       (N_CORES + 11);

    ID_OCL_SLAVE = 0;

}

int main(int argc, char **argv) {
    int rc;
    int slot_id;

    /* initialize the fpga_pci library so we could have access to FPGA PCIe from this applications */
    rc = fpga_pci_init();
    fail_on(rc, out, "Unable to initialize the fpga_pci library");

    /* This demo works with single FPGA slot, we pick slot #0 as it works for both f1.2xl and f1.16xl */
    pci_bar_handle = PCI_BAR_HANDLE_INIT;

    slot_id = 0;

    rc = check_afi_ready(slot_id);
    fail_on(rc, out, "AFI not ready");

    /* initialize the fpga_plat library */
    rc = fpga_mgmt_init();
    fail_on(rc, out, "Unable to initialize the fpga_mgmt library");

    /* Accessing the CL registers via AppPF BAR0, which maps to sh_cl_ocl_ AXI-Lite bus between AWS FPGA Shell and the CL*/
    int op = 0;
    FILE* fg;
    fhex = 0;
    if (argc >=2 ) op = atoi(argv[1]);
    if (argc >=4 ) fhex = fopen(argv[3], "r"); // code hex
    switch(op) {
        case 0:
            dma_example(slot_id);
            break;
        case APP_SSSP:
        case APP_COLOR:
            if (argc >=3) fg=fopen(argv[2], "r");
            else fg=fopen("input_graph", "r");
            fail_on((rc = (fg == 0)? 1:0), out, "unable to open input_graph. ");
            test_sssp(slot_id, FPGA_APP_PF, APP_PF_BAR0, fg, op);
            break;
        case APP_DES:
            // des
            if (argc >=3) fg=fopen(argv[2], "r");
            else fg=fopen("input_net", "r");
            fail_on((rc = (fg == 0)? 1:0), out, "unable to open input_graph. ");
            test_sssp(slot_id, FPGA_APP_PF, APP_PF_BAR0, fg, APP_DES);
            break;
        case APP_ASTAR:
            // astar
            if (argc >=3) fg=fopen(argv[2], "r");
            else fg=fopen("input_astar", "r");
            fail_on((rc = (fg == 0)? 1:0), out, "unable to open input_graph. ");
            test_sssp(slot_id, FPGA_APP_PF, APP_PF_BAR0, fg, APP_ASTAR);
            break;
        case APP_MAXFLOW:
            // astar
            if (argc >=3) fg=fopen(argv[2], "r");
            else fg=fopen("input_maxflow", "r");
            fail_on((rc = (fg == 0)? 1:0), out, "unable to open input_graph. ");
            test_sssp(slot_id, FPGA_APP_PF, APP_PF_BAR0, fg, APP_MAXFLOW);
            break;
        case APP_LAST:
            test_task_unit(slot_id, FPGA_APP_PF, APP_PF_BAR0);
            break;
    }
    return 0;
    printf("===== Starting with peek_poke_example =====\n");
    rc = test_task_unit(slot_id, FPGA_APP_PF, APP_PF_BAR0);
    //rc = peek_poke_example(slot_id, FPGA_APP_PF, APP_PF_BAR0);
    fail_on(rc, out, "peek-poke example failed");


    printf("Developers are encourged to modify the Virtual DIP Switch by calling the linux shell command to demonstrate how AWS FPGA Virtual DIP switches can be used to change a CustomLogic functionality:\n");
    printf("$ fpga-set-virtual-dip-switch -S (slot-id) -D (16 digit setting)\n\n");
    printf("In this example, setting a virtual DIP switch to zero clears the corresponding LED, even if the peek-poke example would set it to 1.\nFor instance:\n");

    printf(
            "# fpga-set-virtual-dip-switch -S 0 -D 1111111111111111\n"
            "# fpga-get-virtual-led  -S 0\n"
            "FPGA slot id 0 have the following Virtual LED:\n"
            "1010-1101-1101-1110\n"
            "# fpga-set-virtual-dip-switch -S 0 -D 0000000000000000\n"
            "# fpga-get-virtual-led  -S 0\n"
            "FPGA slot id 0 have the following Virtual LED:\n"
            "0000-0000-0000-0000\n"
          );


    return rc;


out:
    return 1;
}


    static int
check_slot_config(int slot_id)
{
    int rc;
    struct fpga_mgmt_image_info info = {0};

    /* get local image description, contains status, vendor id, and device id */
    rc = fpga_mgmt_describe_local_image(slot_id, &info, 0);
    fail_on(rc, out, "Unable to get local image information. Are you running as root?");

    /* check to see if the slot is ready */
    if (info.status != FPGA_STATUS_LOADED) {
        rc = 1;
        fail_on(rc, out, "Slot %d is not ready", slot_id);
    }

    /* confirm that the AFI that we expect is in fact loaded */
    if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id ||
            info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
        rc = 1;
        printf("The slot appears loaded, but the pci vendor or device ID doesn't "
                "match the expected values. You may need to rescan the fpga with \n"
                "fpga-describe-local-image -S %i -R\n"
                "Note that rescanning can change which device file in /dev/ a FPGA will map to.\n"
                "To remove and re-add your edma driver and reset the device file mappings, run\n"
                "`sudo rmmod edma-drv && sudo insmod <aws-fpga>/sdk/linux_kernel_drivers/edma/edma-drv.ko`\n",
                slot_id);
        fail_on(rc, out, "The PCI vendor id and device of the loaded image are "
                "not the expected values.");
    }

out:
    return rc;
}
    void
rand_string(char *str, size_t size)
{
    static const char charset[] =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRTSUVWXYZ1234567890";
    static bool seeded = false;

    if (!seeded) {
        srand(time(NULL));
        seeded = true;
    }

    for(int i = 0; i < size-1; ++i) {
        unsigned int key = rand() % (sizeof charset - 1);
        str[i] = charset[key];
    }

    str[size-1] = '\0';
}

void dma_write(unsigned char* write_buffer, uint32_t write_len, size_t write_addr) {

    size_t write_offset = 0;
    int rc;
    // After moving to v1.4, dma transfers larger than 512 B doesn't work.
    // Not sure why this happens; but temp fix by splitting larger transfers to
    // 512 B chunks.
    while (write_offset < write_len) {
        if (write_offset != 0) {
            //    printf("Partial write by driver, trying again with remainder of buffer (%lu bytes)\n",
            //          write_len - write_offset);
        }
        rc = pwrite(write_fd,
                write_buffer + write_offset,
                (write_len - write_offset) > 512 ? 512 : (write_len - write_offset) ,
                write_addr + write_offset);
        if (rc < 0) {
            printf("call to pwrite failed.\n");
        }
        //printf("rc %d\n", rc);
        write_offset += rc;
    }
    rc = 0;

}
uint32_t hti(char c) {
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return c - '0';
}
uint32_t hToI(char *c, uint32_t size) {
    uint32_t value = 0;
    for (uint32_t i = 0; i < size; i++) {
        value += hti(c[i]) << ((size - i - 1) * 4);
    }
    return value;
}
void load_code() {
    printf("Loading code %p\n", fhex);
    int code_len = 1024*1024;
    unsigned char* code_buffer = (unsigned char*) malloc(code_len);
    fseek(fhex, 0, SEEK_END);
    uint32_t size = ftell(fhex);
    fseek(fhex, 0, SEEK_SET);
    char* content = (char*) malloc (size);
    fread(content, 1, size, fhex);

    const unsigned int code_start = 0x80000000;

    uint32_t offset = 0;
    char* line = content;
    while (1) {
        if (line[0] == ':') {
            uint32_t byteCount = hToI(line + 1, 2);
            uint32_t nextAddr = hToI(line + 3, 4) + offset;
            uint32_t key = hToI(line + 7, 2);
            //printf("%d %x %d\n", byteCount, nextAddr,key);
            switch (key) {
                case 0:
                    for (uint32_t i = 0; i < byteCount; i++) {
                        code_buffer[nextAddr + i - code_start] = hToI(line + 9 + i * 2, 2);
                        //printf("%x %x %c%c\n",nextAddr + i,hToI(line + 9 + i*2,2),line[9 + i * 2],line[9 + i * 2+1]);
                    }
                    break;
                case 2:
                    //				cout << offset << endl;
                    offset = hToI(line + 9, 4) << 4;
                    break;
                case 4:
                    //				cout << offset << endl;
                    offset = hToI(line + 9, 4) << 16;
                    break;
                default:
                    //				cout << "??? " << key << endl;
                    break;
            }
        }

        while (*line != '\n' && size != 0) {
            line++;
            size--;
        }
        if (size <= 1)
            break;
        line++;
        size--;
    }

    uint32_t boot_addr = 0x80000074;
    unsigned int boot_code[4];
    boot_code[0] = (boot_addr >> 12) << 12 | 0xb7; // lui x1, main[31:12]
    boot_code[1] = (boot_addr & 0xfff) << 20 | 0x08093; // addi x1,x1,main[11:0]
    boot_code[2] = 0x7e000137; // li sp, 0x7e000
    boot_code[3] = 0x8067; // jalr x1, 0
    for (int i=0;i<4;i++) {
        code_buffer[i*4 + 0] = (boot_code[i] & 0xff);
        code_buffer[i*4 + 1] = (boot_code[i] >> 8) & 0xff;
        code_buffer[i*4 + 2] = (boot_code[i] >> 16) & 0xff;
        code_buffer[i*4 + 3] = (boot_code[i] >> 24) & 0xff;
    }


    free(content);
    int rc =fpga_dma_burst_write(write_fd, code_buffer, code_len, code_start);
    if(rc<0){
        printf("unable to open read dma queue\n");
        exit(0);
    }
    dma_write(code_buffer, code_len, code_start);
}

int test_sssp(int slot_id, int pf_id, int bar_id, FILE* fg, int app) {
    int rc;
    unsigned char *write_buffer, *read_buffer;

    read_buffer = NULL;
    write_buffer = NULL;
    write_fd = -1;
    read_fd = -1;

    /* make sure the AFI is loaded and ready */
    rc = check_slot_config(slot_id);
    if (rc >0) {
        printf("slot config is not correct\n");
        exit(0);
    }

    write_fd = fpga_dma_open_queue(FPGA_DMA_XDMA, slot_id,
            /*channel*/ 0, /*is_read*/ false);
    if(write_fd<0){
        printf("unable to open write dma queue\n");
        exit(0);
    }
    read_fd = fpga_dma_open_queue(FPGA_DMA_XDMA, slot_id,
            /*channel*/ 0, /*is_read*/ true);
    if(read_fd<0){
        printf("unable to open read dma queue\n");
        exit(0);
    }


    // OPEN GRAPH FILE
    //FILE* fg;

    printf("File %p\n", fg);

    write_buffer = (unsigned char *)malloc(1600*1024*1024);
    unsigned int headers[16];
    uint32_t line;
    int ret;
    int n = 0;
    while ( (ret = fscanf(fg,"%8x\n", &line)) != EOF) {
        write_buffer[n ] = line & 0xff;
        write_buffer[n +1] = (line >>8) & 0xff;
        write_buffer[n +2] = (line >>16) & 0xff;
        write_buffer[n +3] = (line >>24) & 0xff;
        if (n<64) headers[n/4] = line;
        //printf("file %d %8x %2x %2x \n", n/4, line, write_buffer[n], write_buffer[n+1]);
        n+=4;

    }
    if (app == APP_MAXFLOW) {
        // global relabel interval
        headers[10] += 0;
        write_buffer[10*4] = headers[10];
    }
    uint32_t numV = headers[1];
    uint32_t numE = headers[2];;
    printf("File Len %d\n", n);

    int file_len = n;
    read_buffer = (unsigned char *)malloc(headers[1]*4);
    //rc =fpga_dma_burst_write(write_fd, write_buffer, file_len, 0);
    dma_write(write_buffer, file_len, 0);

    uint32_t* csr_offset = (uint32_t *) (write_buffer + headers[3]*4);
    uint32_t* csr_neighbors = (uint32_t *) (write_buffer + headers[4]*4);
    uint32_t* csr_color = (uint32_t *) (write_buffer + headers[5]*4);
    if(rc!=0){
        printf("unable to write_dma\n");
        exit(0);
    }
    // DMA Write
    printf("Write success\n");
    rc = 0;

    if (fhex) {
        load_code();
    }
    printf("Loading code... Success\n");


    //fsync(fd);

    rc = fpga_pci_attach(slot_id, pf_id, bar_id, 0, &pci_bar_handle);
    if (rc > 0) {
        printf("Unable to attach to the AFI on slot id %d\n", slot_id);
        exit(0);
    }

    init_params();
    /*
       for (int i=0;i<8;i++) {
       uint32_t inst_word;
       pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB, 0x80000080 + i*4);
       pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &inst_word );
       printf("inst word %8x\n", inst_word);
       }*/

    unsigned char* spill_area = (unsigned char*) malloc(TOTAL_SPILL_ALLOCATION);
    for (int i=0;i<4;i++) spill_area[STACK_PTR_ADDR_OFFSET +i] = 0;
    for (int i=0;i< (1<<LOG_SPLITTER_STACK_SIZE) ; i++) {
        spill_area[STACK_BASE_OFFSET + i* 2  ] = i & 0xff;
        spill_area[STACK_BASE_OFFSET + i* 2+1] = i >> 8;
    }
    for (int i=SCRATCHPAD_BASE_OFFSET; i < SCRATCHPAD_END_OFFSET; i++) {
        spill_area[i] = 0;
    }

    for (int i=0;i<N_TILES;i++) {
        dma_write(spill_area,
                SCRATCHPAD_END_OFFSET,
                ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION);
    }
    uint32_t startCycle, endCycle;
    uint64_t cycles;
    int num_errors = 0;


    uint32_t ocl_data = 0;
    unsigned char* log_buffer = (unsigned char *)malloc(20000*64);
    FILE* fwtu = fopen("task_unit_log", "w");
    FILE* fwtu1 = fopen("task_unit_log_1", "w");
    FILE* fwtu2 = fopen("task_unit_log_2", "w");
    FILE* fwtu3 = fopen("task_unit_log_3", "w");
    FILE* fwcq = fopen("cq_log", "w");
    FILE* fwsp = fopen("splitter_log", "w");
    FILE* fws1 = fopen("core_1_log", "w");
    //FILE* fws4 = fopen("sssp_core_4_log", "w");
    //FILE* fws5 = fopen("sssp_core_5_log", "w");
    FILE* fwl2 = fopen("l2_log", "w");
    FILE* fwul = fopen("undo_log_log", "w");
    // OCL Initialization

    // Checking PCI latency;
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
    printf("PCI latency %d cycles\n", endCycle - startCycle);
    if (endCycle == startCycle) return -1;


    uint32_t tied_cap = 1<<(LOG_TQ_SIZE -2);
    uint32_t clean_threshold = 40;
    uint32_t spill_threshold = (1<<LOG_TQ_SIZE) - 20;
    uint32_t spill_size = 64;
    uint32_t log_active_tiles = 0;

    bool task_unit_logging_on = false;
    task_unit_logging_on = true;

    assert(spill_threshold > (tied_cap + (1<<LOG_CQ_SIZE) + spill_size));
    assert((spill_size % 8) == 0);
    assert(spill_size < (1<<SPILLQ_STAGES) );
    assert(tied_cap < (1<<LOG_TQ_SIZE) );
    assert(clean_threshold < (1<<TQ_STAGES) );
    printf("Spill Alloc %08x %08x\n",ADDR_BASE_SPILL, TOTAL_SPILL_ALLOCATION);

    for (int i=0;i<N_TILES;i++) {
        // set base addresses
        printf("Setting Base Addresses\n");
        //pci_poke(i, ID_ALL_SSSP_CORES, SSSP_BASE_EDGE_OFFSET , headers[3]>>4 );
        //pci_poke(i, ID_ALL_SSSP_CORES, SSSP_BASE_NEIGHBORS   , headers[4]>>4 );
        //pci_poke(i, ID_ALL_SSSP_CORES, SSSP_BASE_DIST        , headers[5]>>4 );

        if (app == APP_DES) {

            pci_poke(i, N_SSSP_CORES, SSSP_BASE_EDGE_OFFSET , headers[8]>>4 );
            pci_poke(i, N_SSSP_CORES, SSSP_BASE_NEIGHBORS   , headers[9]>>4 );

        }

        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_ADDR_STACK_PTR ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION) >> 6 );
        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_BASE_STACK ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION + STACK_BASE_OFFSET) >> 6 );
        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_BASE_SCRATCHPAD ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION + SCRATCHPAD_BASE_OFFSET) >> 6 );
        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_BASE_TASKS ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION + SPILL_TASK_BASE_OFFSET) >> 6 );

        pci_poke(i, ID_TSB, TSB_LOG_N_TILES        ,log_active_tiles );
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_SPILL_THRESHOLD, spill_threshold);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_CLEAN_THRESHOLD, clean_threshold);
        //   pci_poke(i, ID_TASK_UNIT, TASK_UNIT_TIED_CAPACITY, tied_cap* 100);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_SPILL_SIZE, spill_size);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_ALT_DEBUG, 1); // get enq args instead of deq hint/ts
        //pci_poke(i, ID_TASK_UNIT, TASK_UNIT_THROTTLE_MARGIN, 5);
        //pci_poke(i, ID_COALESCER, CORE_START, 0xffffffff);
        //pci_poke(i, ID_CQ, CQ_SIZE, 48);
        pci_poke(i, ID_CQ, CQ_MAXFLOW_THRESHOLD, 0xffffffff);

        if (app == APP_MAXFLOW) {
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_IS_TRANSACTIONAL, 1);
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_GLOBAL_RELABEL_START_MASK, (1<<headers[10]) - 1);
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_GLOBAL_RELABEL_START_INC, 16);
        }
    }
    usleep(20);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
    printf("PCI latency %d cycles\n", endCycle - startCycle);
    if (endCycle == startCycle) return -1;
    /*
       for (int i=0;i<8;i++) {
       uint32_t inst_word;
       pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB, 0x80000080 + i*4);
       pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &inst_word );
       printf("inst word %8x\n", inst_word);
       }
       */
    uint32_t init_l2_read_hits, init_l2_read_miss,
             init_l2_write_hits, init_l2_write_miss, init_l2_evictions;
    uint32_t init_num_enq[N_SSSP_CORES+3];
    uint32_t init_num_deq[N_SSSP_CORES+3];
    bool read_stat_init = false;
    if (read_stat_init) {
        pci_peek(0, ID_L2, L2_READ_HITS   ,  &init_l2_read_hits);
        pci_peek(0, ID_L2, L2_READ_MISSES ,  &init_l2_read_miss);
        pci_peek(0, ID_L2, L2_WRITE_HITS  ,  &init_l2_write_hits);
        pci_peek(0, ID_L2, L2_WRITE_MISSES,  &init_l2_write_miss);
        pci_peek(0, ID_L2, L2_EVICTIONS   ,  &init_l2_evictions);
        for (int i=1;i<N_SSSP_CORES+3;i++) {
            pci_peek(0, i, CORE_NUM_ENQ,  &(init_num_enq[i]));
            pci_peek(0, i, CORE_NUM_DEQ,  &(init_num_deq[i]));
        }
    } else {
        init_l2_read_hits = 0;
        init_l2_read_miss = 0;
        init_l2_write_hits = 0;
        init_l2_write_miss = 0;
        init_l2_evictions = 0;
        for (int i=1;i<N_SSSP_CORES+3;i++) {
            init_num_enq[i] = 0;
            init_num_deq[i] = 0;
        }
    }
    uint32_t inst_word;
    inst_word = 100;
    pci_peek(0, 1, CORE_PC, &inst_word );
    printf("pc %x\n", inst_word);

    pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );
    pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
    printf("app %d\n",app);
    int init_task_tile = 0;
    switch (app) {
        case APP_DES:
            printf("APP_DES\n");
            for (int i=0;i<N_TILES;i++) {
                pci_poke(i, 0, OCL_TASK_ENQ_TTYPE,  1);
            }
            for (int i=0;i<headers[11];i++) { // numI
                unsigned char* ref_ptr = write_buffer + (headers[7] +i)*4;
                //printf("%d\n", *(ref_ptr+1));
                uint32_t enq_hint = (*(ref_ptr + 3)<<24)+
                    (*(ref_ptr + 2)<<16) +
                    (*(ref_ptr + 1)<<8)  +
                    *ref_ptr;
                uint32_t enq_tile = (enq_hint>>4) %( 1<<log_active_tiles);
                pci_poke(enq_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_HINT , enq_hint );
                pci_poke(enq_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );
                //usleep(10);
                pci_poke(enq_tile, ID_OCL_SLAVE, OCL_TASK_ENQ      , 0);

                printf("Enquing initial task %d\n", enq_hint);
            }
            break;
        case APP_SSSP:
            printf("APP_SSSP\n");
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_HINT , headers[7] );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );
            break;
        case APP_ASTAR:
            printf("APP_ASTAR\n");
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 1 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0xffffffff );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_HINT , headers[7] );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 1 );

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );

            break;
        case APP_COLOR:
            printf("APP_COLOR\n");
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_HINT , 0x20000 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 1 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0);

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );
        case APP_MAXFLOW:
            printf("APP_MAXFLOW\n");
            switch (log_active_tiles) {
                case 0 : init_task_tile = 0; break;
                case 1 : init_task_tile = (headers[7] >> 4) & 1; break;
                case 2 : init_task_tile = (headers[7] >> 4) & 3; break;
                case 3 : init_task_tile = (headers[7] >> 4) & 7; break;
            }
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_HINT,
                        headers[7] );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 1 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0);

            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );
            break;

    }
    //uint32_t coal_enq, coal_deq;
    //pci_peek(0, ID_COALESCER, CORE_NUM_ENQ,  &coal_enq);
    //pci_peek(0, ID_COALESCER, CORE_NUM_DEQ,  &coal_deq);
    //printf("Num Initial Events %d\n", headers[9]);
    //printf("Coal %d %d\n", coal_enq, coal_deq);
    printf("Starting SSSP\n");

    for (int i=0;i<N_TILES;i++) {
        pci_poke(i, ID_ALL_SSSP_CORES, CORE_N_DEQUEUES ,0xfffffff);
    }
    usleep(20);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
    printf("PCI latency %d cycles\n", endCycle - startCycle);
    if (endCycle == startCycle) return -1;
    //cq_stats(0);
    if (task_unit_logging_on) {
        pci_poke(0, ID_ALL_SSSP_CORES, CORE_N_DEQUEUES ,0xe0);
    }
    uint32_t core_mask = 0;
    uint32_t active_cores = 8;
    core_mask = (1<<(active_cores+1))-1;
    core_mask |= (1<<ID_COALESCER);
    //core_mask |= (1<<9);
    //core_mask |= (1<<10);
    core_mask |= (1<<ID_SPLITTER);
    printf("mask %x\n", core_mask);
    uint64_t startCycle64 = 0;
    uint64_t endCycle64 = 0;
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_MSB, &startCycle);
    startCycle64 = startCycle;
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    startCycle64 |= (startCycle64 << 32) | startCycle;
    //task_unit_stats(0);
    for (int i=0;i<N_TILES;i++) {
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_START, 1);
        pci_poke(i, ID_ALL_CORES, CORE_START, core_mask);
    }
    printf("Waiting until SSSP completes\n");
    ocl_data = 0;

    int iters = 0;
    pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB, 0 );
    usleep(20);
    /*
       for (int i=0;i<8;i++) {
       pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB, 0x80000070 + i*4);
       pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &inst_word );
       printf("inst word %8x\n", inst_word);
       }
       */
    pci_peek(0, 1, CORE_PC, &inst_word );
   printf("pc %x\n", inst_word);

   //exit(0);


   while(true) {
       //log_splitter(pci_bar_handle, fd, fwsp, ID_SPLITTER);
       uint32_t gvt;
       uint32_t gvt_tb;
       pci_peek(0, ID_CQ, CQ_GVT_TS, &gvt);
       //printf(" gvt %d\n", gvt);
       if (gvt == -1 || gvt == -2) {
           // -2 to ignore some non-spec bugs
           pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_MSB, &endCycle);
           endCycle64 = endCycle;
           pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
           endCycle64 = (endCycle64 << 32) | endCycle;
           pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
           bool done = true;
           if (NON_SPEC) {
               // under non-spec, the exact gvt cannot be computed,
               // and the pseudo-gvt is not non-decreasing.
               // Hence sample a few times before terminating

               for (int i=0;i<15;i++) {
                   usleep(10);
                   if (task_unit_logging_on) {
                       pci_poke(0, ID_ALL_SSSP_CORES, CORE_N_DEQUEUES ,0xd0);
                   }
                   pci_peek(0, ID_CQ, CQ_GVT_TS, &gvt);

                   if (!(gvt == -1 || gvt == -2)) done = false;
               }
           }
           if (done) break;
       }
       if (task_unit_logging_on) {
           usleep(200);
           if (iters < 100000 & iters >= 0) {
               log_task_unit(pci_bar_handle, read_fd, fwtu, log_buffer,
                       ID_TASK_UNIT);
               if (log_active_tiles > 0) {
                   log_task_unit(pci_bar_handle, read_fd, fwtu1, log_buffer,
                       ID_TASK_UNIT | (1<<8));
               }
               if (log_active_tiles > 1) {
                   log_task_unit(pci_bar_handle, read_fd, fwtu2, log_buffer,
                       ID_TASK_UNIT | (2<<8));
                   log_task_unit(pci_bar_handle, read_fd, fwtu3, log_buffer,
                       ID_TASK_UNIT | (3<<8));
               }
           }
           //log_riscv(pci_bar_handle, read_fd, fws1, log_buffer, 1);
           //log_cache(pci_bar_handle, read_fd, fwl2, ID_L2);
           //log_undo_log(pci_bar_handle, read_fd, fwul, log_buffer, ID_UNDO_LOG);
           log_splitter(pci_bar_handle, read_fd, fwsp, ID_SPLITTER);
           if (!NON_SPEC) log_cq(pci_bar_handle, read_fd, fwcq, log_buffer, ID_CQ);
           usleep(200);

           uint32_t n_tasks, n_tied_tasks, heap_capacity;
           uint32_t coal_tasks;
           uint32_t stack_ptr;
           uint32_t cq_state;
           uint32_t tq_debug;
           uint32_t cycle;
           for (int i=0;i<(1<<log_active_tiles);i++) {
               pci_peek(i, ID_CQ, CQ_GVT_TS, &gvt);
               pci_peek(i, ID_CQ, CQ_GVT_TB, &gvt_tb);
               pci_peek(i, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB       , &cycle);
               pci_peek(i, ID_TASK_UNIT, TASK_UNIT_N_TASKS, &n_tasks);
               pci_peek(i, ID_TASK_UNIT, TASK_UNIT_N_TIED_TASKS, &n_tied_tasks);
               pci_peek(i, ID_TASK_UNIT, TASK_UNIT_CAPACITY, &heap_capacity);
               pci_peek(i, ID_COALESCER, CORE_NUM_DEQ, &coal_tasks);
               pci_poke(i, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB,
                       ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION);
               pci_peek(i, ID_OCL_SLAVE, OCL_ACCESS_MEM, &stack_ptr );
               pci_peek(i, ID_CQ, CQ_STATE, &cq_state );
               pci_peek(i, ID_TASK_UNIT, TASK_UNIT_MISC_DEBUG, &tq_debug );
               //pci_peek(0, ID_TSB, TSB_ENTRY_VALID, &stack_ptr );
               printf(" [%4d][%1d][%8u] gvt:(%9x %9d) (%4d %4d %4d) %6d %4x stack_ptr:%4d\n",
                       iters, i, cycle, gvt, gvt_tb,
                       n_tasks, n_tied_tasks, heap_capacity,
                       cq_state, tq_debug, stack_ptr);
               fprintf(fwtu, "log [%4d][%1d][%8u] gvt:%9d (%4d %4d %4d) %6d %4x stack_ptr:%4d\n",
                       iters, i, cycle, gvt,
                       n_tasks, n_tied_tasks, heap_capacity,
                       cq_state, tq_debug, stack_ptr);
               //task_unit_stats(i);
               //cq_stats(i);
               /*
                  for (int j=1;j<=8;j++) {
                  uint32_t core_state, core_pc, num_deq;
                  pci_peek(i, j, CORE_STATE, &core_state );
                  pci_peek(i, j, CORE_PC, &core_pc );
                  pci_peek(i, j, CORE_NUM_DEQ, &num_deq);
                  printf(" \t [core-%d] state:%d pc:%08x n_deq:%8d\n",
                  j, core_state, core_pc, num_deq);
                  }
               */
               //task_unit_stats(i);
                pci_poke(i, ID_ALL_SSSP_CORES, CORE_N_DEQUEUES ,0xd0);

           }

           usleep(1000);
           if (iters == 50000) break;
           if (iters % 1000 == 10) {
               char fname [40];
               sprintf(fname, "state_%d", iters);
               FILE* fpa = fopen(fname, "w");

               pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB , 0);
               if (log_active_tiles > 0)
               pci_poke(1, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB , 0);
               for (int i=0;i <numV;i++) {
                   uint32_t node_addr = (headers[5] + i *16) * 4;
                   uint32_t node_tile = (i>>4)&((1<<log_active_tiles) -1) ;
                   int32_t excess, height;
                   pci_poke(node_tile, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB , node_addr);
                   pci_peek(node_tile, ID_OCL_SLAVE, OCL_ACCESS_MEM, &excess);
                   pci_poke(node_tile, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB , node_addr+ 16);
                   pci_peek(node_tile, ID_OCL_SLAVE, OCL_ACCESS_MEM, &height);
                   fprintf(fpa, "node:%3d excess:%3d height:%3d %s\n",
                           i, excess, height, excess != 0 ? "inflow" : "");
                   uint32_t eo_begin =csr_offset[i];
                   uint32_t eo_end =csr_offset[i+1];
                   for (int j=eo_begin;j<eo_end;j++) {
                        uint32_t n = csr_neighbors[j*4];
                        uint32_t cap = csr_neighbors[j*4+1];
                        int flow;
                        pci_poke(node_tile, ID_OCL_SLAVE,
                                OCL_ACCESS_MEM_SET_LSB ,
                            node_addr+ (6 + (j-eo_begin))*4);
                        pci_peek(node_tile, ID_OCL_SLAVE, OCL_ACCESS_MEM, &flow);
                        fprintf(fpa, "\t%5d cap:%8d flow:%8d\n %s",
                                n, cap, flow, cap<flow ? "overflow":"");
                   }
               }
           }
       }
       iters++;

   }
   usleep(2800);
   if (task_unit_logging_on) {
       log_task_unit(pci_bar_handle, read_fd, fwtu, log_buffer, ID_TASK_UNIT);
       if (log_active_tiles > 0) {
          log_task_unit(pci_bar_handle, read_fd, fwtu1, log_buffer,
                  ID_TASK_UNIT | (1<<8));
       }
       if (log_active_tiles > 1) {
           log_task_unit(pci_bar_handle, read_fd, fwtu2, log_buffer,
               ID_TASK_UNIT | (2<<8));
           log_task_unit(pci_bar_handle, read_fd, fwtu3, log_buffer,
               ID_TASK_UNIT | (3<<8));
       }
       log_cache(pci_bar_handle, read_fd, fwl2, ID_L2);
       log_cq(pci_bar_handle, read_fd, fwcq, log_buffer, ID_CQ);
       log_undo_log(pci_bar_handle, read_fd, fwul, log_buffer, ID_UNDO_LOG);
   }

   {
    /*
       pci_peek(0, ID_SERIALIZER, SERIALIZER_READY_LIST , &ocl_data);
       printf("Serialzer ready %8x\n", ocl_data);
       pci_peek(0, ID_SERIALIZER, SERIALIZER_ARVALID , &ocl_data);
       printf("Serialzer arvalid %8x\n", ocl_data);
       pci_peek(0, ID_SERIALIZER, SERIALIZER_REG_VALID , &ocl_data);
       printf("Serialzer reg_valid %8x\n", ocl_data);
       pci_peek(0, ID_SERIALIZER, SERIALIZER_CAN_TAKE_REQ_3 , &ocl_data);
       printf("Serialzer can_take_req_3 %8x\n", ocl_data);
    */
   }

   fflush(fwtu);
   fflush(fwcq);
   //log_cache(pci_bar_handle, fd, fwl2);
   //write_task_unit_log(log_buffer, fwtu);
   printf("iters %d\n", iters);
   /*
      uint32_t gvt;
      uint32_t n_tasks, n_tied_tasks, heap_capacity;
      uint32_t coal_tasks;
      pci_peek(0, ID_CQ, CQ_GVT_TS, &gvt);
      pci_peek(0, ID_TASK_UNIT, TASK_UNIT_N_TASKS, &n_tasks);
      pci_peek(0, ID_TASK_UNIT, TASK_UNIT_N_TIED_TASKS, &n_tied_tasks);
      pci_peek(0, ID_TASK_UNIT, TASK_UNIT_CAPACITY, &heap_capacity);
      pci_peek(0, ID_COALESCER, CORE_NUM_DEQ, &coal_tasks);
      printf(" [%4d] gvt:%9d (%4d %4d %4d) %6d\n",iters, gvt,
      n_tasks, n_tied_tasks, heap_capacity,
      coal_tasks);
      */
   for (int i=0;i<(1<<log_active_tiles);i++) {
       task_unit_stats(i);
       //if (!NON_SPEC) cq_stats(i);
   }
   log_riscv(pci_bar_handle, read_fd, fws1, log_buffer, 1);


   printf("SSSP completed, flushing cache..\n");
   for (int i=0;i<N_TILES;i++) {
       pci_poke(i, ID_L2, L2_FLUSH , 1 );
   }

   cycles = endCycle64 - startCycle64;
   uint32_t task_unit_ops=0;
   uint32_t total_tasks = 0;
   for (int t=0;t<(1<<log_active_tiles);t++) {
       for (int i=1;i<N_SSSP_CORES+3;i++) {
           uint32_t num_enq, num_deq;
           pci_peek(t, i, CORE_NUM_ENQ,  &num_enq);
           pci_peek(t, i, CORE_NUM_DEQ,  &num_deq);
           num_enq -= init_num_enq[i];
           num_deq -= init_num_deq[i];
           task_unit_ops += num_enq;
           task_unit_ops += num_deq;
           if (i<= N_SSSP_CORES) total_tasks += num_deq;
           if (t==0) printf("Core %2d num_enq:%9u num_deq:%9u\n", i, num_enq, num_deq);
       }
   }
   printf("total tasks:  %d\n", total_tasks);
   /*
      for (int i=1;i<=N_SSSP_CORES;i++) {
      uint32_t state_stats[16];
      printf("Core %d stats\n", i);
      for (int j=1;j<=12;j++) {
      pci_peek(0, i, SSSP_STATE_STATS_BEGIN + (j*4),  &(state_stats[j]));
      printf("state:%2d %10u    ", j, state_stats[j]);
      if ( (j%4==0)) printf("\n");
      }
      } */
   uint32_t l2_read_hits, l2_read_miss, l2_write_hits, l2_write_miss, l2_evictions;
   pci_peek(0, ID_L2, L2_READ_HITS   ,  &l2_read_hits);
   pci_peek(0, ID_L2, L2_READ_MISSES ,  &l2_read_miss);
   pci_peek(0, ID_L2, L2_WRITE_HITS  ,  &l2_write_hits);
   pci_peek(0, ID_L2, L2_WRITE_MISSES,  &l2_write_miss);
   pci_peek(0, ID_L2, L2_EVICTIONS   ,  &l2_evictions);
   l2_read_hits -= init_l2_read_hits;
   l2_write_hits -= init_l2_write_hits;
   l2_read_miss -= init_l2_read_miss;
   l2_write_miss -= init_l2_write_miss;
   l2_evictions -= init_l2_evictions;
   printf("L2 Read  hits:%9d misses:%9d \n",
           l2_read_hits, l2_read_miss);
   printf("L2 Write hits:%9d misses:%9d \n",
           l2_write_hits, l2_write_miss);
   printf("L2 Evictions :%9d \n",
           l2_evictions);
   double hit_rate = (l2_read_hits + l2_write_hits + 0.0) * 100 /
       (l2_read_hits + l2_read_miss + l2_write_hits + l2_write_miss);
   printf("L2 hit-rate %5.2f%%\n", hit_rate);
   printf("Task Unit Ops %d, num_edges %d\n", task_unit_ops, numE);

   //uint32_t n_gvt_going_back;
   //pci_peek(0, ID_CQ, CQ_N_GVT_GOING_BACK,  &n_gvt_going_back);
   //printf("gvt goes back on %d cycles\n", n_gvt_going_back);



   double time_ms = (cycles + 0.0) * 8/1e6;
   double read_bandwidth_MBPS = (l2_read_miss + l2_write_miss) * 64 / (time_ms * 1000) ;
   double write_bandwidth_MBPS = (l2_evictions) * 64 / (time_ms * 1000) ;

   printf("FPGA cycles %ld  (%f ms) (%3f cycles per task)\n",
           cycles,
           time_ms,
           cycles / (total_tasks + 0.0));

   printf("Read BW    %7.2f MB/s\n",read_bandwidth_MBPS);
   printf("Write BW   %7.2f MB/s\n",write_bandwidth_MBPS);

   double l2_tag_contention =
       ((l2_read_hits + l2_write_hits) + 2* (l2_read_miss + l2_write_miss) + 0.0)*100/cycles;
   double task_unit_contention = (task_unit_ops + 0.0)*100/cycles;
   printf("L2 Tag contention %5.2f%%\n", l2_tag_contention);
   printf("Task Unit contention %5.2f%%\n", task_unit_contention);

   ocl_data = 1;
   while(ocl_data==1) {
       for (int i=0;i<N_TILES;i++) {
           pci_peek(i, ID_L2, L2_FLUSH, &ocl_data);
           if (ocl_data == 1) break;
       }
   }
   printf("Flush completed, reading results..\n");
#if 1
   pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB        , 0 );
   uint32_t ref_count=0;
   FILE* mf_state = fopen("maxflow_state", "w");
   switch (app) {
       case APP_DES:
           for (int i=0;i<headers[12];i++) {  // numOutputs
               unsigned char* ref_ptr = write_buffer + (headers[6] +i)*4;
               //printf("%d\n", *(ref_ptr+1));
               uint32_t ref_data = (*(ref_ptr + 3)<<24)+
                   (*(ref_ptr + 2)<<16) +
                   (*(ref_ptr + 1)<<8)  +
                   *ref_ptr;
               uint32_t ref_vid = ref_data >> 16;
               uint32_t ref_val = ref_data & 0x3;
               uint64_t act_addr = 64 + ref_vid * 4;
               uint32_t act_data;
               pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB        , (act_addr ));
               pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &act_data );
               uint32_t act_val = act_data >> 24;
               bool error = (act_val != ref_val);
               if (error) num_errors++;
               if ( (error & (num_errors < 50)) || i==headers[12]-1) {
                   printf("vid:%3d dist:%5u, ref:%5u, %s, num_errors:%2d / %d\n",
                           ref_vid, act_val, ref_val,
                           !error ? "MATCH" : "FAIL", num_errors, headers[12] );
               }
           }
           FILE* fdes = fopen("des_debug", "w");
           for (int i=0;i<numV;i++) {
               uint64_t act_addr = 64 + i * 4;
               uint32_t act_data;
               pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB        , (act_addr ));
               pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &act_data );
               uint32_t outVal = act_data >> 24 & 0x3;
               uint32_t in0 = (act_data >> 22) & 0x3 ;
               uint32_t in1 = (act_data >> 20) & 0x3 ;
               uint32_t type = (act_data >> 16) & 0x7 ;
               uint32_t delay = (act_data ) & 0xffff ;
               fprintf(fdes, "[%3d] outVal: %d in0: %d in1: %d type: %d delay: %4d\n",
                       i, outVal, in0, in1, type, delay
                      );
           }
           fclose(fdes);
           break;
       case APP_SSSP:
       case APP_ASTAR:
           for (int i=0;i<numV;i++) {
               int ref_ptr_loc = (app != APP_ASTAR) ? 6 : 9;
               unsigned char* ref_ptr = write_buffer + (headers[ref_ptr_loc] +i)*4;
               //printf("%d\n", *(ref_ptr+1));
               uint32_t ref_dist = (*(ref_ptr + 3)<<24)+
                   (*(ref_ptr + 2)<<16) +
                   (*(ref_ptr + 1)<<8)  +
                   *ref_ptr;
               //printf("%d %d\n", i ,numV);
               if ((app==APP_ASTAR) && (ref_dist == -1)) continue;

               uint64_t addr = 64 + i * 4;
               if ((addr & 0xffffffff) ==0) {
                   uint32_t msb = addr >> 32;
                   printf("setting msb %d\n", msb);
                   pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB        , msb );
               }
               uint32_t act_dist;
               pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB        , (addr & 0xffffffff ));
               pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &act_dist );

               bool error;
               if (app == APP_ASTAR)
                   error = abs(act_dist - ref_dist) >3;
               else {
                   error = (act_dist != ref_dist);
               }

               if (error) num_errors++;
               ref_count++;
               if ( ( error & (num_errors < 1000)) || i==numV-1)
                   printf("vid:%3d dist:%5d, ref:%5d, %s, num_errors:%2d\n",
                           i, act_dist, ref_dist,
                           act_dist == ref_dist ? "MATCH" : "FAIL", num_errors);
           }
           printf("Total Errors %d / %d\n", num_errors, ref_count);
           break;
       case APP_COLOR:
           for (int i=0;i<numV;i++) {
               uint64_t addr = 64 + i * 4;
               if ((addr & 0xffffffff) ==0) {
                   uint32_t msb = addr >> 32;
                   printf("setting msb %d\n", msb);
                   pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB        , msb );
               }
               uint32_t act_color;
               pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB        , (addr & 0xffffffff ));
               pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &act_color );
               csr_color[i] = act_color;
           }
           // verification
           FILE* fc = fopen("color_verif", "w");
           for (int i=0;i<numV;i++) {
               uint32_t eo_begin =csr_offset[i];
               uint32_t eo_end =csr_offset[i+1];
               uint32_t i_deg = eo_end - eo_begin;
               uint32_t i_color = csr_color[i];
               fprintf(fc,"i=%d d=%d c=%d\n",i, i_deg, i_color);
               bool error = (i_color == -1);
               uint32_t join_cnt = 0;
               for (int j=eo_begin;j<eo_end;j++) {
                    uint32_t n = csr_neighbors[j];
                    uint32_t n_deg = csr_offset[n+1] - csr_offset[n];
                    uint32_t n_color = csr_color[n];
                    fprintf(fc,"\tn=%d d=%d c=%d\n",n, n_deg, n_color);
                    if (i_color == n_color) {
                        fprintf(fc,"\t ERROR:Neighbor has same color\n");
                        error = true;
                    }
                    if (n_deg > i_deg || ((n_deg == i_deg) & (n<i))) join_cnt++;
               }
               fprintf(fc,"\tjoin_cnt=%d\n", join_cnt);
               if (error) num_errors++;
               if ( error & (num_errors < 10) )
                   printf("Error at vid:%3d color:%5d\n",
                           i, csr_color[i]);
           }
           printf("Total Errors %d / %d\n", num_errors, numV);
           break;
      case APP_MAXFLOW:
           pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB , 0);
           maxflow_edge_prop_t* edges =
               (maxflow_edge_prop_t *) (write_buffer + headers[4]*4);
           maxflow_node_prop_t* nodes =
               (maxflow_node_prop_t *) (write_buffer + headers[5]*4);
           for (int j=0;j<16*numV;j++) {
               pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB ,
                       (headers[5] +j)*4);
               pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM,
                       write_buffer + (headers[5]+j)*4);
           }
           for (int i=0;i <numV;i++) {
               uint32_t node_addr = (headers[5] + i *16) * 4;
               uint32_t excess, height;
               fprintf(mf_state, "node:%3d excess:%3d height:%3d %s\n",
                       i, nodes[i].excess, nodes[i].height,
                       (nodes[i].excess>0)?"inflow" : "");
               uint32_t eo_begin =csr_offset[i];
               uint32_t eo_end =csr_offset[i+1];
               int32_t sum_flow =0;

               for (int j=eo_begin;j<eo_end;j++) {
                    uint32_t n = edges[j].dest;
                    int32_t cap = edges[j].capacity;
                    int32_t flow = nodes[i].flow[j-eo_begin];
                    int32_t reverse_edge = edges[j].reverse_index;
                    int32_t reverse_flow = nodes[n].flow[
                        reverse_edge];
                    fprintf(mf_state,
                            "\t%5d cap:%8d flow:%8d reverse_flow:%8d %s\n",
                            n, cap, flow, reverse_flow,
                            (flow+reverse_flow != 0)?"mismatch":"");
                    sum_flow += flow;
               }
               fprintf(mf_state, "\tsum_flow:%d %s\n",
                       sum_flow, sum_flow != 0 ? "WHAT?" : "");

           }
           uint32_t node_addr = (headers[5] + (headers[9]) *16) * 4;
           uint32_t excess, height;
           pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB , node_addr);
           pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &excess);
           pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB , node_addr+ 16);
           pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &height);
           printf("node:%3d excess:%3d height:%3d\n", headers[9], excess, height);
           break;

   }
#endif

#if 0
   size_t read_offset;
   size_t read_len;
   static const size_t buffer_size = 128;

   size_t base_dist;

   log_cache(pci_bar_handle, fd, fwl2);

   base_dist = headers[5]*4;
   read_len = headers[1]*4;
   read_offset = 0;
   while (read_offset < read_len) {
       if (read_offset != 0) {
           printf("Partial read by driver, trying again with remainder of buffer (%lu bytes)\n",
                   buffer_size - read_offset);
       }
       rc = pread(fd,
               read_buffer + read_offset,
               read_len - read_offset,
               base_dist + read_offset);
       if (rc < 0) {
           printf("Call to pread failed\n");
           exit(0);
       }
       read_offset += rc;
   }
   printf("Comparing Output\n");
   num_errors = 0;
   for (int i=0;i<numV;i++) {
       unsigned char* ref_ptr = write_buffer + (headers[6] +i)*4;
       //printf("%d\n", *(ref_ptr+1));
       uint32_t ref_dist = (*(ref_ptr + 3)<<24)+
           (*(ref_ptr + 2)<<16) +
           (*(ref_ptr + 1)<<8)  +
           *ref_ptr;
       unsigned char* act_ptr = read_buffer + i*4;
       uint32_t act_dist = (*(act_ptr+3)<<24) + (*(act_ptr+2)<<16) + (*(act_ptr+1)<<8) + *act_ptr;

       bool error = (act_dist != ref_dist);
       if (error) num_errors++;
       if ( (error & (num_errors < 50)) || i==numV-1)
           printf("vid:%3d dist:%5u, ref:%5u, %s, num_errors:%2d\n", i, act_dist, ref_dist,
                   act_dist == ref_dist ? "MATCH" : "FAIL", num_errors);
   }
#endif
   // fclose(fwtu);
   // fclose(fws3);
   // fclose(fws4);
   // fclose(fws5);
   // fclose(fwl2);

   if (write_buffer != NULL) {
       free(write_buffer);
   }
   if (read_buffer != NULL) {
       free(read_buffer);
   }
   return 0;
}
int dma_example(int slot_id) {
    int write_fd, read_fd, rc;
    char device_file_name[256];
    char *write_buffer, *read_buffer;
    static const size_t buffer_size = 128;
    int channel=0;

    read_buffer = NULL;
    write_buffer = NULL;

    rc = sprintf(device_file_name, "/dev/edma%i_queue_0", slot_id);
    fail_on((rc = (rc < 0)? 1:0), out, "Unable to format device file name.");


    /* make sure the AFI is loaded and ready */
    rc = check_slot_config(slot_id);
    fail_on(rc, out, "slot config is not correct");

    read_fd = fpga_dma_open_queue(FPGA_DMA_XDMA, slot_id,
            /*channel*/ 0, /*is_read*/ true);
    fail_on((rc = (read_fd < 0) ? -1 : 0), out, "unable to open read dma queue");

    write_fd = fpga_dma_open_queue(FPGA_DMA_XDMA, slot_id,
            /*channel*/ 0, /*is_read*/ false);
    fail_on((rc = (write_fd < 0) ? -1 : 0), out, "unable to open write dma queue");

    write_buffer = (char *)malloc(buffer_size);
    read_buffer = (char *)malloc(buffer_size);
    if (write_buffer == NULL || read_buffer == NULL) {
        rc = ENOMEM;
        goto out;
    }

    rand_string(write_buffer, buffer_size);
    rc = fpga_dma_burst_write(write_fd, write_buffer, buffer_size,
            0);

    rc = 0;

    /* fsync() will make sure the write made it to the target buffer
     * before read is done
     */


    rc = fpga_dma_burst_read(read_fd, read_buffer, buffer_size,0);

    if (memcmp(write_buffer, read_buffer, buffer_size) == 0) {
        printf("DRAM DMA read the same string as it wrote on channel %d (it worked correctly!)\n", channel);
    } else {
        int i;
        printf("Bytes written to channel %d:\n", channel);
        for (i = 0; i < buffer_size; ++i) {
            printf("%3d,", write_buffer[i]);
        }

        printf("\n\n");

        printf("Bytes read:\n");
        for (i = 0; i < buffer_size; ++i) {
            printf("%3d,", read_buffer[i]);
        }
        printf("\n\n");

        rc = 1;
        fail_on(rc, out, "Data read from DMA did not match data written with DMA. Was there an fsync() between the read and write?");
    }

out:
    if (write_buffer != NULL) {
        free(write_buffer);
    }
    if (read_buffer != NULL) {
        free(read_buffer);
    }
    /* if there is an error code, exit with status 1 */
    return (rc != 0 ? 1 : 0);
}

