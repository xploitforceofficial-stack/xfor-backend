"""Scan the v5 head junk (0..1000532 outside the payload) for LZW-like fragments:
look for substrings like 'while', 'gsub', 'char', 'byte', 'sub(', '36', '62', 'tonumber'
appearing OUTSIDE the giant payload string."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
head = s[:283] + s[1005930-1005930+1005930-1005930:]
tail_full = s[1005930:]
mid = s[500441:1000524]

print('head (0..283) len:', len(head))
print(repr(head))
print()
import re
for pat in [r'while', r'gsub', r'string', r'char', r'byte', r'tonumber', r'\b36\b', r'\b62\b', r'\b91\b', r'concat']:
    print(pat, '-> mid:', len(re.findall(pat, mid)), ' tail:', len(re.findall(pat, tail_full)))
