import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
s = open(path, encoding="utf-8", errors="replace").read()
print("total chars:", len(s))

lits = []
for m in re.finditer(r"\[(=*)\[(.*?)\]\1\]", s, re.S):
    lits.append((m.start(), len(m.group(2))))
lits.sort(key=lambda x: -x[1])
print("long-bracket literals (pos,len):", lits[:10])

plain = []
for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', s):
    body = m.group(1)
    if len(body) > 200:
        plain.append((m.start(), len(body), body[:80]))
plain.sort(key=lambda x: -x[1])
print("long quoted literals (pos,len,head):")
for p, l, h in plain[:10]:
    print("  ", p, l, repr(h))

if lits:
    p, l = lits[0]
    print("context before longest:", repr(s[max(0, p - 250):p])[:500])
    print("literal head:", repr(s[p:p + 160]))
