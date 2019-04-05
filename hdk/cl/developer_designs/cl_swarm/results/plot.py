import matplotlib.pyplot as plt
import numpy as np

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
for app in data:
    max_cpu_cores = 40
    if (app=='maxflow'):
        max_cpu_cores = 6;
    if (app=='color'):
        max_cpu_cores = 20;
    cpu_self_relative = data[app]['c'][1] / data[app]['c'][max_cpu_cores]
    print([app, 'cpu self-relative', cpu_self_relative])
    for l in data[app]:
        if (l=='c'):
            continue
        eff_factor = (data[app]['c'][1] / data[app][l][1])
        max_cores = max(data[app][l].keys())
        fpga_self_relative = (data[app][l][1] / data[app][l][max_cores])
        print([app,l, eff_factor, fpga_self_relative] ) 

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

lw = 2

l1 = axarr[1, 0].plot( speedups['sssp']['c'][0], speedups['sssp']['c'][1],
        color=color_baseline, linewidth=lw)[0]
l2 = axarr[1, 0].plot( speedups['sssp']['n'][0], speedups['sssp']['n'][1],
        color=color_nonspec, linewidth=lw)[0]
l3 = axarr[1, 0].plot( speedups['sssp']['s'][0], speedups['sssp']['s'][1],
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
axarr[1, 1].plot( speedups['astar']['s'][0], speedups['astar']['s'][1],
        color=color_spec, linewidth=lw)[0]
axarr[1, 1].plot( speedups['astar']['n'][0], speedups['astar']['n'][1],
        color=color_nonspec, linewidth=lw)[0]
axarr[2, 0].plot( speedups['color']['c'][0], speedups['color']['c'][1],
        color=color_baseline, linewidth=lw)[0]
axarr[2, 0].plot( speedups['color']['n'][0], speedups['color']['n'][1],
        color=color_nonspec, linewidth=lw)[0]
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

f.savefig("speedup.pdf", bbox_inches='tight')

