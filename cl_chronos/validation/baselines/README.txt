Note: All baseline experiments were run on the AWS m4.10xlarge instance, with
the Amazon Linux AMI 2018.03.0. 
The authors are happy to provide the reviewers with an access to this instance
if desired. Please contact (maleen@mit.edu) 

All code for baselines are hosted on the shared s3 bucket, "chronos_baselines"
Run fetch_baselines.py to download these. 

Once downloaded, the S3 bucket contains several folders
Galois-2.4/: Contains the source code for sssp, astar and maxflow applications
    in Galois-2.4/lonestar/<sssp/astar/preflowpush> respectively
Galois-2.1/: Contains source code for des in Galois-2.1/apps/des. 
    (DES is from an older version of Galois beacuse DES is deprecated in 2.4)
color      : Contains source code for baseline graph coloring.
binaries/: Precompiled binaries for the four applications. 
inputs/  : Inputs for four applications
run_experiments.py : Runs the binaries with the inputs for all applications at
    at various thread counts and writes the runtime to baseline_runtime.txt
baseline_runtime.txt : The result of our experiments. This file is used as an
    input to the scripts/plot.py to generate Figure 10 in the paper

    

