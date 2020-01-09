# Validation of results in the paper is done by running five separate python
# scripts one after the other. This script specifies this sequence. 

# However, running the entire script might take about a week (mostly to run the
# FPGA build flow), hence it is recommended that the scripts are run
# individually in the specified order

# To facilitate quick evaluation, we also provide precompiled images. 
# To use them, run this script with the --precompiled option. 

import os
import sys
def run_cmd(cmd):
    print(cmd)
    os.system(cmd)

def get_latest_dir(dir_name):
    ## Returns the name of the latest subdirectory in dir_name
    dirs = os.listdir(dir_name)
    dirs = sorted([d for d in dirs if d.startswith("20")])
    return dirs[-1]

Use_Precompiled_Images = False
if len(sys.argv)>1:
    if sys.argv[1] == '--precompiled':
        Use_Precompiled_Images = True


if not Use_Precompiled_Images:
# Step 1: Create Synthesis scripts for each application (gen_synth.py) 
# This script reads apps.txt and generates the synthesis scripts for each
# application. These synthesis scripts are placed in
# validation/synth/<date-index>
    run_cmd("python gen_synth.py")


# Step 2: Launch these synthesis scripts for each app sequentially.
# The output of this is the agfi_list.txt specifying AGFI-ID for each FPGA image
    syn_dir = get_latest_dir("../synth/")
    run_cmd("python launch_synth.py " + syn_dir)

# Step 3: Runs a set of experiments (experiments.txt) on the generated FPGA images and records
# their output ("../runs/<date-index>")
    run_cmd("python run.py ../synth/" +  syn_dir + "/agfi_list.txt")
else: 
    run_cmd("aws s3 cp s3://chronos-images/agfi_list.txt ." )
    run_cmd("python run.py agfi_list.txt")
    

## Following steps require matplotlib
## Please run 'sudo yum install python-matplotlib' if necessary


# Step 4: Averages the result from experiments. Writes output to
# chronos_runtimes.txt
# Also generates the cycle breakdown and queue utilization plots.
run_dir = get_latest_dir("../runs/")
run_cmd("python summarize.py " + run_dir)


# Step 5: Generates the speedup plot in Figure 10, 11 and 14
run_cmd("python plot.py chronos_runtimes.txt ../baselines/runtime_ref.txt") 
