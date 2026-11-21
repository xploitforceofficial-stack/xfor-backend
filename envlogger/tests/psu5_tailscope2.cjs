'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));
const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_lineated.lua'), 'utf8').replace(/end\)\s*$/, 'end');
const ast = luaparse.parse(lineated, { luaVersion: '5.3' });

let result = null;
function isTail(node) {
    const s = JSON.stringify(node);
    return node.type === 'ReturnStatement' && /"name":"A"/.test(s) && /"name":"I"/.test(s) && s.length < 400;
}
function walk(node, scopes) {
    if (!node || typeof node !== 'object' || result) return;
    if (Array.isArray(node)) { node.forEach(c => walk(c, scopes)); return; }
    if (isTail(node)) { result = scopes.slice(); return; }
    let s2 = scopes;
    if (node.type === 'FunctionDeclaration') {
        s2 = scopes.slice();
        if (node.identifier) s2.push(node.identifier.name);
        for (const p of (node.parameters || [])) if (p.type === 'Identifier') s2.push(p.name);
    } else if (node.type === 'LocalStatement') {
        s2 = scopes.slice();
        for (const v of node.variables) s2.push(v.name);
    }
    for (const k of Object.keys(node)) {
        if (k !== 'type') walk(node[k], s2);
    }
}
walk(ast, ['CHUNK']);
if (!result) { console.log('tail not found'); process.exit(0); }

const interesting = result.filter(s => /^(A|I|v|_|f)$/.test(s) || s.startsWith('CHUNK'));
console.log('ALL enclosing bindings:', result.join(', '));
console.log();
console.log('A/I/v/related:', interesting.join(' -> '));
