import re

P = r"C:\Users\Sandr\OneDrive\Desktop\OmniDBF\tools\work\stage147.lua"
t = open(P, encoding="utf8", errors="replace").read()

for pos in (527, 2820, 3910, 5552):
    print("===== call site @%d =====" % pos)
    print(t[max(0, pos - 450):pos + 300])
    print()

print("===== definitions =====")
for name in ("W6", "I6", "FY", "nY", "m6", "r6", "z6", "s6", "W6="):
    m = re.search(re.escape(name) + r"\s*=\s*function", t)
    if m:
        print("--- %s @%d ---" % (name, m.start()))
        print(t[m.start():m.start() + 480])
        print()
