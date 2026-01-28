# BF interpreter
# Includes concepts from (c) 2011 Andrew Brown
# Major rewrite          (c) 2024 Corbin Simpson

import os
import sys

from rpython.jit.codewriter.policy import JitPolicy
from rpython.rlib.jit import JitDriver, unroll_safe
from rpython.rlib.objectmodel import import_from_mixin, specialize

# https://esolangs.org/wiki/Algebraic_Brainfuck
class BF(object):
    def unit(self): pass
    def join(self, l, r): pass
    def joinList(self, bfs):
        if not bfs: return self.unit()
        elif len(bfs) == 1: return bfs[0]
        elif len(bfs) == 2: return self.join(bfs[0], bfs[1])
        else:
            i = len(bfs) >> 1
            return self.join(self.joinList(bfs[:i]), self.joinList(bfs[i:]))
    def plus(self, i): pass
    def right(self, i): pass
    def loop(self, bfs): pass
    def input(self): pass
    def output(self): pass
    def zero(self): return self.loop(self.plus(-1))
    def move(self, i): return self.scalemove(i, 1)
    def move2(self, i, j): return self.scalemove2(i, 1, j, 1)
    def scalemove(self, i, s):
        return self.loop(self.joinList([
            self.plus(-1), self.right(i), self.plus(s), self.right(-i)]))
    def scalemove2(self, i, s, j, t):
        return self.loop(self.joinList([
                self.plus(-1), self.right(i), self.plus(s), self.right(j - i),
                self.plus(t), self.right(-j)]))

class AsStr(object):
    import_from_mixin(BF)
    def unit(self): return ""
    def join(self, l, r): return l + r
    def plus(self, i): return '+' * i if i > 0 else '-' * -i
    def right(self, i): return '>' * i if i > 0 else '<' * -i
    def loop(self, bfs): return '[' + bfs + ']'
    def input(self): return ','
    def output(self): return '.'

jitdriver = JitDriver(greens=['op'], reds=['position', 'tape'])

class Op(object): _immutable_ = True

class _Input(Op):
    _immutable_ = True
    def runOn(self, tape, position): tape[position] = ord(os.read(0, 1)[0]); return position
Input = _Input()
class _Output(Op):
    _immutable_ = True
    def runOn(self, tape, position): os.write(1, chr(tape[position])); return position
Output = _Output()
class Add(Op):
    _immutable_ = True
    _immutable_fields_ = "imm",
    def __init__(self, imm): self.imm = imm
    def runOn(self, tape, position): tape[position] += self.imm; return position
class Shift(Op):
    _immutable_ = True
    _immutable_fields_ = "width",
    def __init__(self, width): self.width = width
    def runOn(self, tape, position): return position + self.width
class _Zero(Op):
    _immutable_ = True
    def runOn(self, tape, position): tape[position] = 0; return position
Zero = _Zero()
class ZeroScaleAdd(Op):
    _immutable_ = True
    _immutable_fields_ = "offset", "scale"
    def __init__(self, offset, scale): self.offset, self.scale = offset, scale
    def runOn(self, tape, position):
        tape[position + self.offset] += tape[position] * self.scale; tape[position] = 0; return position
class ZeroScaleAdd2(Op):
    _immutable_ = True
    _immutable_fields_ = "offset1", "scale1", "offset2", "scale2"
    def __init__(self, offset1, scale1, offset2, scale2):
        self.offset1, self.scale1, self.offset2, self.scale2 = offset1, scale1, offset2, scale2
    def runOn(self, tape, position):
        tape[position + self.offset1] += tape[position] * self.scale1
        tape[position + self.offset2] += tape[position] * self.scale2; tape[position] = 0; return position
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
class AddAt(Op):
    _immutable_ = True
    _immutable_fields_ = "offset", "imm"
    def __init__(self, offset, imm): self.offset, self.imm = offset, imm
    def runOn(self, tape, position): tape[position + self.offset] += self.imm; return position
class InputAt(Op):
    _immutable_ = True
    _immutable_fields_ = "offset",
    def __init__(self, offset): self.offset = offset
    def runOn(self, tape, position): tape[position + self.offset] = ord(os.read(0, 1)[0]); return position
class OutputAt(Op):
    _immutable_ = True
    _immutable_fields_ = "offset",
    def __init__(self, offset): self.offset = offset
    def runOn(self, tape, position): os.write(1, chr(tape[position + self.offset])); return position
class ZeroAt(Op):
    _immutable_ = True
    _immutable_fields_ = "offset",
    def __init__(self, offset): self.offset = offset
    def runOn(self, tape, position): tape[position + self.offset] = 0; return position
class ZeroScaleAddAt(Op):
    _immutable_ = True
    _immutable_fields_ = "src_off", "dst_off", "scale"
    def __init__(self, src_off, dst_off, scale):
        self.src_off, self.dst_off, self.scale = src_off, dst_off, scale
    def runOn(self, tape, position):
        tape[position + self.dst_off] += tape[position + self.src_off] * self.scale
        tape[position + self.src_off] = 0; return position
class ZeroScaleAdd2At(Op):
    _immutable_ = True
    _immutable_fields_ = "src_off", "dst1_off", "scale1", "dst2_off", "scale2"
    def __init__(self, src_off, dst1_off, scale1, dst2_off, scale2):
        self.src_off, self.dst1_off, self.scale1, self.dst2_off, self.scale2 = \
            src_off, dst1_off, scale1, dst2_off, scale2
    def runOn(self, tape, position):
        tape[position + self.dst1_off] += tape[position + self.src_off] * self.scale1
        tape[position + self.dst2_off] += tape[position + self.src_off] * self.scale2
        tape[position + self.src_off] = 0; return position
class PropSeq(Op):
    _immutable_ = True
    _immutable_fields_ = "ops[*]", "net_shift"
    def __init__(self, ops, net_shift): self.ops, self.net_shift = ops, net_shift
    @unroll_safe
    def runOn(self, tape, position):
        for op in self.ops: position = op.runOn(tape, position)
        return position + self.net_shift

class AsOps(object):
    import_from_mixin(BF)
    def unit(self): return Shift(0)
    def join(self, l, r):
        if isinstance(l, Seq) and isinstance(r, Seq):
            return Seq(l.ops + r.ops)
        elif isinstance(l, Seq): return Seq(l.ops + [r])
        elif isinstance(r, Seq): return Seq([l] + r.ops)
        return Seq([l, r])
    def plus(self, i): return Add(i)
    def right(self, i): return Shift(i)
    def loop(self, bfs): return Loop(bfs)
    def input(self): return Input
    def output(self): return Output
    def zero(self): return Zero
    def scalemove(self, i, s): return ZeroScaleAdd(i, s)
    def scalemove2(self, i, s, j, t): return ZeroScaleAdd2(i, s, j, t)

class AbstractDomain(object): pass
meh, aLoop, aZero, theIdentity, anAdd, aRight = [AbstractDomain() for _ in range(6)]

def makePeephole(cls):
    # Optimization domain: tuple of underlying domain, abstract tag, integer
    # (integer only used for adds and shifts)
    domain = cls()
    def stripDomain(bfs): return domain.joinList([t[0] for t in bfs])
    def isConstAdd(bf, i): return bf[1] is anAdd and bf[2] == i
    def oppositeShifts(bf1, bf2):
        return bf1[1] is bf2[1] is aRight and bf1[2] == -bf2[2]
    def oppositeShifts2(bf1, bf2, bf3):
        return (bf1[1] is bf2[1] is bf3[1] is aRight and
                bf1[2] + bf2[2] + bf3[2] == 0)
    def isALoop(ad): return ad is aZero or ad is aLoop

    class Peephole(object):
        import_from_mixin(BF)
        def unit(self): return []
        # Peephole optimizations according to the standard monoid.
        def join(self, l, r):
            if not l: return r
            rv = l[:]
            bfHead, adHead, immHead = rv.pop()
            for bf, ad, imm in r:
                if ad is theIdentity: continue
                elif isALoop(adHead) and isALoop(ad): continue
                elif adHead is theIdentity:
                    bfHead, adHead, immHead = bf, ad, imm
                elif adHead is anAdd and ad is aZero:
                    bfHead, adHead, immHead = bf, ad, imm
                elif adHead is anAdd and ad is anAdd:
                    immHead += imm
                    if immHead: bfHead = domain.plus(immHead)
                    elif rv: bfHead, adHead, immHead = rv.pop()
                    else:
                        bfHead = domain.unit()
                        adHead = theIdentity
                elif adHead is aRight and ad is aRight:
                    immHead += imm
                    if immHead: bfHead = domain.right(immHead)
                    elif rv: bfHead, adHead, immHead = rv.pop()
                    else:
                        bfHead = domain.unit()
                        adHead = theIdentity
                else:
                    rv.append((bfHead, adHead, immHead))
                    bfHead, adHead, immHead = bf, ad, imm
            rv.append((bfHead, adHead, immHead))
            return rv
        def plus(self, i): return [(domain.plus(i), anAdd, i)]
        def right(self, i): return [(domain.right(i), aRight, i)]
        # Loopish pattern recognition.
        def loop(self, bfs):
            if len(bfs) == 1:
                bf, ad, imm = bfs[0]
                if ad is anAdd and imm in (1, -1):
                    return [(domain.zero(), aZero, 0)]
            elif len(bfs) == 4:
                if (isConstAdd(bfs[0], -1) and
                    bfs[2][1] is anAdd and
                    oppositeShifts(bfs[1], bfs[3])):
                    return [(domain.scalemove(bfs[1][2], bfs[2][2]), aLoop, 0)]
                if (isConstAdd(bfs[3], -1) and
                    bfs[1][1] is anAdd and
                    oppositeShifts(bfs[0], bfs[2])):
                    return [(domain.scalemove(bfs[0][2], bfs[1][2]), aLoop, 0)]
            elif len(bfs) == 6:
                if (isConstAdd(bfs[0], -1) and
                    bfs[2][1] is bfs[4][1] is anAdd and
                    oppositeShifts2(bfs[1], bfs[3], bfs[5])):
                    return [(domain.scalemove2(bfs[1][2], bfs[2][2],
                                               bfs[1][2] + bfs[3][2],
                                               bfs[4][2]), aLoop, 0)]
                if (isConstAdd(bfs[5], -1) and
                    bfs[1][1] is bfs[3][1] is anAdd and
                    oppositeShifts2(bfs[0], bfs[2], bfs[4])):
                    return [(domain.scalemove2(bfs[0][2], bfs[1][2],
                                               bfs[0][2] + bfs[2][2],
                                               bfs[3][2]), aLoop, 0)]
            return [(domain.loop(stripDomain(bfs)), aLoop, 0)]
        def input(self): return [(domain.input(), meh, 0)]
        def output(self): return [(domain.output(), meh, 0)]
    return Peephole, stripDomain

AsStr, finishStr = makePeephole(AsStr)
AsOps, finishOps = makePeephole(AsOps)

def propagate(op):
    """Transform Op tree to use pointer propagation (offset-based ops)."""
    if isinstance(op, Seq):
        result = []
        p = 0
        chunk = []
        for child in op.ops:
            if isinstance(child, Shift): p += child.width
            elif isinstance(child, Add): chunk.append(AddAt(p, child.imm))
            elif isinstance(child, _Input): chunk.append(InputAt(p))
            elif isinstance(child, _Output): chunk.append(OutputAt(p))
            elif isinstance(child, _Zero): chunk.append(ZeroAt(p))
            elif isinstance(child, ZeroScaleAdd):
                chunk.append(ZeroScaleAddAt(p, p + child.offset, child.scale))
            elif isinstance(child, ZeroScaleAdd2):
                chunk.append(ZeroScaleAdd2At(p, p + child.offset1, child.scale1,
                                             p + child.offset2, child.scale2))
            elif isinstance(child, Loop):
                if chunk or p:
                    result.append(PropSeq(chunk[:], p))
                    chunk = []
                    p = 0
                result.append(Loop(propagate(child.op)))
            else:
                if chunk or p:
                    result.append(PropSeq(chunk[:], p))
                    chunk = []
                    p = 0
                result.append(propagate(child))
        if chunk or p: result.append(PropSeq(chunk[:], p))
        if not result: return Shift(0)
        elif len(result) == 1: return result[0]
        else: return Seq(result[:])
    elif isinstance(op, Loop): return Loop(propagate(op.op))
    else: return op

@specialize.argtype(1)
def parse(s, domain):
    ops = [domain.unit()]
    i = 0

    # Skip initial comment-loops; this is easier than adding a special case to
    # the optimizers for non-obvious reasons.
    while i < len(s) and s[i] == '[':
        depth = 1
        i += 1
        while i < len(s) and depth:
            if s[i] == '[': depth += 1
            elif s[i] == ']': depth -= 1
            i += 1

    while i < len(s):
        char = s[i]
        if char == '+': ops[-1] = domain.join(ops[-1], domain.plus(1))
        elif char == '-': ops[-1] = domain.join(ops[-1], domain.plus(-1))
        elif char == '<': ops[-1] = domain.join(ops[-1], domain.right(-1))
        elif char == '>': ops[-1] = domain.join(ops[-1], domain.right(1))
        elif char == ',': ops[-1] = domain.join(ops[-1], domain.input())
        elif char == '.': ops[-1] = domain.join(ops[-1], domain.output())
        elif char == '[': ops.append(domain.unit())
        elif char == ']':
            loop = domain.loop(ops.pop())
            ops[-1] = domain.join(ops[-1], loop)
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
        print finishStr(parse(text, AsStr()))
        return 0
    tape = bytearray("\x00" * cells)
    propagate(finishOps(parse(text, AsOps()))).runOn(tape, 0)
    return 0

def target(*args): return entryPoint, None

def jitpolicy(driver): return JitPolicy()

if __name__ == "__main__": sys.exit(entryPoint(sys.argv))
