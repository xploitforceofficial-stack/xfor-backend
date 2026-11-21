'use strict';

const fs = require('fs');
const path = require('path');
const { LuaFactory } = require('wasmoon');

(async () => {
    const root = path.join(__dirname, '..', '..');
    const lua = await new LuaFactory().createEngine();

    lua.global.set('PSU_ENV', { a: 1 });

    const t = await lua.doString(`
        local r = {}
        r.type = type(PSU_ENV)
        r.isnull = (PSU_ENV == nil)
        local n = 0
        if type(PSU_ENV) == 'table' then
            for k, v in pairs(PSU_ENV) do n = n + 1 end
        end
        r.count = n
        return r
    `);
    console.log('simple obj:', t);

    const envJson = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envtable.json'), 'utf8'));
    console.log('JS env size:', Object.keys(envJson).length);
    lua.global.set('PSU_ENV2', envJson);
    const t2 = await lua.doString(`
        local r = {}
        r.type = type(PSU_ENV2)
        local n = 0
        if type(PSU_ENV2) == 'table' then
            for k, v in pairs(PSU_ENV2) do n = n + 1 end
        end
        r.count = n
        return r
    `);
    console.log('real env:', t2);
})();
