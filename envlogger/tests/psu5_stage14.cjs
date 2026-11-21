'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const envJson = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envtable.json'), 'utf8');
    const full = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebulled_full.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    const anchor = 'local function o(n,e,...)';
    const idx = full.indexOf(anchor);

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

    const rebuilt = full.slice(0, idx)
        + `local u,c,n,p,s = PSU_U, 1, 0, string.byte, string.sub\n`
        + XOR + '\n'
        + full.slice(idx);

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_ENV_JSON', envJson);
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_BODY4', rebuilt);

    const res = await lua.doString(`
        -- build a full env: numeric keys resolve to their values; unknown keys
        -- get placeholder numeric values from the JSON where possible
        local env = {}
        for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nk = tonumber(k)
            local nv = tonumber(v)
            if nk then env[nk] = nv else env[k] = v end
        end
        -- some env values are strings that should be identifiers (single letters)
        -- those stay as strings

        -- wrap the bootstrap so we can see the first N reads of d(n)
        local logenv = setmetatable({}, { __index = function(_, k)
            if type(k) == 'string' then
                return nil
            end
            return nil
        end })

        local bodychunk = load(PSU_BODY4, 'psu5body', 't', logenv)

        -- track every access to env[...] by metatable on env
        local accessLog = {}
        local envMt = setmetatable(env, {
            __index = function(t, k)
                accessLog[#accessLog + 1] = tostring(k)
                return rawget(t, k)
            end
        })

        local ok, err = pcall(bodychunk, envMt)

        -- summarize access log
        local seen, order = {}, {}
        for _, k in ipairs(accessLog) do
            if not seen[k] then seen[k] = {count=0, firstVal=rawget(env, k)}; order[#order+1] = k end
            seen[k].count = seen[k].count + 1
        end
        local summary = {}
        for i, k in ipairs(order) do
            if i > 40 then break end
            local v = seen[k]
            local vs = type(v.firstVal) == 'number' and tostring(v.firstVal) or (type(v.firstVal) == 'string' and ('"' .. v.firstVal .. '"') or 'nil')
            summary[#summary+1] = k .. '=' .. vs .. ' x' .. v.count
        end
        return { tostring(ok), tostring(err), table.concat(summary, ' | ') }
    `);
    console.log('ok  :', res[0]);
    console.log('err :', res[1]);
    console.log('env reads:', res[2]);
})();
