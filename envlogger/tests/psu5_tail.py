"""Extract PSU v5 tail (from after the payload to EOF) for analysis."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()

tail = s[1000524:]
print("tail len:", len(tail))
print()
print("=== first 3000:")
print(tail[:3000])
