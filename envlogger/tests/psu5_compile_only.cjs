'use strict';

const fs = require('fs');
const path = require('path');
const { LuaFactory } = require('wasmoon');

(async () => {
    const root = path.join(__dirname, '..', '..');
    const bodySrc = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_body.lua'), 'utf8');
    const lua = await new LuaFactory().createEngine();

    const wrap1 = 'local f = function(e, ...) ' + bodySrc + ' end return type(f)';
    try {
        const r = await lua.doString(wrap1);
        console.log('WRAP1 OK:', r);
    } catch (err) {
        console.log('WRAP1 ERR:', err.message.slice(0, 200));
    }

    const wrap2 = 'local f = function(e, ...)\n' + bodySrc + '\nend\nreturn type(f)';
    try {
        const r = await lua.doString(wrap2);
        console.log('WRAP2 OK:', r);
    } catch (err) {
        console.log('WRAP2 ERR:', err.message.slice(0, 200));
    }

    const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_lineated.lua'), 'utf8');
    try {
        const r = await lua.doString(lineated);
        console.log('WRAP3 OK:', r);
    } catch (err) {
        console.log('WRAP3 ERR:', err.message.slice(0, 200));
    }
})();
