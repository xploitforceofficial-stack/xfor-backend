'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_recon5.lua'), 'utf8');
try {
    luaparse.parse(src, { luaVersion: '5.3' });
    console.log('luaparse: OK');
} catch (e) {
    console.log('luaparse err:', e.message);
    if (e.line !== undefined) {
        console.log('at line', e.line, 'col', e.column, 'index', e.index);
        console.log('context:', JSON.stringify(src.slice(Math.max(0, e.index - 100), e.index + 60)));
    }
}
