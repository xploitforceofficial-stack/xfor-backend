import sys
path = sys.argv[1] if len(sys.argv) > 1 else "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
s = open(path, encoding="utf-8", errors="replace").read()
p = 279402
print("== 400 chars BEFORE literal ==")
print(s[p - 400:p].replace("\r", ""))
print("== 200 chars AFTER literal ==")
print(s[p + 159240 + 2:p + 159240 + 260].replace("\r", ""))

head = s[p + 1:p + 41]
print("head:", repr(head))
print("occurrences of head:", s.count(head))

runs = []
cur = 0
prev = None
start = 0
import re
for m in re.finditer(r"[\x20-\x7e]{2000,}", s):
    runs.append((m.start(), m.end() - m.start()))
print("printable runs > 2000:", runs[:12])
