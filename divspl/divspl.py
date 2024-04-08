import sys

from rpython.jit.codewriter.policy import JitPolicy
from rpython.rlib.jit import JitDriver

# This is a basic interpreter for DIVSPL, as described at
# https://www.promptworks.com/blog/the-fastest-fizzbuzz-in-the-west
# Version 0: Initial functionality
# Version 1: Port to RPython, add JIT

def parseAssignment(line):
    word, number = [w.strip() for w in line.rsplit("=", 1)]
    return word, int(number)

def parse(lines):
    # The first line must be the range.
    start, stop = [int(n.strip()) for n in lines[0].split("...")]
    # Skip empty lines, usually at EOF.
    assignments = [parseAssignment(line) for line in lines[1:] if line]
    return start, stop, assignments

def location(stop, assignments):
    return "%d rules, stop at %d" % (len(assignments), stop)
driver = JitDriver(greens=["stop", "assignments"], reds=["i"],
                   get_printable_location=location)

def run(start, stop, assignments):
    i = start
    while i <= stop:
        driver.jit_merge_point(stop=stop, assignments=assignments, i=i)
        s = [w for w, n in assignments if not i % n]
        print ("".join(s) if s else str(i))
        i += 1

# NB: programs should already be split into lines
def main(argv):
    if len(argv) != 2:
        print "Usage: divspl program.divspl"
        return 1
    with open(argv[1]) as handle: program = handle.read().split("\n")
    start, stop, assignments = parse(program)
    run(start, stop, assignments)
    return 0

def target(*args): return main, None
def jitpolicy(driver): return JitPolicy()

if __name__ == "__main__": sys.exit(main(sys.argv))
