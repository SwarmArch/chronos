import sys, os
if len(sys.argv) < 2:
    print("Usage set_app.py app")
    exit(0)
app = sys.argv[1]

cmd1 = "cp ../../design/apps/%s/config.vh ../../design/app_config.vh" % app
cmd2 = "cp %s_config.sv ../../design/config.sv" % app

print(cmd1)
print(cmd2)

os.system(cmd1)
os.system(cmd2)
