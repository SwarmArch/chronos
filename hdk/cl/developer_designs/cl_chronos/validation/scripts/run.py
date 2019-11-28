## Input
## 1. agfi_list.txt, 
## 2. experiments.txt where each line is [app-name, app-tag, n_tiles, n_threads] 

## Runs the specified experiments. The output of each will be placed in
## validation/runs/<date>/app_tiles_threads.txt

import os
import sys
import datetime
from os import listdir

def run_cmd(cmd):
    print(cmd)
    os.system(cmd)

if len(sys.argv)<2:
    print("Usage: python run.py agfi_list.txt")
    exit(0)

## Save this before we go jumping around
scripts_dir = os.getcwd()

## Read agfi-list
fagfi = open(sys.argv[1], "r")
agfi_list = {} ## indexed by agfi-tag
inputs_list = {}
for line in fagfi:
    s = line.split();
    agfi_list[s[0]] = s[1]

print(agfi_list)

downloaded_inputs = listdir("../inputs")
AWS_PATH = "~/.local/bin/aws"
#AWS_PATH = "aws"

## Read experiments

## The inputs are locates in a public S3 bucket. (set below)
## The experiments.txt file specifies the 
## 1. This public S3 bucket
## 2. The input file names for each application
## 3. The experiments to run with these inputs 
#   Where each experiment is a tuple [app, agfi-tag, n_tiles, n_threads]
S3_BUCKET = "chronos_inputs"
fexp = open("experiments.txt", "r")
for line in fexp:
    if line.startswith("s3_bucket"):
        S3_BUCKET = line.split()[1]
        print(S3_BUCKET)
    if line.startswith("input"):
        s = line.split()
        app = s[1]
        s3_loc = s[2]
        file_name = s[2].split("/")[-1]
        inputs_list[app] = file_name
        if file_name not in downloaded_inputs:
            cmd = AWS_PATH + " s3 cp s3://" + S3_BUCKET + "/"+s[2] +" ../inputs/"
            run_cmd(cmd)

print(inputs_list)

## Locate runtime (and compile if necessary)
if "test_swarm" not in listdir("../../software/runtime"):
    os.chdir("../../software/runtime")
    os.system("make")
    os.chdir(scripts_dir)

if "test_swarm" not in listdir("../../software/runtime"):
    print("ERROR: Runtime cannot be compiled. Please investigate manually....")
    exit(0)

exit(0)

d = datetime.datetime.today()
index = 0
runs = listdir("../runs")
while(True):
    dirname = str(d.year) + "-" + str(d.month) + "-" + str(d.day) + "_" +  str(index)
    if dirname not in runs:
        print("creating directory "+dirname)
        os.mkdir("../runs/" + dirname)
        os.chdir("../runs/" + dirname)
        print(os.getcwd())
        runs_dir = os.getcwd()
        break
    index = index+1


## Runs the specified experiments and save the output to ...




