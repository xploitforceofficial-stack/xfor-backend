'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const envMap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));
    const full = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebulled_full.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    const anchor = 'local function o(n,e,...)';
    const idx = full.indexOf(anchor);

    const prelude = `local u,c,n,p,s = PSU_U, 1, 0, string.byte, string.sub
local x = {}
for i = 0, 255 do x[i] = string.char(i) end
`;

    const rebuilt = full.slice(0, idx) + prelude + full.slice(idx);

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_BODY4', rebuilt);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));

    const res = await lua.doString(`
        local env = {}
        for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*([^,}%n]+)') do
            local nv = tonumber(v)
            env[k] = nv
        end

        local bodychunk = load(PSU_BODY4, 'psu5body', 't', _G)
        local bootstrap = bodychunk()

        local ok, ret = pcall(bootstrap, env)
        if not ok then
            return { 'ERR', tostring(ret) }
        end
        return { 'OK', type(ret), tostring(ret):sub(1, 200) }
    `);
    console.log('result:', res.join(' | '));
})();
