# https://esolangs.org/wiki/But_Is_It_Art%3F

import sys

class Canvas(object):
    def __init__(self, arr, h, w):
        self.arr = arr
        self.h = h
        self.w = w

    def at(self, i, j): return self.arr[j + i * self.w]
    def set(self, i, j, c): self.arr[j + i * self.w] = c

    def asLines(self):
        lines = []
        for i in range(self.h):
            lines.append("".join([chr(self.at(i, j))
                                 for j in range(self.w)]))
        return "\n".join(lines)

def blank(h, w): return Canvas(bytearray(" " * (w * h)), h, w)

def maxList(l):
    rv = l[0]
    for x in l:
        if x > rv: rv = x
    return rv

def frame(s):
    lines = s.split("\n")
    height = len(lines)
    if not height: raise ValueError("invalid tiles")
    width = maxList([len(l) for l in lines])
    if not width: raise ValueError("invalid tiles")
    arr = blank(height, width)
    for i in range(height):
        line = lines[i]
        for j in range(len(line)): arr.set(i, j, ord(line[j]))
    return parse(arr)

def parse(arr):
    rv = []
    i = 0
    while i < arr.h:
        j = 0
        while j < arr.w:
            c = arr.at(i, j)
            if c != ord(' '): rv.append(makeTile(arr, i, j))
            j += 1
        i += 1
    return rv

def makeTile(arr, i, j):
    start = i, j
    mini = maxi = i
    minj = maxj = j
    stack = [start]
    found = {}
    while len(stack):
        i, j = stack.pop()
        if (i, j) in found: continue
        if arr.at(i, j) == ord(' '): continue
        found[i, j] = None
        if i < mini: mini = i
        elif i > maxi: maxi = i
        if j < minj: minj = j
        elif j > maxj: maxj = j
        for di in [-1, 1]:
            di += i
            if 0 <= di < arr.h and 0 <= j < arr.w: stack.append((di, j))
        for dj in [-1, 1]:
            dj += j
            if 0 <= i < arr.h and 0 <= dj < arr.w: stack.append((i, dj))
    sph = maxi + 1 - mini
    spw = maxj + 1 - minj
    sprite = blank(sph, spw)
    for i, j in found.keys():
        sprite.set(i - mini, j - minj, arr.at(i, j))
        arr.set(i, j, ord(' '))
    return sprite

def main(argv):
    if len(argv) != 2:
        print "Usage:", argv[0], "<tiles.txt>"
        return 1
    with open(argv[1], "rb") as handle: tiles = frame(handle.read())
    for tile in tiles:
        print "Got tile: height", tile.h, "width", tile.w
        print tile.asLines()
    return 0

def target(*args): return main, None

if __name__ == "__main__": sys.exit(main(sys.argv))
