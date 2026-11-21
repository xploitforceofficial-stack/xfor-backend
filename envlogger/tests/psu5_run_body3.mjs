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
lua.global.set('PSU_PAYLOAD', fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8'));

const BOOT = `
local envraw = PSU_ENV
local e = {}
for k, v in pairs(envraw) do
    local nk = tonumber(k)
    if nk then e[nk] = tonumber(v) or v else e[k] = v end
end
${lineated}
local ok, err = pcall(f, e, "RUN")
return ok, tostring(err)
`;

try {
    const [ok, err] = await lua.doString(BOOT);
    console.log('ok:', ok);
    console.log('err:', String(err).slice(0, 500));
} catch (e) {
    console.log('threw:', e.message.slice(0, 500));
}
