'use strict';

const fs = require('fs');
const path = require('path');
const { LuaFactory } = require('wasmoon');

(async () => {
    const root = path.join(__dirname, '..', '..');
    const lua = await new LuaFactory().createEngine();

    const envJson = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envtable.json'), 'utf8');
    const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_lineated.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    lua.global.set('PSU_ENV_JSON', envJson);
    lua.global.set('PSU_BODY', lineated);
    lua.global.set('PSU_PAYLOAD', payload);

    const BOOT = `
local json = (function()
    -- minimal: parse flat JSON object of string->string|number pairs
    local src = PSU_ENV_JSON
    local env = {}
    for k, v in src:gmatch('"([^"]+)":%s*"?([^,%}%n]+)"?') do
        local nk = tonumber(k)
        local nv = tonumber(v)
        if nk then env[nk] = nv else env[k] = v end
    end
    return env
end)()
local f, err = load(PSU_BODY)
if not f then return { 'LOADFAIL', tostring(err) } end
local ok, err2 = pcall(f, json, "RUN")
return { tostring(ok), tostring(err2) }
`;

    try {
        const res = await lua.doString(BOOT);
        console.log('result:', res);
    } catch (e) {
        console.log('threw:', e.message.slice(0, 400));
    }
})();
