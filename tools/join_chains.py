"""Join creation-time and first-call chain arrays into post-patch ground truth.

The loader's F[45] replay decrypts descriptor operands AFTER A49 creation
logging, so chains.tsv (creation-time) is stale for patched slots -- jump
targets demonstrably move (verified against op.tsv: 0/148 absolute matches
pre-patch). a49entry.tsv holds the same arrays at first CALL (post-patch).

Outputs (all in the workdir):
  chains_post.tsv  same 9-col format as chains.tsv, post-patch where available
  post_meta.json   per-chain {source: post|pre, slots: n}
  f2chain.json     {f-address: chain} closure-descriptor -> chain index,
                   by matching post-patch f-cell addresses to creation h
  upenv.json       {chain: {path: {tp, v}}} first-call upvalue snapshots
                   (paths like "0.4"; "[box]" suffix = dereferenced capture)
  cmap.json        {closure-address: chain} created-closure identity map

Usage: python tools/join_chains.py [workdir]
"""
import json
import pathlib
import sys

FIELDS = ("t", "i", "w", "D", "f", "O", "z")

def bare(addr):
    addr = addr.strip()
    if addr.startswith("table: "):
        return addr[7:]
    if addr.startswith("function: "):
        return addr[10:]
    return addr

def unescape_lua(s):
    """Inverse of the stage-side __ESC (single left-to-right pass)."""
    out = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch != "\\" or i + 1 >= len(s):
            out.append(ch)
            i += 1
            continue
        e = s[i + 1]
        if e == "n":
            out.append("\n")
        elif e == "r":
            out.append("\r")
        elif e == "t":
            out.append("\t")
        elif e == "\\":
            out.append("\\")
        else:
            out.append("\\" + e)
        i += 2
    return "".join(out)

def read_chains(path):
    slots, order = {}, {}
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
        slots[(c, g)] = vals
        order.setdefault(c, []).append(g)
    return slots, order

def main() -> int:
    work = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        pathlib.Path(__file__).resolve().parent / "work"
    pre_slots, pre_order = read_chains(work / "chains.tsv")

    c2h, h2c = {}, {}
    arrp = work / "a49arr.tsv"
    if arrp.exists():
        for line in arrp.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            if len(parts) == 3:
                try:
                    h = parts[1]
                    h = h[7:] if h.startswith("table: ") else h
                    c2h[int(parts[0])] = h
                    h2c[h] = int(parts[0])
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
            h = parts[0]
            h = h[7:] if h.startswith("table: ") else h
            vals = {f: parts[2 + k].replace("\\t", "\t").replace("\\n", "\n")
                    for k, f in enumerate(FIELDS)}
            post.setdefault(h, {})[g] = vals
    if not post:
        print("no a49entry.tsv: nothing post-patch; did dump_g6 run with entry logging?",
              file=sys.stderr)
        return 2
    out_lines = []
    meta = {}
    f2chain = {}
    n_post = n_pre = 0
    for c in sorted(pre_order):
        h = c2h.get(c)
        post_rows = post.get(h, {}) if h else {}
        for g in sorted(set(pre_order[c])):
            if g in post_rows:
                vals = post_rows[g]
                n_post += 1
                src = "post"
            else:
                vals = pre_slots[(c, g)]
                n_pre += 1
                src = "pre"
            meta.setdefault(str(c), {"source": src, "slots": 0})
            if src != meta[str(c)]["source"] and meta[str(c)]["slots"]:
                meta[str(c)]["source"] = "mixed"
            meta[str(c)]["slots"] += 1
            f = vals["f"]
            if f.startswith("table: ") and f[7:] in h2c:
                f2chain[f[7:]] = h2c[f[7:]]
            cells = [vals[f].replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")
                     for f in FIELDS]
            out_lines.append("%d\t%d\t%s" % (c, g, "\t".join(cells)))
    (work / "chains_post.tsv").write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    (work / "post_meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    (work / "f2chain.json").write_text(json.dumps(f2chain, indent=1), encoding="utf-8")
    n_called = sum(1 for c in pre_order if c2h.get(c) in post)
    print("chains=%d called=%d slots post=%d pre=%d closures-mapped=%d" %
          (len(pre_order), n_called, n_post, n_pre, len(f2chain)))

    upenv = {}
    upp = work / "upvals.tsv"
    n_up = 0
    if upp.exists():
        for line in upp.read_bytes().decode("latin-1").splitlines():
            parts = line.split("\t")
            if len(parts) != 4:
                continue
            h, path, tp, v = parts
            c = h2c.get(bare(h))
            if c is None:
                continue
            if tp == "number":
                try:
                    v = float(v)
                except ValueError:
                    pass
            elif tp == "boolean":
                v = (v == "true")
            elif tp == "string":
                v = unescape_lua(v)
            upenv.setdefault(str(c), {})[path] = {"tp": tp, "v": v}
            n_up += 1
    (work / "upenv.json").write_text(json.dumps(upenv, indent=1, ensure_ascii=False),
                                     encoding="utf-8")

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
    print("upenv chains=%d rows=%d cmap=%d" % (len(upenv), n_up, len(cmap)))
    print("wrote chains_post.tsv, post_meta.json, f2chain.json, upenv.json, cmap.json")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
