
# This script reads apps.txt and generates the synthesis scripts for each
# application

import os
from os import listdir
import datetime

runs = listdir("../synth")
print(runs)

fapps = open("apps.txt", "r")

d = datetime.datetime.today()
index = 0
scripts_dir = os.getcwd()
while(True):
    dirname = str(d.year) + "-" + str(d.month) + "-" + str(d.day) + "_" +  str(index)
    if dirname not in runs:
        print("creating directory "+dirname)
        os.mkdir("../synth/" + dirname)
        os.chdir("../synth/" + dirname)
        print(os.getcwd())
        synth_dir = os.getcwd()
        break
    index = index+1

for line in fapps:
    print(line)
    os.chdir(synth_dir)
    words = line.split()
    config = words[-1];
    print("making directory "+config)
    os.mkdir(config)
    cmd = "cp -r ../../../design " + config
    os.system(cmd)
    os.mkdir(config +"/build")
    cmd = os.path.join(scripts_dir, "build_scripts")
    cmd = "cp -r " + cmd +"/* " +config+ "/build/" 
    os.system(cmd)
    print(cmd)

