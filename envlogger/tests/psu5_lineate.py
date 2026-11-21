"""Add newlines at spaces so the Lua parser reports exact line numbers."""
import subprocess

src = open('Samples/PSU/v5/_rebuilt_body.lua', encoding='utf-8').read()

lineated = src.replace(' ', '\n')
open('Samples/PSU/v5/_rebuilt_lineated.lua', 'w', encoding='utf-8').write(lineated)
print("lines:", lineated.count('\n'))

check = r'''
const fs = require('fs');
const { LuaFactory } = require('wasmoon');
const src = fs.readFileSync('Samples/PSU/v5/_rebuilt_lineated.lua', 'utf8');
(async () => {
  const lua = await new LuaFactory().createEngine();
  try {
    const test = 'local f = function(e, ...) ' + src + ' end return type(f)';
    const r = await lua.doString(test);
    console.log('PARSE OK, type:', r);
  } catch (err) {
    console.log('parse error:', err.message.slice(0, 300));
  }
})();
'''
open('Samples/PSU/v5/_check.cjs', 'w', encoding='utf-8').write(check)
r = subprocess.run(['node', 'Samples/PSU/v5/_check.cjs'], capture_output=True, text=True, timeout=120)
print("stdout:", r.stdout[:400])
