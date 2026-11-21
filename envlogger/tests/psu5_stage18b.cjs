'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_lineated.lua'), 'utf8');
    const envMap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_BODY5', lineated);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));

    const res = await lua.doString(`
        local chunk, err = load(PSU_BODY5, 'psu5body', 't', _G)
        if not chunk then return 'LOADFAIL: ' .. tostring(err) end
        return 'LOAD OK'
    `);
    console.log(res);
})();
