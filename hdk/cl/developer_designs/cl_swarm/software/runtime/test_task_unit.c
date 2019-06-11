
#include "header.h"
int test_task_unit(int slot_id, int pf_id, int bar_id) {
    int rc;
    /* pci_bar_handle_t is a handler for an address space exposed by one PCI BAR on one of the PCI PFs of the FPGA */

    //pci_bar_handle_t pci_bar_handle = PCI_BAR_HANDLE_INIT;

    /* attach to the fpga, with a pci_bar_handle out param
     * To attach to multiple slots or BARs, call this function multiple times,
     * saving the pci_bar_handle to specify which address space to interact with in
     * other API calls.
     * This function accepts the slot_id, physical function, and bar number
     */
    rc = fpga_pci_attach(slot_id, pf_id, bar_id, 0, &pci_bar_handle);
    fail_on(rc, out, "Unable to attach to the AFI on slot id %d", slot_id);

    fail_on(rc, out, "Unable to write ROI !");

    printf("Checking PCI latency\n");
    uint32_t cur_cycle;
    int i;
    uint64_t addr = 0x1;
    init_params();
    for (i=0;i<N_TILES;i++) {
        pci_poke(i, ID_TSB, TSB_LOG_N_TILES        ,0 );
    }
    for (i=0;i<32;i++) {
        rc = 0;
        cur_cycle = 0;

        //addr = 60000 + i*1000;
        rc = fpga_pci_peek(pci_bar_handle, OCL_CUR_CYCLE_LSB, &cur_cycle);
        // fail_on(rc, out, "Unable to read cur cycle !");
        printf("[%d] addr:%8lx cycle: %u rc:%d \n", i,addr,  cur_cycle, rc);
        addr = addr * 2;
    }
    //uint32_t ts[5] = {57,30,99,55,125};
    rc = fpga_pci_poke(pci_bar_handle, OCL_TASK_ENQ_TTYPE, 0);
    rc = fpga_pci_poke(pci_bar_handle, OCL_TASK_ENQ_LOCALE, 0);
    for (i=0;i<32;i++){
        rc = fpga_pci_poke(pci_bar_handle, OCL_TASK_ENQ_LOCALE, i*6);
        rc = fpga_pci_poke(pci_bar_handle, OCL_TASK_ENQ, i*6);
        fail_on(rc, out, "Unable to write to the fpga !");
    }
   uint32_t task_unit_size = 0;
   pci_peek(0, ID_TASK_UNIT, TASK_UNIT_N_TASKS, &task_unit_size);
   printf("Task unit size %d\n", task_unit_size);

   pci_peek(0, ID_TASK_UNIT, TASK_UNIT_CAPACITY, &task_unit_size);
   printf("Task unit heap size %d\n", task_unit_size);

    uint32_t value = 0xefbeadde;
    for (i=0;i<10;i++){
        pci_peek(0, ID_OCL_SLAVE, OCL_TASK_ENQ, &value);
        printf("register: 0x%x\n", value);
        //pci_peek(1, ID_OCL_SLAVE, OCL_TASK_ENQ, &value);
        //printf("register: 0x%x\n", value);
    }
    /*
    for (i=0;i<5;i++){
        rc = fpga_pci_poke(pci_bar_handle, OCL_TASK_ENQ_LOCALE, i+5);
        rc = fpga_pci_poke(pci_bar_handle, OCL_TASK_ENQ, (ts[i]+4)<<16);
        fail_on(rc, out, "Unable to write to the fpga !");
    }
    for (i=0;i<7;i++){
        rc = fpga_pci_peek(pci_bar_handle, OCL_TASK_ENQ, &value);
        fail_on(rc, out, "Unable to read read from the fpga !");
        printf("register: 0x%x\n", value);
    }*/
   pci_peek(0, ID_TASK_UNIT, TASK_UNIT_CAPACITY, &task_unit_size);
   printf("Task unit size %d\n", task_unit_size);
/*
    printf("Checking PCI latency\n");
    uint32_t cur_cycle;
    for (i=0;i<10;i++) {
       rc = fpga_pci_peek(pci_bar_handle, ADDR_LAST_READ_LATENCY, &cur_cycle);
       //fail_on(rc, out, "Unable to read cur cycle !");
       printf("[%d] cycle: %d\n", i, cur_cycle);
    }
*/
out:
    /* clean up */
    if (pci_bar_handle >= 0) {
        rc = fpga_pci_detach(pci_bar_handle);
        if (rc) {
            printf("Failure while detaching from the fpga.\n");
        }
    }

    /* if there is an error code, exit with status 1 */
    return (rc != 0 ? 1 : 0);
}



/*
 * check if the corresponding AFI for hello_world is loaded
 */

int check_afi_ready(int slot_id) {
    struct fpga_mgmt_image_info info = {0};
    int rc;

    /* get local image description, contains status, vendor id, and device id. */
    rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
    fail_on(rc, out, "Unable to get AFI information from slot %d. Are you running as root?",slot_id);

    /* check to see if the slot is ready */
    if (info.status != FPGA_STATUS_LOADED) {
        rc = 1;
        fail_on(rc, out, "AFI in Slot %d is not in READY state !", slot_id);
    }

    printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n",
        info.spec.map[FPGA_APP_PF].vendor_id,
        info.spec.map[FPGA_APP_PF].device_id);

    /* confirm that the AFI that we expect is in fact loaded */
    if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id ||
        info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
        printf("AFI does not show expected PCI vendor id and device ID. If the AFI "
               "was just loaded, it might need a rescan. Rescanning now.\n");

        rc = fpga_pci_rescan_slot_app_pfs(slot_id);
        fail_on(rc, out, "Unable to update PF for slot %d",slot_id);
        /* get local image description, contains status, vendor id, and device id. */
        rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
        fail_on(rc, out, "Unable to get AFI information from slot %d",slot_id);

        printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n",
            info.spec.map[FPGA_APP_PF].vendor_id,
            info.spec.map[FPGA_APP_PF].device_id);

        /* confirm that the AFI that we expect is in fact loaded after rescan */
        if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id ||
             info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
            rc = 1;
            fail_on(rc, out, "The PCI vendor id and device of the loaded AFI are not "
                             "the expected values.");
        }
    }

    return rc;

out:
    return 1;
}
