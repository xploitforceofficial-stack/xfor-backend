'use strict';

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { LuaFactory } from 'wasmoon';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..', '..');

const bodySrc = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_body.lua'), 'utf8');
const envJson = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envtable.json'), 'utf8'));

const lua = await new LuaFactory().createEngine();
lua.global.set('PSU_ENV', envJson);

const BOOT = `
local envraw = PSU_ENV
local e = {}
for k, v in pairs(envraw) do
    local nk = tonumber(k)
    if nk then e[nk] = tonumber(v) or v else e[k] = v end
end
local f = function(e, ...) ${bodySrc} end
local ok, err = pcall(f, e, "RUN")
return ok, err
`;

try {
    const [ok, err] = await lua.doString(BOOT);
    console.log('run ok:', ok, 'err:', String(err).slice(0, 400));
} catch (e) {
    console.log('threw:', e.message.slice(0, 400));
}
