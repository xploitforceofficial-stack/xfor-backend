"""Join (2)-build creation + entry arrays; build closure map.

Mirrors join_chains.py for work_s2's schema:
  a49arr.tsv   c, hid, n, r   (r = interpreter mode selecting the J-loop)
  a49entry.tsv hid, g, m,N,h,y,f,d,n  (first-call snapshots, same col order)
  chains.tsv   c, g, m,N,h,y,f,d,n    (creation-time)

Outputs: chains_post.tsv (9 cols, same order), post_meta.json,
f2chain.json ({descriptor-addr: chain}), cmap.json ({closure-addr: chain}).

Usage: python tools/join_s2.py [workdir, default tools/work_s2]
"""
import json
import pathlib
import sys

FIELDS = ("m", "N", "h", "y", "f", "d", "n")

def bare(addr):
    addr = (addr or "").strip()
    if addr.startswith("table: "):
        return addr[7:]
    if addr.startswith("function: "):
        return addr[10:]
    return addr

def read9(path):
    rows = {}
    raw = pathlib.Path(path).read_bytes().decode("latin-1")
    for line in raw.splitlines():
        parts = line.split("\t")
        if len(parts) != 9:
            continue
        try:
            c, g = int(parts[0]), int(parts[1])
        except ValueError:
            continue
        vals = {f: parts[2 + k].replace("\\t", "\t").replace("\\n", "\n")
                for k, f in enumerate(FIELDS)}
        rows[(c, g)] = vals
    return rows

def main() -> int:
    work = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        pathlib.Path(__file__).resolve().parent / "work_s2"
    pre = read9(work / "chains.tsv")
    order = {}
    for (c, g) in pre:
        order.setdefault(c, []).append(g)
    c2h, h2c, modes = {}, {}, {}
    arrp = work / "a49arr.tsv"
    if arrp.exists():
        for line in arrp.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            if len(parts) >= 3:
                try:
                    c = int(parts[0])
                    h = bare(parts[1])
                    c2h[c] = h
                    h2c[h] = c
                    if len(parts) >= 4:
                        modes[c] = parts[3]
                except ValueError:
                    pass
    post = {}
    entp = work / "a49entry.tsv"
    if entp.exists():
        raw = entp.read_bytes().decode("latin-1")
        for line in raw.splitlines():
            parts = line.split("\t")
            if len(parts) != 9:
                continue
            try:
                g = int(parts[1])
            except ValueError:
                continue
            h = bare(parts[0])
            vals = {f: parts[2 + k].replace("\\t", "\t").replace("\\n", "\n")
                    for k, f in enumerate(FIELDS)}
            post.setdefault(h, {})[g] = vals
    out_lines = []
    meta = {}

    f2chain = {h: c for h, c in h2c.items()}
    n_post = n_pre = 0
    for c in sorted(order):
        h = c2h.get(c)
        prows = post.get(h, {}) if h else {}
        for g in sorted(set(order[c])):
            if g in prows:
                vals = prows[g]
                n_post += 1
                src = "post"
            else:
                vals = pre[(c, g)]
                n_pre += 1
                src = "pre"
            m = meta.setdefault(str(c), {"source": src, "slots": 0,
                                         "mode": modes.get(c)})
            if src != m["source"] and m["slots"]:
                m["source"] = "mixed"
            m["slots"] += 1
            f = vals["f"]
            if f.startswith("table: ") and bare(f) in h2c:
                f2chain[bare(f)] = h2c[bare(f)]
            cells = [vals[f].replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")
                     for f in FIELDS]
            out_lines.append("%d\t%d\t%s" % (c, g, "\t".join(cells)))
    (work / "chains_post.tsv").write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    (work / "post_meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    (work / "f2chain.json").write_text(json.dumps(f2chain, indent=1), encoding="utf-8")
    cmap = {}
    jlp = work / "jlink.tsv"
    if jlp.exists():
        for line in jlp.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            if len(parts) == 2:
                f, b = bare(parts[0]), bare(parts[1])
                if f in f2chain:
                    cmap[b] = f2chain[f]
    (work / "cmap.json").write_text(json.dumps(cmap, indent=1), encoding="utf-8")
    n_called = sum(1 for c in order if c2h.get(c) in post)
    print("chains=%d called=%d slots post=%d pre=%d closures-mapped=%d cmap=%d modes=%s" %
          (len(order), n_called, n_post, n_pre, len(f2chain), len(cmap),
           {k: len([c for c in order if modes.get(c) == k]) for k in set(modes.values())}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
