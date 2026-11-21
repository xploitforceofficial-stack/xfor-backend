'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const envMap = JSON.parse(fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envmap.json'), 'utf8'));
    const rebuilt = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_final.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');
    const script = fs.readFileSync(path.join(root, 'envlogger', 'tests', 'psu5_lineate_trace.lua'), 'utf8');

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_ENVMAP_JSON', JSON.stringify(envMap));
    lua.global.set('PSU_BODY', rebuilt);

    const res = await lua.doString(script);
    console.log(res);
})();
