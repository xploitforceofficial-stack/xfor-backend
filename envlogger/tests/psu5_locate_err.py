"""Locate remaining parse error by progressive prefixes, capturing exact error text."""
import subprocess

src = open('Samples/PSU/v5/_rebuilt_body.lua', encoding='utf-8').read()

check = r'''
const fs = require('fs');
const { LuaFactory } = require('wasmoon');
const src = fs.readFileSync('Samples/PSU/v5/_prefix.lua', 'utf8');
(async () => {
  const lua = await new LuaFactory().createEngine();
  try {
    const test = 'local f = function(e, ...) ' + src + ' end return type(f)';
    await lua.doString(test);
    console.log('PARSE OK');
  } catch (err) {
    console.log('ERR:', err.message.slice(0, 220));
  }
})();
'''
open('Samples/PSU/v5/_check.cjs', 'w', encoding='utf-8').write(check)

def try_parse(chunk):
    open('Samples/PSU/v5/_prefix.lua', 'w', encoding='utf-8').write(chunk)
    r = subprocess.run(['node', 'Samples/PSU/v5/_check.cjs'], capture_output=True, text=True, timeout=60)
    out = r.stdout.strip()
    return out.startswith('PARSE OK'), out

ok, out = try_parse(src)
print("full:", out[:200])
if ok:
    raise SystemExit

import re

prev_ok = 0
for frac in [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]:
    p = int(len(src) * frac)
    ok, out = try_parse(src[:p])
    print(f"{frac:.1f} ({p}): {'OK' if ok else out[:80]}")
    if not ok:
        hi = p
        break
else:
    print("even 10% fails")
    hi = int(len(src) * 0.1)

tokens = [m.start() for m in re.finditer(r'\S+', src)]
lo = prev_ok

for p in tokens:
    if p >= hi:
        break
    ok, out = try_parse(src[:p])
    if ok:
        lo = p
    else:
        break
print(f"\nlast OK at {lo}, fails at next token")

p = lo
ok, out = try_parse(src[:p])
while ok:
    idx = src.find('\S', p) if False else None
    break

for m in re.finditer(r'\S+', src[lo:]):
    p2 = lo + m.start() + len(m.group())
    ok, out = try_parse(src[:p2])
    if not ok:
        print(f"\nFAILS when including token ending at {p2}: {out[:150]}")
        print("token:", repr(src[lo + m.start():p2]))
        print("context:", repr(src[max(0, lo + m.start() - 100):p2 + 60]))
        break
