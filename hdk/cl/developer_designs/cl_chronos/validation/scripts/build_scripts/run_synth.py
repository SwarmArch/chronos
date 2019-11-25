# export CL_DIR=$(pwd)
# run build/script/aws_build_dcp_from_cl.sh in foreground
# run aws s3 cp
# run create fpga-image and write output to agfi.txt
# read agfi.txt and append to ../agfi_list.txt


## Need to be run from validation/synth/<date>/<app>/

#Set the location of aws executable, if running on AWS instances it is just "aws"
#AWS_PATH = "aws"
AWS_PATH = "~/.local/bin/aws"

S3_BUCKET = "maleen"
S3_KEY = "dcp/"
S3_PATH = "s3://" + S3_BUCKET + "/" + S3_KEY 



import os
def run_cmd(cmd):
    print(cmd)
    os.system(cmd)

cwd = os.getcwd()
app = cwd.split("/")[-1]

## Run synthesis
os.chdir("build/scripts")
cmd = "CL_DIR=" + cwd + " aws_build_dcp_from_cl.sh"
run_cmd(cmd)

## copy tar to aws s3
os.chdir(os.path.join(cwd, "build", "checkpoints", "to_aws"))
print(os.getcwd())
file_list = os.listdir(os.getcwd())
file_list = [f for f in file_list if f.find(".tar") >0] #filter tar files
print(file_list)
if len(file_list) == 0:
    print("tar file not found. Exiting...")
    exit(0)
## TODO: IF multiple tar files select the most recent one
tar_file = file_list[0]
cmd = AWS_PATH + " s3 cp " + tar_file +" " + S3_PATH + tar_file
run_cmd(cmd)

## Run create-fpga-image
cmd = AWS_PATH + " ec2 create-fpga-image --name " + app  
cmd += " --input-storage-location Bucket=" + S3_BUCKET
cmd += ",Key=" + S3_KEY+tar_file 
cmd += " --logs-storage-location Bucket="+S3_BUCKET
cmd += ",Key=logs/"+tar_file
cmd += " | tee agfi.txt"
run_cmd(cmd)

## Read agfi.txt and append to ../agfi_list.txt
f = open("agfi.txt", "r")
agfi = ""
afi = ""
for line in f:
    if (line.find("agfi-")>0):
        agfi = line.split(":")[1].split("\"")[1]
        print(agfi)
    if (line.find("afi-")>0):
        afi = line.split(":")[1].split("\"")[1]
        print(afi)
append_line = app +" "+agfi + " "+afi +"\n"
os.chdir(cwd)
f = open("../agfi_list.txt", "a+")
f.write(append_line)
f.close()
    
