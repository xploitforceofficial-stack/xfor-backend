import re
import sys

P = r"C:\Users\Sandr\OneDrive\Desktop\OmniDBF\tools\work\stage147.lua"
t = open(P, encoding="utf8", errors="replace").read()

PAT = re.compile(r"\[\s*(\d{1,2})\s*\]\s*=\s*(?:\()?\s*([A-Za-z_][\w.]*(?:\.\w+)*)")

hits = {}
for m in PAT.finditer(t):
    idx, rhs = m.group(1), m.group(2)
    if any(k in rhs for k in ("read", "wrap", "char", "len", "copy", "unpack", "fill")):
        hits.setdefault(idx, []).append((m.start(), rhs))

for idx in sorted(hits, key=int):
    for pos, rhs in hits[idx][:3]:
        print("[%s] = %-18s @%d" % (idx, rhs, pos))
    if len(hits[idx]) > 3:
        print("      ... %d more" % (len(hits[idx]) - 3))

print()
print("=== context for [13] / [21] / [10] / [11] / [12] assignments ===")
for idx in ("13", "21", "10", "11", "12", "17", "20", "24", "25"):
    for m in re.finditer(r"\[\s*%s\s*\]\s*=" % idx, t):
        s = max(0, m.start() - 200)
        e = min(len(t), m.end() + 220)
        print("--- [%s] @%d ---" % (idx, m.start()))
        print(t[s:e])
        print()
        break
