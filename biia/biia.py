# https://esolangs.org/wiki/But_Is_It_Art%3F

import sys

SP = ord(' ')

def maxList(l):
    rv = l[0]
    for x in l:
        if x > rv: rv = x
    return rv

def anyList(l):
    for x in l:
        if x: return True
    return False

class Canvas(object):
    def __init__(self, arr, h, w):
        self.arr = arr
        self.h = h
        self.w = w

    def at(self, i, j): return self.arr[j + i * self.w]
    def set(self, i, j, c): self.arr[j + i * self.w] = c

    def asLines(self):
        return "\n".join(["".join([chr(self.at(i, j))
                                   for j in range(self.w)])
                          for i in range(self.h)])

    def isFull(self):
        return not anyList([self.arr[i] == SP for i in range(self.h * self.w)])
    def canStart(self): return self.arr[0] != SP

    def interior(self):
        maxh = self.h
        maxw = self.w
        for i in range(self.h):
            for j in range(self.w):
                if self.at(i, j) == SP:
                    maxh = min(maxh, i)
                    maxw = min(maxw, j)
        return maxh, maxw

    def fit(self, tile, x, y):
        for i in range(x, min(self.h, x + tile.h)):
            for j in range(y, min(self.w, y + tile.w)):
                if self.at(i, j) != SP and tile.at(x - i, y - j) != SP:
                    return None
        rv = blank(max(self.h, x + tile.h), max(self.w, y + tile.w))
        rv.blit(self, 0, 0)
        rv.blit(tile, x, y)
        return rv

    def blit(self, tile, x, y):
        for i in range(tile.h):
            for j in range(tile.w):
                self.set(x + i, y + j, tile.at(i, j))

def blank(h, w): return Canvas(bytearray(" " * (w * h)), h, w)

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
            if c != SP: rv.append(makeTile(arr, i, j))
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
        if arr.at(i, j) == SP: continue
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
        arr.set(i, j, SP)
    return sprite

def applyTiles(boards, tiles):
    rv = []
    for board in boards:
        maxx, maxy = board.interior()
        for tile in tiles:
            for x in range(maxx):
                candidate = board.fit(tile, x, maxy + 1)
                if candidate is None: continue
                rv.append(candidate)
            for y in range(maxy):
                candidate = board.fit(tile, maxx + 1, y)
                if candidate is None: continue
                rv.append(candidate)
            candidate = board.fit(tile, maxx + 1, maxy + 1)
            if candidate is None: continue
            rv.append(candidate)
    return rv

def main(argv):
    if len(argv) != 2:
        print "Usage:", argv[0], "<tiles.txt>"
        return 1
    with open(argv[1], "rb") as handle: tiles = frame(handle.read())
    for tile in tiles:
        print "Got tile: height", tile.h, "width", tile.w
        print tile.asLines()
    boards = [tile for tile in tiles if tile.canStart()]
    gen = 0
    while len(boards):
        gen += 1
        print "Generation:", gen, "Live boards:", len(boards)
        for board in boards:
            if board.isFull():
                print "Found a complete board:"
                print board.asLines()
                return 0
        newBoards = applyTiles(boards, tiles)
        if not len(newBoards):
            print "Ran out of boards; previous generation:"
            for board in boards: print board.asLines()
        if gen >= 5: break
        boards = newBoards
    print "No more viable boards to search!"
    return 1

def target(*args): return main, None

if __name__ == "__main__": sys.exit(main(sys.argv))
