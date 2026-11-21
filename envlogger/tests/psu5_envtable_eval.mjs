'use strict';

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { LuaFactory } from 'wasmoon';

const here = path.dirname(fileURLToPath(import.meta.url));
const [srcPath, outPath] = process.argv.slice(2);
if (!srcPath || !outPath) {
    console.error('usage: node psu5_envtable_eval.mjs <envtable.lua> <out.json>');
    process.exit(1);
}

const src = fs.readFileSync(srcPath, 'utf8');
const lua = await new LuaFactory().createEngine();

const chunk = `
local ok, res, err = pcall(function() ${src} end)
if not ok then
    return "ERR:" .. tostring(err)
end
local parts = {}
local n = 0
for k, v in pairs(res) do
    n = n + 1
    parts[n] = tostring(k) .. CHAR_TAB .. tostring(v)
end
return "OK:" .. n .. CHAR_TAB .. table.concat(parts, CHAR_NL)
`;

lua.global.set('CHAR_TAB', '\t');
lua.global.set('CHAR_NL', '\n');

const out = String(await lua.doString(chunk));
console.log('first line:', out.split('\n')[0]);

if (out.startsWith('OK:')) {
    const entries = {};
    for (const line of out.split('\n').slice(1)) {
        const i = line.indexOf('\t');
        if (i > 0) entries[line.slice(0, i)] = line.slice(i + 1);
    }
    fs.writeFileSync(outPath, JSON.stringify(entries, null, 1));
    console.log('saved', Object.keys(entries).length, 'entries ->', outPath);
} else {
    console.log(out.slice(0, 400));
    process.exit(1);
}
