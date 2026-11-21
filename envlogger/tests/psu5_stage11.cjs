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
        'local p = string.byte',
        'local s = string.sub',
        'local c = 1',
        'local n = 0',
        XOR,
    ].join('\n');

    const rebuilt = full.slice(0, idx) + prelude + full.slice(idx);
    lua.global.set('PSU_BODY4', rebuilt);

    const res = await lua.doString(`
        local accessed = {}
        local mt = { __index = function(_, k)
            accessed[tostring(k)] = (accessed[tostring(k)] or 0) + 1
            return nil
        end }
        local logenv = setmetatable({}, mt)

        local bodychunk, err = load(PSU_BODY4, 'psu5body', 't', logenv)
        if not bodychunk then return { 'LOADFAIL', tostring(err) } end

        local env = {}
        for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nk = tonumber(k)
            local nv = tonumber(v)
            if nk then env[nk] = nv else env[k] = v end
        end
        env.UPex4im = 'UPex4im'

        local ok, err2 = pcall(bodychunk, env)

        local names = {}
        for k in pairs(accessed) do names[#names + 1] = k .. '(' .. accessed[k] .. ')' end
        table.sort(names)
        return { tostring(ok), tostring(err2), table.concat(names, ', ') }
    `);
    console.log('ok    :', res[0]);
    console.log('err   :', res[1]);
    console.log('globals accessed:', res[2]);
})();
