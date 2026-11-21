'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));
const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_lineated.lua'), 'utf8').replace(/end\)\s*$/, 'end');
const ast = luaparse.parse(lineated, { luaVersion: '5.3', range: true });

const tailIdx = lineated.indexOf('return A(I(),{},v())');
if (tailIdx < 0) { console.log('tail text not found'); process.exit(0); }
console.log('tail at char', tailIdx);

const stack = [];
(function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }
    const r = node.range;
    const isFn = node.type === 'FunctionDeclaration';
    if (isFn && r && r[0] <= tailIdx && tailIdx <= r[1]) {
        stack.push({
            name: node.identifier ? node.identifier.name : '(anon)',
            start: lineated.slice(r[0], r[0] + 60).replace(/\n/g, ' '),
        });
    }
    for (const k of Object.keys(node)) {
        if (k !== 'type') walk(node[k]);
    }
})(ast);

console.log('functions containing the tail:');
stack.forEach((s, i) => console.log(`  ${i}: ${s.name} :: ${s.start}`));
