"""Show the exact first 3000 chars of v4 harness readable to extract prelude definitions."""
s = open('Samples/PSU/v5/_v4_harness.lua', encoding='utf-8', errors='replace').read()

chunk = s[:3500]
chunk = chunk.replace(';', ';\n')
print(chunk)
