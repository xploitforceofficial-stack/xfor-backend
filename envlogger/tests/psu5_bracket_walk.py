"""Find the first unbalanced closing bracket in the PSU v5 rebuilt body via token walk."""
s = open(r"C:/Users/Sandr/OneDrive/Desktop/OmniDBF/Samples/PSU/v5/_rebuilt_final.lua",
         encoding="utf-8", errors="replace").read()

i, n = 0, len(s)
depth = 0
line = 1
stack = []
in_str = None
in_comment = False

while i < n:
    c = s[i]
    if c == "\n":
        line += 1
        i += 1
        continue
    if in_comment:
        if c == "\n":
            in_comment = False
        i += 1
        continue
    if in_str:
        if c == "\\":
            i += 2
        elif c == in_str:
            in_str = None
            i += 1
        else:
            i += 1
        continue
    if c == "-" and s[i:i+2] == "--":
        in_comment = True
        i += 2
        continue
    if c in "\"'":
        in_str = c
        i += 1
        continue
    if c in "([{":
        stack.append((c, line, i))
        depth += 1
        i += 1
        continue
    if c in ")]}":
        if not stack:
            print(f"UNMATCHED CLOSE '{c}' at line {line}, offset {i}")
            print("  context:", repr(s[max(0, i-100):i+60]))
            raise SystemExit
        o, ol, oi = stack.pop()
        depth -= 1

        expect = {"(": ")", "[": "]", "{": "}"}[o]
        if c != expect:
            print(f"MISMATCH: '{o}' opened line {line} (off {oi}) closed by '{c}' at line {line}, off {i}")
            print("  context:", repr(s[max(0, i-100):i+60]))
            raise SystemExit
        i += 1
        continue
    i += 1

if stack:
    o, ol, oi = stack[-1]
    print(f"UNCLOSED '{o}' from line {ol}, offset {oi} — never closed")
    print("  context:", repr(s[oi:oi+140]))
else:
    print("all brackets balanced")
