"""Dump the first 12 lines of the rebuilt full body to see what line 4 is."""
s = open('Samples/PSU/v5/_rebulled_full.lua', encoding='utf-8', errors='replace').read()
print("total len:", len(s))
print()
for i, line in enumerate(s.split('\n')[:12], 1):
    print(f"{i:3}: {line[:180]}")
