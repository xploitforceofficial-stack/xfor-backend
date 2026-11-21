"""Reference FSE decode of the zstd huffman weight stream, to diff against ours.

Inputs are taken verbatim from the debug line the Luau decoder prints, so the
only thing being compared is the decode itself.

Reference: FSE_buildDTable + FSE_decompress_usingDTable from the zstd format
specification.
"""
import sys

FIRST, LAST = 17, 62
TABLE_LOG = 5
NORM = {0: 11, 1: 5, 2: 5, 3: 4, 4: 4, 5: 2, 6: 1}

def highbit(v: int) -> int:
    return v.bit_length() - 1

def build_dtable(norm, table_log):
    size = 1 << table_log
    high_threshold = size - 1
    sym_next = {s: (1 if c == -1 else c) for s, c in norm.items()}
    sym = {}
    step = (size >> 1) + (size >> 3) + 3
    mask = size - 1
    pos = 0

    for s, c in norm.items():
        if c == -1:
            sym[high_threshold] = s
            high_threshold -= 1
    for s, c in norm.items():
        if c > 0:
            for _ in range(c):
                sym[pos] = s
                pos = (pos + step) & mask
                while pos > high_threshold:
                    pos = (pos + step) & mask
    assert pos == 0, "spread left holes"
    table = {}
    for u in range(size):
        s = sym[u]
        ns = sym_next[s]
        sym_next[s] = ns + 1
        nb = table_log - highbit(ns)
        table[u] = (s, (ns << nb) - size, nb)
    return table

class Rev:
    """Backwards bit reader, mirroring env/zstd.luau's newRev/revRead."""

    def __init__(self, data, first, last):
        self.d, self.first, self.bi = data, first, last
        lb = data[last]
        hb = 7
        while not (lb >> hb) & 1:
            hb -= 1
        self.bb = hb
        self.over = False

    def peek(self, n):

        if n == 0:
            return 0
        bi, bb = self.bi, self.bb
        v, got = 0, 0
        while got < n:
            take = bb
            need = n - got
            if take > need:
                take = need
            if take > 0:
                b = self.d[bi] if 0 <= bi < len(self.d) else 0

                v = (v << take) | ((b >> (bb - take)) & ((1 << take) - 1))
                got += take
                bb = bb - take
            if bb == 0:
                bi -= 1
                bb = 8
        return v

    def skip(self, n):
        left = n
        while left > 0:
            if self.bb == 0:
                self.bi -= 1
                self.bb = 8
            take = self.bb
            if take > left:
                take = left
            self.bb -= take
            left -= take
        if self.bi < self.first:
            self.over = True

    def read(self, n):
        v = self.peek(n)
        self.skip(n)
        return v

def decode(data):
    tbl = build_dtable(NORM, TABLE_LOG)
    rst = Rev(data, FIRST, LAST)
    s1 = rst.read(TABLE_LOG)
    s2 = rst.read(TABLE_LOG)
    weights = []
    while True:
        e1 = tbl[s1]
        weights.append(e1[0])
        s1 = e1[1] + rst.read(e1[2])
        if rst.over:
            weights.append(tbl[s2][0])
            break
        e2 = tbl[s2]
        weights.append(e2[0])
        s2 = e2[1] + rst.read(e2[2])
        if rst.over:
            weights.append(tbl[s1][0])
            break
    return weights

def main():
    data = open(sys.argv[1], "rb").read()
    w = decode(data)
    total = sum(2 ** (x - 1) for x in w if x and x > 0)
    table_log = highbit(total) + 1 if total else 0
    left = (1 << table_log) - total if total else 0
    print("reference weights:", len(w))
    print("total=%d tableLog=%d left=%d left_is_pow2=%s"
          % (total, table_log, left, bool(left) and (left & (left - 1)) == 0))
    print("weights:", ",".join(str(x) for x in w))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
