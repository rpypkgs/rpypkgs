# BF interpreter
# Includes concepts from (c) 2011 Andrew Brown
# Major rewrite          (c) 2024 Corbin Simpson

import os
import sys

from rpython.jit.codewriter.policy import JitPolicy
from rpython.rlib.jit import JitDriver, purefunction

def opEq(ops1, ops2):
    if len(ops1) != len(ops2): return False
    for i, op in enumerate(ops1):
        if op is not ops2[i]: return False
    return True

def printableProgram(pc, loop): return loop.ops[pc].asStr()
jitdriver = JitDriver(greens=['pc', 'loop'], reds=['position', 'tape'],
                      get_printable_location=printableProgram)

class Op(object):
    _immutable_fields_ = "width", "imm"

class _Input(Op):
    def asStr(self): return ','
    def runOn(self, tape, position):
        tape[position] = ord(os.read(0, 1)[0])
        return position
Input = _Input()
class _Output(Op):
    def asStr(self): return '.'
    def runOn(self, tape, position):
        os.write(1, chr(tape[position]))
        return position
Output = _Output()
class Add(Op):
    _immutable_fields_ = "imm",
    def __init__(self, imm): self.imm = imm
    def asStr(self): return "add(%d)" % self.imm
    def runOn(self, tape, position):
        tape[position] += self.imm
        return position
addCache = {}
def add(imm):
    if imm not in addCache: addCache[imm] = Add(imm)
    return addCache[imm]
Inc = add(1)
Dec = add(-1)
class Shift(Op):
    _immutable_fields_ = "width",
    def __init__(self, width): self.width = width
    def asStr(self): return "shift(%d)" % self.width
    def runOn(self, tape, position): return position + self.width
shiftCache = {}
def shift(width):
    if width not in shiftCache: shiftCache[width] = Shift(width)
    return shiftCache[width]
Left = shift(-1)
Right = shift(1)
class _Zero(Op):
    def asStr(self): return "0"
    def runOn(self, tape, position):
        tape[position] = 0
        return position
Zero = _Zero()
class ZeroScaleAdd(Op):
    _immutable_fields_ = "offset", "scale"
    def __init__(self, offset, scale):
        self.offset = offset
        self.scale = scale
    def asStr(self): return "0scaleadd(%d, %d)" % (self.scale, self.offset)
    def runOn(self, tape, position):
        tape[position + self.offset] += tape[position] * self.scale
        tape[position] = 0
        return position
scaleAddCache = {}
def scaleAdd(offset, scale):
    if (offset, scale) not in scaleAddCache:
        scaleAddCache[offset, scale] = ZeroScaleAdd(offset, scale)
    return scaleAddCache[offset, scale]
class ZeroScaleAdd2(Op):
    _immutable_fields_ = "offset1", "scale1", "offset2", "scale2"
    def __init__(self, offset1, scale1, offset2, scale2):
        self.offset1 = offset1
        self.scale1 = scale1
        self.offset2 = offset2
        self.scale2 = scale2
    def asStr(self):
        return "0scaleadd2(%d, %d; %d, %d)" % (self.scale1, self.offset1, self.scale2, self.offset2)
    def runOn(self, tape, position):
        tape[position + self.offset1] += tape[position] * self.scale1
        tape[position + self.offset2] += tape[position] * self.scale2
        tape[position] = 0
        return position
scaleAdd2Cache = {}
def scaleAdd2(offset1, scale1, offset2, scale2):
    k = offset1, scale1, offset2, scale2
    if k not in scaleAdd2Cache:
        scaleAdd2Cache[k] = ZeroScaleAdd2(offset1, scale1, offset2, scale2)
    return scaleAdd2Cache[k]
class Loop(Op):
    _immutable_fields_ = "ops[*]",
    def __init__(self, ops): self.ops = ops
    def asStr(self):
        return '[' + '; '.join([op.asStr() for op in self.ops]) + ']'
    def runOn(self, tape, position):
        while tape[position]:
            i = 0
            while i < len(self.ops):
                jitdriver.jit_merge_point(pc=i, loop=self,
                                          position=position, tape=tape)
                position = self.ops[i].runOn(tape, position)
                i += 1
        return position
loopCache = []
def loop(ops):
    for l in loopCache:
        if opEq(ops, l.ops): return l
    rv = Loop(ops)
    loopCache.append(rv)
    return rv

def peep(ops):
    if not ops: return ops
    rv = []
    temp = ops[0]
    for op in ops[1:]:
        if isinstance(temp, Loop) and isinstance(op, Loop): continue
        elif isinstance(temp, Shift) and isinstance(op, Shift):
            temp = shift(temp.width + op.width)
        elif isinstance(temp, Add) and isinstance(op, Add):
            temp = add(temp.imm + op.imm)
        elif isinstance(temp, Add) and op is Zero: temp = Zero
        else:
            rv.append(temp)
            temp = op
    rv.append(temp)
    return rv

def oppositeShifts(op1, op2):
    if not isinstance(op1, Shift) or not isinstance(op2, Shift): return False
    return op1.width == -op2.width

def oppositeShifts2(op1, op2, op3):
    if not isinstance(op1, Shift) or not isinstance(op2, Shift) or not isinstance(op3, Shift):
        return False
    return op1.width + op2.width + op3.width == 0

def isConstAdd(op, imm): return isinstance(op, Add) and op.imm == imm

def loopish(ops):
    if len(ops) == 1 and isConstAdd(ops[0], -1):
        return Zero
    elif (len(ops) == 4 and
          isConstAdd(ops[0], -1) and isinstance(ops[2], Add) and
          oppositeShifts(ops[1], ops[3])):
        return scaleAdd(ops[1].width, ops[2].imm)
    elif (len(ops) == 4 and
          isConstAdd(ops[3], -1) and isinstance(ops[1], Add) and
          oppositeShifts(ops[0], ops[2])):
        return scaleAdd(ops[0].width, ops[1].imm)
    elif (len(ops) == 6 and
          isConstAdd(ops[0], -1) and isinstance(ops[2], Add) and isinstance(ops[4], Add) and
          oppositeShifts2(ops[1], ops[3], ops[5])):
        return scaleAdd2(ops[1].width, ops[2].imm, ops[1].width + ops[3].width, ops[4].imm)
    elif (len(ops) == 6 and
          isConstAdd(ops[5], -1) and isinstance(ops[1], Add) and isinstance(ops[3], Add) and
          oppositeShifts2(ops[0], ops[2], ops[4])):
        return scaleAdd2(ops[0].width, ops[1].imm, ops[0].width + ops[2].width, ops[3].imm)
    return loop(ops[:])

parseTable = {
    ',': Input, '.': Output,
    '+': Inc, '-': Dec,
    '<': Left, '>': Right,
}
def parse(s):
    ops = [[]]

    for char in s:
        if char in parseTable: ops[-1].append(parseTable[char])
        elif char == '[': ops.append([])
        elif char == ']':
            loop = loopish(peep(ops.pop()))
            ops[-1].append(loop)

    return peep(ops.pop())

def entryPoint(argv):
    if len(argv) < 2 or "-h" in argv:
        print "Usage: bf [-c <number of cells>] [-h] [-d] <program.bf>"
        print "To dump an AST: bf -d <program.bf>"
        return 1
    cells = 30000
    if argv[1] == "-c":
        cells = int(argv[2])
        path = argv[3]
    elif argv[1] == "-d": path = argv[2]
    else: path = argv[1]
    with open(path) as handle: program = parse(handle.read())
    if "-d" in argv:
        print "AST:", "; ".join([op.asStr() for op in program])
        return 0
    tape = bytearray("\x00" * cells)
    position = 0
    for op in program: position = op.runOn(tape, position)
    return 0

def target(*args): return entryPoint, None

def jitpolicy(driver): return JitPolicy()

if __name__ == "__main__":
    entryPoint(sys.argv)
