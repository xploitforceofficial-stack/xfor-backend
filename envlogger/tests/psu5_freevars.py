"""The deserializer _( ) reads u/c/n — free locals of the IIFE(e,...) body. They were
defined in the destroyed prelude (head junk). In v4.5 the prelude was:
   local s,t=(LZW_IIFE)('PSU|...'),(#S-106)
For v5 we must REBUILD: u = LZW(decoded 500KB blob), c = 1, n = initial xor key.
The LZW IIFE code itself was in the destroyed head. Reconstruct it from v4.5's
known-good algorithm adapted to v5's alphabet/base (base62?). Wait — v4.5's varint
used base36 and its payload had base62-looking chars? Check v4.5's payload charset."""
s45 = open('Samples/PSU/v4.5/1.lua', encoding='latin1').read()
import re
m = re.search(r'PSU\|([0-9A-Za-z]+)', s45)
blob45 = m.group(1)
import collections
chars = collections.Counter(blob45)
print('v4.5 payload charset size:', len(chars))
print('has uppercase:', any(c.isupper() for c in chars))
print('sample:', repr(blob45[:80]))
