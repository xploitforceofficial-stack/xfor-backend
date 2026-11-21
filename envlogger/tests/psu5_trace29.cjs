'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const envMap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));
    const rebuilt = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_final.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    let n = 0;
    const diag = rebuilt.replace(/;(end);/g, (m, p1) => {
        n++;
        return ';' + p1 + ' print("MK' + n + '");';
    });
    console.log('markers:', n);

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));
    lua.global.set('PSU_BODY', diag);

    const res = await lua.doString(`
        local env = {}
        for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nv = tonumber(v)
            if k:match('^%d+$') then env[tonumber(k)] = nv
            else env[k] = nv or v end
        end
        local chunk = load(PSU_BODY, 'psu5body', 't', _G)
        local bootstrap = chunk()
        local ok, ret = pcall(bootstrap, env)
        return 'after: ' .. tostring(ok) .. ' | ' .. tostring(ret):sub(1, 120)
    `);
    console.log(res);
})();
