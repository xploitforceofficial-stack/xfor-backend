"""Reference decode of a zstd frame's literals, checked against known output.

For a compressed Luau stage the first Regenerated_Size bytes of the output ARE
the literals, so a correct decode can be verified directly against the expected
decompressed bytes. Everything here follows the format spec:

  Literals_Section_Header (Size_Format 2 -> 4 bytes)
  Huffman_Tree_Description: iSize byte; <128 means FSE-compressed weights
  Jump_Table for 4 streams: 3 x 2-byte LE sizes, 4th deduced
  4 independent backward bitstreams

Usage: python tools/lit_ref.py <frame.bin> <expected.bin>
"""
import sys

sys.path.insert(0, "tools")
from fse_ref import Rev, build_dtable, highbit

def read_ncount(data, p, max_symbol, max_log):
    """FSE_readNCount: forward bit reader."""
    class Fwd:
        def __init__(self, d, p):
            self.d, self.p, self.bit = d, p, 0

        def read(self, n):
            v = 0
            for i in range(n):
                byte = self.d[self.p + (self.bit >> 3)]
                bit = (byte >> (self.bit & 7)) & 1
                v |= bit << i
                self.bit += 1
            self.p += (self.bit >> 3)
            return v

    st = Fwd(data, p)
    table_log = st.read(4) + 5
    if table_log > max_log:
        return None, None, None
    remaining = (1 << table_log) + 1
    threshold = 1 << table_log
    nb_bits = table_log + 1
    charnum = 0
    previous0 = False
    norm = {}
    while remaining > 1 and charnum <= max_symbol:
        if previous0:
            n0 = charnum
            while st.read(16) == 0xFFFF:
                n0 += 24
            while st.read(2) == 3:
                n0 += 3
            n0 += st.read(2)
            if n0 > max_symbol + 1:
                return None, None, None
            while charnum < n0:
                norm[charnum] = 0
                charnum += 1
            previous0 = False
            continue
        mx = (2 * threshold - 1) - remaining
        val = st.read(nb_bits - 1)
        if (val & (threshold - 1)) < mx:
            pass
        else:
            val = (val & (threshold - 1)) + st.read(1) * threshold
        proba = val - mx
        if proba == threshold - 1:
            norm[charnum] = 1
            remaining -= 1
        elif proba & (threshold - 1) == threshold - 1:
            pass
        else:
            norm[charnum] = proba >> nb_bits
            remaining -= norm[charnum]
        previous0 = norm[charnum] == 0
        charnum += 1
        while remaining < threshold:
            nb_bits -= 1
            threshold >>= 1
    norm[max_symbol + 1] = 0
    return norm, charnum - 1, st.p + (0 if previous0 else 0)

def build_huff(weights, nb_symbols):
    total = 0
    for i in range(1, nb_symbols + 1):
        w = weights[i]
        if w and w > 0:
            total += 1 << (w - 1)
    table_log = highbit(total) + 1
    rest = (1 << table_log) - total
    if rest <= 0 or (rest & (rest - 1)) != 0:
        return None, None
    while len(weights) < nb_symbols + 2:
        weights.append(0)
    weights[nb_symbols + 1] = highbit(rest) + 1
    nb_symbols += 1
    rank_count = {}
    for i in range(1, nb_symbols + 1):
        w = weights[i]
        rank_count[w] = rank_count.get(w, 0) + 1
    rank_start = {}
    nxt = 0
    for w in range(1, table_log + 1):
        rank_start[w] = nxt
        nxt += rank_count.get(w, 0) * (1 << (w - 1))
    if nxt != (1 << table_log):
        return None, None
    dt = [None] * (1 << table_log)
    for i in range(1, nb_symbols + 1):
        w = weights[i]
        if not w or w <= 0:
            continue
        length = 1 << (w - 1)
        start = rank_start.get(w)
        if start is None:
            return None, None
        for k in range(start, start + length):
            dt[k] = (i - 1, table_log + 1 - w)
        rank_start[w] = start + length
    return dt, table_log

def main():
    data = open(sys.argv[1], "rb").read()
    expected = open(sys.argv[2], "rb").read()

    p = 4
    fhd = data[p]
    p += 1
    fcs_flag = fhd >> 6
    if not ((fhd >> 5) & 1):
        p += 1
    p += (1, 2, 4, 8)[fcs_flag]
    bh = int.from_bytes(data[p:p + 3], "little")
    p += 3
    btype = (bh >> 1) & 3
    bsize = bh >> 3
    assert btype == 2, "not a compressed block"
    lit_start = p
    b0 = data[p]
    v = int.from_bytes(data[p:p + 4], "little")
    regen = (v >> 4) & 0x3FFF
    comp = (v >> 18) & 0x3FFF
    p += 4
    lit_end = lit_start + comp - 1
    print("block size=%d regen=%d comp=%d lit %d..%d" % (bsize, regen, comp, p, lit_end))

    isize = data[p]
    assert isize < 128, "expected FSE-compressed weights"

    import fse_ref
    weights = [0] + fse_ref.decode(data)
    nw = len(weights) - 1
    dt, table_log = build_huff(weights, nw)
    assert dt, "huffman build failed"
    print("weights=%d tableLog=%d entries=%d" % (nw, table_log, sum(1 for x in dt if x)))

    jt = p + 1 + isize
    s1s = int.from_bytes(data[jt:jt + 2], "little")
    s2s = int.from_bytes(data[jt + 2:jt + 4], "little")
    s3s = int.from_bytes(data[jt + 4:jt + 6], "little")
    s4s = (lit_end - (jt + 6) + 1) - s1s - s2s - s3s
    sizes = [s1s, s2s, s3s, s4s]
    print("stream sizes", sizes, "sum", sum(sizes))
    seg = (regen + 3) // 4
    targets = [seg, seg, seg, regen - 3 * seg]

    out = bytearray()
    sp = jt + 6
    for s in range(4):
        sEnd = sp + sizes[s] - 1
        r = Rev(data, sp, sEnd)
        for _ in range(targets[s]):
            idx = r.peek(table_log)
            e = dt[idx]
            assert e, "code %d outside table" % idx
            r.skip(e[1])
            out.append(e[0])
        sp = sEnd + 1
    want = expected[:regen]
    print("decoded %d literals; match=%s" % (len(out), bytes(out) == want))
    if bytes(out) != want:
        for i, (a, b) in enumerate(zip(out, want)):
            if a != b:
                print("first difference at %d: got %r want %r" % (i, out[i:i + 24], want[i:i + 24]))
                print("got :", bytes(out[i:i + 40]).decode("latin-1"))
                print("want:", want[i:i + 40].decode("latin-1"))
                break
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
