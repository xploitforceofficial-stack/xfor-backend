'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));
const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_lineated.lua'), 'utf8').replace(/end\)\s*$/, 'end');
const ast = luaparse.parse(lineated, { luaVersion: '5.3', range: true });

function offsetOf(text, idx) {
    let off = 0, line = 1;

    return -1;
}
const targets = [];
const lines = lineated.split('\n');
let acc = 0;
for (let i = 0; i < lines.length; i++) {
    const ln = lines[i];
    const m = ln.match(/local function (\w+)\(/);
    if (m && ['o', 'i', 'd', 'f', 'a', 'k', 'I', '_', 'A'].includes(m[1])) {
        targets.push({ off: acc + m.index, name: m[1], line: i + 1 });
    }
    if (ln.includes('return A(I(),{},v())')) {
        targets.push({ off: acc + ln.indexOf('return A'), name: '(TAIL)', line: i + 1 });
    }
    acc += ln.length + 1;
}

const chain = [];
(function walk(node, stack) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(c => walk(c, stack)); return; }
    const isFn = node.type === 'FunctionDeclaration';
    let entry = null;
    if (isFn && node.range) {
        entry = {
            name: node.identifier ? node.identifier.name : '(anon)',
            start: node.range[0], end: node.range[1],
        };
        stack.push(entry);
    }
    for (const t of targets) {
        if (node.range && node.range[0] <= t.off && t.off <= node.range[1] && !t.chain) {
            t.chain = stack.map(s => s.name).join(' > ') || 'CHUNK';
        }
    }
    for (const k of Object.keys(node)) {
        if (k !== 'type') walk(node[k], stack);
    }
    if (isFn) stack.pop();
})(ast, []);

for (const t of targets) {
    console.log(`line ${t.line} ${t.name}: ${t.chain || 'CHUNK'}`);
}
