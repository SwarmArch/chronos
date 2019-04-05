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
    data = {}
    reading_core_breakdown = False
    reading_stall_breakdown = False
    n_tiles = 0
    n_cores = 0
    tot_cycles = 0
    non_spec = 0
    ret = {}
    ret['commit_frac'] = 1.0
    if (app == 'maxflow'):
        stall_states = maxflow_stall_states;
        enq_states = maxflow_enq_states
    if (app == 'sssp') :
        stall_states = sssp_stall_states;
        enq_states = sssp_enq_states;
    if (app == 'color') :
        stall_states = color_stall_states;
        enq_states = color_enq_states;
    if (app == 'astar') :
        stall_states = astar_stall_states;
        enq_states = astar_enq_states;
    if (app == 'des') :
        stall_states = des_stall_states;
        enq_states = des_enq_states;
    for line in fres:
        if (line.find('cores each')>=0):
            sp = line.split()
            n_cores = int(sp[2])
            if (app == "astar"):
                n_cores -=2
            if (app == "des"):
                n_cores -=1
            state_stats = [ [0 for x in range(128)] for y in range(n_cores) ]
            stall_stats = [ [0 for x in range(7)] for y in range(n_cores) ]
            wrapper_stats = [ [0 for x in range(8)] for y in range(n_cores) ]
            print(n_cores)
        if (line.find('FPGA cycles') >=0):
            sp = line.split()
            tot_cycles = int(sp[2])
            print(tot_cycles)
        if (line.find('Non spec') >=0):
            sp = line.split()
            non_spec = int(sp[2])
            print(non_spec)
        if (line.find('core state stats')>=0):
            reading_core_breakdown = True
        if (line.find('Tile 0 stats')>=0):
            reading_core_breakdown = False
        if (line.find('num_enq')>=0):
            reading_stall_breakdown = True
            continue;
        if (line.find('CQ occ')>=0):
            sp = line.replace(',',' ').split()
            print(sp)
            ret['cqsize'] = float(sp[-1]) *n_tiles
        if (line.find('cum CQ')>=0):
            reading_stall_breakdown = False
        if (line.find('cores each')>=0):
            n_tiles = int(line.split()[0])
        if (line.find('avg Tasks')>=0):
            sp = line.replace(':', ' ').split()
            ret['avgTasks'] = float(sp[2]) * n_tiles
            ret['heapUtil'] = float(sp[4]) * n_tiles
            print(sp)
        if (line.find('cum commit')>=0):
            sp = line.replace(':', ' ').split()
            ret['commit_frac'] =  int(sp[2])/(int(sp[2])+int(sp[4]))
            #if (app=='des'):
                # Temp until I get des 8t cycle breakdowns 
            #    ret['commit_frac'] = (13.6/(13.6+1.2))
            print(sp)
        if (reading_core_breakdown):
            sp = line.split()
            if (sp[0][:-1].isdigit()):
                state = int(sp[0][:-1])
                for i in range(n_cores):
                    state_stats[i][state] = int(sp[i+1]) 
            if (sp[0][0] == 'W') :
                state = int(sp[0][1])
                for i in range(n_cores):
                    wrapper_stats[i][state] = int(sp[i+1]) 
        if (reading_stall_breakdown):
            sp = line.split()
            if (sp[0][:-1].isdigit()):
                core = int(sp[0][:-1]) -1
                if (core >= n_cores):
                    continue
                for i in range(7):
                    stall_stats[core][i] = int(sp[i+1])


    work_cycles = [0 for x in range(n_cores)]
    mem_stalls = [0 for x in range(n_cores)]
    task_oh = [0 for x in range(n_cores)]
    cq_full = [0 for x in range(n_cores)]
    serialize_stall = [0 for x in range(n_cores)]
    no_task = [0 for x in range(n_cores)]
    other_core = [0 for x in range(n_cores)]
    num_enq = [stall_stats[i][0] for i in range(n_cores)]
    num_deq = [stall_stats[i][1] for i in range(n_cores)]
    enq_stalls = [0 for x in range(n_cores)]

    for i in range(n_cores):
        for s in stall_states:
            mem_stalls[i] += state_stats[i][s]
        for s in enq_states:
            enq_stalls[i] += state_stats[i][s]
        enq_stalls[i] -= num_enq[i]
        sum_all = 0
        for s in range(64):
            sum_all += state_stats[i][s]

        no_task_cycles = state_stats[i][0] - (sum_all - tot_cycles)
        work_cycles[i] = tot_cycles - mem_stalls[i] - enq_stalls[i] - no_task_cycles

        task_oh[i] = wrapper_stats[i][1]*3   + wrapper_stats[i][2] + ( 
            + wrapper_stats[i][5] + wrapper_stats[i][4])
            

        mem_stalls[i] += wrapper_stats[i][6] + wrapper_stats[i][7]
        cq_full[i] = stall_stats[i][3]
        serialize_stall[i] = stall_stats[i][6]
        no_task[i] = stall_stats[i][4]
        other_core[i] = stall_stats[i][2]

        s = work_cycles[i] + mem_stalls[i] + task_oh[i] + cq_full[i] + (
                serialize_stall[i] + no_task[i] + other_core[i] + enq_stalls[i])
        #print(work_cycles[i])
        #print(work_cycles[i])
        #print(task_oh[i])
        #print(mem_stalls[i])
        #print(enq_stalls[i])
        #print(task_oh[i])
        print([s, tot_cycles-s])
        #print("\n")
    
    total = sum(work_cycles) + sum(task_oh) + sum(mem_stalls) + sum(enq_stalls)
    total += sum(cq_full) + sum(serialize_stall) + sum(no_task) +sum(other_core) 
    ret['work'] = sum(work_cycles) * 100 / total 
    ret['oh'] = sum(task_oh) * 100 / total
    ret['mem_stall'] = sum(mem_stalls) * 100 /total
    ret['enq_stall'] = sum(enq_stalls)*100 /total 
    ret['cq_full'] = sum(cq_full) * 100 /total
    ret['serialize'] = sum(serialize_stall) * 100 /total
    ret['no_task'] = sum(no_task) * 100 /total
    ret['other_core'] = sum(other_core) * 100 /total


    return ret

apps = {}

apps['des'] = getData('des', 'logs/des_8t_ks_cq_6')
apps['maxflow'] = getData('maxflow', 'logs/maxflow_6t_37')
apps['sssp'] = getData('sssp', 'logs/sssp_8t_USA')
apps['astar'] = getData('astar', 'logs/astar_4t_germany')
#apps['color'] = getData('color', 'logs/color_4t_youtube')

plot_commit_abort = True

print(apps['des'])
mpl_fig, ax = plt.subplots(figsize=(11,6))
#ax = mpl_fig.add_subplot(111, figsize=(5,10))
N = 4
app_list = ['des' ,'maxflow', 'sssp', 'astar', ]

work = [ apps[app]['work'] + apps[app]['oh'] for app in app_list ]
mem_stall = [ apps[app]['mem_stall'] for app in app_list ] 
cq_full = [ apps[app]['cq_full'] + apps[app]['serialize'] for app in app_list ] 
enq_stall = [ apps[app]['enq_stall'] + apps[app]['other_core'] for app in app_list ] 
no_task = [ apps[app]['no_task'] for app in app_list ] 
other_core = [ apps[app]['other_core'] for app in app_list ] 

cfrac = [ apps[app]['commit_frac'] for app in app_list]

commit = [ (work[i] + mem_stall[i]) * cfrac[i] for i in range(N)]
abort = [ (work[i] + mem_stall[i]) * (1-cfrac[i]) for i in range(N)]

print(['abort fraction', sum(abort)/N])

print(abort)
ind = np.arange(N)    # the x locations for the groups,
#ind = [i*0.6 for i in ind]
print(ind)
width = 0.65       # the width of the bars: can also be len(x) sequence

if (plot_commit_abort) : 

    p1 = ax.bar(ind, commit, width)
    b = commit;
    p2 = ax.bar(ind, abort, width, color='red', bottom=b)
    b = [b[i] +abort[i] for i in range(N)]
else :
    p1 = ax.bar(ind, work, width)
    b = work

    p2 = ax.bar(ind, mem_stall, width, color='green',
                         bottom=b)
    b = [b[i] +mem_stall[i] for i in range(N)]
p3 = ax.bar(ind, enq_stall, width, color='purple',
                     bottom=b)
b = [b[i] +enq_stall[i] for i in range(N)]
p4 = ax.bar(ind, cq_full, width, color='orange',
                     bottom=b)
b = [b[i] +cq_full[i] for i in range(N)]
p5 = ax.bar(ind, no_task, width, color='grey',
                     bottom=b)
ax.set_ylabel('PE Cycles (%)', fontsize=22)
ax.set_xlabel('Applications', fontsize=22)
#ax.set_title('PE Cycle breakdown',fontsize=18)

box = ax.get_position()

ax.set_xticks(ind + width/2.)
ax.set_ylim([0, 100])
ax.set_xticklabels(('des', 'maxflow', 'sssp', 'astar', ))

mpl_fig.legend( [p5, p4, p3, p2, p1 ] ,
          labels = [
            "No Task",
            "Full CQ", 
            "Enq/Deq\nStalls",
            'Memory stalls' if not plot_commit_abort else 'Aborted', 
            'Work' if not plot_commit_abort else 'Committed', 
            ],
          loc = 'lower right',
          bbox_to_anchor=(0.82,0.40),
          ncol = 1,
          fontsize = 20
          )
ax.set_position([box.x0, box.y0, box.width, box.height*0.8])
ax.tick_params(axis='both', labelsize=22)
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
ax.set_ylim([0, 1650])
#ax2.set_ylim([0, 1280])
ax.set_xticklabels(('des', 'maxflow', 'sssp', 'astar'))
mpl_fig.legend( [p1, p2] ,
          labels = [
            'Avg. TQ Utilization',
            'Avg. CQ Utilization'
            ],
          loc = 'lower right',
          bbox_to_anchor=(0.57,0.745),
          ncol = 1,
          fontsize = 20
          )
ax.set_ylabel('Entries Used', fontsize=26)#, color=ax1color)
#ax2.set_ylabel('TRB Entries', fontsize=22, color=ax2color)
ax.set_xlabel('Applications', fontsize=26)
ax.tick_params(axis='both', labelsize=26)
ax.tick_params(axis='y')#, labelcolor=ax1color)
#ax2.tick_params(axis='both', labelsize=22)
#ax2.tick_params(axis='y', labelcolor=ax2color)
plt.text(3.17 , 1650, '%d' % tq_util[3],
    ha='center', va='bottom', fontsize=26)
plt.text(2.17 , 1650, '%d' % tq_util[2],
    ha='center', va='bottom', fontsize=26)
#for rect in p1 + p2:
#    height = rect.get_height()

#    plt.text(rect.get_x() + rect.get_width()/2.0, height, '%d' % int(height),
#        ha='center', va='bottom')

mpl_fig.tight_layout()
plt.gcf().subplots_adjust(top=0.93)

mpl_fig.savefig("queue.pdf")#, bbox_inches='tight')



#### Specialized vs Risc-V


mpl_fig = plt.figure()
mpl_fig, ax = plt.subplots(figsize=(5,5))
#ax = mpl_fig.add_subplot(111)

custom = [ 1, 1, 1, 1] 

riscv_runtime = [90.3, 259, 1341, 307]
app_runtime = [ 22.0, 66.4, 495, 129] 

speedup = [riscv_runtime[i] / app_runtime[i] for i in range(4)]

ind = np.arange(4)    # the x locations for the groups
p1 = ax.bar(ind, speedup, width=0.7, color='mediumseagreen') 
#p2 = ax.bar([i + 0.2 for i in ind], riscv, width=0.2, color='r') 
#ax.bar(x1, z, width=0.2, color='b') 
ax.set_xticks(ind + width/2.)
ax.set_yticks([0, 1, 2 ,3 ,4])
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
ax.set_ylabel('Speedup from custom cores', fontsize=18)
ax.set_xlabel('Applications', fontsize=20)
ax.tick_params(axis='both', labelsize=20)
mpl_fig.tight_layout()
mpl_fig.savefig("riscv.pdf")#, bbox_inches='tight')

exit(0)

