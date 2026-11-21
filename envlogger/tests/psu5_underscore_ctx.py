"""Context around underscore globals (_6, _11, _106...) and plain capital-letter globals."""
import re

clean = open('Samples/PSU/v5/_vmcode_clean.lua', encoding='utf-8').read()

unames = sorted(set(re.findall(r'\b_\d+\b', clean)), key=lambda x: int(x[1:]))
print("underscore names:", unames)
print()

for nm in unames:
    ctxs = re.findall(rf'.{{40}}\b{nm}\b.{{40}}', clean)
    print(f"--- {nm} ({len(ctxs)} uses):")
    for c in ctxs[:2]:
        print("   ", c)
print()

for nm in ['_11', '_106', '_113']:
    ctxs = re.findall(rf'local\w*\=\({nm}\)', clean)
    print(f"locala=({nm}) occurrences:", len(ctxs))
