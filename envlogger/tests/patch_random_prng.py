"""Replace the sandbox's Random PRNG with a full-precision generator.

Why: the old implementation was a 31-bit Park-Miller LCG, so every NextNumber()
was a multiple of 2^-31 and two unseeded Random.new() instances produced
identical streams. Both are one-line fingerprints for anti-tamper scripts.
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATH = os.path.join(ROOT, "envlogger", "src", "env", "datatypes.luau")

with io.open(PATH, "r", encoding="utf-8", newline="") as fh:
    text = fh.read()

start = text.find("\tout.Random = {")
if start < 0:
    sys.exit("could not find out.Random block")
end_marker = "\tout.RaycastParams = {"
end = text.find(end_marker, start)
if end < 0:
    sys.exit("could not find block end")

new_block = '''\tlocal unseededCounter = 0

\tout.Random = {
\t\tnew = function(seed: any?): any
\t\t\tif seed ~= nil and type(Spy.unwrap(seed) or seed) ~= "number" then
\t\t\t\tlocal got = Symbol.typeName(seed)
\t\t\t\tif type(got) ~= "string" or got == "" then
\t\t\t\t\tgot = type(Spy.unwrap(seed) or seed)
\t\t\t\tend
\t\t\t\terror("invalid argument #1 to 'new' (number expected, got " .. got .. ")", 2)
\t\t\tend

\t\t\tlocal unwrappedSeed = tonumber(Spy.unwrap(seed) or seed)

\t\t\t-- xoshiro128** over four 32-bit words, two words per float. The client's
\t\t\t-- NextNumber carries a full mantissa at every exponent, so a narrow
\t\t\t-- generator (values that are all multiples of 2^-31) is trivially
\t\t\t-- fingerprintable; this keeps the client's precision profile.
\t\t\tlocal st: { number } = { 0, 0, 0, 0 }

\t\t\tlocal function mul32(a: number, b: number): number
\t\t\t\tlocal a0 = bit32.band(a, 0xFFFF)
\t\t\t\tlocal a1 = bit32.rshift(a, 16)
\t\t\t\tlocal b0 = bit32.band(b, 0xFFFF)
\t\t\t\tlocal b1 = bit32.rshift(b, 16)
\t\t\t\tlocal mid = (a0 * b1 + a1 * b0) % 65536
\t\t\t\treturn (a0 * b0 + bit32.lshift(mid, 16)) % 4294967296
\t\t\tend

\t\t\tlocal function splitmix(ref: { v: number }): number
\t\t\t\tref.v = (ref.v + 0x9E3779B9) % 4294967296
\t\t\t\tlocal z = ref.v
\t\t\t\tz = mul32(bit32.bxor(z, bit32.rshift(z, 16)), 0x85EBCA6B)
\t\t\t\tz = mul32(bit32.bxor(z, bit32.rshift(z, 13)), 0xC2B2AE35)
\t\t\t\treturn bit32.bxor(z, bit32.rshift(z, 16))
\t\t\tend

\t\t\tlocal function seedState(base: number)
\t\t\t\tlocal ref = { v = bit32.band(math.floor(base), 0xFFFFFFFF) }
\t\t\t\tfor i = 1, 4 do
\t\t\t\t\tst[i] = splitmix(ref)
\t\t\t\tend
\t\t\t\tif st[1] == 0 and st[2] == 0 and st[3] == 0 and st[4] == 0 then
\t\t\t\t\t-- all-zero state is a fixed point of the generator
\t\t\t\t\tst[1] = 0x9E3779B9
\t\t\t\tend
\t\t\tend

\t\t\tlocal function next32(): number
\t\t\t\tlocal result = mul32(bit32.rotateleft(st[2], 7), 9)
\t\t\t\tlocal t = bit32.lshift(st[2], 9)
\t\t\t\tst[3] = bit32.bxor(st[3], st[1])
\t\t\t\tst[4] = bit32.bxor(st[4], st[2])
\t\t\t\tst[2] = bit32.bxor(st[2], st[3])
\t\t\t\tst[1] = bit32.bxor(st[1], st[4])
\t\t\t\tst[3] = bit32.bxor(st[3], t)
\t\t\t\tst[4] = bit32.rotateleft(st[4], 11)
\t\t\t\treturn result
\t\t\tend

\t\t\t-- two 32-bit words per float => 53-bit mantissa, uniform on [0, 1)
\t\t\tlocal function nextFloat(): number
\t\t\t\tlocal hi = next32()
\t\t\t\tlocal lo = next32()
\t\t\t\treturn (hi * 4294967296 + lo) * 5.421010862427522e-20
\t\t\tend

\t\t\tif unwrappedSeed ~= nil then
\t\t\t\tseedState(unwrappedSeed)
\t\t\telse
\t\t\t\t-- unseeded Random.new() must not repeat between instances, so seed from
\t\t\t\t-- ambient entropy exactly like the client does
\t\t\t\tunseededCounter += 1
\t\t\t\tlocal entropy = (math.random(0, 0x7FFFFFFF) * 65536
\t\t\t\t\t+ math.random(0, 0xFFFF)) % 4294967296
\t\t\t\tentropy = (entropy
\t\t\t\t\t+ math.floor(os.clock() * 1000000)
\t\t\t\t\t+ unseededCounter * 2654435761) % 4294967296
\t\t\t\tseedState(entropy)
\t\t\tend

\t\t\tlocal rng: any = {}

\t\t\trng.NextNumber = function(_self: any, ...: any): number
\t\t\t\tlocal given = select("#", ...)
\t\t\t\tif given ~= 0 and given ~= 2 then
\t\t\t\t\terror("Random:NextNumber requires 0 or 2 arguments", 2)
\t\t\t\tend
\t\t\t\tlocal low, high = ...
\t\t\t\tlocal value = nextFloat()
\t\t\t\tif given == 2 then
\t\t\t\t\tlocal lo = tonumber(low) or 0
\t\t\t\t\tlocal hi = tonumber(high) or 0
\t\t\t\t\treturn lo + value * (hi - lo)
\t\t\t\tend
\t\t\t\treturn value
\t\t\tend

\t\t\trng.NextInteger = function(_self: any, low: any?, high: any?): number
\t\t\t\tif low == nil then
\t\t\t\t\terror("invalid argument #1 to 'NextInteger' (number expected, got nil)", 2)
\t\t\t\tend
\t\t\t\tif high == nil then
\t\t\t\t\terror("invalid argument #2 to 'NextInteger' (number expected, got nil)", 2)
\t\t\t\tend
\t\t\t\tlocal lo = tonumber(low)
\t\t\t\tlocal hi = tonumber(high)
\t\t\t\tif lo == nil or lo % 1 ~= 0 then
\t\t\t\t\terror("invalid argument #1 to 'NextInteger' (number has no integer representation)", 2)
\t\t\t\tend
\t\t\t\tif hi == nil or hi % 1 ~= 0 then
\t\t\t\t\terror("invalid argument #2 to 'NextInteger' (number has no integer representation)", 2)
\t\t\t\tend
\t\t\t\tif hi < lo then
\t\t\t\t\terror("invalid argument #2 to 'NextInteger' (max must be greater than or equal to min)", 2)
\t\t\t\tend
\t\t\t\treturn math.floor(lo + nextFloat() * (hi - lo + 1))
\t\t\tend

\t\t\trng.NextUnitVector = function(): any
\t\t\t\treturn makeVector3(
\t\t\t\t\tnextFloat() * 2 - 1,
\t\t\t\t\tnextFloat() * 2 - 1,
\t\t\t\t\tnextFloat() * 2 - 1
\t\t\t\t).Unit
\t\t\tend

\t\t\trng.Shuffle = function(_self: any, target: any): any
\t\t\t\tif type(target) ~= "table" then
\t\t\t\t\terror(string.format(
\t\t\t\t\t\t"invalid argument #1 to 'Shuffle' (table expected, got %s)",
\t\t\t\t\t\tglobals.typeof(target)), 2)
\t\t\t\tend
\t\t\t\tlocal count = #target
\t\t\t\tfor i = count, 2, -1 do
\t\t\t\t\tlocal roll = math.floor(nextFloat() * i) + 1
\t\t\t\t\tif roll > i then
\t\t\t\t\t\troll = i
\t\t\t\t\tend
\t\t\t\t\tif roll ~= i then
\t\t\t\t\t\ttarget[i], target[roll] = target[roll], target[i]
\t\t\t\t\tend
\t\t\t\tend
\t\t\t\treturn target
\t\t\tend

\t\t\trng.Clone = function(_self: any): any
\t\t\t\t-- the client advances the source generator once and then hands the copy
\t\t\t\t-- that same state, so clone and source stay in lockstep
\t\t\t\tnextFloat()
\t\t\t\tlocal copy = out.Random.new(0)
\t\t\t\tlocal dest = copy.__box.st
\t\t\t\tfor i = 1, 4 do
\t\t\t\t\tdest[i] = st[i]
\t\t\t\tend
\t\t\t\treturn copy
\t\t\tend

\t\t\trng.__box = { st = st }
\t\t\trequire("./fidelity").registerTree(rng)
\t\t\treturn Symbol.tag(rng, {
\t\t\t\tkind = "datatype",
\t\t\t\texpression = "Random.new(" .. Serializer.numberLiteral(unwrappedSeed or 0) .. ")",
\t\t\t\ttypeName = "Random",
\t\t\t})
\t\tend,
\t}

'''

new_block = new_block.replace("\n", "\r\n") if "\r\n" in text else new_block
text = text[:start] + new_block + text[end:]

with io.open(PATH, "w", encoding="utf-8", newline="") as fh:
    fh.write(text)

print("replaced out.Random block (%d chars)" % len(new_block))
