import os, sys

from rpython.rlib.rfloat import formatd
from rpython.rlib.rmmap import mmap, ACCESS_READ, MADV_SEQUENTIAL

class Summary(object):
    count = 1

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

def main(argv):
    if len(argv) != 2:
        print "Usage:", argv[0], "<samples.txt>"
        return 1
    path = argv[1]
    indices = {}
    summaries = []
    hunk = ""
    i = 0
    with open(path, "rb") as handle:
        lines = mmap(handle.fileno(), 0, access=ACCESS_READ)
        lines.madvise(MADV_SEQUENTIAL, 0, lines.size)
        lines.check_valid()
        while True:
            line = lines.readline()
            if not line: break
            i += 1
            station, sample = line.split(";", 2)
            end = len(sample) - 1
            assert end >= 0, "missing sample on line %d" % i
            f = float(sample[:end])
            if station in indices: summaries[indices[station]].observe(f)
            else:
                indices[station] = len(summaries)
                summaries.append(Summary(f))
    print "Number of samples:", i
    print "Number of stations:", len(summaries)
    i = 0
    for station in indices:
        i += 1
        if i > 5: break
        print "Station %d (%s):" % (i, station), summaries[indices[station]].show()
    return 0

def target(*args): return main, None

if __name__ == "__main__": sys.exit(main(sys.argv))
