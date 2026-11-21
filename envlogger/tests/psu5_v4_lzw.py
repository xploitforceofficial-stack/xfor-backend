"""Extract v4's full LZW decoder + seed + constants block verbatim for v5 adaptation."""
import re

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

st = v4.find('local M=')
en = v4.find(',(#R-G);')
block = v4[st:en + len(',(#R-G);')]
print("block len:", len(block))

header = """-- v4 PSU deserializer block (verbatim, constants stubbed from env table)
return function(l, R)
%s
end
""" % block

open('Samples/PSU/v5/_v4_lzw_block.lua', 'w', encoding='utf-8').write(header)
print("saved _v4_lzw_block.lua")
print()
print("=== block head:")
print(block[:600])
print()
print("=== need env keys used by block:")
keys = set(re.findall(r"l\[([0-9]+)\]", block)) | set(re.findall(r"l\['([A-Za-z0-9]+)'\]", block)) | set(re.findall(r"l\.(\w+)", block))
print(sorted(keys, key=lambda x: (len(x), x))[:40])
