# BF interpreter
# Includes concepts from (c) 2011 Andrew Brown
# Major rewrite          (c) 2024 Corbin Simpson

import os
import sys

from rpython.jit.codewriter.policy import JitPolicy
from rpython.rlib.jit import JitDriver, purefunction

def printableProgram(program): return program.asStr()

jitdriver = JitDriver(greens=['program'], reds=['position', 'tape'],
                      get_printable_location=printableProgram)

class Op(object):
    _immutable_fields_ = "width",

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
Inc = Add(1)
Dec = Add(-1)
class Shift(Op):
    _immutable_fields_ = "width",
    def __init__(self, width): self.width = width
    def asStr(self): return "shift(%d)" % self.width
    def runOn(self, tape, position): return position + self.width
Left = Shift(-1)
Right = Shift(1)
class _Zero(Op):
    def asStr(self): return "0"
    def runOn(self, tape, position):
        tape[position] = 0
        return position
Zero = _Zero()
class ZeroAdd(Op):
    _immutable_fields_ = "offset",
    def __init__(self, offset): self.offset = offset
    def asStr(self): return "zeroadd(%d)" % self.offset
    def runOn(self, tape, position):
        tape[position + self.offset] += tape[position]
        tape[position] = 0
        return position
class Loop(Op):
    _immutable_fields_ = "ops[*]",
    def __init__(self, ops): self.ops = ops
    def asStr(self):
        return '[' + '; '.join([op.asStr() for op in self.ops]) + ']'
    def runOn(self, tape, position):
        while tape[position]:
            jitdriver.jit_merge_point(program=self,
                                      position=position, tape=tape)
            for op in self.ops: position = op.runOn(tape, position)
        return position

def peep(ops):
    rv = []
    temp = ops[0]
    for op in ops[1:]:
        if isinstance(temp, Shift) and isinstance(op, Shift):
            temp = Shift(temp.width + op.width)
        elif isinstance(temp, Add) and isinstance(op, Add):
            temp = Add(temp.imm + op.imm)
        else:
            rv.append(temp)
            temp = op
    rv.append(temp)
    return rv

def oppositeShifts(op1, op2):
    if not isinstance(op1, Shift) or not isinstance(op2, Shift): return False
    return op1.width == -op2.width

def isConstAdd(op, imm): return isinstance(op, Add) and op.imm == imm

def loopish(ops):
    if len(ops) == 1 and isConstAdd(ops[0], -1):
        return Zero
    elif (len(ops) == 4 and
          isConstAdd(ops[0], -1) and isConstAdd(ops[2], 1) and
          oppositeShifts(ops[1], ops[3])):
        return ZeroAdd(ops[1].width)
    return Loop(ops[:])

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
        print "Usage: bf [-c <number of cells>] [-h] <program.bf>"
        return 1
    cells = 30000
    if argv[1] == "-c":
        cells = int(argv[2])
        path = argv[3]
    else: path = argv[1]
    with open(path) as handle: program = parse(handle.read())
    tape = [0] * cells
    position = 0
    for op in program: position = op.runOn(tape, position)
    return 0

def target(*args): return entryPoint, None
    
def jitpolicy(driver): return JitPolicy()

if __name__ == "__main__":
    entryPoint(sys.argv)