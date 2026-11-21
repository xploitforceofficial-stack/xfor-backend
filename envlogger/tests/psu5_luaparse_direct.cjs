'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');
try {
    luaparse.parse(src, { luaVersion: '5.2', ranges: true, encodingMode: 'x-user-defined' });
    console.log('PARSE OK');
} catch (e) {
    console.log('fail:', e.message.slice(0, 300));

    const m = /\[(\d+):(\d+)\]/.exec(e.message);
    if (m) {
        const line = +m[1], col = +m[2];
        const lines = src.split('\n');
        console.log('line', line, 'col', col);
        if (lines[line - 1]) console.log('context:', JSON.stringify(lines[line - 1].slice(Math.max(0, col - 60), col + 60)));
    }
}
