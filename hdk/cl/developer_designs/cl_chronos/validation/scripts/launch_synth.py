
## Input month-day-index
## Launches the synth scripts (in ../synth/<date-index>/<app> all in parallel
## Once a synthesis job is complete, each app would append an entry to the file
## ../synth/<date-index>/agfi_list.txt

import sys
import os
if (len(sys.argv) == 1):
    print ("Usage: python launch_synth.py <year-month-date_index>")
    exit(0);

folder = sys.argv[1]
os.chdir("../synth")
dirs = os.listdir(os.getcwd())
print(dirs)
if folder not in dirs:
    print(folder + " not found in ../synth/. Exiting..")
    exit(0)

os.chdir(folder)
print(os.getcwd())

apps = os.listdir(os.getcwd())
print(apps)
cwd = os.getcwd();

for app in apps:
    print(app)
    os.chdir(os.path.join(cwd, app))
    print(os.getcwd())
    pid = os.fork() #Uncomment to run serially
    if (pid==0):
        cmd = "python run_synth.py > synth_out"
        os.system(cmd)


