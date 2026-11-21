'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const envMap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));
    const rebuilt = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_full2.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));
    lua.global.set('PSU_BODY', rebuilt);

    const res = await lua.doString(`
        local env = {}
        for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*([^,}%n]+)') do
            env[k] = tonumber(v)
        end
        local chunk, err = load(PSU_BODY, 'psu5body', 't', _G)
        if not chunk then return 'LOADFAIL: ' .. tostring(err) end
        local ok, bootstrap = pcall(chunk)
        if not ok then return 'CHUNK ERR: ' .. tostring(bootstrap) end
        -- f is the returned function; call it with env
        local ok2, ret = pcall(bootstrap, env)
        if not ok2 then return 'BODY ERR: ' .. tostring(ret) end
        return 'OK: ' .. type(ret) .. ' ' .. tostring(ret):sub(1, 120)
    `);
    console.log(res);
})();
