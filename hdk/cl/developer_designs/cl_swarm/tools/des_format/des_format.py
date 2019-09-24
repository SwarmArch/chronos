import sys
if len(sys.argv) > 1:
    fname = sys.argv[1]
else:
    fname = 'xor.net'
f = open(fname)
tokens = []
for line in f:
    if (line.find('//')>=0):
        continue
    line = line.replace('#'," ")
    line = line.replace(','," ")
    line = line.replace('='," ")
    line = line.replace('('," ")
    line = line.replace(')'," ")
    tokens.extend(line.split())
t = 0
nid = 0
outputs = []
nodes = {} # each entry [nid, delay]
neighbors = {}
finish_time = 0
initlist = {}
outvalues = {}
while (t<len(tokens)):
    tok = tokens[t]
    if (tok == 'inputs'):
        t += 1
        while (tokens[t] != 'end'):
            var = tokens[t]
            nodes [var] = [nid, 'buf', 0] ; 
            #print ("Input ", var, nid)
            neighbors [var] = []
            nid += 1
            t += 1
    elif (tok == 'outputs'):
        t = t+1
        while (tokens[t] != 'end'):
            var = tokens[t]
            outputs.append(var)
            t += 1
    elif (tok == 'finish'):
        finish_time = int(tokens[t+1])
        t += 2
    elif (tok == 'initlist'):
        var = tokens[t+1]
        vid = nodes[var][0]
        initlist[vid] = []
        t += 2;
        while (tokens[t] != 'end'):
            initlist[vid].append((int(tokens[t]),  int(tokens[t+1])) )
            t += 2;
    elif (tok == 'outvalues'):
        t += 1
        while (tokens[t] != 'end'):
            outvalues[ tokens[t] ] = tokens[t+1]
            t += 2
    elif (tok == 'netlist'): 
        t += 1
        # Assumes nets sources are defined before the sinks 
        while (tokens[t] != 'end'):
            gate = tokens[t]
            o_node = tokens[t+1]
            single_input_gate = gate in ['inv', 'buf']
            if (single_input_gate):
                i0_node = tokens[t+2]
                delay = int(tokens[t+3])
                t += 4
            else: 
                i0_node = tokens[t+2]
                i1_node = tokens[t+3]
                delay = int(tokens[t+4])
                t += 5
            
            nodes[o_node] = [nid, gate, delay] 
            print (o_node, nid, gate, delay)
            nid += 1
            neighbors[o_node] = []
           
            neighbors[i0_node].append([o_node,0])
            if not single_input_gate:
                neighbors[i1_node].append([o_node,1])
    else :
        t += 1
print ("Output" ,outputs)
print finish_time
#print initlist
print outvalues
print ("Neighbors")

gate_type_map = { 'buf' :0, 'inv' : 1, 'nand2' : 2, 'nor2' : 3, 
        'and2' : 4, 'or2' : 5, 'xor2' : 6, 'xnor2' : 7 }
                

numV = len(nodes)
numE = sum([ len(neighbors[x]) for x in neighbors])
print ('numV', numV)
print ('numE', numE)

# csr_data format ( [23:22]:in0, [21:20]:in1, [19:16] gate, [15:0] delay
csr_data = [0 for i in range(numV)]
csr_offset = [0 for i in range(numV+1)]
csr_neighbors = [0 for i in range(numE)]

for n in nodes:
    nid = nodes[n][0]
    gate = nodes[n][1]
    delay = nodes[n][2]
    csr_data[nid] = [gate_type_map[gate] , delay]
    csr_offset[nid+1] = len(neighbors[n])

#prefix sum
for i in range(1,numV+1):
    csr_offset[i] = csr_offset[i-1] + csr_offset[i] 

for n in nodes: 
    nid = nodes[n][0]
    nc = 0
    for [e,port] in neighbors[n]:
        dest_id = nodes[e][0] # find the index
        csr_neighbors[csr_offset[nid] + nc] = (dest_id, port)
        nc += 1
#print "node_data"
#print csr_data
#print "csr_offset"
print csr_offset
#print "csr_neighbors"
print csr_neighbors

numO = len(outputs)
numInit = sum( [len(initlist[i]) for i in initlist])
print ("Initlist size ", numInit)

max_fanout = max([ len(neighbors[x]) for x in neighbors])
print ("max fanout ", max_fanout)

numI = len(initlist)

SIZE_DIST =((numV+15)/16)*16;
SIZE_EDGE_OFFSET =( (numV+1 +15)/ 16) * 16;
SIZE_NEIGHBORS =( (numE+ 15)/16 ) * 16;

SIZE_INITLIST_EDGEOFFSET =((numI+1+15)/16)*16;
SIZE_INITLIST =  ((numInit * 15)/16) * 16
SIZE_GROUND_TRUTH =((numO+15)/16)*16;

BASE_DIST = 16;
BASE_EDGE_OFFSET = BASE_DIST + SIZE_DIST
BASE_NEIGHBORS = BASE_EDGE_OFFSET + SIZE_EDGE_OFFSET
BASE_INITLIST_VID = BASE_NEIGHBORS + SIZE_NEIGHBORS
BASE_INITLIST_EDGE_OFFSET = BASE_INITLIST_VID + SIZE_INITLIST_EDGEOFFSET
BASE_INITLIST = BASE_INITLIST_EDGE_OFFSET + SIZE_INITLIST_EDGEOFFSET
BASE_GROUND_TRUTH = BASE_INITLIST + SIZE_INITLIST

BASE_END = BASE_GROUND_TRUTH + SIZE_GROUND_TRUTH
    
data = [0 for i in range(BASE_END)]
data[0] = 0xdead;
data[1] = numV;
data[2] = numE;
data[3] = BASE_EDGE_OFFSET;
data[4] = BASE_NEIGHBORS;
data[5] = BASE_DIST;
data[6] = BASE_GROUND_TRUTH;
data[7] = BASE_INITLIST_VID;
data[8] = BASE_INITLIST_EDGE_OFFSET;
data[9] = BASE_INITLIST;
data[10] = BASE_END;
data[11] = numI;
data[12] = numO;


print (data[0:13])
for i in range (numV):
    
    data[BASE_DIST + i] = ( 2 << 24 |
                            csr_data[i][0] << 16 |
                            csr_data[i][1] )
    data[BASE_EDGE_OFFSET + i] = csr_offset[i]
data[BASE_EDGE_OFFSET + numV] = csr_offset[numV]

for i in range (numE):
    data[BASE_NEIGHBORS + i] = csr_neighbors[i][0]<<1 | csr_neighbors[i][1]

i=0
for o in outvalues:
    outVal = int(outvalues[o])
    outId = nodes[o][0]
    data[BASE_GROUND_TRUTH + i] = (outId << 16) | outVal
    i +=1
    print (o,outId, outVal)

print('initlist base offset')
i=0
offset = 0;
for vid in range(0,numI):
#for var in initlist:
    #vid = nodes[var][0]    
    data[BASE_INITLIST_VID + vid] = vid 
    data[BASE_INITLIST_EDGE_OFFSET + vid] = offset;
    print (vid,offset)
    for (delay, val) in initlist[vid]:
        data[BASE_INITLIST + offset  ] = val << 24 | delay;
        offset += 1
data[BASE_INITLIST_EDGE_OFFSET + numI] = offset
print ('offset_end',offset)

fw = open(fname +".csr","w")
for i in range(BASE_END):
    fw.write("%08x\n" % data[i])

