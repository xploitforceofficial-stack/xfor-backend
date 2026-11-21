'use strict';

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { LuaFactory } from 'wasmoon';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..', '..');

const v4 = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v4', '1.lua'), 'utf8');

const head = v4.indexOf('return(function(l,...)');
const chainStart = head + 'return(function(l,...)'.length;
const lzwStart = v4.indexOf('local u,t=(function(o)');
const chain = v4.slice(chainStart, lzwStart);

const lzwEnd = v4.indexOf(',(#R-G);', lzwStart) + ',(#R-G);'.length;
const lzw = v4.slice(lzwStart, lzwEnd);

const DUMP = `
DUMP_LEN = #u;
DUMP_HEAD = string.sub(u, 1, 200);
DUMP_TAIL = string.sub(u, -60);
DUMP_T = t;
`;

const src = `return(function(l,...)
${chain}
${lzw}
${DUMP}
end)`;

fs.writeFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v4_lzw_harness.lua'), src);
console.log('harness written, chain len', chain.length, 'lzw len', lzw.length);

const envJson = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v4_envtable.json'), 'utf8'));
const lua = await new LuaFactory().createEngine();
await lua.global.set('ENV_TABLE', JSON.stringify(envJson));

await factory_mount(lua, src);

async function factory_mount(lua, src) {

    const f = new LuaFactory();

    await lua.global.set('SRC', src);
}

const RUN = `
local env = {}
local decoded = JSON.decode and JSON.decode or nil
-- wasmoon exposes global JSON? Use manual parse via string table:
local jsonstr = ENV_TABLE_JSON
`;
console.log('ready to run — need env table as lua literal (next step)');
