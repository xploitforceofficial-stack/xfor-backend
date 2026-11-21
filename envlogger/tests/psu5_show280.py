"""Show raw v5 bytes around the long-string open."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
print(repr(s[240:470]))
