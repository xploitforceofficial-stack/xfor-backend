'use strict';

const fs = require('fs');
const path = require('path');
const { LuaFactory } = require('wasmoon');

(async () => {
    const root = path.join(__dirname, '..', '..');
    const lua = await new LuaFactory().createEngine();

    const envJson = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envtable.json'), 'utf8');
    const full = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebulled_full.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    lua.global.set('PSU_ENV_JSON', envJson);
    lua.global.set('PSU_PAYLOAD', payload);

    const mark = 'local function i(';
    const idx = full.indexOf(mark);

    const XOR = `local function l(x, y)
        local r, b = 0, 1
        while x > 0 or y > 0 do
            if (x % 2) ~= (y % 2) then r = r + b end
            x = math.floor(x / 2)
            y = math.floor(y / 2)
            b = b * 2
        end
        return r
    end`;

    const prelude = [
        'local u = PSU_PAYLOAD',
        'local p = string.sub',
        'local c = 1',
        'local n = 0',
        XOR,
        'local o = 256',
        'local a = 256',
        'local t = 1',
        'local A = 4',
        'local h = 4',
        'local g = 255',
        'local w = 8',
        'local y = 0',
        'local x = {}',
    ].join(' ');

    const rebuilt = full.slice(0, idx) + prelude + full.slice(idx);
    const lineated = rebuilt.replace(' ', '\n');
    lua.global.set('PSU_BODY3', lineated);

    const res = await lua.doString(`
        local bodychunk, err = load(PSU_BODY3)
        if not bodychunk then return { 'LOADFAIL', tostring(err) } end
        local bootstrap = bodychunk()

        -- parse env table
        local env = {}
        for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nk = tonumber(k)
            local nv = tonumber(v)
            if nk then env[nk] = nv else env[k] = v end
        end
        env.UPex4im = 'UPex4im'

        -- debug hook to catch first error site with locals
        local steps = 0
        debug.sethook(function(ev, line)
            steps = steps + 1
            if steps > 2000000 then
                debug.sethook()
                error('STEP LIMIT')
            end
        end, '', 100000)

        local ok, err2 = pcall(bootstrap, env)
        debug.sethook()

        -- if error, grab traceback
        if not ok then
            return { tostring(ok), tostring(err2), debug.traceback(err2, 2) }
        end
        return { tostring(ok), tostring(err2) }
    `);
    console.log('result:');
    for (const r of res) console.log('  ' + tostring(r));
    function tostring(x) { return typeof x === 'string' ? x : JSON.stringify(x); }
})();
