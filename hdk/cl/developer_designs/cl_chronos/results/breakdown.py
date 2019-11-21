import matplotlib.pyplot as plt
import numpy as np

maxflow_stall_states = [2, 7, 9, 13, 16, 19, 22, 24, 26, 38, 
        40, 47, 53, 55, 57, 59, 61]
maxflow_enq_states = [5, 14, 17, 28, 36, 45, 62]

sssp_stall_states = [2, 4, 6, 8, 10, 12 , 14]
sssp_enq_states = [13]

color_stall_states = [7, 9, 11, 14, 18, 21, 24, 26, 29]
color_enq_states = [4, 5, 16, 22, 27, 32]
astar_stall_states = [2, 4, 6, 8, 10, 13, 15]
astar_enq_states = [16]
des_stall_states = [2, 4, 6, 8, 11, 13, 14]
des_enq_states = []
# Return dict 
def getData(app, file):
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
        if (line.find('tiles') >=0):
            sp = line.split()
            n_tiles = int(sp[0])
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
            cq_full = int(sp[3])
            no_task = int(sp[-1])
        if (line.find('STAT_N_DEQ_TASK')>=0):
            sp = line.split()
            print(sp)
            n_deq = int(sp[-1])
        if (line.find('STAT_N_ABORT_TASK')>=0):
            sp = line.split()
            n_aborts = int(sp[-1])

        if (line.find('avg Tasks')>=0):
            sp = line.replace(':', ' ').split()
            ret['avgTasks'] = float(sp[2]) * n_tiles
            ret['heapUtil'] = float(sp[4]) * n_tiles
            print(sp)


    ret['cq_full'] = cq_full * 100 / tot_cycles 
    ret['no_task'] = no_task * 100 / tot_cycles 
    ret['work'] = 100 - ret['cq_full'] - ret['no_task'] 

    ret['commit_frac'] = 1-(n_aborts/n_deq);
    print(app)
    print(ret)

    return ret

def getDataNonspec(app, file, baselineTasks):
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
        if (line.find('tiles') >=0):
            sp = line.split()
            n_tiles = int(sp[0])
        if (line.find('FPGA cycles') >=0):
            sp = line.split()
            tot_cycles = int(sp[2])
            print(['cycles' ,tot_cycles])
        if (line.find('Non spec') >=0):
            sp = line.split()
            non_spec = int(sp[2])
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
            n_deq += int(sp[-1])
            tiles_read += 1
        if (line.find('ro read stall')>=0):
            sp = line.split()
            serializer_full = int(sp[-1])
    
    work_cycles = n_deq * 2 / tiles_read + serializer_full;
    ret['cq_full'] = 0
    ret['no_task'] = (tot_cycles - work_cycles)  * 100 / tot_cycles 
    ret['work'] = 100 - ret['no_task'] 

    ret['commit_frac'] = baselineTasks/n_deq;
    print(app)
    print(ret)

    return ret
apps = {}

apps['des'] = getData('des', 'asplos20/des/des_8_16')
apps['maxflow'] = getData('maxflow', 'asplos20/maxflow/maxflow_8_16')
#apps['sssp'] = getData('sssp', 'asplos20/sssp-spec/sssp_8_16')
apps['sssp'] = getDataNonspec('sssp',
        'asplos20/sssp-nonspec/breakdown_log_5000', 58333344)
#apps['astar'] = getData('astar', 'asplos20/astar-spec/astar_6_16')
apps['astar'] = getDataNonspec('astar',
        'asplos20/astar-nonspec/breakdown_log_900',3347700)
#apps['color'] = getData('color', 'logs/color_4t_youtube')

plot_commit_abort = True

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

if (plot_commit_abort) : 

    p1 = ax.bar(ind, commit, width, color=[0.05,0.32,0.05])
    b = commit;
    p2 = ax.bar(ind, abort, width, color='red', bottom=b)
    b = [b[i] +abort[i] for i in range(N)]
else :
    p1 = ax.bar(ind, work, width)
    b = work

    p2 = ax.bar(ind, mem_stall, width, color='green',
                         bottom=b)
    b = [b[i] +mem_stall[i] for i in range(N)]
#p3 = ax.bar(ind, enq_stall, width, color='purple',
#                     bottom=b)
#b = [b[i] +enq_stall[i] for i in range(N)]
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
            'Memory stalls' if not plot_commit_abort else 'Aborted/\nUselessed', 
            'Work' if not plot_commit_abort else 'Committed', 
            ],
          loc = 'lower right',
          bbox_to_anchor=(0.83,0.40),
          ncol = 1,
          fontsize = 22
          )
ax.set_position([box.x0, box.y0, box.width, box.height*0.8])
ax.tick_params(axis='both', labelsize=23)
#plt.gcf().subplots_adjust(top=0.75)
plt.gcf().subplots_adjust(left=0.15)
plt.gcf().subplots_adjust(bottom=0.15)
plt.gcf().subplots_adjust(right=0.55)

if (plot_commit_abort):
    mpl_fig.savefig("commit.pdf")#, bbox_inches='tight')
else:
    mpl_fig.savefig("cycle_break.pdf")#, bbox_inches='tight')

#### Taks Q Util

tq_util = [ apps[app]['avgTasks'] for app in app_list]
cq_util = [ apps[app]['cqsize'] for app in app_list]

print(cq_util)

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
ax.set_ylim([0, 2000])
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
plt.text(3.17 , 2000, '%d' % tq_util[3],
    ha='center', va='bottom', fontsize=28)
plt.text(2.17 , 2000, '%d' % tq_util[2],
    ha='center', va='bottom', fontsize=28)
#for rect in p1 + p2:
#    height = rect.get_height()

#    plt.text(rect.get_x() + rect.get_width()/2.0, height, '%d' % int(height),
#        ha='center', va='bottom')

mpl_fig.tight_layout()
plt.gcf().subplots_adjust(top=0.80)

mpl_fig.savefig("queue.pdf")#, bbox_inches='tight')



#### Specialized vs Risc-V


mpl_fig = plt.figure()
mpl_fig, ax = plt.subplots(figsize=(5,5))
#ax = mpl_fig.add_subplot(111)

custom = [ 1, 1, 1, 1] 

riscv_runtime = [90.3 * 344/662, 259, 1341, 307]
app_runtime = [ 22.0, 66.4, 495, 129] # 4-tiles 
app_runtime = [ 4.87, 18.1, 96.8, 75] # best tiles 

speedup = [riscv_runtime[i] / app_runtime[i] for i in range(4)]

ind = np.arange(4)    # the x locations for the groups
p1 = ax.bar(ind, speedup, width=0.7, color='mediumseagreen') 
#p2 = ax.bar([i + 0.2 for i in ind], riscv, width=0.2, color='r') 
#ax.bar(x1, z, width=0.2, color='b') 
ax.set_xticks(ind + width/2.)
ax.set_yticks([0, 2, 4 ,6, 8 ,10, 12, 14, 16])
#ax.set_ylim([0, 1, 4.5])
ax.set_xticklabels(('des', 'maxflow', ' sssp', 'color'))
#mpl_fig.legend( [p1, p2] ,
#          labels = [
#            'Application specific PEs',
#            'RISC-V Soft cores'
#            ],
#          loc = 'lower right',
#          bbox_to_anchor=(0.68,0.75),
#          ncol = 1
#          )
ax.set_ylabel('Speedup' , fontsize=21)
ax.set_xlabel('Applications', fontsize=21)
ax.tick_params(axis='both', labelsize=21)
mpl_fig.tight_layout()
mpl_fig.savefig("riscv.pdf")#, bbox_inches='tight')

exit(0)

