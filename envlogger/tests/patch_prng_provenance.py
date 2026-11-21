"""Wire PRNG provenance: mark Random draws; disclose comparisons involving them."""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DT = os.path.join(ROOT, "envlogger", "src", "env", "datatypes.luau")
SB = os.path.join(ROOT, "envlogger", "src", "core", "sandbox.luau")

def apply(path, pairs, label):
    with io.open(path, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()
    for old, new in pairs:
        hit = None
        for cand in (old, old.replace("\n", "\r\n")):
            if text.count(cand) == 1:
                hit = cand
                break
        if hit is None:
            print("ANCHOR MISS in", label, "->", old.splitlines()[0][:70])
            sys.exit(1)
        text = text.replace(hit, new.replace("\n", "\r\n") if "\r\n" in hit else new)
    with io.open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    print("patched", label)

apply(DT, [

    ('local Serializer = require("../core/serializer")',
     'local PrngTrace = require("./prngtrace")\nlocal Serializer = require("../core/serializer")'),

    ('\t\t\t\tlocal value = nextFloat()\n'
     '\t\t\t\tif given == 2 then\n'
     '\t\t\t\t\tlocal lo = tonumber(low) or 0\n'
     '\t\t\t\t\tlocal hi = tonumber(high) or 0\n'
     '\t\t\t\t\treturn lo + value * (hi - lo)\n'
     '\t\t\t\tend\n'
     '\t\t\t\treturn value',

     '\t\t\t\tlocal value = nextFloat()\n'
     '\t\t\t\tPrngTrace.mark(value)\n'
     '\t\t\t\tif given == 2 then\n'
     '\t\t\t\t\tlocal lo = tonumber(low) or 0\n'
     '\t\t\t\t\tlocal hi = tonumber(high) or 0\n'
     '\t\t\t\t\tlocal ranged = lo + value * (hi - lo)\n'
     '\t\t\t\t\tPrngTrace.mark(ranged)\n'
     '\t\r\n'
     '\t\t\t\t\treturn ranged\n'
     '\t\t\t\tend\n'
     '\t\t\t\treturn value'),

    ('\t\t\t\treturn math.floor(lo + nextFloat() * (hi - lo + 1))',
     '\t\t\t\tlocal drawn = math.floor(lo + nextFloat() * (hi - lo + 1))\n'
     '\t\t\t\tPrngTrace.mark(drawn)\n'
     '\t\t\t\treturn drawn'),
], "datatypes.luau")

apply(SB, [

    ('local Instrument = require("./instrument")',
     'local Instrument = require("./instrument")\nlocal PrngTrace = require("../env/prngtrace")'),

    ('\t\t\tif invented then\n'
     '\t\t\t\tunknownOpCounter += 1\n'
     '\t\t\tend',

     '\t\t\t-- A comparison that touches a PRNG-derived value can only be trusted\n'
     '\t\t\t-- if our Random emulation is byte-exact with the client. Until that is\n'
     '\t\t\t-- validated, disclose it as sandbox-decided (concrete=false) so the\n'
     '\t\t\t-- report never presents an emulated anti-tamper outcome as fact.\n'
     '\t\t\tif not invented and PrngTrace.containsAny(leftValue, rightValue, left, right) then\n'
     '\t\t\t\tinvented = true\n'
     '\t\t\tend\n'
     '\n'
     '\t\t\tif invented then\n'
     '\t\t\t\tunknownOpCounter += 1\n'
     '\t\t\tend'),
], "sandbox.luau")

print("provenance wiring complete")
