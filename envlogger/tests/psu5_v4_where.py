"""Find v4's data source: search for long [0-9a-zA-Z] runs (the compressed stream)."""
import re

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

runs = [(m.start(), m.end()) for m in re.finditer(r'[0-9a-zA-Z]{100,}', v4)]
print("alpha runs >= 100:", len(runs))
for st, en in runs[:5]:
    print(f"  {st}..{en} ({en-st}): {v4[st:st+60]!r} ... {v4[en-30:en]!r}")
    print("  before:", repr(v4[max(0,st-120):st]))
    print("  after :", repr(v4[en:en+120]))

print("\n'..' concatenation count:", len(re.findall(r'\.\.', v4)))

i = v4.find('local A,k,b')
print("\nlocal A,k,b at:", i)
print(v4[i:i+400] if i >= 0 else "not found")
