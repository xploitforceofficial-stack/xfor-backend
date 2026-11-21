import re

P = r"C:\Users\Sandr\OneDrive\Desktop\OmniDBF\tools\work\stage147.lua"
t = open(P, encoding="utf8", errors="replace").read()

PAT = re.compile(r"\[\s*(31|35|36|41|42|43|44|45|40)\s*\]\s*\(\s*\)")

hits = {}
for m in PAT.finditer(t):
    hits.setdefault(m.group(1), []).append(m.start())

for k in sorted(hits, key=int):
    print("[%s]()  %d call sites  %s" % (k, len(hits[k]), hits[k][:10]))

print()
for k in sorted(hits, key=int):
    for pos in hits[k][:4]:
        print("=== [%s]() @%d ===" % (k, pos))
        print(t[max(0, pos - 380):pos + 200])
        print()
