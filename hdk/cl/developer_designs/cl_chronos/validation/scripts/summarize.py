## Input folder name in validation/runs/
## output chronos_runtimes.txt

## Reads all the text files to get runtimes,
## averages them and writes to a text file


import os
import sys
import datetime
from os import listdir

def run_cmd(cmd):
    print(cmd)
    os.system(cmd)

if len(sys.argv)<2:
    print("Usage: python summarize.py results_directory")
    exit(0)

## Save this before we go jumping around
scripts_dir = os.getcwd()

## Read agfi-list
result_dir = sys.argv[1]

os.chdir("../runs/"+result_dir)
print(os.getcwd())

# indexed by [app, n_tiles, n_threads]
cum_time = {}
n_instances = {}

file_list = listdir(".")
for f in file_list:
    if not f.endswith(".result"):
        continue
    print(f)
    s = f.split("_")
    app = s[0];
    n_tiles = int(s[4])
    n_threads = int(s[6])
    index = (app, n_tiles, n_threads)
    res_file = open(f,"r")
    for line in res_file:
        if line.startswith("FPGA cycles"):
            time_ms = float(line.split()[3].strip("("))
            print([index ,time_ms])
            if (index not in cum_time.keys()):
                cum_time[index] = 0
                n_instances[index] = 0
            cum_time[index] += time_ms
            n_instances[index] += 1

os.chdir(scripts_dir)
fout = open("chronos_runtimes.txt","w")
for index in sorted(cum_time.keys()):
    avg_time = cum_time[index] / n_instances[index]
    print([index, avg_time])
    fout.write(index[0] +" "+ str(index[1]) +" "+ str(index[2]) +" " +
            str(avg_time) +"\n" )

