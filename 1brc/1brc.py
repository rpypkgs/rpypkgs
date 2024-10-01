import os, sys

from rpython.rlib.rfloat import formatd
from rpython.rlib.rmmap import mmap, ACCESS_READ, MADV_SEQUENTIAL

class Summary(object):
    count = 1

    def __init__(self, f): self.high = self.low = self.average = f

    def observe(self, f):
        count = self.count + 1
        # Cut-down Welford's algorithm. Kahan summation is skipped because
        # inputs are already truncated and output will be truncated too;
        # empirical error is less than one part per million, so don't bother.
        self.average += (f - self.average) / count
        # ILP hacking: Write the average first for data dependencies, then the
        # count, and then do the conditional writes last.
        self.count = count
        if f > self.high: self.high = f
        elif f < self.low: self.low = f

    def show(self):
        return (formatd(self.low, 'f', 1) + "/" +
                formatd(self.average, 'f', 1) + "/" +
                formatd(self.high, 'f', 1))

def collectLines(lines):
    indices = {}
    summaries = []
    pos = 0
    top = lines.size
    while True:
        semilen = 1
        while lines.data[pos + semilen] != ';':
            if pos + semilen > top: return indices, summaries
            semilen += 1
        station = lines.getslice(pos, semilen)
        pos += semilen + 1
        nllen = 1
        while lines.data[pos + nllen] != '\n':
            if pos + nllen > top: return indices, summaries
            nllen += 1
        sample = float(lines.getslice(pos, nllen))
        pos += nllen + 1
        if station in indices: summaries[indices[station]].observe(sample)
        else:
            indices[station] = len(summaries)
            summaries.append(Summary(sample))

def main(argv):
    if len(argv) != 2:
        print "Usage:", argv[0], "<samples.txt>"
        return 1
    with open(argv[1], "rb") as handle:
        lines = mmap(handle.fileno(), 0, access=ACCESS_READ)
        lines.madvise(MADV_SEQUENTIAL, 0, lines.size)
        lines.check_valid()
        indices, summaries = collectLines(lines)
    print "Number of stations:", len(summaries)
    i = 0
    for station in indices:
        i += 1
        if i > 3: break
        print "Station %d (%s):" % (i, station), summaries[indices[station]].show()
    return 0

def target(*args): return main, None

if __name__ == "__main__": sys.exit(main(sys.argv))
