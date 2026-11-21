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
    if (idx < 0) throw new Error('i() marker not found');

    const prelude = [
        'local u = PSU_PAYLOAD',
        'local p = string.sub',
        'local c = 1',
        'local n = 0',
        'local l = function(x, y) return x ^^ y end',
        'local o = 256',
        'local a = 256',
        'local t = 1',
        'local A = 4',
        'local h = 4',
        'local g = 255',
        'local w = 8',
        'local y = 0',
        'local x = {}',
        'local f = nil',
    ].join(' ');

    const rebuilt = full.slice(0, idx) + prelude + full.slice(idx);
    lua.global.set('PSU_BODY2', rebuilt);

    const BOOT = `
local env = {}
for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,%}%n]+)"?') do
    local nk = tonumber(k)
    local nv = tonumber(v)
    if nk then env[nk] = nv else env[k] = v end
end
env.UPex4im = 'UPex4im'
local bodychunk, err = load(PSU_BODY2)
if not bodychunk then return { 'LOADFAIL', tostring(err) } end
local bootstrap = bodychunk()
local ok, err2 = pcall(bootstrap, env, PSU_PAYLOAD)
return { tostring(ok), tostring(err2) }
`;
    lua.global.set('PSU_BOOT', BOOT);

    try {
        const res = await lua.doString(`
            local ok, res = pcall(load(PSU_BOOT))
            if not ok then error(res) end
            return res
        `);
        console.log('result:', res);
    } catch (e) {
        console.log('threw:', e.message.slice(0, 600));
    }
})();
