"""Check the actual charset of the 500KB blob."""
from collections import Counter

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
blob = s[439:500441]
c = Counter(blob)
print("unique chars:", len(c))
print("distribution:")
for ch, cnt in c.most_common():
    print(f"  {ch!r}: {cnt} ({cnt*100.0/len(blob):.2f}%)")
