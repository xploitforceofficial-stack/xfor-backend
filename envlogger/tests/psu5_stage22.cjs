'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const envMap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));
    const rebuilt = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_final.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));
    lua.global.set('PSU_BODY', rebuilt);

    const res = await lua.doString(`
        local env = {}
        for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nv = tonumber(v)
            if k:match('^%d+$') then
                env[tonumber(k)] = nv
            else
                env[k] = nv or v
            end
        end

        local chunk, err = load(PSU_BODY, 'psu5body', 't', _G)
        if not chunk then return 'LOADFAIL: ' .. tostring(err) end
        local ok, bootstrap = pcall(chunk)
        if not ok then return 'CHUNK ERR: ' .. tostring(bootstrap) end
        -- chunk returns f; f(e,...) runs the deserializer, returns A(I(),{},v())(...)
        local ok2, ret = pcall(bootstrap, env)
        if not ok2 then return 'BODY ERR: ' .. tostring(ret) end
        if type(ret) ~= 'function' then return 'RET: ' .. type(ret) .. ' ' .. tostring(ret):sub(1, 150) end
        -- the returned closure is the VM interpreter: call it
        local ok3, ret3 = pcall(ret)
        if not ok3 then return 'VM ERR: ' .. tostring(ret3) end
        return 'VM OK: ' .. type(ret3) .. ' ' .. tostring(ret3):sub(1, 150)
    `);
    console.log(res);
})();
