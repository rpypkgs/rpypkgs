# BF interpreter
# Includes concepts from  (c) 2011 Andrew Brown
# Rewrite, final encoding (c) 2024 Corbin Simpson
# Pointer propagation     (c) 2026 Corbin Simpson

import os
import sys

from rpython.jit.codewriter.policy import JitPolicy
from rpython.rlib.jit import JitDriver, unroll_safe
from rpython.rlib.listsort import make_timsort_class
from rpython.rlib.objectmodel import import_from_mixin, specialize

# Initial-coded tokens for whether offsets are absolute or relative.
class Offset(object): pass
class Absolute(Offset): pass
class Relative(Offset): pass
ABS = Absolute(); REL = Relative()

# https://esolangs.org/wiki/Algebraic_Brainfuck
# v1: builtins, monoid, zero, move, move2, scalemove, scalemove2
# v2: propagate
class BF(object):
    def propagate(self, adjust, diffs): pass
    def unit(self): return self.propagate(0, {})
    def join(self, l, r): pass
    def plus(self, i): return self.propagate(0, {0: (REL, i)})
    def right(self, i): return self.propagate(i, {})
    def loop(self, bfs): pass
    def input(self): pass
    def output(self): pass
    def zero(self): return self.propagate(0, {0: (ABS, 0)})
    def move(self, i): return self.scalemove(i, 1)
    def move2(self, i, j): return self.scalemove2(i, 1, j, 1)
    def scalemove(self, i, s):
        return self.loop([self.propagate(0, {0: (REL, -1), i: (REL, s)})])
    def scalemove2(self, i, s, j, t):
        return self.loop([
            self.propagate(0, {0: (REL, -1), i: (REL, s), j: (REL, t)}),
        ])

KeySort = make_timsort_class(lt=lambda l, r: l[0] < r[0])

class AsStr(object):
    import_from_mixin(BF)
    def unit(self): return ""
    def join(self, l, r): return l + r
    def propagate(self, adjust, diffs):
        pieces = []
        pointer = 0
        ds = diffs.items()
        KeySort(ds).sort()
        # NB: if pointer will end up left of starting point
        # then is more efficient to traverse RTL.
        if adjust < 0: ds.reverse()
        for (k, (ty, v)) in ds:
            pieces.append(self.right(k - pointer))
            pointer += k - pointer
            if ty is ABS: pieces.append(self.zero())
            pieces.append(self.plus(v))
        pieces.append(self.right(adjust - pointer))
        return ''.join(pieces)
    def zero(self): return '[-]'
    def plus(self, i): return '+' * i if i > 0 else '-' * -i
    def right(self, i): return '>' * i if i > 0 else '<' * -i
    def loop(self, bfs): return '[' + ''.join(bfs) + ']'
    def input(self): return ','
    def output(self): return '.'

jitdriver = JitDriver(greens=['op'], reds=['position', 'tape'])

class Op(object): _immutable_ = True

class _Input(Op):
    _immutable_ = True
    def runOn(self, tape, position):
        tape[position] = ord(os.read(0, 1)[0])
        return position
Input = _Input()
class _Output(Op):
    _immutable_ = True
    def runOn(self, tape, position):
        os.write(1, chr(tape[position]))
        return position
Output = _Output()
class Propagate(Op):
    _immutable_ = True
    _immutable_fields_ = "adjust", "diffs[*]"
    def __init__(self, adjust, diffs):
        self.adjust = adjust
        self.diffs = diffs
    @unroll_safe
    def runOn(self, tape, position):
        for (k, (ty, v)) in self.diffs:
            if   ty is ABS: tape[position + k] = v
            elif ty is REL: tape[position + k] += v
            else: assert False, "offsetting"
        return position + self.adjust
class ZeroScaleAdd(Op):
    _immutable_ = True
    _immutable_fields_ = "offset", "scale"
    def __init__(self, offset, scale):
        self.offset = offset
        self.scale = scale
    def runOn(self, tape, position):
        tape[position + self.offset] += tape[position] * self.scale
        tape[position] = 0
        return position
class ZeroScaleAdd2(Op):
    _immutable_ = True
    _immutable_fields_ = "offset1", "scale1", "offset2", "scale2"
    def __init__(self, offset1, scale1, offset2, scale2):
        self.offset1 = offset1
        self.scale1 = scale1
        self.offset2 = offset2
        self.scale2 = scale2
    def runOn(self, tape, position):
        tape[position + self.offset1] += tape[position] * self.scale1
        tape[position + self.offset2] += tape[position] * self.scale2
        tape[position] = 0
        return position
class Loop(Op):
    _immutable_ = True
    _immutable_fields_ = "op",
    def __init__(self, op): self.op = op
    def runOn(self, tape, position):
        op = self.op
        while tape[position]:
            jitdriver.jit_merge_point(op=op, position=position, tape=tape)
            position = op.runOn(tape, position)
        return position
class Seq(Op):
    _immutable_ = True
    _immutable_fields_ = "ops[*]",
    def __init__(self, ops): self.ops = ops
    @unroll_safe
    def runOn(self, tape, position):
        for op in self.ops: position = op.runOn(tape, position)
        return position

class AsOps(object):
    import_from_mixin(BF)
    def unit(self): return Propagate(0, [])
    def join(self, l, r):
        if isinstance(l, Seq) and isinstance(r, Seq):
            return Seq(l.ops + r.ops)
        elif isinstance(l, Seq): return Seq(l.ops + [r])
        elif isinstance(r, Seq): return Seq([l] + r.ops)
        return Seq([l, r])
    def propagate(self, adjust, diffs):
        ds = diffs.items()
        KeySort(ds).sort()
        return Propagate(adjust, ds)
    def loop(self, bfs): return Loop(Seq(bfs))
    def input(self): return Input
    def output(self): return Output
    def scalemove(self, i, s): return ZeroScaleAdd(i, s)
    def scalemove2(self, i, s, j, t): return ZeroScaleAdd2(i, s, j, t)

# https://graphics.stanford.edu/~seander/bithacks.html#DetermineIfPowerOf2
# Special case for i=1, whose orbit does include 0!
def orbitReachesZero(i): return bool((abs(i) & 1) | (abs(i) & (abs(i) - 1)))

def makePeephole(cls):
    # Optimization domain is a tuple of: (underlying domain, adjust, diffs)
    # (diffs is None <=> is not propagator)
    domain = cls()
    def stripDomain(bfs): return [t[0] for t in bfs]
    def isProp(t): return t[2] is not None

    class Peephole(object):
        import_from_mixin(BF)
        def unit(self): return []
        def join(self, l, r):
            if not len(l): return r
            if not len(r): return l
            if not isProp(l[-1]) or not isProp(r[0]): return l + r
            _, ladj, lds = l[-1]
            _, radj, rds = r[0]
            adjust = ladj + radj
            diffs = lds.copy()
            for (k, (rty, rv)) in rds.iteritems():
                lty, lv = diffs.get(ladj + k, (REL, 0))
                if   rty is ABS: diffs[ladj + k] = ABS, rv
                elif rty is REL: diffs[ladj + k] = lty, lv + rv
                else: assert False, "offputting"
            return l[:-1] + self.propagate(adjust, diffs) + r[1:]
        def propagate(self, adjust, diffs):
            return [(domain.propagate(adjust, diffs), adjust, diffs)]
        def loop(self, bfs):
            ts = []
            for bf in bfs: ts.extend(bf)
            # Loopish pattern recognition.
            if len(ts) == 1 and isProp(ts[0]):
                bf, adjust, diffs = ts[0]
                if adjust == 0 and 0 in diffs:
                    diffs = diffs.copy()
                    ty, v = diffs[0]
                    del diffs[0]
                    if len(diffs) == 0 and orbitReachesZero(v) and ty is REL:
                        return self.zero()
                    elif len(diffs) == 1:
                        ik, (ity, iv) = diffs.items()[0]
                        if ty is REL and v == -1 and ity is REL:
                            return [(domain.scalemove(ik, iv), 0, None)]
                        # XXX could also add new op for ABS ity
                    elif len(diffs) == 2:
                        dis = diffs.items()
                        ik, (ity, iv) = dis[0]
                        jk, (jty, jv) = dis[1]
                        if ty is REL and v == -1 and ity is jty is REL:
                            return [(domain.scalemove2(ik, iv, jk, jv), 0, None)]
            return [(domain.loop(stripDomain(ts)), 0, None)]
        def input(self): return [(domain.input(), 0, None)]
        def output(self): return [(domain.output(), 0, None)]
    return Peephole, stripDomain

AsStr, finishStr = makePeephole(AsStr)
AsOps, finishOps = makePeephole(AsOps)

def parsePropagator(s, i):
    pointer = 0
    diffs = {}
    while i < len(s):
        if s[i] in ',.[]': break
        elif s[i] == '+':
            ty, v = diffs.get(pointer, (REL, 0))
            diffs[pointer] = ty, v + 1
        elif s[i] == '-':
            ty, v = diffs.get(pointer, (REL, 0))
            diffs[pointer] = ty, v - 1
        elif s[i] == '>': pointer += 1
        elif s[i] == '<': pointer -= 1
        i += 1
    return i, pointer, diffs

def skipLoop(s, i):
    depth = 1
    i += 1
    while i < len(s) and depth:
        if s[i] == '[': depth += 1
        elif s[i] == ']': depth -= 1
        i += 1
    return i

@specialize.argtype(1)
def parse(s, domain):
    ops = [domain.unit()]
    i = 0

    # Skip initial comment-loops; this is easier than adding a special case to
    # the optimizers for non-obvious reasons.
    skipNextLoop = True
    while i < len(s):
        if s[i] in '+-<>':
            i, pointer, diffs = parsePropagator(s, i)
            ops[-1] = domain.join(ops[-1], domain.propagate(pointer, diffs))
            skipNextLoop = False
            continue
        elif s[i] == ',':
            ops[-1] = domain.join(ops[-1], domain.input())
            skipNextLoop = False
        elif s[i] == '.': ops[-1] = domain.join(ops[-1], domain.output())
        elif s[i] == '[':
            if skipNextLoop:
                i = skipLoop(s, i)
                continue
            else: ops.append(domain.unit())
        elif s[i] == ']':
            loop = domain.loop([ops.pop()])
            ops[-1] = domain.join(ops[-1], loop)
            skipNextLoop = True
        i += 1

    return ops.pop()

def entryPoint(argv):
    if len(argv) < 2 or "-h" in argv:
        print "Usage: bf [-c <number of cells>] [-h] [-o] <program.bf>"
        print "To dump a minimized optimized program: bf -o <program.bf>"
        return 1
    cells = 30000
    if argv[1] == "-c":
        cells = int(argv[2])
        path = argv[3]
    elif argv[1] == "-o": path = argv[2]
    else: path = argv[1]
    with open(path) as handle: text = handle.read()
    if "-o" in argv:
        print ''.join(finishStr(parse(text, AsStr())))
        return 0
    tape = bytearray("\x00" * cells)
    Seq(finishOps(parse(text, AsOps()))).runOn(tape, 0)
    return 0

def target(*args): return entryPoint, None

def jitpolicy(driver): return JitPolicy()

if __name__ == "__main__": sys.exit(entryPoint(sys.argv))
