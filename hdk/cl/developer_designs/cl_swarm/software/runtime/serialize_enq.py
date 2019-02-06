import sys
# Reads tq log, filters enqs that was not child-aborted
# and sorts in ts order
f = open(sys.argv[1])
i = 0
slot_lines = [None]*4096
slot_ts = [None]*4096
slot_seq= [None]*4096
enqs = []
fw = open("a", "w")
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
    seq = int(line[1:7])
    slot_loc = line.find('slot:')
    ts_loc = line.find('ts:')
    if (slot_loc >0):
        slot = int(line[slot_loc+5:slot_loc+9])

    if (line.find('task_enqueue')>0):
        slot_lines[slot] = line
        ts = int(line[ts_loc+3:ts_loc+7], 16)
        slot_ts[slot] = ts
        slot_seq[slot] = seq
     
    if (line.find('commit')>0):
        enqs.append([ slot_ts[slot], slot_seq[slot], slot_lines[slot]]) 

enqs.sort(key=lambda tup: tup[0]*1000000 + tup[1])
for (ts, seq, line) in enqs:
    if (line[95] == ' '):
        line = line[0:94] + "     " + line[95:]
    print("%s" % line[:-1])
    
