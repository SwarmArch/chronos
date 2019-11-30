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

file_list = listdir(".")
for f in file_list:
    if not f.endswith(".result"):
        continue
    print(f)
    s = f.split("_")
