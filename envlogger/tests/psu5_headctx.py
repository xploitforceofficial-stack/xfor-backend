"""Inspect raw content right before the long-string close at 1005928 — the VM code
INSIDE the string and how it meets the tail code."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
print('inside-string before close (700..0):')
print(repr(s[1005928-700:1005928+2]))
