"""Final structure verdict: is the v5 sample parseable anywhere, and what is it really?"""
import re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
n = len(s)

print("=== file size:", n)
print("=== head 0-290:")
print(repr(s[:290]))
print()

head = s[:290]
print("=== count of 'PSU|' markers:", s.count('PSU|'))
print("=== count of 'PSu' variants:", len(re.findall(r'PS[Uu]\|?', head)))
print()

FILLER = set(' &=|/#_\n\r\t')
runs = []
cur_start = None
for i, c in enumerate(s):
    if c not in FILLER:
        if cur_start is None:
            cur_start = i
    else:
        if cur_start is not None and i - cur_start >= 12:
            runs.append((cur_start, i))
        cur_start = None
if cur_start is not None and n - cur_start >= 12:
    runs.append((cur_start, n))

print(f"=== printable runs >= 12 chars (outside filler): {len(runs)}")
for st, en in runs[:25]:
    print(f"  {st:8d}..{en:8d} ({en-st:6d} ch): {s[st:min(st+90, en)]!r}")
