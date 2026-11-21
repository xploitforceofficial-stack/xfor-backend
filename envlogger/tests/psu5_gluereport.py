"""Show all S-substitution sites in the rebuilt body — the parse error is near one of them."""
import re

src = open('Samples/PSU/v5/_rebuilt_body.lua', encoding='utf-8').read()

sites = [(m.start()) for m in re.finditer(r'\bS\b', src)]
print("bare S sites:", len(sites))

for p in sites[:50]:
    print(f"  @{p}: {src[max(0,p-45):p+45]!r}")
