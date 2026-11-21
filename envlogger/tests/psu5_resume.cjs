'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require(path.join(root, 'node_modules', 'wasmoon'));

const envmap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));
const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_final.lua'), 'utf8');

(async () => {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();

    const entries = Object.entries(envmap).map(([k, v]) => {
        if (typeof v === 'number') return `['${k}'] = ${v}`;
        if (v === null) return `['${k}'] = nil`;
        return `['${k}'] = '${String(v).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
    }).join(',\n');
    await lua.global.set('ENVMAP_LUA', 'return {\n' + entries + '\n}');
    await factory.mountFile('/body.lua', src);

    const out = await lua.doString(`
        local env = load(ENVMAP_LUA)()
        env['FJ3bzQ5i0j'] = 20
        env['QCl5H'] = setmetatable
        env['udTlwPHfj'] = tostring
        local bodyenv = setmetatable({ K = math.ldexp, D = math.floor }, { __index = _G })
        local bootstrap = dofile('/body.lua')
        local frames = {}
        local function handler(err)
            for lvl = 1, 14 do
                local info = debug.getinfo(lvl, 'nSl')
                if not info then break end
                frames[#frames+1] = lvl .. ':' .. tostring(info.name or '?') .. '@' ..
                    tostring(info.currentline) .. ':' .. tostring(info.short_src):sub(-10)
            end
            return tostring(err) .. ' ||| ' .. table.concat(frames, ' > ')
        end
        local ok, ret = xpcall(bootstrap, handler, env)
        if not ok then return 'ERR: ' .. ret end
        return 'OK type=' .. type(ret)
    `);
    console.log(out.slice(0, 1600));
})().catch(e => console.error('JSERR:', e.message.slice(0, 500)));
