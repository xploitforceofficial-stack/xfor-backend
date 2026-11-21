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
        ['S1', ';local m=', ' print("S1"); '],
        ['S2', ';local function k(', ' print("S2"); '],
        ['S3', ';local function _(', ' print("S3"); '],
        ['S4', ';local function A(', ' print("S4"); '],
        ['S5', 'return A(I(),{},v())', ' print("S5"); '],
    ];

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));

    lua.global.set('PSU_BODY', rebuilt);
    let r = await lua.doString(`
        local chunk, lerr = load(PSU_BODY, 'b', 't', _G)
        if chunk then return 'BASE OK' else return 'BASE FAIL ' .. lerr end
    `);
    console.log(r);

    for (const [name, needle, probe] of marks) {
        const i = rebuilt.lastIndexOf(needle);
        const diag = rebuilt.slice(0, i) + probe + rebuilt.slice(i);
        lua.global.set('PSU_BODY', diag);
        r = await lua.doString(`
            local chunk, lerr = load(PSU_BODY, 'b', 't', _G)
            if chunk then return '${name} OK' else return '${name} FAIL ' .. lerr end
        `);
        console.log(r, '(needle at', i + ')');
    }
})();
