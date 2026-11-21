"""Check _ENV and (S) usage in v5 clean body — what else the wrapper must provide."""
import re

clean = open('Samples/PSU/v5/_vmcode_clean.lua', encoding='utf-8').read()

print("_ENV uses:")
for m in list(re.finditer(r'_ENV', clean))[:8]:
    print("  @", m.start(), ":", clean[max(0, m.start() - 60):m.start() + 60])

print()
print("'S' (capital S string constant) uses:")
for m in list(re.finditer(r'#\(S\)', clean))[:6]:
    print("  @", m.start(), ":", clean[max(0, m.start() - 60):m.start() + 60])

m = re.search(r'\bS\b', clean)
print("\nfirst bare S use:")
print("  @", m.start(), ":", clean[max(0, m.start() - 80):m.start() + 80])
