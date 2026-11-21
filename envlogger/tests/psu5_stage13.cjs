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

    const anchor = 'local function o(n,e,...)';
    const idx = full.indexOf(anchor);

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
        'local PSU_PAYLOAD_ENV = ...',
        XOR,
    ].join('\n');

    const rebuilt = full.slice(0, idx)
        + `local u,c,n,p,s = PSU_U, 1, 0, string.byte, string.sub\n`
        + XOR + '\n'
        + full.slice(idx);

    let ast;
    try {
        ast = luaparse.parse(rebuilt, { luaVersion: '5.3' });
        console.log('PARSE OK');
    } catch (e) {
        console.log('parse failed:', e.message);
        return;
    }

    const free = new Set();
    function walk(node, scope) {
        if (!node || typeof node !== 'object') return;
        if (Array.isArray(node)) { for (const c of node) walk(c, scope); return; }
        switch (node.type) {
            case 'Chunk': walk(node.body, new Set()); break;
            case 'LocalStatement':
                for (const v of node.variables) walk(v, scope);
                if (node.init) for (const ini of node.init) walk(ini, scope);
                break;
            case 'FunctionDeclaration': {
                const s = new Set(scope);
                if (node.identifier) s.add(node.identifier.name);
                if (node.parameters) for (const p of node.parameters) {
                    if (p.type === 'Identifier') s.add(p.name);
                }
                walk(node.body, s);
                break;
            }
            case 'ForGenericStatement': {
                const s = new Set(scope);
                for (const v of node.variables) if (v.type === 'Identifier') s.add(v.name);
                for (const it of node.iterators) walk(it, scope);
                walk(node.body, s);
                break;
            }
            case 'ForNumericStatement': {
                const s = new Set(scope);
                if (node.variable && node.variable.type === 'Identifier') s.add(node.variable.name);
                walk(node.start, scope); walk(node.end, scope);
                if (node.step) walk(node.step, scope);
                walk(node.body, s);
                break;
            }
            case 'Identifier':
                if (!scope.has(node.name)) free.add(node.name);
                break;
            default:
                for (const k of Object.keys(node)) {
                    if (k === 'type') continue;
                    walk(node[k], scope);
                }
        }
    }
    walk(ast, new Set());
    console.log('free globals:', [...free].sort().join(', '));

    const lua = await new LuaFactory().createEngine();
    lua.global.set('PSU_ENV_JSON', envJson);
    lua.global.set('PSU_PAYLOAD', payload);
    lua.global.set('PSU_BODY4', rebuilt);

    const res = await lua.doString(`
        local accessed = {}
        local logenv = setmetatable({}, { __index = function(_, k)
            accessed[tostring(k)] = (accessed[tostring(k)] or 0) + 1
            return nil
        end })

        local bodychunk, err = load(PSU_BODY4, 'psu5body', 't', logenv)
        if not bodychunk then return { 'LOADFAIL', tostring(err) } end

        local env = {}
        for k, v in PSU_ENV_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
            local nk = tonumber(k)
            local nv = tonumber(v)
            if nk then env[nk] = nv else env[k] = v end
        end

        local ok, err2 = pcall(bodychunk, env)

        local names = {}
        for k in pairs(accessed) do names[#names + 1] = k .. '(' .. accessed[k] .. ')' end
        table.sort(names)
        return { tostring(ok), tostring(err2), table.concat(names, ', ') }
    `);
    console.log('ok    :', res[0]);
    console.log('err   :', res[1]);
    console.log('globals accessed:', res[2]);
})();
