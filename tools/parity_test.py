"""Check whether the u8 runs in the read log tile as strict (tag, value) pairs.

nY (stage147.lua) reads one u8 tag per constant, then a typed payload. If every
u8 constant is exactly two reads, then between any two typed reads the run of
readu8 must have an even length (plus the string-length byte when a readstring
follows). Parity that holds across 96k reads is proof of the layout.
"""
import re
import glob
import os
import collections

WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
PAT = re.compile(r"^(read\w+) off=(-?\d+)(?: = (.*))?$")

def load():
    files = [f for f in sorted(glob.glob(os.path.join(WORK, "reads.log.*")))
             if re.search(r"reads\.log\.\d+$", f)]
    rows = []
    for path in files:
        for line in open(path, encoding="utf8", errors="replace"):
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("CALLER"):
                continue
            m = PAT.match(line)
            if m:
                rows.append((m.group(1), int(m.group(2)), m.group(3)))
    rows.sort(key=lambda r: r[1])
    return rows

def main():
    rows = load()

    i = 0
    while i < len(rows) and rows[i][1] < 4:
        i += 1

    runs = []
    run = 0
    while i < len(rows):
        fn = rows[i][0]
        if fn == "readu8":
            run += 1
            i += 1
            continue
        runs.append((run, fn))
        run = 0
        i += 1

    odd = collections.Counter()
    odd_examples = []
    for n, nxt in runs:

        eff = n - 1 if nxt == "readstring" else n
        if eff % 2:
            odd[nxt] += 1
            if len(odd_examples) < 12:
                odd_examples.append((n, nxt))
    print("u8 runs:", len(runs))
    print("typed reads seen:", collections.Counter(t for _, t in runs))
    print("ODD runs (breaks the pair theory):", sum(odd.values()))
    print("  by following read:", dict(odd))
    print("  examples (runlen, next):", odd_examples)

    i = 0
    while i < len(rows) and rows[i][1] < 4:
        i += 1
    tags = collections.Counter()
    typed = collections.Counter()
    bad = None
    while i < len(rows):
        fn, off, val = rows[i]
        if fn != "readu8":
            bad = ("not-a-tag", i, rows[max(0, i - 4):i + 4])
            break
        tag = int(val)
        nxt = rows[i + 1] if i + 1 < len(rows) else None
        if nxt is None:
            bad = ("eof-after-tag", i, rows[max(0, i - 4):])
            break
        if nxt[0] == "readu8":
            tags[tag] += 1
            i += 2
        elif nxt[0] == "readstring":

            if i + 2 >= len(rows) or rows[i + 2][0] != "readstring":
                bad = ("string-shape", i, rows[max(0, i - 4):i + 5])
                break
            tags[tag] += 1
            typed["str"] += 1
            i += 3
        else:
            tags[tag] += 1
            typed[nxt[0]] += 1

            i += 2
    print()
    print("strict pair parse records:", sum(tags.values()))
    print("stop:", bad[0] if bad else "END-OF-LOG")
    if bad:
        print("at", bad[1])
        for r in bad[2]:
            print("   ", r)
    print()
    print("tag -> payload, from the strict parse:")

    i = 0
    while i < len(rows) and rows[i][1] < 4:
        i += 1
    table = collections.defaultdict(collections.Counter)
    while i < len(rows) - 1:
        if rows[i][0] != "readu8":
            break
        tag = int(rows[i][1 + 0 - 1] if False else rows[i][2])
        nxt = rows[i + 1]
        if nxt[0] == "readu8":
            table[tag]["u8"] += 1
            i += 2
        elif nxt[0] == "readstring":
            table[tag]["str"] += 1
            i += 3
        else:
            table[tag][nxt[0]] += 1
            i += 2
    for tag in sorted(table):
        print("   tag %3d (0x%02x)  %s" % (tag, tag, dict(table[tag])))

if __name__ == "__main__":
    main()
