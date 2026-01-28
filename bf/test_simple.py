#!/usr/bin/env python
# Quick syntax check for bf.py
import sys
import ast

try:
    with open('bf.py') as f:
        code = f.read()
    compile(code, 'bf.py', 'exec')
    print "SUCCESS: bf.py compiles without syntax errors"
    print "Lines:", len(code.splitlines())
except SyntaxError as e:
    print "SYNTAX ERROR:", e
    sys.exit(1)
