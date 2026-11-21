"""Deep dive into v5 tail: main VM call chain and chunk table fields."""
import re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
body = s[1000524:]

i = body.find('locall=i(n);')
print("=== around 'local l=i(n)':")
print(repr(body[i - 200:i + 400]) if i >= 0 else "not found directly, trying spaced")

if i < 0:

    clean = open('Samples/PSU/v5/_vmcode_clean.lua', encoding='utf-8').read()
    i = clean.find('locall=i(n);')
    print("clean @", i, ":", clean[i - 150:i + 400])

j = body.find('return(_(')
print("\n=== around 'return(_(':")
print(repr(body[j - 300:j + 200]) if j >= 0 else "not found")

k = body.find('return({[S]=')
print("\n=== chunk table return:")
print(repr(body[k:k + 400]) if k >= 0 else "not found")
