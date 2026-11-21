"""Align the g6 instruction headers with the varint stream in prog_1.bin.

The stage reads the program as a stream of 7-bit varints:
  - offsets 0..3      varint count H (=71374), flag byte C
  - offsets 4..7096   the 1222 constant-pool records (parse_pool.py)
  - offsets 7097..    the instruction stream, decoded one header at a time by
                      g6, which reads exactly three varints (A, Y, H=c[3] value)

g6 is called once per instruction, so its logged cursor tells us exactly where
each header starts. Everything between header(i) and header(i+1) belongs to
instruction i's operand payload.
"""
import json
import pathlib

WORK = pathlib.Path(__file__).resolve().parent / "work"
PROG = WORK / "prog_1.bin"
G6 = WORK / "g6.tsv"

def varints(buf: bytes, start: int):
    p = start
    while p < len(buf):
        v = 0
        sh = 0
        first = p
        while True:
            c = buf[p]
            p += 1
            v |= (c & 0x7F) << sh
            if c < 128:
                break
            sh += 7
        yield first, p - 1, v

def main() -> int:
    buf = PROG.read_bytes()
    vs = list(varints(buf, 7097))
    by_end = {e: i for i, (_, e, _) in enumerate(vs)}
    print(f"varints from 7097: {len(vs)}  last end={vs[-1][1]}  buflen={len(buf)}")

    rows = []
    for line in G6.read_text(encoding="utf-8").splitlines():
        rows.append(tuple(int(x) for x in line.split("\t")))
    print(f"g6 headers: {len(rows)}")

    bad = 0
    headers = []
    for n, l3, H, A, Y, _c in rows:
        i_h = by_end.get(l3 - 1)
        if i_h is None or i_h < 2:
            bad += 1
            continue
        v_h, v_y, v_a = vs[i_h], vs[i_h - 1], vs[i_h - 2]
        if (v_h[2], v_y[2], v_a[2]) != (H, Y, A):
            bad += 1
            continue
        headers.append((n, i_h - 2, i_h, A, Y, H, v_a[0]))
    print(f"aligned={len(headers)} mismatched={bad}")

    instrs = []
    for k, (n, i_a, i_h, A, Y, H, off) in enumerate(headers):
        end = headers[k + 1][1] if k + 1 < len(headers) else len(vs)
        instrs.append(
            {"n": n, "vi": i_a, "end": end, "width": end - i_a,
             "off": off, "A": A, "Y": Y, "H": H}
        )
    widths = [d["width"] for d in instrs]
    print("varints per instruction: min=%d max=%d" % (min(widths), max(widths)))
    import collections

    print("width hist", collections.Counter(widths).most_common(12))

    out = {
        "varints": [[s, e, v] for s, e, v in vs],
        "instructions": instrs,
    }
    (WORK / "stream.json").write_text(json.dumps(out), encoding="utf-8")
    print("wrote", WORK / "stream.json")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
