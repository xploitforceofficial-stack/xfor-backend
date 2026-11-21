'use strict';

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { LuaFactory } from 'wasmoon';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..', '..');

const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_lineated.lua'), 'utf8');
const envJson = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envtable.json'), 'utf8'));

const lua = await new LuaFactory().createEngine();
lua.global.set('PSU_ENV', envJson);
lua.global.set('PSU_BODY', lineated);
lua.global.set('PSU_PAYLOAD', fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8'));

const BOOT = `
local f, err = load(PSU_BODY)
if not f then return { 'LOADFAIL', tostring(err) } end
local envraw = PSU_ENV
local e = {}
for k, v in pairs(envraw) do
    local nk = tonumber(k)
    if nk then e[nk] = tonumber(v) or v else e[k] = v end
end
local ok, err2 = pcall(f, e, "RUN")
return { tostring(ok), tostring(err2) }
`;

try {
    const res = await lua.doString(BOOT);
    console.log('result:', res);
} catch (e) {
    console.log('threw:', e.message.slice(0, 500));
}
