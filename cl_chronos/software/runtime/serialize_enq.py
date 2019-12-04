import sys
# Reads tq log, filters enqs that was not child-aborted
# and sorts in ts order
f = open(sys.argv[1])
i = 0
slot_lines = [None]*4096
slot_ts = [None]*4096
slot_seq= [None]*4096
enqs = []
#fw = open("a", "w")
n_tied_enq = 0
n_cut_tie = 0
n_commit = 0
n_abort = 0
last_cut_tie_cycle = 0
last_cut_tie_slot = 0
seq =0

log_count = 0

for line in f:
    i=i+1
    slot = 0
    ts = 0
    if (line.find('log') >= 0):
        continue
    if (line.find('mismatch') >= 0):
        print(line)
        continue
    if (line.find('going') >=0):
    #    print(line)
        continue
    #seq = int(line[1:7])
    seq = i
    slot_loc = line.find('slot:')
    ts_loc = line.find('ts:')
    object_loc = line.find('object')
    if (slot_loc >0):
        slot = int(line[slot_loc+5:slot_loc+9])

    if (line.find('task_enqueue')>0):
        slot_lines[slot] = line
        ts = int(line[ts_loc+3:object_loc], 16)
        slot_ts[slot] = ts
        slot_seq[slot] = seq
     
    if (line.find('commit')>0):
        if (slot_ts[slot] is not None):
            enqs.append([ slot_ts[slot], slot_seq[slot], slot_lines[slot]]) 
    if (line.find('overflow')>0):
        enqs.append([ slot_ts[slot], slot_seq[slot], slot_lines[slot]]) 

enqs.sort(key=lambda tup: tup[0]*1000000000 + tup[1])
for (ts, seq, line) in enqs:
    #if (line[99+1] == ' '):
    #    line = line[0:99] + "     " + line[100:]
    print("%s" % line[:-1])
    
