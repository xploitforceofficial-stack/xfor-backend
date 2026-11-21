"""Recover the Luraph v14 program-buffer record format.

Two independent lines of evidence fix the format, and neither is a guess:

* The read log. Every `buffer.read*` the stage performs on the program buffer
  is recorded, and the stream never steps backwards. Measured directly: all 326
  `readu16` are preceded by the byte 182, all 140 `readi16` by 157, all 31
  `readi32` by 88, both `readf32` by 33, and the `readu32` stream splits into
  13 records of two words behind 74 and 13 single words behind 215. So those
  seven tags have exactly one payload width each.

* stage147.lua. `nY` is the deserializer: it reads a u8 tag and picks a reader
  by range - `i>215` goes to `kY` (u8 or string), `157<i<=215` to `CY`/`FY`
  (u16 up to 182, u32 above), `i<=157` to an i16, `i<=74` to `pY` (74 is a
  pair of u32, the rest f32), `i<=88` to `lY` (i32), and 89 returns a constant
  with no read at all.

The parse is only accepted if it consumes every read in the log.
"""
import re
import glob
import os
import collections
import json
import sys

WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
PAT = re.compile(r"^(read\w+) off=(-?\d+)(?: =\s?(.*))?$")
HEADER_READS = 4
SZ = {"readu8": 1, "reads8": 1, "readu16": 2, "readi16": 2,
      "readu32": 4, "readi32": 4, "readf32": 4, "readf64": 8}

def load():
    files = [f for f in sorted(glob.glob(os.path.join(WORK, "reads.log.*")))
             if re.search(r"reads\.log\.\d+$", f)]
    rows = []
    for path in files:
        for line in open(path, encoding="utf8", errors="replace"):
            line = line.rstrip("\r\n")
            if not line.strip() or line.startswith("#") or line.startswith("CALLER"):
                continue
            m = PAT.match(line)
            if m:
                rows.append((m.group(1), int(m.group(2)), m.group(3)))
    rows.sort(key=lambda r: r[1])
    return rows

TYPED_TAGS = {
    33:  ["f32"],
    74:  ["u32x2"],
    88:  ["i32"],
    89:  ["none"],
    157: ["i16"],
    182: ["u16"],
    215: ["u32"],
    251: ["str", "u8", "none"],
}

GENERIC = ["u8", "str", "none", "i16", "u16", "u32", "i32", "f32", "bulk"]

def shapes_for(tag):
    """Payload shapes a tag may carry, most specific first."""
    if tag in TYPED_TAGS:
        return TYPED_TAGS[tag] + ["bulk"]
    if 216 <= tag <= 255:
        return ["u8", "str", "none", "bulk"]
    return list(GENERIC)

def inflate(rows):
    """Insert a synthetic `bulk` read wherever the stage skipped bytes.

    A long string is lifted out of the program buffer with `buffer.copy`
    instead of `buffer.readstring`, so those bytes never show up as a read.
    Marking the hole keeps the record parse honest about why the offset jumps.
    """
    out = []
    for k, (fn, off, val) in enumerate(rows):
        if out:
            pfn, poff, _ = out[-1]
            if pfn == "bulk":
                pend = poff
            elif pfn == "readstring":
                pend = None
            else:
                pend = poff + SZ[pfn]
            if pend is not None and off > pend:
                out.append(("bulk", pend, str(off - pend)))
        out.append((fn, off, val))
    return out

def build(rows, i, shape):
    """Try to read `shape` starting after the tag at i. Returns next index."""
    j = i + 1
    n = len(rows)
    if shape == "none":
        return j
    if shape == "bulk":
        if j < n and rows[j][0] == "bulk":
            return j + 1
        return None
    if shape == "str":
        if j + 1 < n and rows[j][0] == "readu8" and rows[j + 1][0] == "readstring":
            return j + 2
        return None
    want = {"u8": "readu8", "u16": "readu16", "i16": "readi16",
            "u32": "readu32", "u32x2": "readu32", "i32": "readi32",
            "f32": "readf32", "f64": "readf64"}[shape]
    if j >= n or rows[j][0] != want:
        return None
    if shape == "u32x2":
        if j + 1 >= n or rows[j + 1][0] != "readu32":
            return None
        return j + 2
    return j + 1

def solve(rows, start=0):
    n = len(rows)
    ok = [False] * (n + 1)
    choice = [None] * (n + 1)
    ok[n] = True
    for i in range(n - 1, start - 1, -1):
        if rows[i][0] != "readu8":
            continue
        try:
            tag = int(rows[i][2])
        except (TypeError, ValueError):
            continue
        for shape in shapes_for(tag):
            nxt = build(rows, i, shape)
            if nxt is not None and ok[nxt]:
                choice[i] = (shape, nxt)
                ok[i] = True
                break
    if not ok[start]:
        return None
    recs = []
    i = start
    while i < n:
        shape, nxt = choice[i]
        tag = int(rows[i][2])
        if shape == "str":
            payload = [("str", rows[i + 2][2])]
        elif shape == "u32x2":
            payload = [("u32", rows[i + 1][2]), ("u32", rows[i + 2][2])]
        elif shape == "none":
            payload = []
        elif shape == "bulk":
            payload = [("bulk", rows[i + 1][2])]
        else:
            payload = [(shape, rows[i + 1][2])]
        recs.append((tag, rows[i][1], shape, payload))
        i = nxt
    return recs

def diagnose(rows, start=0):
    """Walk forward with the range rules and report the first dead end."""
    i = start
    n = len(rows)
    steps = 0
    while i < n:
        if rows[i][0] != "readu8":
            return ("not-a-tag", i, steps, rows[max(0, i - 5):i + 4])
        try:
            tag = int(rows[i][2])
        except (TypeError, ValueError):
            return ("bad-tag", i, steps, rows[max(0, i - 5):i + 4])
        moved = None
        for shape in shapes_for(tag):
            nxt = build(rows, i, shape)
            if nxt is not None:
                moved = (shape, nxt)
                break
        if moved is None:
            return ("no-shape-for-tag", i, steps, rows[max(0, i - 5):i + 4])
        i = moved[1]
        steps += 1
    return None

def frontier(rows, start=0):
    """Where the range rules stop agreeing with the log."""
    n = len(rows)
    ok = [False] * (n + 1)
    ok[n] = True
    for i in range(n - 1, start - 1, -1):
        if rows[i][0] != "readu8":
            continue
        try:
            tag = int(rows[i][2])
        except (TypeError, ValueError):
            continue
        for shape in shapes_for(tag):
            nxt = build(rows, i, shape)
            if nxt is not None and ok[nxt]:
                ok[i] = True
                break

    pre = [False] * (n + 1)
    pre[start] = True
    for i in range(start, n + 1):
        if not pre[i] or i >= n or rows[i][0] != "readu8":
            continue
        try:
            tag = int(rows[i][2])
        except (TypeError, ValueError):
            continue
        for shape in shapes_for(tag):
            nxt = build(rows, i, shape)
            if nxt is not None:
                pre[nxt] = True
    far = max((i for i in range(start, n + 1) if pre[i]), default=None)
    print("forward parse reaches index: %s of %s (ok=%s)"
          % (far, n, ok[far] if far is not None else None))
    if far is not None and far < n:
        for r in rows[max(0, far - 8):min(n, far + 8)]:
            print("     ", r)
    return far, ok, pre

def main():
    rows = inflate(load())
    print("reads+bulk: %d" % len(rows))
    hi, ok, reachable = frontier(rows, HEADER_READS)
    print("forward-reachable at that index: %s"
          % (reachable[hi] if hi is not None else None))
    if hi is None or hi < len(rows):
        print("range rules do not cover the whole log")
        return
    recs = None
    used = 0
    for start in (0, HEADER_READS):
        recs = solve(rows, start)
        if recs is not None:
            used = start
            break
    if recs is None:
        print("NO PARSE with the range rules")
        return
    print("records: %d  start=%d  (consumed every read)" % (len(recs), used))

    table = collections.defaultdict(collections.Counter)
    for tag, off, shape, _ in recs:
        table[tag][shape] += 1
    print()
    print("tag -> shape:")
    for tag in sorted(table):
        print("   tag %3d (0x%02x)  %s" % (tag, tag, dict(table[tag])))
    print()
    print("shapes:", dict(collections.Counter(s for _, _, s, _ in recs)))

    strings = [p[1] for _, _, _, pl in recs for p in pl if p[0] == "str"]
    print("strings:", len(strings))
    for s in strings[:40]:
        print("   %r" % (s[:100],))

    out = os.path.join(WORK, "format.json")
    with open(out, "w", encoding="utf8") as fh:
        json.dump([{"tag": t, "off": o, "shape": s, "p": p}
                   for t, o, s, p in recs], fh)
    print("wrote %s" % out)

if __name__ == "__main__":
    main()
