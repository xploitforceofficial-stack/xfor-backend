"""Binary-search the parse error in the rebuilt v5 body via wasmoon prefixes."""
import subprocess

src = open('Samples/PSU/v5/_rebuilt_body.lua', encoding='utf-8').read()
print("total len:", len(src))

check = r'''
const fs = require('fs');
const { LuaFactory } = require('wasmoon');
const src = fs.readFileSync('Samples/PSU/v5/_prefix.lua', 'utf8');
(async () => {
  const lua = await new LuaFactory().createEngine();
  try {
    const test = 'local f = function(e, ...) ' + src + ' end return type(f)';
    const r = await lua.doString(test);
    console.log('PARSE OK');
  } catch (err) {
    console.log('ERR:', err.message.slice(0, 200));
  }
})();
'''
open('Samples/PSU/v5/_check.cjs', 'w', encoding='utf-8').write(check)

def parses(chunk):
    open('Samples/PSU/v5/_prefix.lua', 'w', encoding='utf-8').write(chunk)
    r = subprocess.run(['node', 'Samples/PSU/v5/_check.cjs'], capture_output=True, text=True, timeout=60)
    return 'PARSE OK' in r.stdout, r.stdout

lo, hi = 0, len(src)

import re
words = [(m.start()) for m in re.finditer(r'\S+', src)]
step = 200
last_ok = 0
for p in range(0, len(src), step):
    ok, out = parses(src[:p])
    if ok:
        last_ok = p
    else:
        print(f"first failing prefix ~{p}: {out.strip()[:120]}")
        lo = last_ok
        hi = p
        break
else:
    print("all coarse prefixes OK?!")
    hi = len(src)

print(f"\nfine search {lo}..{hi}")
for p in range(lo, hi, 1):
    ok, out = parses(src[:p])
    if not ok:
        print(f"fails at {p}: {out.strip()[:150]}")
        print("context:", repr(src[max(0, p - 80):p + 80]))
        break
else:
    print("no failure found in fine range")
