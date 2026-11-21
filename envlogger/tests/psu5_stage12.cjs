'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const luaparse = require(path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'node_modules', 'luaparse'));
const { LuaFactory } = require('wasmoon');

(async () => {

    const envJson = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_envtable.json'), 'utf8');
    const full = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebulled_full.lua'), 'utf8');
    const payload = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_vmpayload.txt'), 'utf8');

    const mark = 'local function i(';
    const idx = full.indexOf(mark);

    const XOR = `local function l(x, y)
local r, b = 0, 1
while x > 0 or y > 0 do
if (x % 2) ~= (y % 2) then r = r + b end
x = math.floor(x / 2)
y = math.floor(y / 2)
b = b * 2
end
return r
end`;

    const prelude = [
        'local u = PSU_PAYLOAD',
        'local p = string.byte',
        'local s = string.sub',
        'local c = 1',
        'local n = 0',
        XOR,
    ].join('\n');

    const rebuilt = full.slice(0, idx) + prelude + full.slice(idx);

    let ast;
    try {
        ast = luaparse.parse(rebuilt, { luaVersion: '5.3' });
    } catch (e) {
        console.log('parse failed:', e.message);
        return;
    }

    const bound = new Set();
    const free = new Set();

    function walk(node, scope) {
        if (!node || typeof node !== 'object') return;
        if (Array.isArray(node)) { for (const c of node) walk(c, scope); return; }
        switch (node.type) {
            case 'Chunk': {
                const s = new Set(scope);
                walk(node.body, s);
                break;
            }
            case 'LocalStatement': {
                for (const v of node.variables) walk(v, scope);
                if (node.init) for (const ini of node.init) walk(ini, scope);
                break;
            }
            case 'FunctionDeclaration': {
                const s = new Set(scope);
                if (node.identifier) walk(node.identifier, s);
                if (node.parameters) for (const p of node.parameters) {
                    if (p.type === 'Identifier') s.add(p.name);
                    else if (p.type === 'VarargLiteral') s.add('...');
                }
                walk(node.body, s);
                break;
            }
            case 'ForGenericStatement': {
                const s = new Set(scope);
                if (node.variable) { s.add(node.variable.name); walk(node.variable, scope); }
                if (node.forBody) {
                    for (const v of (node.forBody || [])) if (v.type === 'Identifier') s.add(v.name);
                }
                if (node.iterators) for (const it of node.iterators) walk(it, scope);
                walk(node.body, s);
                break;
            }
            case 'ForNumericStatement': {
                const s = new Set(scope);
                if (node.variable && node.variable.type === 'Identifier') s.add(node.variable.name);
                if (node.start) walk(node.start, scope);
                if (node.end) walk(node.end, scope);
                if (node.step) walk(node.step, scope);
                walk(node.body, s);
                break;
            }
            case 'DoStatement': {
                const s = new Set(scope);
                walk(node.body, s);
                break;
            }
            case 'WhileStatement': {
                walk(node.condition, scope);
                const s = new Set(scope);
                walk(node.body, s);
                break;
            }
            case 'RepeatStatement': {
                const s = new Set(scope);
                walk(node.body, s);
                walk(node.condition, s);
                break;
            }
            case 'IfStatement': {
                for (const c of node.clauses) walk(c, scope);
                break;
            }
            case 'IfClause': case 'ElseifClause': {
                walk(node.condition, scope);
                const s = new Set(scope);
                walk(node.body, s);
                break;
            }
            case 'ElseClause': {
                const s = new Set(scope);
                walk(node.body, s);
                break;
            }
            case 'Identifier': {
                if (!scope.has(node.name) && !bound.has(node.name)) free.add(node.name);
                break;
            }
            default: {
                for (const k of Object.keys(node)) {
                    if (k === 'type') continue;
                    walk(node[k], scope);
                }
            }
        }
    }

    walk(ast, new Set());
    const freeList = [...free].sort();
    console.log('free globals needed:', freeList.join(', '));
    console.log('count:', freeList.length);

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_ENV_JSON', envJson);
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_BODY4', rebuilt);
    lua.global.set('PSU_FREELIST', freeList.join(','));

    const res = await lua.doString(`
        local accessed = {}
        local mt = { __index = function(_, k)
            accessed[tostring(k)] = (accessed[tostring(k)] or 0) + 1
            return nil
        end }
        local logenv = setmetatable({}, mt)

        local bodychunk, err = load(PSU_BODY4, 'psu5body', 't', logenv)
        if not bodychunk then return { 'LOADFAIL', tostring(err) } end

        local env = {}
        for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nk = tonumber(k)
            local nv = tonumber(v)
            if nk then env[nk] = nv else env[k] = v end
        end
        env.UPex4im = 'UPex4im'

        local ok, err2 = pcall(bodychunk, env)

        local names = {}
        for k in pairs(accessed) do names[#names + 1] = k .. '(' .. accessed[k] .. ')' end
        table.sort(names)
        return { tostring(ok), tostring(err2), table.concat(names, ', ') }
    `);
    console.log('ok    :', res[0]);
    console.log('err   :', res[1]);
    console.log('globals accessed at runtime:', res[2]);
})();
