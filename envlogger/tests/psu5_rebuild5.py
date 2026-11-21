"""Rebuild v5 with distinct name for substituted string literals: use PSU_STR.
This avoids collision with VM locals that get reassigned (like local Q=e[...]).
Also define the protoo/userdata stubs if needed."""
import subprocess

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
body_src = s[1000524:]

def strip_keep_space(src):
    out = []
    i = 0
    n = len(src)
    BS = chr(92)
    while i < n:
        c = src[i]
        if c == '"' or c == "'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == BS:
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                j += 1
            out.append('PSU_STR')
            i = j
        elif src[i:i+2] == '--':
            j = i + 2
            if j < n and src[j] == '[':
                eq = 0
                k = j + 1
                while k < n and src[k] == '=':
                    eq += 1
                    k += 1
                if k < n and src[k] == '[':
                    close = ']' + '=' * eq + ']'
                    f = src.find(close, k + 1)
                    i = (f + len(close)) if f != -1 else n
                    continue
            while j < n and src[j] != '\n':
                j += 1
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)

clean = strip_keep_space(body_src)
i = clean.find('local function o(')
vmbody = clean[i:]
vmbody = vmbody[:vmbody.find('end)(({')]

und = ['_6', '_11', '_16', '_33', '_44', '_46', '_50', '_53', '_73', '_76',
       '_87', '_95', '_99', '_106', '_113', '_129', '_135', '_141', '_152', '_169', '_191']
prologue = "local PSU_STR='' " + ' '.join(f"local {u}=nil" for u in und) + " "
full = "local f = function(e, ...) " + prologue + vmbody + " end return f"

lineated = full.replace(' ', '\n')
open('Samples/PSU/v5/_rebuilt_lineated.lua', 'w', encoding='utf-8').write(lineated)
open('Samples/PSU/v5/_rebulled_full.lua', 'w', encoding='utf-8').write(full)
print("lines:", lineated.count('\n'))

check = r'''
const fs = require('fs');
const { LuaFactory } = require('wasmoon');
const src = fs.readFileSync('Samples/PSU/v5/_rebuilt_lineated.lua', 'utf8');
(async () => {
  const lua = await new LuaFactory().createEngine();
  try {
    const r = await lua.doString(src);
    console.log('PARSE OK:', r);
  } catch (err) {
    console.log('parse error:', err.message.slice(0, 250));
  }
})();
'''
open('Samples/PSU/v5/_check.cjs', 'w', encoding='utf-8').write(check)
r = subprocess.run(['node', 'Samples/PSU/v5/_check.cjs'], capture_output=True, text=True, timeout=120)
print("stdout:", r.stdout[:200])
