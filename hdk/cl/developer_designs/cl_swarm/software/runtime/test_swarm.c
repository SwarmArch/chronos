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



int dma_example(int slot_i);
/* Constants determined by the CL */
/* a set of register offsets; this CL has only one */
/* these register addresses should match the addresses in */
/* /aws-fpga/hdk/cl/examples/common/cl_common_defines.vh */


pci_bar_handle_t pci_bar_handle;
uint32_t APP_ID;
uint32_t N_TILES;
uint32_t N_CORES;
uint32_t ID_OCL_SLAVE;
uint32_t READY_LIST_SIZE;
uint32_t L2_BANKS;

uint32_t ID_RW_READ;
uint32_t ID_RW_WRITE;
uint32_t ID_RO_STAGE;
uint32_t ID_SPLITTER;
uint32_t ID_COALESCER;
uint32_t ID_TASK_UNIT;
uint32_t ID_L2_RW; // RW/ RO naming is for historical reasons. Both caches are read-write now.
uint32_t ID_L2_RO;
uint32_t ID_TSB;
uint32_t ID_CQ;
uint32_t ID_CM;
uint32_t ID_SERIALIZER;
uint32_t ID_LAST;
uint32_t LOG_TQ_SIZE, LOG_CQ_SIZE;
uint32_t TQ_STAGES, SPILLQ_STAGES;
uint32_t NON_SPEC;

uint32_t USING_PIPELINED_TEMPLATE;

uint32_t active_tiles;
bool logging_on = false;
uint32_t logging_phase_tasks = 0x100;
uint32_t reading_binary_file = false;

uint16_t pci_vendor_id = 0x1D0F; /* Amazon PCI Vendor ID */
uint16_t pci_device_id = 0xF000; /* PCI Device ID preassigned by Amazon for F1 applications */

/* Declaring the local functions */

int peek_poke_example(int slot, int pf_id, int bar_id);
int test_task_unit(int slot, int pf_id, int bar_id);
int test_swarm(int slot_id, int pf_id, int bar_id, FILE* fg, int);
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

    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_APP_ID, &APP_ID);
    USING_PIPELINED_TEMPLATE = (APP_ID >> 16) & 1;

    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_N_TILES, &N_TILES);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_N_CORES, &N_CORES);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_TQ_HEAP_STAGES, &TQ_STAGES);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_NON_SPEC, &NON_SPEC);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_TQ_SIZE, &LOG_TQ_SIZE);
    if (NON_SPEC) LOG_TQ_SIZE = TQ_STAGES;
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_CQ_SIZE, &LOG_CQ_SIZE);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_SPILL_Q_SIZE, &SPILLQ_STAGES);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_READY_LIST_SIZE, &READY_LIST_SIZE);
    pci_peek(0, ID_OCL_SLAVE, OCL_PARAM_LOG_L2_BANKS, &L2_BANKS);
    L2_BANKS = (1<<L2_BANKS);
    READY_LIST_SIZE = (1<<READY_LIST_SIZE);
    //L2_BANKS = 1; READY_LIST_SIZE = 8;

    printf("APP_ID %x Pipelined:%d\n", APP_ID, USING_PIPELINED_TEMPLATE);

    printf("%d tiles\n", N_TILES);
    printf("Non spec %d\n", NON_SPEC);
    printf("TQ Size %d CQ Size %d\n", LOG_TQ_SIZE, LOG_CQ_SIZE);
    //L2_BANKS = 1;
    //READY_LIST_SIZE = 32;
    printf("L2 banks: %d Ready list size: %d\n", L2_BANKS, READY_LIST_SIZE);

    ID_RW_READ        =       1;
    ID_RW_WRITE       =       2;
    ID_RO_STAGE       =       3;

    ID_SPLITTER         =       4;
    ID_COALESCER        =       5;

    ID_TASK_UNIT        =       6;
    ID_L2_RW            =       7;
    ID_L2_RO            =       8;
    ID_TSB              =       9;
    ID_CQ               =      10;
    ID_CM               =      11;
    ID_SERIALIZER       =      12;
    ID_LAST             =      13;

    ID_OCL_SLAVE = 0;

}

int main(int argc, char **argv) {
    int rc;
    int slot_id;

    char* usage = "Usage ./test_swarm app <input> <riscv_hex_file>";
    if ( (argc <2) || (argc >4)) {
        printf("%s\n", usage);
        exit(0);
    }

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
    int app = -1; // Invalid number
    FILE* fg;
    fhex = 0;
    if (strcmp(argv[1], "dma_test") ==0) {
        dma_example(slot_id);
        exit(0);
    }
    if (strcmp(argv[1], "sssp") ==0) {
        app = APP_SSSP;
    }
    if (strcmp(argv[1], "des") ==0) {
        app = APP_DES;
    }
    if (strcmp(argv[1], "astar") ==0) {
        app = APP_ASTAR;
    }
    if (strcmp(argv[1], "maxflow") ==0) {
        app = APP_MAXFLOW;
    }
    if (strcmp(argv[1], "color") ==0) {
        app = APP_COLOR;
    }
    if (strcmp(argv[1], "silo") ==0) {
        app = APP_SILO;
    }
    if (argc >=4 ) fhex = fopen(argv[3], "r"); // code hex
    if ( (app > 0) & (argc <3)) {
        printf("Need input file\n");
        exit(0);
    }
    // Read the first word to determine if file is binary
    fg = fopen(argv[2], "rb");
    fail_on((rc = (fg == 0)? 1:0), out, "unable to open input file. ");
    uint32_t magic_op;
    fread( &magic_op, 1, 4, fg);
    printf("MAGIC_OP %x\n", magic_op);
    reading_binary_file = (magic_op == 0xdead);
    if (!reading_binary_file) {
        fclose(fg);
        fg=fopen(argv[2], "r");
    }
    if (app == -1) {
        printf("Invalid app\n"); exit(0);
    }
    test_swarm(slot_id, FPGA_APP_PF, APP_PF_BAR0, fg, app);
    return 0;

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
    uint32_t chunk_size = 512;
    while (write_offset < write_len) {
        if (write_offset != 0) {
            //    printf("Partial write by driver, trying again with remainder of buffer (%lu bytes)\n",
            //          write_len - write_offset);
        }
        //rc = fpga_dma_burst_write(write_fd,
        rc = pwrite(write_fd,
                write_buffer + write_offset,
                (write_len - write_offset) > chunk_size ? chunk_size: (write_len - write_offset) ,
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
    unsigned char* data_buffer = (unsigned char*) malloc(code_len);
    fseek(fhex, 0, SEEK_END);
    uint32_t size = ftell(fhex);
    fseek(fhex, 0, SEEK_SET);
    char* content = (char*) malloc (size);
    fread(content, 1, size, fhex);

    const unsigned int code_start = 0x80000000;
    const unsigned int data_start = 0xc0000000;

    uint32_t offset = 0;
    char* line = content;
    bool reading_code = true;
    while (1) {
        if (line[0] == ':') {
            uint32_t byteCount = hToI(line + 1, 2);
            uint32_t nextAddr = hToI(line + 3, 4) + offset;
            uint32_t key = hToI(line + 7, 2);
            //printf("%d %x %d\n", byteCount, nextAddr,key);
            switch (key) {
                case 0:
                    for (uint32_t i = 0; i < byteCount; i++) {
                        if (reading_code) {
                            code_buffer[nextAddr + i - code_start] = hToI(line + 9 + i * 2, 2);
                        } else {
                            data_buffer[nextAddr + i - data_start] = hToI(line + 9 + i * 2, 2);
                        }
                        //printf("%x %x %c%c\n",nextAddr + i,hToI(line + 9 + i*2,2),line[9 + i * 2],line[9 + i * 2+1]);
                    }
                    break;
                case 2:
                    offset = hToI(line + 9, 4) << 4;
                    printf("offset %x\n", offset);
                    break;
                case 4:
                    offset = hToI(line + 9, 4) << 16;
                    printf("offset %x\n", offset);
                    if (offset == data_start) reading_code = false;
                    else if (offset == code_start) reading_code = true;
                    else {
                        printf("unexpect offset\n");
                        exit(0);
                    }
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
    boot_code[2] = 0x80000137; // li sp, 0x80000
    boot_code[3] = 0x8067; // jalr x1, 0
    for (int i=0;i<4;i++) {
        code_buffer[i*4 + 0] = (boot_code[i] & 0xff);
        code_buffer[i*4 + 1] = (boot_code[i] >> 8) & 0xff;
        code_buffer[i*4 + 2] = (boot_code[i] >> 16) & 0xff;
        code_buffer[i*4 + 3] = (boot_code[i] >> 24) & 0xff;
    }


    free(content);
    //int rc =fpga_dma_burst_write(write_fd, code_buffer, code_len, code_start);
    //if(rc<0){
    //    printf("unable to open read dma queue\n");
    //    exit(0);
   // }
    dma_write(code_buffer, code_len, code_start);
    dma_write(data_buffer, code_len, data_start);
}

int test_swarm(int slot_id, int pf_id, int bar_id, FILE* fg, int app) {
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
            /*channel*/ 1, /*is_read*/ false);
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
    rc = fpga_pci_attach(slot_id, pf_id, bar_id, 0, &pci_bar_handle);
    if (rc > 0) {
        printf("Unable to attach to the AFI on slot id %d\n", slot_id);
        exit(0);
    }
    init_params();


    // Change here if you want to reduce the system size
    active_tiles = 1;
    uint32_t max_threads = 1e9;

    if (N_TILES < active_tiles) {
        printf("N_TILES %d < active_tiles %d\n", N_TILES, active_tiles);
        exit(0);
    }

    // Stage 1: Read input file and transfer to the FPGA
    printf("File %p\n", fg);
    write_buffer = (unsigned char *)malloc(1600*1024*1024);
    uint32_t* headers = (uint32_t*) write_buffer;
    long lSize;
    if (reading_binary_file) {
       fseek (fg , 0 , SEEK_END);
       lSize = ftell (fg);
       printf("File %p size %ld\n", fg, lSize);
       rewind (fg);
       fread( (void*) write_buffer, 1, lSize, fg);
       for (int i=0;i<16;i++) {
            printf("headers %d %x \n", i, headers[i]);
       }
    } else {
        uint32_t line;
        int ret;
        int n = 0;
        while ( (ret = fscanf(fg,"%8x\n", &line)) != EOF) {
            //line = n;
            write_buffer[n ] = line & 0xff;
            write_buffer[n +1] = (line >>8) & 0xff;
            write_buffer[n +2] = (line >>16) & 0xff;
            write_buffer[n +3] = (line >>24) & 0xff;
            if (n<64) headers[n/4] = line;
            n+=4;
        }
        printf("File Len %d\n", n);
        lSize = n;
    }
    if (app == APP_MAXFLOW) {
        uint32_t log_gr_interval = headers[10];
        // global relabel interval
        bool adjust_relabel_interval = true;
        if (adjust_relabel_interval) {
            log_gr_interval += -(int) log2(active_tiles) ;
            if (log_gr_interval < 5) log_gr_interval = 5;

        }
        headers[10] = log_gr_interval;
        headers[11] = ((1<<log_gr_interval) -1 )<<8;
        headers[12] = ~((1<<(log_gr_interval+8 ))-1);

        headers[13] = 0; // ordered edges
        headers[14] = 1; // producer task
        headers[15] = 0; // bfs non-spec
    }
    if (app == APP_COLOR) {
        headers[9] = 24;
        write_buffer[9*4] = headers[9];
    }
    if (app == APP_DES) {
        headers[13] = 1;
    }
    if (app == APP_ASTAR) {
        uint32_t base_latlon = headers[6];
        uint32_t destNode = headers[8];
        // copy dest lat lon
        uint32_t dest_lat_addr = (base_latlon ) + destNode *2;
        headers[11] =  ((uint32_t *) write_buffer)[dest_lat_addr]  ;
        headers[12] =  ((uint32_t *) write_buffer)[dest_lat_addr + 1]  ;
        headers[13] = 3;
        printf("dest lat %d %x\n", dest_lat_addr, headers[11]);
    }
    uint32_t numV = headers[1];
    uint32_t numE = headers[2];;


    uint32_t startCycle, endCycle;

    int file_len = lSize;
    read_buffer = (unsigned char *)malloc(headers[1]*4);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    rc =fpga_dma_burst_write(write_fd, write_buffer, file_len, 0);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
    printf("Write input data: cycles from %d %d\n", startCycle, endCycle);
    rc = 0;

    uint32_t* csr_offset = (uint32_t *) (write_buffer + headers[3]*4);
    uint32_t* csr_neighbors = (uint32_t *) (write_buffer + headers[4]*4);
    uint32_t* csr_ref_color = (uint32_t *) (write_buffer + headers[6]*4);

    if(rc!=0){
        printf("unable to write_dma\n");
        exit(0);
    }


    if (fhex) {
        // If running on risc-v cores
        load_code();
    }
    printf("Loading code... Success\n");


    // Stage 2: Intialize Task-spilling data structures
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
    uint64_t cycles;
    int num_errors = 0;

    uint32_t ocl_data = 0;


    // Stage 3: Global Initialization

    // for debug logs (if enabled in config)
    FILE* fwtu = fopen("task_unit_log", "w");
    FILE* fwddr = fopen("ddr_log", "w");
    FILE* fwser = fopen("serializer_log", "w");
    FILE* fwcoal = fopen("coalescer_log", "w");
    FILE* fwsp = fopen("splitter_log", "w");
    FILE* fwro = fopen("ro_log", "w");
    FILE* fwcq = fopen("cq_log", "w");
    FILE* fwrw = fopen("rw_log", "w");
    FILE* fwl2 = fopen("l2_rw", "w");
    FILE* fwl2ro = fopen("l2_ro", "w");
    FILE* fwrv_0 = fopen("riscv_log_0", "w");
    unsigned char* log_buffer = (unsigned char *)malloc(20000*64);

    sleep(1);


    // OCL Initialization

    // Checking PCI latency;
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
    printf("PCI latency %d cycles\n", endCycle - startCycle);
    if (endCycle == startCycle) return -1;


    uint32_t tied_cap = 1<<(LOG_TQ_SIZE -2);
    uint32_t clean_threshold = 40;
    uint32_t spill_threshold = (1<<LOG_TQ_SIZE) - 500;
    //tied_cap = 100;
    //tied_cap = 0;
    //spill_threshold = 1500;
    uint32_t spill_size = 240;

    uint32_t deq_tolerance = 3;
    uint32_t pre_enq_fifo_thresh = 1;


    assert(spill_threshold > (tied_cap + (1<<LOG_CQ_SIZE) + spill_size));
    assert((spill_size % 8) == 0);
    assert(spill_size < (1<<SPILLQ_STAGES) );
    assert(tied_cap < (1<<LOG_TQ_SIZE) );
    assert(clean_threshold < (1<<TQ_STAGES) );
    printf("Spill Alloc %08x %08x\n",ADDR_BASE_SPILL, TOTAL_SPILL_ALLOCATION);

    //pci_poke(N_TILES, ID_GLOBAL, MEM_XBAR_NUM_CTRL, 4);

    for (int i=0;i<N_TILES;i++) {

        // configure base addresses
        for (int j=0;j<16;j++) {
            pci_poke(i, ID_ALL_APP_CORES, j*4, headers[j]);
        }
        pci_poke(i, ID_RW_READ, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, 14);
        pci_poke(i, ID_RW_WRITE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, 14);
        pci_poke(i, ID_RO_STAGE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, 14);
        pci_poke(i, ID_SERIALIZER, SERIALIZER_N_THREADS, 16);

        // Spilling config
        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_ADDR_STACK_PTR ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION) >> 6 );
        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_BASE_STACK ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION + STACK_BASE_OFFSET) >> 6 );
        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_BASE_SCRATCHPAD ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION + SCRATCHPAD_BASE_OFFSET) >> 6 );
        pci_poke(i, ID_COAL_AND_SPLITTER, SPILL_BASE_TASKS ,
                (ADDR_BASE_SPILL + i*TOTAL_SPILL_ALLOCATION + SPILL_TASK_BASE_OFFSET) >> 6 );

        pci_poke(i, ID_TSB, TSB_LOG_N_TILES        , active_tiles );
        pci_poke(i, ID_SERIALIZER, SERIALIZER_N_MAX_RUNNING_TASKS , max_threads );
        if (app != APP_ASTAR) {
            // astar relies on simple mapping to send termination tasks to all
            // tiles
            pci_poke(i, ID_TSB, TSB_HASH_KEY       , 1);
        }
        pci_poke(i, ID_L2_RW, L2_CIRCULATE_ON_STALL  , 1);
        pci_poke(i, ID_L2_RO, L2_CIRCULATE_ON_STALL  , 1);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_SPILL_THRESHOLD, spill_threshold);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_CLEAN_THRESHOLD, clean_threshold);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_TIED_CAPACITY, tied_cap);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_SPILL_SIZE, spill_size);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_SPILL_CHECK_LIMIT, spill_size * 16);
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_ALT_DEBUG, 1); // get enq args instead of deq locale/ts

        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_PRE_ENQ_BUF,
                (pre_enq_fifo_thresh << 16) | deq_tolerance);
        // Do not dequeue a task with a timestamp larger by this much than the gvt
        if (NON_SPEC) {
            // astar - 900
            // sssp - 5000
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_THROTTLE_MARGIN, 1000);
        }

        if (app == APP_MAXFLOW) {
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_IS_TRANSACTIONAL, 1);
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_GLOBAL_RELABEL_START_MASK, (1<<headers[10]) - 1);
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_GLOBAL_RELABEL_START_INC, 16);
            pci_poke(i, ID_CQ, CQ_IGNORE_GVT_TB, 1);
        }

        if (app == APP_COLOR) {
            pci_poke(i, ID_TASK_UNIT, TASK_UNIT_PRODUCER_THRESHOLD, 50);
        }
        pci_poke(i, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB, 0 );
    }
    usleep(20);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
    printf("PCI latency %d cycles\n", endCycle - startCycle);

    pci_poke(0, ID_L2_RO, L2_LOG_BVALID, 1);

    if (endCycle == startCycle) return -1; // OCL_BUS is broken -> abort!!

    // Stage 4 : Application-specific initialization

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
                uint32_t enq_locale = (*(ref_ptr + 3)<<24)+
                    (*(ref_ptr + 2)<<16) +
                    (*(ref_ptr + 1)<<8)  +
                    *ref_ptr;
                uint32_t enq_tile = (enq_locale>>4) %(active_tiles);
                pci_poke(enq_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_LOCALE , enq_locale );
                pci_poke(enq_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );
                //usleep(10);
                pci_poke(enq_tile, ID_OCL_SLAVE, OCL_TASK_ENQ      , 0);

                printf("Enquing initial task %d\n", enq_locale);
            }
            break;
        case APP_SSSP:
            printf("APP_SSSP\n");
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_LOCALE , headers[7] );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );
            break;
        case APP_ASTAR:
            printf("APP_ASTAR\n");
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 1 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0xffffffff );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_LOCALE , headers[7] );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 1 );

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );

            break;
        case APP_COLOR:
            printf("APP_COLOR\n");

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_LOCALE , 0x20000 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );
            break;
        case APP_MAXFLOW:
            printf("APP_MAXFLOW\n");
            init_task_tile = (headers[7] >> 4) % active_tiles;
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_LOCALE,
                        headers[7] );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 1 );
            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0);

            pci_poke(init_task_tile, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );
            break;
        case APP_SILO:
            printf("APP_SILO\n");

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_LOCALE , 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_TTYPE, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARG_WORD, 0 );
            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ_ARGS , 0 );

            pci_poke(0, ID_OCL_SLAVE, OCL_TASK_ENQ, 0 );
            break;

    }
    printf("Starting Applicaton\n");

    // Stage 5: Start Application

    for (int i=0;i<N_TILES;i++) {
        // Number of remaining dequues
        pci_poke(i, ID_ALL_APP_CORES, CORE_N_DEQUEUES ,0xfffffff);
    }
    usleep(20);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &endCycle);
    printf("PCI latency %d cycles\n", endCycle - startCycle);
    if (endCycle == startCycle) return -1;

    if (logging_on) {
        // If we are in debugging mode, only allow a small number of tasks at a
        // time, lest the on-chip buffers fill up.
        pci_poke(0, ID_ALL_APP_CORES, CORE_N_DEQUEUES , logging_phase_tasks);
    }
    uint32_t core_mask = 0;
    uint32_t active_cores = N_CORES;
    core_mask = (1<<(active_cores))-1;
    if (!USING_PIPELINED_TEMPLATE) core_mask <<= 16;
    core_mask |= (1<<ID_COALESCER);
    core_mask |= (1<<ID_SPLITTER);
    printf("mask %x\n", core_mask);
    uint64_t startCycle64 = 0;
    uint64_t endCycle64 = 0;
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_MSB, &startCycle);
    startCycle64 = startCycle;
    pci_peek(0, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB, &startCycle);
    startCycle64 |= (startCycle64 << 32) | startCycle;
    for (int i=0;i<N_TILES;i++) {
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_START, 1);
        pci_poke(i, ID_ALL_CORES, CORE_START, core_mask);
    }

    usleep(200);

    printf("Waiting until app completes\n");

    // Stage 6: Wait until Application completes

    ocl_data = 0;
   uint32_t* results;

    int iters = 0;

   while(true) {
       uint32_t gvt;
       if (NON_SPEC) {
           pci_peek(0, ID_OCL_SLAVE, OCL_DONE, (uint32_t*) &gvt);
           //loop_debuggin_nonspec(iters);
       } else {
           pci_peek(0, ID_CQ, CQ_GVT_TS, &gvt);
       }
       if (gvt == -1) {
           // Record the ending cycle immediately
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
               for (int i=0;i<64;i++) {
                   usleep(1);
                   if (logging_on) {
                       pci_poke(0, ID_ALL_APP_CORES, CORE_N_DEQUEUES, logging_phase_tasks);
                   }
                   pci_peek(i%active_tiles, ID_OCL_SLAVE, OCL_DONE, (uint32_t*) &gvt);
                   if (gvt != -1) done=false;
               }
           }
           if (done) break;
       }
       if (logging_on) {

           log_ddr(pci_bar_handle, read_fd, fwddr, log_buffer,
                       (N_TILES << 8) | ID_GLOBAL);
           log_task_unit(pci_bar_handle, read_fd, fwtu, log_buffer, ID_TASK_UNIT);
           if (APP_ID == RISCV_ID) {
              log_riscv(pci_bar_handle, read_fd, fwrv_0, log_buffer, 16);
           } else if (USING_PIPELINED_TEMPLATE) {
              log_ro_stage(pci_bar_handle, read_fd, fwro, log_buffer, ID_RO_STAGE);
              log_rw_stage(pci_bar_handle, read_fd, fwrw, log_buffer, ID_RW_READ) ;
           }

           log_cache(pci_bar_handle, read_fd, fwl2, log_buffer, ID_L2_RW);
           log_cache(pci_bar_handle, read_fd, fwl2ro, log_buffer, ID_L2_RO);
           log_cq(pci_bar_handle, read_fd, fwcq, log_buffer, ID_CQ);
           log_coalescer(pci_bar_handle, read_fd, fwcoal, log_buffer, ID_COALESCER);
           log_splitter(pci_bar_handle, read_fd, fwsp, log_buffer, ID_SPLITTER);
           log_serializer(pci_bar_handle, read_fd, fwser, log_buffer, ID_SERIALIZER);
           fflush(fwtu); fflush(fwro); fflush(fwcq); fflush(fwl2); fflush(fwrv_0);
           fflush(fwl2ro); fflush(fwcoal); fflush(fwsp);
           usleep(200);

           loop_debuggin_spec(iters);
       }
       iters++;

   }
   // disable new dequeues from cores; for accurate counting of no tasks stalls
   pci_poke(0, ID_ALL_APP_CORES, CORE_N_DEQUEUES ,0x0);
   for (int i=0;i<N_TILES;i++) {
       pci_poke(i, ID_ALL_CORES, CORE_START, 0);
   }
   usleep(2800);
   usleep(300000);
   if (logging_on) {
       log_ddr(pci_bar_handle, read_fd, fwddr, log_buffer,
                   (N_TILES << 8) | ID_GLOBAL);
       log_task_unit(pci_bar_handle, read_fd, fwtu, log_buffer, ID_TASK_UNIT);
       //log_ro_stage(pci_bar_handle, read_fd, fwro, log_buffer, ID_RO_STAGE);
       //log_rw_stage(pci_bar_handle, read_fd, fwrw, log_buffer, ID_RW_READ);
       if (APP_ID == RISCV_ID) {
          log_riscv(pci_bar_handle, read_fd, fwrv_0, log_buffer, 16);
       } else if (USING_PIPELINED_TEMPLATE) {
          log_ro_stage(pci_bar_handle, read_fd, fwro, log_buffer, ID_RO_STAGE);
          log_rw_stage(pci_bar_handle, read_fd, fwrw, log_buffer, ID_RW_READ) ;
       }
       log_cache(pci_bar_handle, read_fd, fwl2, log_buffer, ID_L2_RW);
       log_cache(pci_bar_handle, read_fd, fwl2ro, log_buffer, ID_L2_RO);
       log_cq(pci_bar_handle, read_fd, fwcq, log_buffer, ID_CQ);
       log_serializer(pci_bar_handle, read_fd, fwser, log_buffer, ID_SERIALIZER);

       fflush(fwl2); fflush(fwl2ro); fflush(fwrw); fflush(fwro); fflush(fwser);
   }

   fflush(fwtu);
   printf("iters %d\n", iters);
   cycles = endCycle64 - startCycle64;
   //core_stats(0, cycles);
   for (int i=0;i< (NON_SPEC?active_tiles:1); i++) {
           task_unit_stats(i, cycles);
       if (i==0) {
           serializer_stats(i, ID_SERIALIZER);
       }
   }

   printf("Completed, flushing cache..\n");
   for (int i=0;i<N_TILES;i++) {
      pci_poke(i, ID_L2_RW, L2_FLUSH , 1 );
      pci_poke(i, ID_L2_RO, L2_FLUSH , 1 );
      usleep(100000);
   }

   // Stage 7: Application completed. Read counters for analysis.

   if (!NON_SPEC) {
       cq_stats(0, cycles);
   }

   uint32_t task_unit_ops=0;
   uint32_t total_tasks = 0;
   pci_peek(0, ID_TASK_UNIT, TASK_UNIT_STAT_N_DEQ_TASK, & total_tasks);
   printf("num tasks Tile:0  %9d Total: %9d\n",
           total_tasks,
           total_tasks * active_tiles
           );

   // L2 stats
   uint32_t sum_l2_read_miss =0;
   uint32_t sum_l2_write_miss =0;
   uint32_t sum_l2_evictions=0;
   uint32_t sum_l2_read_hit=0;
   uint32_t sum_l2_write_hit=0;
   uint32_t l2_read_hits, l2_read_miss, l2_write_hits, l2_write_miss, l2_evictions;
   for (int t=0; t<active_tiles;t++) {
       for (int b=0;b<2;b++) {
           pci_peek(t, ID_L2_RW+b, L2_READ_HITS   ,  &l2_read_hits);
           pci_peek(t, ID_L2_RW+b, L2_READ_MISSES ,  &l2_read_miss);
           pci_peek(t, ID_L2_RW+b, L2_WRITE_HITS  ,  &l2_write_hits);
           pci_peek(t, ID_L2_RW+b, L2_WRITE_MISSES,  &l2_write_miss);
           pci_peek(t, ID_L2_RW+b, L2_EVICTIONS   ,  &l2_evictions);
           if (t==0) {
               printf("Tile:%d L2 bank %d\n",t, b);
               printf("\tL2 Read  hits:%9d misses:%9d \n",
                       l2_read_hits, l2_read_miss);
               printf("\tL2 Write hits:%9d misses:%9d \n",
                       l2_write_hits, l2_write_miss);
               printf("\tL2 Evictions :%9d \n",
                       l2_evictions);
               double hit_rate = (l2_read_hits + l2_write_hits + 0.0) * 100 /
                   (l2_read_hits + l2_read_miss + l2_write_hits + l2_write_miss);
               printf("\tL2 hit-rate %5.2f%%\n", hit_rate);

               uint32_t retry_stall, retry_not_empty, retry_count, stall_in;
               pci_peek(t, ID_L2_RW+b, L2_RETRY_STALL   ,  &retry_stall);
               pci_peek(t, ID_L2_RW+b, L2_RETRY_NOT_EMPTY ,  &retry_not_empty);
               pci_peek(t, ID_L2_RW+b, L2_RETRY_COUNT ,  &retry_count);
               pci_peek(t, ID_L2_RW+b, L2_STALL_IN ,  &stall_in);

               printf("\tretry:  stall:%9d, not_empty:%9d, count:%9d\n",
                       retry_stall, retry_not_empty, retry_count);
               printf("\tstall_in     :%9d\n", stall_in);
           }

           sum_l2_read_hit += l2_read_hits;
           sum_l2_read_miss += l2_read_miss;
           sum_l2_write_hit += l2_write_hits;
           sum_l2_write_miss += l2_write_miss;
           sum_l2_evictions += l2_evictions;
       }
   }
   printf("Task Unit Ops %d, num_edges %d\n", task_unit_ops, numE);


   double time_ms = (cycles + 0.0) * 8/1e6;
   double read_bandwidth_MBPS = (sum_l2_read_miss + sum_l2_write_miss) * 64 / (time_ms * 1000) ;
   double write_bandwidth_MBPS = (sum_l2_evictions) * 64 / (time_ms * 1000) ;

   printf("FPGA cycles %ld  (%f ms) (%3f cycles/task/tile)\n",
           cycles,
           time_ms,
           cycles / (total_tasks + 0.0));

   printf("Read BW    %7.2f MB/s\n",read_bandwidth_MBPS);
   printf("Write BW   %7.2f MB/s\n",write_bandwidth_MBPS);

   double l2_tag_contention =
       (
        (sum_l2_read_hit + sum_l2_write_hit) +
            2* (sum_l2_read_miss + sum_l2_write_miss) + 0.0)*100
                   /
                (cycles * L2_BANKS);
   double task_unit_contention = (task_unit_ops + 0.0)*100/cycles;
   printf("L2 Tag contention %5.2f%%\n", l2_tag_contention);
   //printf("%d %d %d %d\n", sum_l2_read_hit, sum_l2_read_miss, sum_l2_write_hit, sum_l2_write_miss);
   printf("L2 accesses per task %5.2f\n",
           (sum_l2_read_hit + sum_l2_read_miss + sum_l2_write_miss + sum_l2_write_hit+0.0)/
             total_tasks);
   printf("Task Unit contention %5.2f%%\n", task_unit_contention);


    // Stage 8: application specific verification

   printf("Flush completed, reading results..\n");
   ocl_data = 1;
   uint32_t iter=0;
   while(ocl_data==1) {
       if (iter++ > 10) {
           printf("Flush did not complete.. Reading anyway\n");
           break;
       }
       for (int i=0;i<N_TILES;i++) {
           pci_peek(i, ID_L2_RW, L2_FLUSH, &ocl_data);
           if (ocl_data == 1) break;
           usleep(1000);
       }
   }


   pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_MSB        , 0 );
   uint32_t ref_count=0;
   uint32_t astar_low_fail_node = 0;
   uint32_t astar_low_fail_ref = 1e8;

   FILE* mf_state = fopen("maxflow_state", "w");
   FILE* fastar = fopen("astar_verif", "w");
   switch (app) {
       case APP_DES:
           results = (uint32_t*) malloc(4*(numV+16));
           for (int i=0;i<numV/16 +1;i++){
               fpga_dma_burst_read(read_fd, (uint8_t*) (results + i*16), 16*4, 64 + i*64);
           }
           for (int i=0;i<headers[12];i++) {  // numOutputs
               unsigned char* ref_ptr = write_buffer + (headers[6] +i)*4;
               //printf("%d\n", *(ref_ptr+1));
               uint32_t ref_data = (*(ref_ptr + 3)<<24)+
                   (*(ref_ptr + 2)<<16) +
                   (*(ref_ptr + 1)<<8)  +
                   *ref_ptr;
               uint32_t ref_vid = ref_data >> 16;
               uint32_t ref_val = ref_data & 0x3;
               uint32_t act_data = results[ref_vid];
               uint32_t act_val = (act_data >> 24) & 0x3;
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
               uint32_t act_data = results[i];
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
           results = (uint32_t*) malloc(4*(numV+16));
           for (int i=0;i<numV/16 +1;i++){
               fpga_dma_burst_read(read_fd, (uint8_t*) (results + i*16), 16*4, 64 + i*64);
           }
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
               //pci_poke(0, ID_OCL_SLAVE, OCL_ACCESS_MEM_SET_LSB        , (addr & 0xffffffff ));
              // pci_peek(0, ID_OCL_SLAVE, OCL_ACCESS_MEM, &act_dist );
               act_dist = results[i];
               bool error;
               if (app == APP_ASTAR)
                   error = abs(act_dist - ref_dist) >3;
               else {
                   error = (act_dist != ref_dist);
               }

               if (error) num_errors++;
               ref_count++;
               if (app == APP_SSSP) {
                   if ( ( error & (num_errors < 10)) || i==numV-1) {
                       printf("vid:%3d dist:%5d, ref:%5d, %s, num_errors:%2d\n",
                               i, act_dist, ref_dist,
                               act_dist == ref_dist ? "MATCH" : "FAIL", num_errors);
                   }
               } else {
                   if (act_dist != ref_dist) {
                     if ( (astar_low_fail_ref > ref_dist) ) {
                         astar_low_fail_node = i; astar_low_fail_ref = ref_dist;
                     }
                   }
                   fprintf(fastar, "vid:%3d dist:%5d, ref:%5d, %s, num_errors:%2d\n",
                           i, act_dist, ref_dist,
                           act_dist == ref_dist ? "MATCH" : "FAIL", num_errors);
                   if (i == headers[8]) {
                       printf("vid:%3d dist:%5d, ref:%5d, %s, num_errors:%2d\n",
                               i, act_dist, ref_dist,
                               act_dist == ref_dist ? "MATCH" : "FAIL", num_errors);
                   }
               }
           }
           printf("Total Errors %d / %d\n", num_errors, ref_count);
           if (num_errors > 0) {
               printf("Earliest Fail %d (%x) / %d\n",
                       astar_low_fail_node, astar_low_fail_node, astar_low_fail_ref);
           }
           break;
       case APP_COLOR:
           results = (uint32_t*) malloc(16*(numV+100));
           for (int i=0;i<numV/16 + 1;i++){
               fpga_dma_burst_read(read_fd, (uint8_t*) (results + i*16*4),
                       16*16, 64 + i*16*16);
           }
           color_node_prop_t* c_nodes =
               (color_node_prop_t *) (results);// (write_buffer + headers[5]*4);
           // verification

           FILE* fc = fopen("color_verif", "w");
           for (int i=0;i<numV;i++) {
               uint32_t eo_begin =c_nodes[i].eo_begin;
               uint32_t eo_end =eo_begin + c_nodes[i].degree;
               uint32_t i_deg = eo_end - eo_begin;
               uint32_t i_color = c_nodes[i].color;

                // read_join_counter and scratch;
               uint32_t bitmap = c_nodes[i].scratch;
               uint32_t join_counter = c_nodes[i].ndp;

               fprintf(fc,"i=%d d=%d c=%d bitmap=%8x counter=(%d %d) ref:%d\n",
                       i, i_deg, i_color,
                       bitmap,
                        join_counter, c_nodes[i].ncp,
                        csr_ref_color[i]);
               bool error = (i_color != csr_ref_color[i]);
               uint32_t join_cnt = 0;
               for (int j=eo_begin;j<eo_end;j++) {
                    uint32_t n = csr_neighbors[j];
                    uint32_t n_deg = c_nodes[n].degree;
                    uint32_t n_color = c_nodes[n].color;
                    fprintf(fc,"\tn=%d d=%d c=%d r=%d\n",n, n_deg, n_color, csr_ref_color[n]);
                    if (i_color == n_color) {
                        fprintf(fc,"\t ERROR:Neighbor has same color\n");
                    }
                    if (n_deg > i_deg || ((n_deg == i_deg) & (n<i))) join_cnt++;
               }
               fprintf(fc,"\tjoin_cnt=%d\n", join_cnt);
               if (error) num_errors++;
               if ( error & (num_errors < 10) )
                   printf("Error at vid:%3d color:%5d\n",
                           i, c_nodes[i].color);

           }
           printf("Total Errors %d / %d\n", num_errors, numV);
           break;
      case APP_MAXFLOW:
           results = (uint32_t*) malloc(64*(numV+100));
           for (int i=0;i<numV/16 + 1;i++){
               fpga_dma_burst_read(read_fd, (uint8_t*) (results + i*16*16),
                       16*64, 64 + i*64*16);
           }
           maxflow_edge_prop_t* edges =
               (maxflow_edge_prop_t *) (write_buffer + headers[4]*4);
           maxflow_node_prop_t* nodes =
               (maxflow_node_prop_t *) (results);// (write_buffer + headers[5]*4);
           for (int i=0;i <numV;i++) {
               fprintf(mf_state, "node:%3d excess:%3d height:%3d %s\n",
                       i, nodes[i].excess, nodes[i].height,
                       (nodes[i].excess>0)?"inflow" : "");
               uint32_t eo_begin =csr_offset[i];
               uint32_t eo_end =csr_offset[i+1];
               int32_t sum_flow =0;

               for (int j=eo_begin;j<eo_end;j++) {
                    uint32_t n = edges[j].dest & 0xffffff;
                    int32_t cap = edges[j].capacity;
                    int32_t flow = nodes[i].flow[j-eo_begin];
                    int32_t reverse_edge = edges[j].dest >> 24;
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
           printf("node:%3d excess:%3d height:%3d\n", headers[9], nodes[headers[9]].excess, nodes[headers[9]].height);
           fflush(mf_state);
           break;

   }

   if (write_buffer != NULL) {
       free(write_buffer);
   }
   if (read_buffer != NULL) {
       free(read_buffer);
   }
   return 0;
}


int dma_example(int slot_id) {
    // Small example to test DMA
    int write_fd, read_fd, rc;
    char device_file_name[256];
    uint8_t *write_buffer, *read_buffer;
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

    write_buffer = (uint8_t *)malloc(buffer_size);
    read_buffer = (uint8_t *)malloc(buffer_size);
    if (write_buffer == NULL || read_buffer == NULL) {
        rc = ENOMEM;
        goto out;
    }

    rand_string((char*) write_buffer, buffer_size);
    rc = fpga_dma_burst_write(write_fd, write_buffer, buffer_size,
            0);

    rc = 0;

    /* fsync() will make sure the write made it to the target buffer
     * before read is done
     */


    rc = fpga_dma_burst_read(read_fd, read_buffer, buffer_size, 0);

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

void loop_debuggin_nonspec(uint32_t iters){

    uint32_t gvt, gvt_tb;
    uint32_t n_tasks, n_tied_tasks, heap_capacity;
    uint32_t coal_tasks;
    uint32_t coal_state;
    uint32_t stack_ptr=0;
    uint32_t cq_state;
    uint32_t tq_debug;
    uint32_t cycle;
    uint32_t ser_debug;
    uint32_t ser_locale =0;
    uint32_t ser_ready;
    uint32_t tsb_entry_valid;
    uint32_t rw_read_fifo_occ;
    uint32_t rw_write_fifo_occ;

    for (int i=0;i<(active_tiles);i++) {
        pci_peek(i, ID_OCL_SLAVE, OCL_DONE, (uint32_t*) &gvt);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_LVT, &gvt_tb);
        pci_peek(i, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB       , &cycle);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_N_TASKS, &n_tasks);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_N_TIED_TASKS, &n_tied_tasks);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_CAPACITY, &heap_capacity);
        pci_peek(i, ID_COALESCER, CORE_NUM_DEQ, &coal_tasks);
        pci_peek(i, ID_CQ, CQ_STATE, &cq_state );
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_MISC_DEBUG, &tq_debug );
        pci_peek(i, ID_COALESCER, CORE_STATE, &coal_state );
        pci_peek(i, ID_COALESCER, COAL_STACK_PTR, &stack_ptr );

        pci_peek(i, ID_SERIALIZER, SERIALIZER_READY_LIST, &ser_ready);
        pci_peek(i, ID_SERIALIZER, SERIALIZER_DEBUG_WORD, &ser_debug);
        pci_peek(i, ID_SERIALIZER, SERIALIZER_S_LOCALE, &ser_locale);
        pci_peek(i, ID_RW_READ, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD , &rw_read_fifo_occ );
        pci_peek(i, ID_RW_WRITE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD , &rw_write_fifo_occ );

        pci_peek(i, ID_TSB, TSB_ENTRY_VALID, &tsb_entry_valid );
        printf(" [%4d][%1d][%8u] gvt:(%9x %9d) (%4d %4d %4d) %6d %4x stack_ptr:%4x | %8d %8x %8x | %x %2d %2d\n",
                iters, i, cycle, gvt, gvt_tb,
                n_tasks, n_tied_tasks, heap_capacity,
                cq_state, tq_debug, stack_ptr & 0xffff,
                ser_locale, ser_ready, ser_debug, tsb_entry_valid,
                rw_read_fifo_occ, rw_write_fifo_occ
              );
        //cq_stats(0, ID_CQ);

    }
    if (iters > 2999){
        uint32_t l2_debug;
        uint32_t rw_read_debug, rw_write_debug;
        uint32_t w_count;
        uint32_t mshr_valid;
        uint32_t ocl_l2_debug;
        uint32_t fifo_size;
        for (int i=0;i<active_tiles;i++) {
            pci_peek(i, ID_L2_RW, L2_DEBUG_WORD, &l2_debug);
            pci_peek(i, ID_RW_READ, CORE_DEBUG_WORD, &rw_read_debug);
            pci_peek(i, ID_RW_WRITE, CORE_DEBUG_WORD, &rw_write_debug);
            pci_peek(i, ID_L2_RW, L2_DEBUG_WORD + 4, &w_count);
            pci_peek(i, ID_L2_RW, L2_DEBUG_WORD + 8, &mshr_valid);
            pci_peek(i, ID_RW_READ, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, &fifo_size);
            printf("%d RW %8x (%8x) rw_read:%8x write:%8x mshr:%8x fifo:%8x\n",
                    i, l2_debug, w_count,
                    rw_read_debug, rw_write_debug, mshr_valid,
                    fifo_size);
            pci_peek(i, ID_L2_RO, L2_DEBUG_WORD, &l2_debug);
            pci_peek(i, ID_RO_STAGE, CORE_DEBUG_WORD, &rw_write_debug);
            pci_peek(i, ID_L2_RO, L2_DEBUG_WORD + 8, &mshr_valid);
            pci_peek(i, ID_OCL_SLAVE, OCL_L2_DEBUG, &ocl_l2_debug);
            pci_peek(i, ID_RO_STAGE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, &fifo_size);
            printf("%d RO l2:%8x stage:%8x mshr:%8x ocl:%8x fifo:%8x\n",
                    i, l2_debug, rw_write_debug, mshr_valid, ocl_l2_debug,
                    fifo_size);
            //pci_peek(i, ID_RO_STAGE,
            //        CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, &l2_debug);
            //printf("RO fifo %8x\n", l2_debug);

        }
        uint32_t ddr_status;
        for (int i=0;i<=20;i+=4) {
            pci_peek(N_TILES, ID_GLOBAL, i, &ddr_status);
            printf("DDR status %d: %8x\n", i, ddr_status);
        }
        uint32_t ddr_stats[20];
        for (int i=0;i<=20;i++) {
            pci_peek(N_TILES, ID_GLOBAL, 0x20 + 4*i, &ddr_stats[i]);
        }
        printf("DDR count\n");
        for (int i=0;i<5;i++) {
            printf(" i: %d ", i);
            for (int j=0;j<4;j++) {
                printf("%8d ", ddr_stats[i*4+j]);
            }
            printf("\n");
        }
        //if (iters == 3000) break;
    }
}

void loop_debuggin_spec(uint32_t iters){

    uint32_t gvt, gvt_tb;
    uint32_t n_tasks, n_tied_tasks, heap_capacity;
    uint32_t coal_deq, coal_enq;
    uint32_t coal_state;
    uint32_t stack_ptr=0;
    uint32_t cq_state;
    uint32_t tq_debug, tq_debug_1;
    uint32_t cycle;
    uint32_t ser_debug;
    uint32_t ser_locale =0;
    uint32_t ser_ready;
    uint32_t tsb_entry_valid;
    uint32_t rw_read_fifo_occ =0;
    uint32_t rw_write_fifo_occ = 0;
    for (int i=0;i<(active_tiles);i++) {
        pci_peek(i, ID_CQ, CQ_GVT_TS, &gvt);
        if (NON_SPEC) {
            pci_peek(i, ID_OCL_SLAVE, OCL_DONE, (uint32_t*) &gvt);
        }
        pci_peek(i, ID_CQ, CQ_GVT_TB, &gvt_tb);
        pci_peek(i, ID_OCL_SLAVE, OCL_CUR_CYCLE_LSB       , &cycle);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_N_TASKS, &n_tasks);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_N_TIED_TASKS, &n_tied_tasks);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_CAPACITY, &heap_capacity);
        pci_peek(i, ID_COALESCER, CORE_NUM_DEQ, &coal_deq);
        pci_peek(i, ID_COALESCER, CORE_NUM_ENQ, &coal_enq);
        pci_peek(i, ID_COALESCER, CORE_STATE, &coal_state);
        pci_peek(i, ID_CQ, CQ_STATE, &cq_state );
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_SET_STAT_ID, 0);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_MISC_DEBUG, &tq_debug );
        pci_poke(i, ID_TASK_UNIT, TASK_UNIT_SET_STAT_ID, 1);
        pci_peek(i, ID_TASK_UNIT, TASK_UNIT_MISC_DEBUG, &tq_debug_1 );
        pci_peek(i, ID_COALESCER, CORE_STATE, &stack_ptr );

        pci_peek(i, ID_SERIALIZER, SERIALIZER_READY_LIST, &ser_ready);
        pci_peek(i, ID_SERIALIZER, SERIALIZER_DEBUG_WORD, &ser_debug);
        pci_peek(i, ID_SERIALIZER, SERIALIZER_S_LOCALE, &ser_locale);
        //pci_peek(i, ID_RW_READ, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD , &rw_read_fifo_occ );
        //pci_peek(i, ID_RW_WRITE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD , &rw_write_fifo_occ );

        pci_peek(i, ID_TSB, TSB_ENTRY_VALID, &tsb_entry_valid );
        printf(" [%4d][%1d][%8u] gvt:(%9x %9d) (%4d %4d %4d) %6d %4x stack_ptr:%4x | %8d %8x %8x | %x %2d %2d\n",
                iters, i, cycle, gvt, gvt_tb,
                n_tasks, n_tied_tasks, heap_capacity,
                cq_state, tq_debug, stack_ptr,
                ser_locale, ser_ready, ser_debug, tsb_entry_valid,
                rw_read_fifo_occ, rw_write_fifo_occ
              );
        printf(" coal state:%8x deq: %7d enq: %7d tq_state_2: %8x\n", coal_state, coal_deq, coal_enq, tq_debug_1);
        pci_poke(i, ID_ALL_APP_CORES, CORE_N_DEQUEUES, logging_phase_tasks);
        //cq_stats(0, ID_CQ);
        /*
           uint32_t l2_debug;
           uint32_t rw_read_debug, rw_write_debug;
           uint32_t w_count;
           uint32_t mshr_valid;
           uint32_t ocl_l2_debug;
           uint32_t fifo_size;
           for (int i=0;i<active_tiles;i++) {
           pci_peek(i, ID_L2_RW, L2_DEBUG_WORD, &l2_debug);
           pci_peek(i, ID_RW_READ, CORE_DEBUG_WORD, &rw_read_debug);
           pci_peek(i, ID_RW_WRITE, CORE_DEBUG_WORD, &rw_write_debug);
           pci_peek(i, ID_L2_RW, L2_DEBUG_WORD + 4, &w_count);
           pci_peek(i, ID_L2_RW, L2_DEBUG_WORD + 8, &mshr_valid);
           printf("%d RW %8x (%8x) rw_read:%8x write:%8x mshr:%8x \n",
           i, l2_debug, w_count,
           rw_read_debug, rw_write_debug, mshr_valid
           );
           pci_peek(i, ID_L2_RO, L2_DEBUG_WORD, &l2_debug);
           pci_peek(i, ID_RO_STAGE, CORE_DEBUG_WORD, &rw_write_debug);
           pci_peek(i, ID_L2_RO, L2_DEBUG_WORD + 8, &mshr_valid);
           pci_peek(i, ID_OCL_SLAVE, OCL_L2_DEBUG, &ocl_l2_debug);
           pci_peek(i, ID_RO_STAGE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, &fifo_size);
           printf("%d RO l2:%8x stage:%8x mshr:%8x ocl:%8x \n",
           i, l2_debug, rw_write_debug, mshr_valid, ocl_l2_debug,
           fifo_size);

           pci_peek(i, ID_RW_READ, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, &rw_read_debug);
           pci_peek(i, ID_RW_WRITE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, &rw_write_debug);
           pci_peek(i, ID_RO_STAGE, CORE_FIFO_OUT_ALMOST_FULL_THRESHOLD, &fifo_size);
           printf("%d fifo size rw_read:%4x rw_write:%4x ro:%8x\n", i,
           rw_read_debug, rw_write_debug, fifo_size);

           }
           if (iters==2999) {
           printf("ser debug %d %8x %x\n", ser_locale, ser_ready, ser_debug);
           }
           */
    }
    usleep(1000);
}
