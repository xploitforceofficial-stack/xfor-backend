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
        -- string table x[] for char reconstruction: x[byte] = char
        local x = {}
        for i = 0, 255 do x[i] = string.char(i) end

        -- full env: resolve every numeric key to its value, plus single-letter
        -- string values (they are identifiers). Everything else nil.
        local env = {}
        for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nk = tonumber(k)
            local nv = tonumber(v)
            if nk then env[nk] = nv else env[k] = v end
        end

        local bodychunk = load(PSU_BODY4, 'psu5body', 't', _G)

        -- wrap the deserializer's string output: intercept print/error
        local msgs = {}
        local function hookErr(e)
            msgs[#msgs+1] = 'ERR: ' .. tostring(e)
            return e
        end

        local function runWithEnv(envTable)
            local ok, err = pcall(bodychunk, envTable)
            msgs[#msgs+1] = 'bootstrap ok=' .. tostring(ok) .. ' err=' .. tostring(err)
            if ok then
                -- bootstrap returned a closure (A(I(),{},v())(...))
                -- it may need more env; try calling it
                local ok2, err2 = pcall(err)  -- err is actually the return value if ok
                msgs[#msgs+1] = 'invoke ok=' .. tostring(ok2) .. ' err=' .. tostring(err2)
            end
        end

        runWithEnv(env)

        return { table.concat(msgs, ' || '):sub(1, 800) }
    `);
    console.log('output:', res[0]);
})();
