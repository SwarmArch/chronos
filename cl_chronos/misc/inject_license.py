#!/usr/bin/python

import os, sys

# Look for all files under the following tree and inject the license code

exts = [".c", ".cpp", ".h", ".vh", ".sv"] # only C/C++ files for now
licTextId = "$lic$" # license headers MUST have this text somewhere, and be a multi-line comment

targetDir = sys.argv[1]

srcs = [os.path.join(dir, file) for (dir, x, files) in os.walk(targetDir) for file in files if os.path.splitext(file)[1] in exts]
srcs.sort()

print "Will operate on " +  str(len(srcs)) + " source files:"
for src in srcs: print " " + src

def askForPermission():
    resp =  raw_input("Continue (y/n)? ")
    if not resp == "y":
        print "Not continuing"
        sys.exit(0)

askForPermission()

# Open license header file, read its text
licHdrFile = sys.argv[2]
f = open(licHdrFile, 'r')
licHdr = f.read()
f.close()

print "Will inject license header:"
print licHdr

if licHdr.find(licTextId) == -1:
    print "ERROR: License identifier text not found in provided header"
    sys.exit(-1)


# Open each file for r/we, read its contents and produce modifications (but don't write them yet!)
addedList = []
modifiedList = []
compliantList = []

for src in srcs:
    f = open(src, 'r+') # we open for read/write here to fail early on read-only files
    txt = f.read()
    f.close()
    if txt.find(licHdr) != -1:
        # This already has the current license header
        compliantList.append(src)
    elif txt.find(licTextId) == -1:
        # No license header, insert at the beginning
        addedList.append((src, licHdr + txt))
    else:
        # NOTE: This detection algorithm is pretty basic, and could raise hell in corner cases
        licPos = txt.find(licTextId)

        # Check lic text is after a comment start, and before a comment end
        prevCommentOpen = txt.rfind("/*", 0, licPos)
        prevCommentClose = txt.rfind("*/", 0, licPos)
        if prevCommentOpen == -1 or prevCommentOpen < prevCommentClose:
            print "BOGUS " + licTextId + "detected on " + src + ", unmatched start, aborting"
            sys.exit(-1)

        nextCommentOpen = txt.find("/*", licPos)
        nextCommentClose = txt.find("*/", licPos)
        if nextCommentClose == -1 or (not nextCommentOpen == -1 and nextCommentClose > nextCommentOpen):
            print "BOGUS " + licTextId + "detected on " + src + ", unmatched end, aborting"
            sys.exit(-1)

        #print prevCommentOpen, nextCommentClose
        newTxt = txt[:prevCommentOpen] + txt[nextCommentClose+2:] # kill old license comment
        newTxt = licHdr + newTxt.lstrip() # prepend new license (not that this works if careless developers put code or comments before the license comment)
        #print newTxt

        modifiedList.append((src, newTxt))

print "Will add license to %d files, %d will be modified, %d are already compliant" % (len(addedList), len(modifiedList), len(compliantList))

askForPermission()

for (src, txt) in addedList + modifiedList:
    f = open(src, 'w')
    f.write(txt)
    f.close()

print "Done!"

