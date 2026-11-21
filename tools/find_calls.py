import re
import sys

P = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\Sandr\OneDrive\Desktop\OmniDBF\tools\work\stage147.lua"
t = open(P, encoding="utf8", errors="replace").read()
print("stage len", len(t))

PATS = [r"\[\s*28\s*\]\s*\(", r"\[\s*15\s*\]\s*\(", r"\[\s*16\s*\]\s*\(",
        r"\[\s*18\s*\]\s*\(", r"\[\s*22\s*\]\s*\(", r"\[\s*13\s*\]\s*\("]

only = sys.argv[2] if len(sys.argv) > 2 else None

for pat in PATS:
    if only and only not in pat:
        continue
    n = 0
    for m in re.finditer(pat, t):
        if n >= 5:
            break
        s = max(0, m.start() - 300)
        e = min(len(t), m.end() + 300)
        print("--- %s @%d ---" % (m.group(0).replace(" ", ""), m.start()))
        print(t[s:e])
        print()
        n += 1
