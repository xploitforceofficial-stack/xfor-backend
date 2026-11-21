import re
import glob
import os

WORK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "work")
PAT = re.compile(r"^(read\w+) off=(-?\d+)(?: = (.*))?$")

SPEC = {
    228: ["u8"],
    182: ["u16"],
    157: ["i16"],
    74:  ["u32", "u32"],
    215: ["u32"],
    88:  ["i32"],
    33:  ["f32"],
    251: ["len", "str"],
}
FORD = {"u8": "readu8", "u16": "readu16", "i16": "readi16",
        "u32": "readu32", "i32": "readi32", "f32": "readf32",
        "len": "readu8"}

def load():
    files = [f for f in sorted(glob.glob(os.path.join(WORK, "reads.log.*")))
             if re.search(r"reads\.log\.\d+$", f)]
    rows = []
    for path in files:
        for line in open(path, encoding="utf8", errors="replace"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = PAT.match(line)
            if m:
                rows.append((m.group(1), int(m.group(2)), m.group(3)))
    rows.sort(key=lambda r: r[1])
    return rows

def main():
    rows = load()
    print("reads:", len(rows))
    i = 0
    while i < len(rows) and rows[i][1] < 4:
        i += 1
    print("start idx %d -> %s" % (i, rows[i]))
    recs = 0
    unknown = {}
    fails = None
    while i < len(rows):
        fn, off, val = rows[i]
        if fn != "readu8":
            fails = ("not-a-tag", i, rows[max(0, i - 4):i + 4])
            break
        try:
            tag = int(val)
        except (TypeError, ValueError):
            fails = ("bad-tag", i, rows[max(0, i - 4):i + 4])
            break
        spec = SPEC.get(tag)
        if spec is None:
            unknown[tag] = unknown.get(tag, 0) + 1
            fails = ("unknown-tag", i, rows[max(0, i - 5):i + 5])
            break
        j = i + 1
        ok = True
        got = {}
        for k in spec:
            if j >= len(rows):
                ok = False
                break
            if k == "str":

                if got.get("len") == "0":
                    continue
                if rows[j][0] != "readstring":
                    ok = False
                    break
                got["str"] = rows[j][2]
                j += 1
            elif rows[j][0] != FORD[k]:
                ok = False
                break
            else:
                got[k] = rows[j][2]
                j += 1
        if not ok:
            fails = ("payload-mismatch", i, rows[max(0, i - 5):i + 6])
            break
        recs += 1
        i = j
    print("records:", recs)
    print("stop:", fails[0] if fails else "END-OF-LOG")
    if fails:
        print("at read index", fails[1])
        for r in fails[2]:
            print("   ", r)

if __name__ == "__main__":
    main()
