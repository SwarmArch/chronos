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
# Return dict 
def getData(app, file):
    fres = open(file,'r')
    data = {}
    reading_core_breakdown = False
    reading_stall_breakdown = False
    n_cores = 0
    tot_cycles = 0
    non_spec = 0
    ret = {}
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
    for line in fres:
        if (line.find('cores each')>=0):
            sp = line.split()
            n_cores = int(sp[2])
            if (app == "astar"):
                n_cores -=2
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
        if (line.find('cum CQ')>=0):
            reading_stall_breakdown = False
        if (line.find('avg Tasks')>=0):
            sp = line.replace(':', ' ').split()
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

apps['maxflow'] = getData('maxflow', 'logs/maxflow_6t_37')
apps['sssp'] = getData('sssp', 'logs/sssp_8t_USA')
apps['astar'] = getData('astar', 'logs/astar_spec_4t_germany')
apps['color'] = getData('color', 'logs/color_4t_youtube')

print(apps)
mpl_fig = plt.figure()
ax = mpl_fig.add_subplot(111)
N = 4
app_list = ['maxflow', 'sssp', 'astar', 'color']
 
work = [ apps[app]['work'] + apps[app]['oh'] for app in app_list ]
mem_stall = [ apps[app]['mem_stall'] + apps[app]['other_core'] for app in app_list ] 
cq_full = [ apps[app]['cq_full'] + apps[app]['serialize'] for app in app_list ] 
enq_stall = [ apps[app]['enq_stall'] for app in app_list ] 
no_task = [ apps[app]['no_task'] for app in app_list ] 
other_core = [ apps[app]['other_core'] for app in app_list ] 
print(work)
menMeans = (20, 35, 30, 35, 27)
womenMeans = (25, 32, 34, 20, 25)
menStd = (2, 3, 4, 1, 2)
womenStd = (3, 5, 2, 3, 3)
ind = np.arange(N)    # the x locations for the groups
width = 0.45       # the width of the bars: can also be len(x) sequence

p1 = ax.bar(ind, work, width)
b = work

p2 = ax.bar(ind, mem_stall, width, color='green',
                     bottom=b)
b = [b[i] +mem_stall[i] for i in range(N)]
p3 = ax.bar(ind, cq_full, width, color='orange',
                     bottom=b)
b = [b[i] +cq_full[i] for i in range(N)]
p4 = ax.bar(ind, enq_stall, width, color='red',
                     bottom=b)
b = [b[i] +enq_stall[i] for i in range(N)]
p5 = ax.bar(ind, no_task, width, color='aqua',
                     bottom=b)
ax.set_ylabel('% Cycles', fontsize=18)
ax.set_xlabel('Applications', fontsize=18)
ax.set_title('PE Cycle breakdown',fontsize=18)

box = ax.get_position()

ax.set_xticks(ind + width/2.)
ax.set_ylim([0, 100])
ax.set_xticklabels(('maxflow', 'sssp', 'astar', 'color'))

mpl_fig.legend( [p1, p2, p3, p4, p5] ,
          labels = ['Work', 'Memory stalls', 
            "ROB Stalls", "Enqueue Stalls", "No Task"],
          loc = 'lower right',
          bbox_to_anchor=(0.88,0.80),
          ncol = 3
          )
ax.set_position([box.x0, box.y0, box.width, box.height*0.8])
ax.tick_params(axis='both', labelsize=18)

mpl_fig.savefig("breakdown.pdf")#, bbox_inches='tight')


exit(0)


fres = open('runtime.txt','r')
data = {}
for line in fres:
    s = line.split()
    if (len(s) <3): 
        continue
    app = s[0]
    l = s[1]
    c = int(s[2])
    time = float(s[3])
    if (app not in data):
        data[app] = {}
    if (l not in data[app]):
        data[app][l] = {}
    data[app][l][c] = time 
    print(s)

print(data)

speedups = {}
for app in data:
    speedups[app] = {}
    norm = data[app]['c'][1]
    print([app, norm])
    for l in data[app]:
        speedups[app][l] = [[],[]] 
        max_cores = max(data[app][l].keys())
        for c in sorted(data[app][l]):
            speedups[app][l][0].append(c/max_cores * 100)
            speedups[app][l][1].append( norm /  data[app][l][c])
print(speedups)
x = np.linspace(0, 2, 130)

f, axarr = plt.subplots(3,2)

color_baseline = 'red'
color_nonspec = 'blue'
color_spec = 'green'

app_plot_loc = {'des':[0,0], 
                'maxflow' : [0, 1],
                'sssp' : [1, 0],
                'astar' : [1,1],
                'color' : [2,0] }


l1 = axarr[1, 0].plot( speedups['sssp']['c'][0], speedups['sssp']['c'][1],
        color=color_baseline)[0]
l2 = axarr[1, 0].plot( speedups['sssp']['n'][0], speedups['sssp']['n'][1],
        color=color_nonspec)[0]
l3 = axarr[1, 0].plot( speedups['sssp']['s'][0], speedups['sssp']['s'][1],
        color=color_spec)[0]
axarr[0, 0].plot( speedups['des']['c'][0], speedups['des']['c'][1],
        color=color_baseline)[0]
axarr[0, 0].plot( speedups['des']['s'][0], speedups['des']['s'][1],
        color=color_spec)[0]
axarr[0, 1].plot( speedups['maxflow']['c'][0], speedups['maxflow']['c'][1],
        color=color_baseline)[0]
axarr[0, 1].plot( speedups['maxflow']['s'][0], speedups['maxflow']['s'][1],
        color=color_spec)[0]
axarr[1, 1].plot( speedups['astar']['c'][0], speedups['astar']['c'][1],
        color=color_baseline)[0]
axarr[1, 1].plot( speedups['astar']['s'][0], speedups['astar']['s'][1],
        color=color_spec)[0]
axarr[1, 1].plot( speedups['astar']['n'][0], speedups['astar']['n'][1],
        color=color_nonspec)[0]
axarr[2, 0].plot( speedups['color']['c'][0], speedups['color']['c'][1],
        color=color_baseline)[0]
axarr[2, 0].plot( speedups['color']['n'][0], speedups['color']['n'][1],
        color=color_nonspec)[0]
axarr[0,0].set(xlabel='% system used', ylabel='Speedup')
axarr[1,1].set(xlabel='% system used')
axarr[0,1].set(xlabel='% system used')
axarr[1,0].set(xlabel='% system used')
axarr[1,0].set(ylabel='Speedup')
axarr[2,0].set(xlabel='% system used', ylabel='Speedup')

for app in app_plot_loc:
    loc = app_plot_loc[app]
    axarr[loc[0], loc[1]].set_title(app)
f.legend( [l1, l2, l3] ,
          labels = ['Baseline CPU', 'Chronos Non-Speculative', 
            'Chronos Speculative'],
          loc = 'lower right',
          bbox_to_anchor=(0.88,0.09),
          title = "Legend"
          )
axarr[2,1].axis('off')
f.set_size_inches(7.5,8)
f.subplots_adjust(hspace=0.5, wspace=0.4)

#plt.legend()
#plt.show()

f.savefig("foo.pdf", bbox_inches='tight')

