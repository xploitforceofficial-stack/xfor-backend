'use strict';

const fs = require('fs');
const { LuaFactory } = require('wasmoon');

(async () => {
    const lua = await new LuaFactory().createEngine();
    const src = fs.readFileSync('Samples/PSU/v5/_rebuilt_body.lua', 'utf8');

    const test = 'local f = function(e, ...) ' + src + ' end';
    try {
        await lua.doString(test);
        console.log('PARSE OK');
    } catch (err) {
        console.log('ERR:', err.message.slice(0, 400));

        const m = err.message.match(/near '(.+?)'/);
        if (m) console.log('near token:', JSON.stringify(m[1]));
    }
})();
