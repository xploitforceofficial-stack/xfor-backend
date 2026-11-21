"""Determine what S must be in v5: check if S is assigned in the body (local S=) or only read."""
import re

clean = open('Samples/PSU/v5/_vmcode_clean.lua', encoding='utf-8').read()

assigns = re.findall(r'local\w*[S]=', clean)
print("local..S= assignments:", assigns)

assigns2 = re.findall(r'localS=', clean)
print("exact localS= :", assigns2)

print("\ne[S] reads:", len(re.findall(r'\be\[S\]', clean)))
print("h[S] reads:", len(re.findall(r'\bh\[S\]', clean)))
print("n[S] reads:", len(re.findall(r'\bn\[S\]', clean)))
print("d[S] reads:", len(re.findall(r'\bd\[S\]', clean)))
print("c[S] reads:", len(re.findall(r'\bc\[S\]', clean)))
print("[S]= writes:", len(re.findall(r'\[S\]=', clean)))

print("\n#(S) uses:", len(re.findall(r'#\(S\)', clean)))
print("#S uses:", len(re.findall(r'#S\b', clean)))

m = re.search(r'\be\[S\]', clean)
if m:
    print("\nfirst e[S] context:", clean[max(0, m.start() - 80):m.start() + 80])
