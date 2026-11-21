"""Extract v5's main structures: deserializer entry (e/l/n function), chunk builder, VM dispatcher A()."""
import re

clean = open('Samples/PSU/v5/_vmcode_clean.lua', encoding='utf-8').read()

print("=== clean length:", len(clean))
print("\n=== first 1200 chars of clean body:")
print(clean[:1200])
print()
print("=== the A() dispatcher region:")
i = clean.find('localfunctionA(')
print(clean[i:i + 1500] if i >= 0 else "not found")
