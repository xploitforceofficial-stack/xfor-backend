"""Extract the real VM code region (1000524..end) and study head/tail for reconstruction."""
s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

VM = s[1000524:]
open('Samples/PSU/v5/_vmcode.lua', 'w', encoding='utf-8').write(VM)
print("VM code len:", len(VM))
open('Samples/PSU/v5/_vmpayload.txt', 'w', encoding='utf-8').write(s[439:500439])
print("payload len:", 500439 - 439)

print("\n=== VM head (first 500):")
print(repr(VM[:500]))
print("\n=== VM tail (last 700):")
print(repr(VM[-700:]))
