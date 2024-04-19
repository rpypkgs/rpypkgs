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

class Op(object): pass

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
class _Inc(Op):
    def asStr(self): return '+'
    def runOn(self, tape, position):
        tape[position] += 1
        return position
Inc = _Inc()
class _Dec(Op):
    def asStr(self): return '-'
    def runOn(self, tape, position):
        tape[position] -= 1
        return position
Dec = _Dec()
class _Left(Op):
    def asStr(self): return '<'
    def runOn(self, tape, position):
        if position == 0: raise Exception("Stack underflow")
        return position - 1
Left = _Left()
class _Right(Op):
    def asStr(self): return '>'
    def runOn(self, tape, position):
        if len(tape) <= position: tape.extend([0] * 1000)
        return position + 1
Right = _Right()
class Loop(Op):
    _immutable_fields_ = "ops[*]",
    def __init__(self, ops): self.ops = ops
    def asStr(self):
        return '[' + ''.join([op.asStr() for op in self.ops]) + ']'
    def runOn(self, tape, position):
        while tape[position]:
            jitdriver.jit_merge_point(program=self,
                                      position=position, tape=tape)
            for op in self.ops: position = op.runOn(tape, position)
        return position

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
            loop = Loop(ops.pop()[:])
            ops[-1].append(loop)
    
    return ops.pop()

def entryPoint(argv):
    if len(argv) < 2:
        print "You must supply a filename"
        return 1
    with open(argv[1]) as handle: program = parse(handle.read())
    tape = [0] * 30000
    position = 0
    for op in program: position = op.runOn(tape, position)
    return 0

def target(*args): return entryPoint, None
    
def jitpolicy(driver): return JitPolicy()

if __name__ == "__main__":
    entryPoint(sys.argv)
