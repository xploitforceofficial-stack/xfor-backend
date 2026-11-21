"""Compare v4 vs v5 VM: function names, control flow, handler structure."""
import re

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()
v5 = open('Samples/PSU/v5/_vmcode.lua', encoding='utf-8', errors='replace').read()

print("=== v4 structure:")

print("v4 top-level locals:", re.findall(r'return\(function\((\w+),(\.\.\.)\)', v4))
print("v4 string-key env access 'l.efuh4mRFS':", 'efuh4mRFS' in v4)

print("v4 'while true do' count:", len(re.findall(r'while true do', v4)))
print("v4 'elseif' count:", len(re.findall(r'elseif', v4)))
print("v5 'elseif' count:", len(re.findall(r'elseif', v5)))
print("v4 numeric-dispatch pattern 'if(n==' style:", len(re.findall(r'if\(\w+==\d+\)then', v5)), "in v5")

i = v4.find('efuh4mRFS')
print("\n=== v4 after watermark (800 chars):")
print(v4[i:i+800])
