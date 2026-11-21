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

    const prelude = 'local u = PSU_U; local c = 1; local n = 0; local p = string.byte; local s = string.sub; local x = {};';

    const rebuilt = full.slice(0, idx) + prelude + full.slice(idx);

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_U', payload);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));

    const masked = rebuilt.replace(/"([^"]*)"/g, (m, inner) => `"${'\u0001'.repeat(Math.min(inner.length, 0))}"`);

    const lineated = rebuilt.replace(/;end;/g, ';\n');

    fs.writeFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_lineated.lua'), lineated);
    lua.global.set('PSU_BODY5', lineated);

    const res = await lua.doString(`
        local env = {}
        for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*([^,}%n]+)') do
            env[k] = tonumber(v)
        end
        local bodychunk = load(PSU_BODY5, 'psu5body', 't', _G)
        if not bodychunk then return 'LOADFAIL' end
        local bootstrap = bodychunk()
        local ok, ret = pcall(bootstrap, env)
        if not ok then return 'ERR: ' .. tostring(ret) end
        return 'OK ' .. type(ret)
    `);
    console.log(res);
})();
