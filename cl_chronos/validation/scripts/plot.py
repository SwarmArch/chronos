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
    if app == "sssp" or app == "astar":
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
    speedups[app] = {}
    print(app)
    print(data[app])
    norm = data[app]['c'][1]
    print([app, norm])
    for l in data[app]:
        speedups[app][l] = [[],[]] 
        max_cores = max(data[app][l].keys())
        for c in sorted(data[app][l]):
            speedups[app][l][0].append(c/max_cores * 100)
            speedups[app][l][1].append( norm /  data[app][l][c])
print(speedups)
for app in data:
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
#l3 = axarr[1, 0].plot( speedups['sssp']['s'][0], speedups['sssp']['s'][1],
#        color=color_spec, linewidth=lw)[0]
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
#axarr[1, 1].plot( speedups['astar']['s'][0], speedups['astar']['s'][1],
#        color=color_spec, linewidth=lw)[0]
axarr[1, 1].plot( speedups['astar']['n'][0], speedups['astar']['n'][1],
        color=color_spec, linewidth=lw)[0]
#axarr[2, 0].plot( speedups['color']['c'][0], speedups['color']['c'][2],
#        color=color_baseline, linewidth=lw)[0]
#axarr[2, 0].plot( speedups['color']['n'][0], speedups['color']['n'][1],
#        color=color_nonspec, linewidth=lw)[0]
axarr[0,0].set_xlabel('% system used', fontsize=fontsize-1)
axarr[0,1].set_xlabel('% system used', fontsize=fontsize-1)
axarr[1,0].set_xlabel('% system used', fontsize=fontsize-1)
axarr[1,1].set_xlabel('% system used', fontsize=fontsize-1)
axarr[0,0].set_ylabel('Speedup', fontsize=fontsize-1)
axarr[1,0].set_ylabel('Speedup', fontsize=fontsize-1)
axarr[1,0].set_ylim(0, 80)
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
