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

best_result_file = {}
best_result_cycles = {}

file_list = listdir(".")
for f in file_list:
    if not f.endswith(".result"):
        continue
    #if (f.find("rate_ctrl") >=0):
    #    continue
    #if (f.find("riscv") >=0):
    #    continue
    print(f)
    s = f.split("_")
    app = s[0];
    riscv = f.startswith("riscv")
    throttle = (f.find("rate_ctrl") > 0)
    if riscv:
        if throttle:
            n_tiles = int(s[7])
            n_threads = int(s[9])
            app = "throttle-"+s[5]
        else: 
            n_tiles = int(s[5])
            n_threads = int(s[7])
            app += "-"+s[3]
    else:
        n_tiles = int(s[4])
        n_threads = int(s[6])
        if (f.find("astar_r") >=0):
            app += "-r"
        if (f.find("sssp_r") >=0):
            app += "-r"
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
            if app not in best_result_file.keys():
                best_result_file[app] = ''
                best_result_cycles[app] = 1e10;
            if best_result_cycles[app] > time_ms:
                best_result_file[app] = f
                best_result_cycles[app] = time_ms

os.chdir(scripts_dir)
fout = open("chronos_runtimes.txt","w")
for index in sorted(cum_time.keys()):
    avg_time = cum_time[index] / n_instances[index]
    print([index, avg_time])
    fout.write(index[0] +" "+ str(index[1]) +" "+ str(index[2]) +" " +
            str(avg_time) +"\n" )


## Cycle breakdown and Queue utilization plots

def getData(file): # For apps with rollback
    fres = open(file,'r')
    n_tiles = 0
    n_cores = 0
    tot_cycles = 0
    non_spec = 0
    n_deq = 0
    n_aborts = 0
    cq_full = 0
    no_task = 0
    ret = {}
    ret['commit_frac'] = 1.0
    for line in fres:
        if (line.find('n_tiles') >=0):
            sp = line.split()
            print(sp)
            n_tiles = int(sp[2])
        if (line.find('FPGA cycles') >=0):
            sp = line.split()
            tot_cycles = int(sp[2])
            print(['cycles' ,tot_cycles])
        if (line.find('Non spec') >=0):
            sp = line.split()
            non_spec = int(sp[2])
        if (line.find('CQ occ')>=0):
            sp = line.replace(',',' ').split()
            print(sp)
            ret['cqsize'] = float(sp[-1]) *n_tiles
        if (line.find('stall cycles')>=0):
            sp = line.replace(':',' ').replace(',',' ').split()
            print(sp)
            cq_full = float(sp[3])
            no_task = float(sp[-1])
        if (line.find('STAT_N_DEQ_TASK')>=0):
            sp = line.split()
            print(sp)
            n_deq = float(sp[-1])
        if (line.find('STAT_N_ABORT_TASK')>=0):
            sp = line.split()
            n_aborts = float(sp[-1])

        if (line.find('avg Tasks')>=0):
            sp = line.replace(':', ' ').split()
            ret['avgTasks'] = float(sp[2]) * n_tiles
            ret['heapUtil'] = float(sp[4]) * n_tiles
            print(sp)


    ret['cq_full'] = float(cq_full) * 100 / tot_cycles 
    ret['no_task'] = float(no_task) * 100 / tot_cycles 
    ret['work'] = 100 - ret['cq_full'] - ret['no_task'] 

    ret['commit_frac'] = 1-(n_aborts/n_deq);
    print(ret)

    return ret

def getDataNonspec(file, baselineTasks):
    fres = open(file,'r')
    data = {}
    n_tiles = 0
    tot_cycles = 0
    n_deq = 0
    tiles_read = 0
    ret = {}
    ret['commit_frac'] = 1.0
    ret['cqsize'] = 0
    work_cycles = 0;
    ret['avgTasks'] = 0
    serializer_full = 0
    for line in fres:
        if (line.find('n_tiles') >=0):
            sp = line.split()
            print(sp)
            n_tiles = int(sp[2])
        if (line.find('FPGA cycles') >=0):
            sp = line.split()
            tot_cycles = float(sp[2])
            print(['cycles' ,tot_cycles])
        if (line.find('Non spec') >=0):
            sp = line.split()
            non_spec = float(sp[2])
            if (non_spec != 1):
                exit(0)
        if (line.find('task_issued')>=0):
            sp = line.replace(':',' ').replace(',',' ').split()
            #work_cycles += int(sp[-1])
        if (line.find('task_not_taken')>=0):
            sp = line.replace(':',' ').replace(',',' ').split()
            #work_cycles += int(sp[-1])
            #work_cycles += int(sp[1])

        if (line.find('avg Tasks')>=0):
            sp = line.replace(':', ' ').split()
            ret['avgTasks'] += float(sp[2]) 
            print(sp)
        if (line.find('STAT_N_DEQ_TASK')>=0):
            sp = line.split()
            n_deq += float(sp[-1])
            tiles_read += 1
        if (line.find('ro read stall')>=0):
            sp = line.split()
            serializer_full = float(sp[-1])
    
    work_cycles = n_deq * 2 / tiles_read + serializer_full;
    ret['cq_full'] = 0
    ret['no_task'] = (tot_cycles - work_cycles)  * 100 / tot_cycles 
    ret['work'] = 100 - ret['no_task'] 

    ret['commit_frac'] = baselineTasks/n_deq;
    print(app)
    print(ret)

    return ret

print("Cycle breakdown plot")
os.chdir("../runs/"+result_dir)
print(best_result_file)
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

## http://phyletica.org/matplotlib-fonts/
matplotlib.rcParams['pdf.fonttype'] = 42
matplotlib.rcParams['ps.fonttype'] = 42

apps = {}
apps['des'] = getData( best_result_file['des'] )
apps['maxflow'] = getData( best_result_file['maxflow'] )
## The baselineTasks parameter for the non-rollback variant is obtained by
## manually inspecting the 1-tile 1-thread variants. TODO: automate
apps['sssp'] = getDataNonspec( best_result_file['sssp'] , 58333344)
apps['astar'] = getDataNonspec( best_result_file['astar'], 2686985)
apps['astar-r'] = getData( best_result_file['astar-r'])
apps['sssp-r'] = getData( best_result_file['sssp-r'])
#apps['astar'] = getDataNonspec( best_result_file['astar'], 3347700)

os.chdir(scripts_dir)

mpl_fig, ax = plt.subplots(figsize=(11,6))
#ax = mpl_fig.add_subplot(111, figsize=(5,10))
N = 4
app_list = ['des' ,'maxflow', 'sssp', 'astar', ]

work = [ apps[app]['work']  for app in app_list ]
cq_full = [ apps[app]['cq_full']  for app in app_list ] 
no_task = [ apps[app]['no_task'] for app in app_list ] 


print(['cq_full', cq_full])

cfrac = [ apps[app]['commit_frac'] for app in app_list]

commit = [ (work[i] ) * cfrac[i] for i in range(N)]
abort = [ (work[i] ) * (1-cfrac[i]) for i in range(N)]
print(['work', work])

print(['abort/(abort+commit)', sum(abort)/(sum(commit) + sum(abort))  ])
print(['abort/all', sum(abort)/N  ])

print(abort)
ind = np.arange(N)    # the x locations for the groups,
#ind = [i*0.6 for i in ind]
print(ind)
width = 0.65       # the width of the bars: can also be len(x) sequence


p1 = ax.bar(ind, commit, width, color=[0.05,0.32,0.05])
b = commit;
p2 = ax.bar(ind, abort, width, color='red', bottom=b)
b = [b[i] +abort[i] for i in range(N)]
p4 = ax.bar(ind, cq_full, width, color=[0.99,0.5,0.0],#'orange',
                     bottom=b)
b = [b[i] +cq_full[i] for i in range(N)]
p5 = ax.bar(ind, no_task, width, color=[224/255,224/255,224/255],#,grey',
                     bottom=b)
ax.set_ylabel('PE Cycles (%)', fontsize=23)
ax.set_xlabel('Applications', fontsize=23)
#ax.set_title('PE Cycle breakdown',fontsize=18)

box = ax.get_position()

ax.set_xticks(ind + width/2.)
ax.set_ylim([0, 100])
ax.set_xticklabels(('des', 'maxflow', 'sssp', 'astar', ))

mpl_fig.legend( [p5, p4, p2, p1 ] ,
          labels = [
            "No Task",
            "Full CQ", 
            #"Enq/Deq\nStalls",
            'Aborted/\nUseless', 
            'Committed', 
            ],
          loc = 'lower right',
          bbox_to_anchor=(0.83,0.40),
          ncol = 1,
          frameon=False,
          fontsize = 22
          )
ax.set_position([box.x0, box.y0, box.width, box.height*0.8])
ax.tick_params(axis='both', labelsize=23)
#plt.gcf().subplots_adjust(top=0.75)
plt.gcf().subplots_adjust(left=0.15)
plt.gcf().subplots_adjust(bottom=0.15)
plt.gcf().subplots_adjust(right=0.55)
#plt.gcf().subplots_adjust(top=0.70)

mpl_fig.savefig("cycle_break.pdf")#, bbox_inches='tight')

#### Taks Q Util

app_list_cq = ['des' ,'maxflow', 'sssp-r', 'astar-r', ]
tq_util = [ apps[app]['avgTasks'] for app in app_list]
cq_util = [ apps[app]['cqsize'] for app in app_list_cq]

print(cq_util)
print("TQ util")
print(tq_util)

ax1color = 'cornflowerblue'
ax2color = 'navy'
#mpl_fig = plt.figure()
mpl_fig, ax = plt.subplots(figsize=(9.5,6))
#ax = mpl_fig.add_subplot(111)
p1 = ax.bar(ind, tq_util, width=0.4, color=ax1color) 
#ax2 = ax.twinx()
p2 = ax.bar([i + 0.4 for i in ind], cq_util, width=0.4, color=ax2color) 
#ax.bar(x1, z, width=0.2, color='b') 
ax.set_xticks(ind + width/2.)
ax.set_ylim([0, 2080])
#ax2.set_ylim([0, 1280])
ax.set_xticklabels(('des', 'maxflow', 'sssp', 'astar'))
mpl_fig.legend( [p1, p2] ,
          labels = [
            'Avg. TQ Utilization',
            'Avg. CQ Utilization'
            ],
          loc = 'lower right',
          bbox_to_anchor=(1.01,0.845),
          ncol = 2,
          fontsize = 26,
          frameon=False,
          columnspacing=1.
          )
ax.set_ylabel('Entries Used', fontsize=28)#, color=ax1color)
#ax2.set_ylabel('TRB Entries', fontsize=22, color=ax2color)
ax.set_xlabel('Applications', fontsize=28)
ax.tick_params(axis='both', labelsize=28)
ax.tick_params(axis='y')#, labelcolor=ax1color)
#ax2.tick_params(axis='both', labelsize=22)
#ax2.tick_params(axis='y', labelcolor=ax2color)
plt.text(3.17 , 2080, '%d' % tq_util[3],
    ha='center', va='bottom', fontsize=28)
plt.text(2.17 , 2080, '%d' % tq_util[2],
    ha='center', va='bottom', fontsize=28)
#for rect in p1 + p2:
#    height = rect.get_height()

#    plt.text(rect.get_x() + rect.get_width()/2.0, height, '%d' % int(height),
#        ha='center', va='bottom')

mpl_fig.tight_layout()
plt.gcf().subplots_adjust(top=0.75)

mpl_fig.savefig("queue.pdf")#, bbox_inches='tight')

os.chdir(scripts_dir)

exit(0)

