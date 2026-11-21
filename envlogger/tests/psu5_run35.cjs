'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const envMap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));
    const rebuilt = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_final.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    const marks = [
        [';local m=', ' LOG("S1"); '],
        [';local function k(', ' LOG("S2"); '],
        [';local function _(', ' LOG("S3"); '],
        [';local function A(', ' LOG("S4"); '],
        ['return A(I(),{},v())', ' LOG("S5"); '],
    ];
    let diag = rebuilt;
    for (const [needle, probe] of marks) {
        const i = diag.lastIndexOf(needle);
        if (i < 0) { console.log('missing needle:', needle); continue; }
        diag = diag.slice(0, i) + probe + diag.slice(i);
    }

    const logs = [];
    const lua = await new LuaFactory().createEngine();
    lua.global.set('LOG', (msg) => logs.push(String(msg)));
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));
    lua.global.set('PSU_BODY', diag);

    const res = await lua.doString(`
        local env = {}
        for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nv = tonumber(v)
            if k:match('^%d+$') then env[tonumber(k)] = nv
            else env[k] = nv or v end
        end
        local chunk, lerr = load(PSU_BODY, 'b', 't', _G)
        if not chunk then return 'LOADFAIL ' .. tostring(lerr) end
        local bootstrap = chunk()
        LOG("bootstrap called")
        local ok, ret = pcall(bootstrap, env)
        return table.concat({"after:", tostring(ok), tostring(ret):sub(1,200)}, " | ")
    `);
    console.log('markers reached:', logs);
    console.log(res);
})();
