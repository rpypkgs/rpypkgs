import os, sys

from rpython.rlib.rfloat import formatd

class Summary(object):
    count = 1
    c1 = 0.0

    def __init__(self, f): self.high = self.low = self.average = f

    def observe(self, f):
        self.count += 1
        if f > self.high: self.high = f
        if f < self.low: self.low = f
        # Cut-down Welford's algorithm. Kahan summation is skipped because
        # inputs are already truncated and output will be truncated too.
        self.average += (f - self.average) / self.count

    def show(self):
        return (formatd(self.low, 'f', 1) + "/" +
                formatd(self.average, 'f', 1) + "/" +
                formatd(self.high, 'f', 1))

def main(_argv):
    bsize = os.fstatvfs(0).f_bsize
    print "Block size:", bsize
    indices = {}
    summaries = []
    hunk = ""
    i = 0
    reads = 0
    while True:
        hunk += os.read(0, bsize)
        reads += 1
        if not hunk: break
        lines = hunk.split("\n")
        hunk = lines.pop()
        for line in lines:
            i += 1
            station, sample = line.split(";", 2)
            f = float(sample)
            if station in indices: summaries[indices[station]].observe(f)
            else:
                indices[station] = len(summaries)
                summaries.append(Summary(f))
    print "Number of samples:", i
    print "Number of read() calls:", reads
    print "Number of stations:", len(summaries)
    i = 0
    for station in indices:
        i += 1
        if i > 5: break
        print "Station %d (%s):" % (i, station), summaries[indices[station]].show()
    return 0

def target(*args): return main, None

if __name__ == "__main__": sys.exit(main(sys.argv))
