import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

import sys

if (len(sys.argv)<3):
    print("Usage: python plot.py chronos_runtimes.txt baseline_runtimes.txt")
    exit(0)

fbaseline = open(sys.argv[2],'r')
data = {}
for line in fbaseline:
    s = line.split()
    if (len(s) <3): 
        continue
    app = s[0]
    l = 'c' # (C)pu baseline
    c = int(s[1])
    time = float(s[2])
    if (app not in data):
        data[app] = {}
    if (l not in data[app]):
        data[app][l] = {}
    data[app][l][c] = time 
    print(s)

fchronos = open(sys.argv[1],'r')
for line in fchronos:
    s = line.split()
    if (len(s) <3): 
        continue
    app = s[0]
    if app == "sssp" or app == "astar" or app == "color":
        l = 'n' # (N)o rollback
    else: 
        l = 's' # (S)peculative, aka. with rollback
    c = int(s[2]) * int(s[1])
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
    if (app.startswith("riscv")):
        continue
    speedups[app] = {}
    print(app)
    print(data[app])
    norm = data[app]['c'][1]
    print([app, norm])
    for l in data[app]:
        speedups[app][l] = [[],[]] 
        max_cores = max(data[app][l].keys())
        for c in sorted(data[app][l]):
            speedups[app][l][0].append(float(c)/max_cores * 100)
            speedups[app][l][1].append( norm /  data[app][l][c])
print("Printng Speedups")
print(speedups)
for app in data:
    if (app.startswith("riscv")):
        continue
    opt_cpu_cores = 1
    for c in data[app]['c']:
        if (data[app]['c'][c] < data[app]['c'][opt_cpu_cores]):
            opt_cpu_cores = c;
    cpu_self_relative = data[app]['c'][1] / data[app]['c'][opt_cpu_cores]
    print([app, 'cpu self-relative', cpu_self_relative])
    for l in data[app]:
        if (l=='c'):
            continue
        fpga_1task = (data[app]['c'][1] / data[app][l][1])
        #continue
        fpga_1tile = (data[app]['c'][1] / data[app][l][16])
        max_cores = max(data[app][l].keys())
        fpga_all_tiles = (data[app]['c'][1] / data[app][l][max_cores])
        fpga_self_relative = (data[app][l][1] / data[app][l][max_cores])
        overall = (data[app]['c'][opt_cpu_cores] / data[app][l][max_cores])
        print([app,l, fpga_1task, fpga_1tile, fpga_all_tiles,
            fpga_self_relative, overall] ) 

x = np.linspace(0, 2, 130)

f, axarr = plt.subplots(2,2, figsize=[8,9])

color_baseline = [0.6, 0.1, 0.1]# 'red'
color_nonspec = [0.44, 0.64, 0.81]#'blue'
color_spec =  [0.3, 0.7, 0.36]#'green'

app_plot_loc = {'des':[0,0], 
                'maxflow' : [0, 1],
                'sssp' : [1, 0],
                'astar' : [1,1],
                }
fontsize = 19
lw = 3

l1 = axarr[1, 0].plot( speedups['sssp']['c'][0], speedups['sssp']['c'][1],
        color=color_baseline, linewidth=lw)[0]
l2 = axarr[1, 0].plot( speedups['sssp']['n'][0], speedups['sssp']['n'][1],
        color=color_spec, linewidth=lw)[0]
axarr[0, 0].plot( speedups['des']['c'][0], speedups['des']['c'][1],
        color=color_baseline, linewidth=lw)[0]
axarr[0, 0].plot( speedups['des']['s'][0], speedups['des']['s'][1],
        color=color_spec, linewidth=lw)[0]
axarr[0, 1].plot( speedups['maxflow']['c'][0], speedups['maxflow']['c'][1],
        color=color_baseline, linewidth=lw)[0]
axarr[0, 1].plot( speedups['maxflow']['s'][0], speedups['maxflow']['s'][1],
        color=color_spec, linewidth=lw)[0]
axarr[1, 1].plot( speedups['astar']['c'][0], speedups['astar']['c'][1],
        color=color_baseline, linewidth=lw)[0]
axarr[1, 1].plot( speedups['astar']['n'][0], speedups['astar']['n'][1],
        color=color_spec, linewidth=lw)[0]
axarr[0,0].set_xlabel('% system used', fontsize=fontsize-1)
axarr[0,1].set_xlabel('% system used', fontsize=fontsize-1)
axarr[1,0].set_xlabel('% system used', fontsize=fontsize-1)
axarr[1,1].set_xlabel('% system used', fontsize=fontsize-1)
axarr[0,0].set_ylabel('Speedup', fontsize=fontsize-1)
axarr[1,0].set_ylabel('Speedup', fontsize=fontsize-1)
axarr[1,0].set_ylim(0, 60)
#axarr[1,1].set_ylim(0, 60)
#axarr[2,0].set(xlabel='% system used', ylabel='Speedup')

plt.gcf().subplots_adjust(top=0.795)
#plt.gcf().subplots_adjust(bottom=0.105)
#f.set_size_inches(7.5,8.5)
for app in app_plot_loc:
    loc = app_plot_loc[app]
    axarr[loc[0], loc[1]].set_title(app, fontsize=fontsize)
    axarr[loc[0], loc[1]].tick_params(axis='both', labelsize=fontsize-2)
lgd= f.legend( [l1, l2] ,
          labels = ['Baseline CPU', 'Chronos FPGA'], 
          #labels = ['Baseline CPU', 'Chronos with rollback', 
          #  'Chronos without rollback'],
          loc = 'lower right',
          bbox_to_anchor=(0.83,0.83),
          ncol = 2,
          fontsize = 17
          )
#axarr[2,1].axis('off')
f.subplots_adjust(hspace=0.45, wspace=0.3)

 
#f.tight_layout()
#plt.legend()
#plt.show()

f.savefig("speedup.pdf",bbox_extra_artists=(lgd,))#, bbox_inches='tight')

f, ax = plt.subplots(figsize=[4,4])
l1 =ax.plot( speedups['color']['c'][0], speedups['color']['c'][1],
                color=color_baseline, linewidth=lw)[0]
l2 =ax.plot( speedups['color']['n'][0], speedups['color']['n'][1],
                color=color_nonspec, linewidth=lw)[0]
ax.set_ylabel('Speedup', fontsize=fontsize-1)
ax.set_xlabel('% System used', fontsize=fontsize-1)
plt.gcf().subplots_adjust(bottom=0.155)
plt.gcf().subplots_adjust(left=0.155)
#plt.gcf().subplots_adjust(top=0.795)
plt.text(39 ,6.7 , 'Baseline CPU',
            ha='left', va='bottom', rotation=5, rotation_mode='anchor',
            fontsize=16)
plt.text(10 ,0.85 , 'Chronos non-speculative',
            ha='left', va='bottom', rotation=15, rotation_mode='anchor',
            fontsize=16)
#lgd= f.legend( [l1, l2] ,
#          labels = ['Baseline', 'Chronos Non-Speculative'],
#          loc = 'lower right',
#          bbox_to_anchor=(0.93,0.805),
#          ncol = 1,
#          fontsize = 14
#          )
f.savefig("color.pdf",bbox_extra_artists=(lgd,))#, bbox_inches='tight')

## RISCV core plot
def getmaxval(d):
    inv = [(value, key) for key, value in d.items()]
    return min(inv)[0]


mpl_fig = plt.figure()
mpl_fig, ax = plt.subplots(figsize=(5,5))
#ax = mpl_fig.add_subplot(111)

custom = [ 1, 1, 1, 1] 

width = 0.65

riscv_runtime = [
            getmaxval(data['riscv_des']['s']),
            getmaxval(data['riscv_maxflow']['s']),
            getmaxval(data['riscv_sssp']['s']),
            getmaxval(data['riscv_color']['s']),
            ]
            #90.3 * 344/662, 259, 1341, 307]
app_runtime = [
            getmaxval(data['des']['s']),
            getmaxval(data['maxflow']['s']),
            getmaxval(data['sssp']['n']),
            getmaxval(data['color']['n']),
            ]
#app_runtime = [ 22.0, 66.4, 495, 129] # 4-tiles 
#app_runtime = [ 4.87, 18.1, 96.8, 75] # best tiles 

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
