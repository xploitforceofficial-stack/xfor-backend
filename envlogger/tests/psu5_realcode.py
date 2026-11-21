"""Dump the real executable code after the v5 long string closes at 1005928."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()

close = 1005928
print('after close (first 3000):')
print(s[close:close+3000])
print()
print('...')
print('last 400:')
print(repr(s[-400:]))
