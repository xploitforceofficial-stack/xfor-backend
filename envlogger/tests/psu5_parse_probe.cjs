'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_recon5.lua'), 'utf8');

try {
    luaparse.parse(src, { luaVersion: '5.2', ranges: true, encodingMode: 'x-user-defined' });
    console.log('PARSE OK with luaVersion 5.2');
} catch (e) {
    console.log('5.2 fail:', e.message.slice(0, 200));
}

try {
    luaparse.parse(src, { luaVersion: '5.1', ranges: true, encodingMode: 'x-user-defined' });
    console.log('PARSE OK with luaVersion 5.1');
} catch (e) {
    console.log('5.1 fail:', e.message.slice(0, 200));
}
