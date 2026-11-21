"""Rebuild a parseable v5 file:
1. take the clean body (all troll strings removed)
2. define S='' and L=string as locals
3. define _6.._191 as nil (they're inside local statements, value irrelevant)
4. wrap so the payload + env table flow matches the v4 execution model
"""
clean = open('Samples/PSU/v5/_vmcode_clean.lua', encoding='utf-8').read()

i = clean.find('localfunctiono(')
if i < 0:
    i = clean.find('local function o(')
body = clean[i:]
print("body starts at clean offset", i, "->", repr(body[:60]))

und = ['_6', '_11', '_16', '_33', '_44', '_46', '_50', '_53', '_73', '_76',
       '_87', '_95', '_99', '_106', '_113', '_129', '_135', '_141', '_152', '_169', '_191']

prologue = "local S='' local L=string " + ' '.join(f"local {u}=nil" for u in und) + " "

rebuilt = prologue + body
open('Samples/PSU/v5/_rebuilt_body.lua', 'w', encoding='utf-8').write(rebuilt)
print("rebuilt body len:", len(rebuilt))

import json, subprocess, sys
check = f'''
const fs = require('fs');
const {{ LuaFactory }} = require('wasmoon');
const src = fs.readFileSync('Samples/PSU/v5/_rebuilt_body.lua', 'utf8');
(async () => {{
  const lua = await new LuaFactory().createEngine();
  const chunk = 'return function(e, ...) ' + src + ' end';
  try {{
    await lua.doString('local f = ' + chunk.slice(0, 0) + 'nil');
    // just try to load it as a function expression
    const test = 'local ok, err = pcall(function() local _ = function(e,...) ' + src + ' end end)';
    const r = await lua.doString(test);
    console.log('parse result:', r);
  }} catch (err) {{
    console.log('parse threw:', err.message.slice(0, 200));
  }}
}})();
'''
open('Samples/PSU/v5/_check.cjs', 'w', encoding='utf-8').write(check)
r = subprocess.run(['node', 'Samples/PSU/v5/_check.cjs'], capture_output=True, text=True, timeout=60)
print("stdout:", r.stdout[:400])
print("stderr:", r.stderr[:400])
