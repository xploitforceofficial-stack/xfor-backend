"""Show context at error 23498 in j2 (the tail env-table region)."""
s = open('Samples/PSU/v5/_v5cand_j2.lua', encoding='latin1').read()
print('len:', len(s))
print(repr(s[23380:23520]))
