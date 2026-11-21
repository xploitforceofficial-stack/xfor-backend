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

    const XOR = `local READLOG = {}
local function l(x, y)
local r, b = 0, 1
while x > 0 or y > 0 do
if (x % 2) ~= (y % 2) then r = r + b end
x = math.floor(x / 2)
y = math.floor(y / 2)
b = b * 2
end
return r
end`;

    const prelude = `local u,c,n,p,s = PSU_U, 1, 0, string.byte, string.sub
` + XOR + `
local function i()
local e = l(p(u,c,c), n)
n = e % 256
c = c + 1
if #READLOG < 40 then READLOG[#READLOG+1] = 'i@' .. c .. '=' .. e end
return e
end
local function d()
local e,t = p(u,c,c+1), p(u,c+1,c+1)
e = l(e,n); n = e % 256
t = l(t,n); n = t % 256
c = c + 2
if #READLOG < 40 then READLOG[#READLOG+1] = 'd@' .. c .. '=' .. (t*256+e) end
return (t*256)+e
end
`;

    const rebuilt = full.slice(0, idx) + prelude + full.slice(idx);

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_ENV_JSON', envJson);
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_BODY4', rebuilt);

    const res = await lua.doString(`
        local env = {}
        for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nk = tonumber(k)
            local nv = tonumber(v)
            if nk then env[nk] = nv else env[k] = v end
        end

        local bodychunk = load(PSU_BODY4, 'psu5body', 't', _G)
        local bootstrap = bodychunk()

        local ok, err = pcall(bootstrap, env)
        return { tostring(ok), tostring(err), PSU_READLOG and table.concat(PSU_READLOG, ' | ') or 'no log var' }
    `);
    console.log('ok :', res[0]);
    console.log('err:', res[1]);
    console.log('reads:', res[2]);
})();
