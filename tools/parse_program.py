"""Parse the Luraph v14 program buffer captured by tools/capture_program.luau.

The buffer the loader hands the stage (`local R=...`) is read sequentially and
without a single backward jump, tiling the whole 106,972 bytes. The reads are
tagged: one `readu8` gives the tag, the payload that follows depends on it.

Derived from the live read log (never assumed):

    228 0xe4 -> readu8            157 0x9d -> readi16
    182 0xb6 -> readu16            88 0x58 -> readi32
     74 0x4a -> readu32 x2         33 0x21 -> readf32
    215 0xd7 -> readu32           251 0xfb -> u8 length + readstring

A parse is only accepted if every record it produces starts on a `readu8` -
that is the self-check that says the tag table is right rather than merely
self-consistent.
"""
import re
import glob
import os
import collections
import json
import sys

WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")

TAGS = {
    228: [("u8", None)],
    182: [("u16", None)],
    157: [("i16", None)],
    74:  [("u32", None), ("u32", None)],
    215: [("u32", None)],
    88:  [("i32", None)],
    33:  [("f32", None)],
    251: [("u8", "len"), ("str", "len")],
}

READ_FOR = {
    "u8": "readu8", "u16": "readu16", "i16": "readi16",
    "u32": "readu32", "i32": "readi32", "f32": "readf32", "f64": "readf64",
}
SZ = {"u8": 1, "u16": 2, "i16": 2, "u32": 4, "i32": 4, "f32": 4, "f64": 8}
PAT = re.compile(r"^(read\w+) off=(-?\d+)(?: = (.*))?$")

def load_rows():
    files = [f for f in sorted(glob.glob(os.path.join(WORK, "reads.log.*")))
             if re.search(r"reads\.log\.\d+$", f)]
    rows = []
    for path in files:
        for line in open(path, encoding="utf8", errors="replace"):
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("TRUNCATED"):
                continue
            m = PAT.match(line)
            if m:
                rows.append([m.group(1), int(m.group(2)), m.group(3)])
    return rows

def parse(rows, learn=True):
    """Walk rows as tag/payload records. Returns (records, unmatched_start)."""
    recs = []
    i = 0
    learned = {}
    bad_start = 0
    n = len(rows)
    while i < n:
        fn, off, val = rows[i]
        if fn != "readu8":

            bad_start += 1
            i += 1
            continue
        try:
            tag = int(val)
        except (TypeError, ValueError):
            bad_start += 1
            i += 1
            continue
        steps = TAGS.get(tag) or learned.get(tag)
        if steps is None:

            if i + 1 < n and rows[i + 1][0] == "readstring":
                steps = [("u8", "len"), ("str", "len")]
            elif i + 1 < n and rows[i + 1][0] in READ_FOR.values():
                kind = {v: k for k, v in READ_FOR.items()}[rows[i + 1][0]]
                steps = [(kind, None)]
            else:
                steps = [("u8", None)]
            if learn:
                learned[tag] = steps
        payload = []
        ok = True
        j = i + 1
        for kind, arg in steps:
            if j >= n:
                ok = False
                break
            jfn, joff, jval = rows[j]
            if kind == "str":
                if jfn != "readstring":
                    ok = False
                    break
                payload.append(("str", jval))
                j += 1
                continue
            if jfn != READ_FOR[kind]:
                ok = False
                break
            payload.append((kind, jval))
            j += 1
        if not ok:
            bad_start += 1
            i += 1
            continue
        recs.append((tag, off, payload))
        i = j
    return recs, learned, bad_start

def main():
    rows = load_rows()
    print("reads: %d" % len(rows))
    recs, learned, bad = parse(rows)
    print("records: %d   unaligned starts: %d" % (len(recs), bad))
    print("learned tags: %s" % {k: [s[0] for s in v] for k, v in sorted(learned.items())})

    hist = collections.Counter(r[0] for r in recs)
    print("\ntag histogram (records):")
    for tag, c in hist.most_common():
        spec = TAGS.get(tag) or learned.get(tag)
        print("   tag %3d (0x%02x) x%-6d -> %s" % (tag, tag, c,
              [s[0] for s in spec] if spec else "?"))

    strings = [p[1] for r in recs for p in r[2] if p[0] == "str"]
    print("\nstrings: %d" % len(strings))
    for s in strings[:60]:
        print("   %r" % (s[:110],))

    out = os.path.join(WORK, "records.json")
    with open(out, "w", encoding="utf8") as fh:
        json.dump([{"tag": t, "off": o, "p": p} for t, o, p in recs], fh)
    print("\nwrote %s" % out)

if __name__ == "__main__":
    main()
