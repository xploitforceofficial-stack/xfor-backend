'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));
const lineated = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_lineated.lua'), 'utf8').replace(/end\)$/m, 'end');
const ast = luaparse.parse(lineated, { luaVersion: '5.3' });

let result = null;
function walk(node, scopes) {
    if (!node || typeof node !== 'object' || result) return;
    if (Array.isArray(node)) { for (const c of node) walk(c, scopes); return; }
    if (node.type === 'ReturnStatement' && JSON.stringify(node).includes('A(I')) {
        result = scopes.slice();
        return;
    }
    let s2 = scopes;
    if (node.type === 'FunctionDeclaration') {
        s2 = scopes.slice();
        if (node.identifier) s2.push('FUNC:' + node.identifier.name);
        if (node.parameters) for (const p of node.parameters) {
            if (p.type === 'Identifier') s2.push(p.name);
        }
    } else if (node.type === 'LocalStatement') {
        s2 = scopes.slice();
        for (const v of node.variables) s2.push(v.name);
    }
    for (const k of Object.keys(node)) {
        if (k === 'type') continue;
        walk(node[k], s2);
    }
}
walk(ast, ['(top)']);
console.log('tail visible bindings (last 25):');
console.log(result ? result.slice(-25).join(', ') : 'tail not found');
